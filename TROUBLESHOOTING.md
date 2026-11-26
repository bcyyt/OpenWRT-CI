# 固件踩坑记录（Troubleshooting）

编译与线上运维遇到过的坑，新问题按时间追加。

---

## 坑1 [已修进 CI]：geosite.dat 缺分类 → daed 空载，代理整体失效

**日期**：2026-11-18（S20P / mediatek-filogic，ImmortalWrt r0-fdb0dfb 首次发现）

**现象**：刷机/重启后 daed 进程活着、面板能开，但代理完全不通。
日志特征（`/var/log/daed/daed.log`）：

```text
[Reload] Load new control plane          ← 之后没有 Waiting for network / Bind
Failed to restore last running state: failed to load new config:
  ApplyRulesOptimizers error: code gfw not found in /usr/share/daed/geosite.dat
[Reload] Failed to reload; try to roll back configuration
```

**根因**：ROM 里 `/usr/share/daed/geosite.dat -> ../v2ray/geosite.dat`（v2ray 包提供的
dat）缺少 dae 需要的分类（含 gfw），routing 规则 `domain(geosite:gfw) -> proxy`
解析失败，整个控制平面被回滚成空配置（Routing match set len: 1/1024 即空）。

**连锁坑**：启动恢复失败时 daed 会把 `wing.db` 的 `systems.running` 清 0，
之后即使修好 dat，-daed 也不会自动恢复运行，必须手动把 running 置回 1
（或面板里点"启动"）。表现为：停/重启服务后永远停在 Ready、无 Bind。

**线上修复（当天手工操作）**：

```sh
# 1. 换完整版 dat（Loyalsoldier，约 11MB，jsdelivr 国内可达）
curl -fsSL -o /usr/share/v2ray/geosite.dat \
  https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/geosite.dat
# 2. 复位运行标志（若被清 0）
sqlite3 /etc/daed/wing.db "update systems set running=1"
# 3. 重启服务
/etc/init.d/daed restart
```

**CI 修复**：`WRT-CORE.yml` 的 `Custom Settings` 步骤在构建时下载
Loyalsoldier 完整版放入 `files/usr/share/v2ray/geosite.dat`，rootfs 打包时
覆盖 ROM 文件（含体积校验，<5MB 视为下载失败直接 fail）。
下一次编译的固件不再带这个坑。

**验收要点**（刷机后检查 daed 是否真的在工作）：

```sh
grep -E 'Bind to|Routing match set' /var/log/daed/daed.log | tail
# 必须看到 Bind to LAN / Bind to WAN，且 Routing match set len > 1（1=空配置）
tc qdisc show dev pppoe-wan | grep -c clsact   # 应为 1（WAN 侧 eBPF 已挂载）
nslookup www.google.com 127.0.0.1             # 应返回真实 Google IP（142.251.x 等）
```

---

## 坑2 [运维注意]：wing.db 的 running 标志与"Ready 但不工作"

daed 的启动逻辑：读 `wing.db` 的 `systems.running`——为 1 时才把数据库里
的订阅/分组/路由推给 dae core（日志出现 `[Reload] Load new control plane`
→ `Waiting for network` → `Network online` → `Bind to LAN/WAN`）。

- 只有 `Ready`、没有 `[Reload]`、没有 `Bind` = 核心空载（配置没推送）。
- `Routing match set len: 1/1024` = 空规则集（坑1 的直接证据）。
- 排查顺序：先看有没有 `[Reload]` 报错（配置加载失败）→ 再查 running
  标志 → 最后才怀疑网络在线检测。
- 注意：路由器本机（127.0.0.1 / dnsmasq 自身）的 DNS 解析**不经过** daed
  代理路径，直接 `nslookup www.google.com 127.0.0.1` 拿到污染 IP 不能证明
  daed 坏了；判断 daed 死活要看 `grep '_qname' /var/log/daed/daed.log` 里
  客户端流量的 outbound 是什么。

---

## 坑3 [运行时配置]：PPPoE 动态 wan6 别名重拨后不重建 → v6 前缀丢失

**现象**：LuCI 上 wan 接口 IPv6-PD 为空，`ipv6-prefix: []`，无 IPv6 默认路由；
`ip -6 addr show br-lan` 里残留 deprecated 的旧前缀。

**根因**：仅靠 `network.wan.ipv6='1'` 时 netifd 自动创建的动态 v6 别名接口
（日志显示为 wan6）在 PPPoE 重拨后不会重建，DHCPv6-PD 客户端随之失效。

**修复**（已在线上实施并持久化）：显式建 wan6 接口接管 DHCPv6-PD：

```sh
uci set network.wan6=interface
uci set network.wan6.device='@wan'
uci set network.wan6.proto='dhcpv6'
uci set network.wan6.reqaddress='try'
uci set network.wan6.reqprefix='auto'
uci delete network.wan.ip6assign        # PPPoE 上挂 ip6assign 无意义且碍事
uci set network.wan6.peerdns='0'        # 别把 ISP 的 v6 DNS 塞进 dnsmasq（会引入污染答案）
uci commit network
ifup wan6

# LAN 侧下发（否则客户端分不到 v6 地址）
uci set dhcp.lan.ra='server'
uci set dhcp.lan.dhcpv6='server'
uci set dhcp.lan.ra_default='1'
uci commit dhcp
uci add_list firewall.@zone[1].network='wan6'   # wan6 归入防火墙 wan zone
uci commit firewall
/etc/init.d/odhcpd restart
```

重启后 PD 自动重新获取（30 秒内拿到新 /60），LAN 客户端 SLAAC 秒拿地址。

## 附：geosite.dat 自动更新守护（2026-11-18 部署）

上游 Loyalsoldier **每日 22:04** 发版；routing 的 `fallback: direct` 意味着
dat 过期后新被墙站点会漏到直连（打不开），因此规则库必须保持新鲜。

- 固件出厂：构建时打入当时最新完整版（上面坑1的修复）
- 运行期：`/etc/daed-geosite-update.sh` 每周一 04:17 由 cron 拉最新版
  - 双下载源（jsdelivr 主 + ghfast 备）
  - md5 相同则跳过（幂等）；体积 <5MB 拒收
  - 替换后重启 daed，轮询等待 `Bind to WAN`（最多 45s）确认新规则加载成功
  - 加载失败自动回滚旧 dat 并重启
  - 并发锁带 PID 陈锁自愈
- 日志：`/var/log/geosite-update.log`；手动触发直接跑该脚本
- 注意：脚本在 `/etc/`（sysupgrade 保留），刷机后 cron 条目由
  uci-defaults 97-geosite-cron 自动重建

v1 脚本曾因健康检查用 `tail -60` 找 Bind，被启动初期刷屏的节点 ALIVE
日志挤出窗口造成误判回滚——v3 改为重启后日志全量 grep + 轮询。

---

## 坑4 [已修进 CI]：IPv6 前缀慢/无地址双坑——wan_6 崩溃循环 + wan6 缺 reqaddress

**日期**：2026-11-26 根治（SBE1V1K / IPQ9574 + 重庆电信 PPPoE，全程实机验证；坑3 的彻底版）

**现象**（v19.9d 实机）：
1. 刷机/重拨后 IPv6 前缀 2~16 分钟才拿到（波动），期间 wan6 一直 pending；
2. `logread` 里 `wan_6` 每秒 5 条 `setting up` + `ubus error: Invalid argument` 崩溃循环；
3. 前缀到手后 wan6 仍无 IPv6 地址（LuCI ipv6-address 空）。

**根因（两个独立坑，均为固件出厂内置）**：
- **坑A**：`config_generate` pppoe 分支给 wan 写 `ipv6='1'` → netifd 依此动态生成
  `wan_6`（与静态 wan6 只差一个下划线，LuCI 极易混淆）。该 handler 在 owrt 源码上
  无限崩溃重启，每次重启都向 BRAS 发起新 DHCPv6 会话抢前缀——br-lan 同期堆积 3 组
  不同租期 /60 即此症状，静态 wan6 被拖入反复重试（"很久"的直接原因）。
  **删掉该参数后 pppd 照常协商 IPv6CP**（LL 地址日志可见），实测拨号后 6 秒拿前缀。
- **坑B**：同一分支生成的 wan6 不带 `reqaddress` → odhcp6c 不带 `-Ntry` 启动；
  国内 BRAS 普遍只发 IA_PD 不发 IA_NA，WAN 侧地址靠 SLAAC 生成，odhcp6c 不请求
  就不上报地址 → wan6"拿到前缀却永远没地址"。补 `reqaddress='try'` 即时解决。

**坑3 的更正**：当时判为"动态 wan6 重拨后不重建"，实为 wan_6 handler 崩溃循环
（现象相似、机制不同）；坑3 的静态 wan6 方案正确并沿用，本坑补齐另两个根因。

**CI 修复（Settings.sh 尾部 + Scripts/inject/，2026-11-26）**：
1. 出厂层：`wan6-v6.sed` 修构建树 config_generate——删 pppoe 分支 `ipv6='1'`、
   dhcp/pppoe 双分支 wan6 补 `reqaddress='try'`；命中情况回显，未命中仅告警
   （lede 等他源结构漂移不阻断编译）。
2. 兜底层：`uci-defaults/96-wan6-ipv6-fix` 开机一次性强效——额外覆盖 sysupgrade
   恢复"带 wan.ipv6='1' 的旧备份"路径；wan6 非 dhcpv6 板卡守卫跳过。

**验收要点**（刷新固件首开后）：

```sh
logread | grep -c "wan_6.*setting up"   # 应为 0（不再生成 wan_6）
logread | grep "LL address"             # pppd 应有 local/remote LL（IPv6CP 正常）
ifstatus wan6 | grep -A2 ipv6-address   # 应有 240e: 开头的全局地址
```

**注意**：LuCI 里手动把 wan 的"Obtain IPv6 address"改成启用会写回 `ipv6='1'`，
等于手动复活坑A——保持自动即可（v6 客户端由静态 wan6 承担）。
