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

## 坑4 [已修进 CI]：wan6 开机拿不到 IPv6——netifd 开机竞态（固件 bug，自愈兜底）

**日期**：2026-11-27（SBE1V1K / IPQ9574 + 重庆电信 PPPoE，实机验证）

**现象**：刷机/重启后 wan6 长时间拿不到前缀与地址；隔一会儿再查"又有了"——
这不是玄学，是自愈脚本的窗口期（约 1 分钟内）。

**根因**（固件 bug，上游 netifd 竞态，本仓库不做源码修复、保持出厂形态）：
wan ifup 高峰期（拨号完成瞬间）启动的 DHCPv6 接口，其 proto notify 撞上
尚未就绪的 netifd proto 状态机 → `ubus error: Invalid argument` → 接口
setup 失败被 disabled。netifd 稳定后重拉同一接口则 100% 成功（实机多轮
对照验证：手动慢速路径创建 100% 成功，开机自动路径撞竞态必挂）。

**修复**（自愈兜底，实机验证有效）：`/etc/hotplug.d/iface/99-wan6-retry`
wan ifup 后每 30s 检查 wan6 状态，未 up 则 ifdown/ifup 重拉，最多 6 次
（间隔 2s），带 PID 锁防并发，全程约 1 分钟内自动完成。不改变任何出厂
配置与行为，根因留给上游修。

**验收要点**（刷新固件首开后，等 1~2 分钟）：

```sh
logread | grep wan6-retry            # 重试路径应见 "retry 1/6" 后止步；顺利则见 "already up"
ubus call network.interface.wan6 status | grep '"up"'    # 应为 true
ifstatus wan6 | grep -A2 ipv6-address                    # 应有 240e: 全局地址
```

---

## 坑6 [已修进 CI]：手机登录页 footer 遮挡密码输入框——键盘弹起时叠压

**日期**：2026-11-27（SBE1V1K / Argon 主题，Playwright 手机视口实测定位）

**现象**：手机访问登录页，点密码框弹起键盘后，"Powered by LuCI Master..."
页脚叠在密码输入框上，影响输入；桌面端无此问题。

**根因**（主题 CSS 设计缺陷，非固件 bug）：
- 登录页 footer `position:absolute; bottom:0` 钉死在视口底部
- Android 键盘弹起会压缩视口高度（实测 667→400px），footer 跟着视口底上移，
  正好压住密码框（实测重叠 y=334~400 vs 密码框 294~335）
- 主题自带的 resize 补偿脚本查询 `.ftc`，但登录页 HTML 根本没有该元素——
  空操作，从未生效

**修复**（Packages.sh 追加 CSS，不删文字）：
```css
@media (max-width:600px) and (max-height:520px){ .login-page footer{display:none!important} }
@media (max-width:600px){ .login-page footer{pointer-events:none} }
```
键盘弹起（视口被压缩）时 footer 让位隐藏，键盘收起立即恢复显示；
平时 pointer-events:none 保证任何情况下不拦截输入框点击。
"Powered by" 文字在桌面端与手机端平时均正常保留。

**验收要点**（Playwright 四视口全过）：
- 375x667 普通手机：footer 可见、密码框可点击、无重叠
- 375x400 / 360x350 键盘弹起：footer 自动隐藏、密码框可点击
- 390x844 iPhone14：footer 可见、无重叠
