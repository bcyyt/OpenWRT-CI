#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

#修正 firewall4 镜像哈希：VIKINGYFY owrt 2026-11-11 批次 PKG_MIRROR_HASH 有误
#（70cbaec5 无法复现，官方镜像下载与 git 重生成实测均为 a95c6cfe），上游修复后此 sed 自动失效
sed -i 's/70cbaec533e7d635c00f5288a31a1d5d44cd43390d18c2df296e00079d1e4efe/a95c6cfe419c7d4e22bda5608aa6e46c67dadc9c7096879702d614cc498759d0/' ./package/network/config/firewall4/Makefile 2>/dev/null || true

#移除luci-app-attendedsysupgrade
find ./feeds/luci/collections/ -type f -name "Makefile" -exec sed -i "/attendedsysupgrade/d" {} +
#修改默认主题
find ./feeds/luci/collections/ -type f -name "Makefile" -exec sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" {} +
#修改immortalwrt.lan关联IP
find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js" -exec sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" {} +
#添加编译日期标识
find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js" -exec sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ $WRT_MARK-$WRT_DATE')/g" {} +

#修改默认WIFI账号密码
WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
ROUTER_TOOL="./package/emortal/luci-app-router-tool/root/etc/config/router-tool"
for file in "$ROUTER_TOOL" "$WIFI_UC"; do
        [ -f "$file" ] && sed -i "s/ssid '.*'/ssid '$WRT_SSID'/g; s/key '.*'/key '$WRT_WORD'/g" "$file"
done

CFG_FILE="./package/base-files/files/bin/config_generate"
#修改默认IP地址
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $CFG_FILE
#修改默认主机名
sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" $CFG_FILE

#===内核rmem_max按内存自适应：≤512MB→16M；≤1GB→32M；>1GB→64M===
#开机首次启动动态生成 /etc/sysctl.d/99-rmem.conf（字母序99最后生效，覆盖包内置的15-iptav-auth.conf下限值）
mkdir -p ./package/base-files/files/etc/uci-defaults
cat > ./package/base-files/files/etc/uci-defaults/99-rmemmax <<'RMEMMAX'
#!/bin/sh
MEM_KB=$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null)
[ -n "$MEM_KB" ] || exit 0
mkdir -p /etc/sysctl.d
if [ "$MEM_KB" -le 524288 ]; then
        RMEM=16777216
elif [ "$MEM_KB" -le 1048576 ]; then
        RMEM=33554432
else
        RMEM=67108864
fi
echo "net.core.rmem_max=$RMEM" > /etc/sysctl.d/99-rmem.conf
exit 0
RMEMMAX

#===自动挂载eMMC剩余分区为数据盘：mmcblk0p6(data) → /mnt/data===
#首次启动自动格式化并写入fstab；幂等：已挂载/已配置则跳过；绝不重格已有数据的分区
mkdir -p ./package/base-files/files/etc/uci-defaults
#===刷机保配置：daed/natfrp 数据目录进 sysupgrade 保留列表（幂等，开机自检）===
# LuCI 保存配置时会重写 sysupgrade.conf 洗掉非包声明行，故开机每次自检补齐
mkdir -p ./package/base-files/files/etc/uci-defaults
cat > ./package/base-files/files/etc/uci-defaults/99-keep-confs <<'KEEPCONF'
#!/bin/sh
# 去掉存在性检查：首启时 /etc/natfrp 尚未生成也要先写入保留清单
#（sysupgrade 对缺失路径自动跳过，natfrp 配置好后的下一次升级即受保护；2026-11-20 实际翻车点）
for f in /etc/config/daed /etc/config/natfrp /etc/daed /etc/natfrp /etc/statusflow /etc/statusmon; do
        grep -qxF "$f" /etc/sysupgrade.conf 2>/dev/null || echo "$f" >> /etc/sysupgrade.conf
done
exit 0
KEEPCONF

cat > ./package/base-files/files/etc/uci-defaults/99-datadisk <<'DATADISK'
#!/bin/sh
#机型守卫（2026-11-21）：p6 预留数据分区仅 SuperGateway S20 系列成立；
#SBE1V1K(IPQ9574) eMMC 为 OEM 多分区布局（p1..p27+），误格 p6 会毁厂商分区
case "$(cat /tmp/sysinfo/board_name 2>/dev/null)" in
        supergateway,s20*) ;;
        *) exit 0 ;;
esac
DEV="/dev/mmcblk0p6"
MNT="/mnt/data"
[ -b "$DEV" ] || exit 0
mkdir -p "$MNT"
UUID=$(blkid -s UUID -o value "$DEV" 2>/dev/null)
if [ -z "$UUID" ]; then
        command -v mkfs.ext4 >/dev/null 2>&1 || exit 0
        mount | grep -q " on $MNT " && exit 0
        mkfs.ext4 -L data "$DEV" >/dev/null 2>&1 || exit 0
        UUID=$(blkid -s UUID -o value "$DEV" 2>/dev/null)
        [ -n "$UUID" ] || exit 0
fi
# 已配置 = 存在 enabled=1 且 target=$MNT 的条目（不能只按 uuid 去重：
# block detect 也会生成同 uuid 的 enabled=0 条目，裸 uuid 匹配会被骗过 → 数据盘双挂载）
_ok=0
_i=0
while uci -q get fstab.@mount[$_i] >/dev/null 2>&1; do
        [ "$(uci -q get fstab.@mount[$_i].target)" = "$MNT" ] && [ "$(uci -q get fstab.@mount[$_i].enabled)" = "1" ] && _ok=1
        _i=$((_i+1))
done
if [ "$_ok" = "0" ]; then
        touch /etc/config/fstab
        uci -q batch <<UCI >/dev/null 2>&1
add fstab mount
set fstab.@mount[-1].target='$MNT'
set fstab.@mount[-1].uuid='$UUID'
set fstab.@mount[-1].enabled='1'
commit fstab
UCI
fi
# fstab 修复完成后，已挂载即可收工（下次开机由 blockd 正式认领，不再匿名双挂）
mount | grep -q " on $MNT " && exit 0
block mount >/dev/null 2>&1
mount | grep -q " on $MNT " || mount "$DEV" "$MNT" 2>/dev/null
exit 0
DATADISK


#===DNS 上游固化（2026-11-19）：dnsmasq → AliDNS 双上游并发 + 大缓存，开机首启/升级后自动生效===
# 注：daed 对 53 端口仅计数放行（不劫持不代理），DNS 全链路走 dnsmasq → AliDNS 直连
# 选项名依据固件源码 dnsmasq.init 校验：noresolv/allservers/cachesize/min_cache_ttl/nonegcache 均有效
# use_stale_cache 已删：init 脚本无此 uci 映射（stale-cache 需 conf-dir 逃生通道，暂不做）
cat > ./package/base-files/files/etc/uci-defaults/99-dns-tune <<'DNSTUNE'
#!/bin/sh
uci -q batch <<UCI >/dev/null 2>&1
delete dhcp.@dnsmasq[0].server
delete dhcp.@dnsmasq[0].noresolvers
add_list dhcp.@dnsmasq[0].server='223.5.5.5'
add_list dhcp.@dnsmasq[0].server='223.6.6.6'
set dhcp.@dnsmasq[0].noresolv='1'
set dhcp.@dnsmasq[0].allservers='1'
set dhcp.@dnsmasq[0].cachesize='8000'
set dhcp.@dnsmasq[0].min_cache_ttl='3600'
set dhcp.@dnsmasq[0].nonegcache='1'
commit dhcp
UCI
exit 0
DNSTUNE

#===NTP 时间源统一阿里云（2026-11-20）：cn.ntp.org.cn 被 dnsmasq rebind 防护拦截，时间同步反复失败===
# 顺带消掉每 4 分钟一次的 DNS-rebind 告警噪音；uci-defaults 首启/升级后自动生效
cat > ./package/base-files/files/etc/uci-defaults/99-ntp-aliyun <<'NTPALI'
#!/bin/sh
uci -q batch <<UCI >/dev/null 2>&1
delete system.ntp.server
add_list system.ntp.server='ntp.aliyun.com'
add_list system.ntp.server='ntp1.aliyun.com'
add_list system.ntp.server='ntp2.aliyun.com'
commit system
UCI
exit 0
NTPALI

#===daed 防DNS投毒路由工具（2026-11-19）：8.8.8.8 DNS 走代理 + dnsmasq 不再豁免劫持===
# 现网已生效；/etc/daed 在 sysupgrade 保留清单内，仅全新安装/重置 daed 后需手动跑一次：
#   daed-routing-tune
mkdir -p ./package/base-files/files/usr/bin
cat > ./package/base-files/files/usr/bin/daed-routing-tune <<'TUNE'
#!/bin/sh
# daed 路由防投毒调优：dip(8.8.8.8,8.8.4.4)->proxy 置顶 + dnsmasq 移出 must_direct 豁免
python3 - <<'PY' || exit 1
import sqlite3, subprocess, sys, time
DB = '/etc/daed/wing.db'
NEW = (
    "routing {\n"
    "dip(8.8.8.8, 8.8.4.4) -> proxy\n"
    "pname(NetworkManager, systemd-resolved, natfrp-frpc) -> must_direct\n"
    "dip(geoip:private) -> direct\n"
    "domain(geosite:gfw) -> proxy\n"
    "fallback: direct\n"
    "}"
)
try:
    import sqlite3 as s
except ImportError:
    print('缺 python3-sqlite3，请先安装：apk add python3-sqlite3（或 opkg）'); sys.exit(1)
def sh(c): return subprocess.run(c, shell=True, capture_output=True, text=True, timeout=90)
def pid(): return sh("pgrep -f 'daed run' | head -1").stdout.strip()
try:
    db = s.connect('file:%s?mode=ro' % DB, uri=True)
    row = db.execute('SELECT routing FROM routings WHERE selected=1').fetchone()
    db.close()
    if row and row[0].strip() == NEW.strip():
        print('路由已是目标配置，无需修改'); sys.exit(0)
except Exception as e:
    print('读取 daed 配置库失败(%s)：请先启动一次 daed 再运行本工具' % e); sys.exit(1)
sh('/etc/init.d/daed stop; sleep 2')
if pid():
    sh('pkill -f "daed run"; sleep 3')
db = s.connect(DB)
db.execute('UPDATE routings SET routing=?, version=version+1 WHERE selected=1', (NEW,))
db.commit(); db.close()
sh('/etc/init.d/daed start'); time.sleep(5)
ok = bool(pid())
print('daed ' + ('防投毒路由已应用，运行中' if ok else '启动失败！请检查 /etc/init.d/daed'))
sys.exit(0 if ok else 1)
PY
TUNE
chmod +x ./package/base-files/files/usr/bin/daed-routing-tune

#配置文件修改
echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-$WRT_THEME=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-$WRT_THEME-config=y" >> ./.config

#===仪表盘/代理运行时包固化（2026-11-17）：原依赖 workflow_dispatch 手动输入 PACKAGE，不输入即丢失===
# 仅 MEDIATEK-WIFI-*（VIKINGYFY 源，无 statusfw）；2026-11-21: IPQ95XX（SBE1V1K）线并入
# 2026-11-19: S20P-612 线（Argon）Vantage 主题件（zte-wifi 等）维持取消；
#   状态监控以"原生独立页面"方案恢复——luci-app-statusmon-dash 全功能仪表盘页
# 2026-11-19: CS 线已整体下线删除（workflow + Config）
case "$WRT_CONFIG" in
  MEDIATEK-WIFI-*|IPQ95XX)
        echo "CONFIG_PACKAGE_luci-app-statusmon=y" >> ./.config
        echo "CONFIG_PACKAGE_zte-wifi=y" >> ./.config
        # 2026-11-18: daed 全面接管代理，openclash 移出固件（运行时也可 apk del）
        ;;
  MEDIATEK-S20P-*)
        echo "CONFIG_PACKAGE_luci-app-statusmon-dash=y" >> ./.config
        ;;
esac

#===IPQ95XX-WIFI-NO（SBE1V1K 纯有线线，2026-11-21）：完整剥离无线栈===
#仪表盘保留（有线侧监控全功能）；2026-11-23: zte-wifi 改为编入——本机虽无无线，
#但 ZTE mesh AP 经有线上联，守护走网络（ZXSLC）拉取 mesh 节点的无线客户端/拓扑，
#纯有线线同样有数据；未配置 zte-wifi 时守护自动休眠无副作用
case "$WRT_CONFIG" in
  IPQ95XX-WIFI-NO|LEDE-IPQ95XX-WIFI-NO)
        #2026-11-21: LEDE 纯有线线并入（无线剥离逻辑同源，lede ipq95xx.mk 设备定义与 owrt 一字不差）
        #仪表盘后端按主题门控：bootstrap 非 v 主题线不编入 statusmon（同 2026-11-21 LEDE 决策）
        if [ "$WRT_THEME" = "vantage" ]; then
                echo "CONFIG_PACKAGE_luci-app-statusmon=y" >> ./.config
        fi
        echo "CONFIG_PACKAGE_zte-wifi=y" >> ./.config
        #设备定义剥无线包：ath12k 固件 blob + 校准数据。
        #DEVICE_PACKAGES 是镜像级依赖，config 负选项拦不住，必须改 .mk；
        #保留风扇/LED/RTL8261 万兆 PHY 四件套
        [ -f target/linux/qualcommbe/image/ipq95xx.mk ] && sed -i \
                '/^define Device\/askey_sbe1v1k$/,/^endef$/{
                        s/ipq-wifi-askey_sbe1v1k //g
                        s/ath12k-firmware-qcn9274-ddwrt //g
                }' target/linux/qualcommbe/image/ipq95xx.mk
        #双保险：防止固件/校准包从其它依赖链回流
        echo "CONFIG_PACKAGE_ath12k-firmware-qcn9274-ddwrt=n" >> ./.config
        echo "CONFIG_PACKAGE_ipq-wifi-askey_sbe1v1k=n" >> ./.config
        ;;
esac

#===SBE1V1K 升级脚本布局自适应（2026-11-22）：LuCI sysupgrade 双布局安全===
#背景: 原生/mainline 布局内核窗仅 7MiB, V大源系内核 7.59MiB 超窗 → LuCI 直刷必截断软砖;
#     固化大分区(large, v4.0 工具)后有 32MiB kernel 分区
#补丁: CI_KERNPART 优先取 GPT 标签 kernel(large 布局 P28, 32MiB 窗);
#     无 kernel 标签(find_mmc_part 精确匹配, 原生/mainline 布局)回退 0:HLOS = 原行为不变
#生效: 刷了本补丁版固件后, large 布局上 LuCI 网页/sysupgrade 命令均安全可用
python3 - <<'PYEOF' || echo "[警告] platform.sh 补丁未命中(上游结构变了?), 请人工检查升级路径!"
import sys
p = 'target/linux/qualcommbe/ipq95xx/base-files/lib/upgrade/platform.sh'
try:
    s = open(p).read()
except FileNotFoundError:
    sys.exit(0)  # 非 qualcommbe/ipq95xx 构建, 静默跳过
old = '''\tarista,c-460|\\
\taskey,sbe1v1k)
\t\tCI_KERNPART="0:HLOS"
\t\tCI_ROOTPART="rootfs"'''
new = '''\tarista,c-460|\\
\taskey,sbe1v1k)
\t\tCI_KERNPART="kernel"
\t\t[ -z "$(find_mmc_part kernel)" ] && CI_KERNPART="0:HLOS"
\t\tCI_ROOTPART="rootfs"'''
if old in s:
    open(p, 'w').write(s.replace(old, new, 1))
    print('SBE1V1K platform.sh 布局自适应补丁 OK: kernel标签优先 / 0:HLOS回退')
elif 'find_mmc_part kernel' in s:
    print('platform.sh 已含布局自适应补丁, 幂等跳过')
else:
    sys.exit(1)
PYEOF

#===daede 前端切换（2026-11-19）：S20P-612 + WIFI-618 两线 daed 包源已在 Packages.sh 替换为 kenzok8/openwrt-daede===
#官方 luci-app-daed 关闭防双管理，改用 luci-app-daede（UCI 统一管 dae/daed，可热切换）
case "$WRT_CONFIG" in
  MEDIATEK-S20P-*|MEDIATEK-WIFI-*)
        echo "CONFIG_PACKAGE_luci-app-daed=n" >> ./.config
        echo "CONFIG_PACKAGE_luci-app-daede=y" >> ./.config
        ;;
esac

#===LEDE mac80211 sockaddr_unsized 修复 v2（2026-11-22，run#3-#6 根因终判）===
#内核 stable 在 6.18.61+ 把 sockaddr_unsized 从 include/linux/socket.h 回退
#（实测 v6.18.60 有 / v6.18.64 无，文件小 674B）。lede 的 160 补丁 guard
#<6.18.57 是为 .57-.60 时代写的（内核自带类型），在 6.18.64 上它把 backports
#自己的定义也编译掉→类型凭空消失→net.h 垫片原型作用域→qmi.c 类型不匹配
#-Werror 致命。V大树 6.18.60 构建成功正因为未踩回退。修法：移除 lede 的
#160，让 backports 原生 <6.19 guard 提供定义（6.18.64 内核侧无此类型，
#零重定义风险）。
case "$WRT_SOURCE" in
  coolsnowwolf/lede)
        rm -f package/kernel/mac80211/patches-qualcommbe/build/160-backports-sockaddr_unsized-is-in-6.18.57.patch
        echo "lede: 已移除 160 补丁（6.18.61+ 内核回退了 sockaddr_unsized，该补丁反而致命）"
        # samba4 全家禁用（run#8 WIFI-NO 腿：lede 默认包集带入 samba4-server 4.24.6，
        # pidl 在新 perl 下解析 smbXsrv.idl 报 Unable to determine origin of type，
        # package/install Error 255。SBE1V1K 作 IPTV 路由器无需 samba。）
        echo "CONFIG_PACKAGE_samba4-server=n" >> ./.config
        echo "CONFIG_PACKAGE_samba4-client=n" >> ./.config
        echo "CONFIG_PACKAGE_luci-app-samba4=n" >> ./.config
        echo "lede: samba4 全家已禁用（默认带入且 pidl 编译失败）"
        # 金丝雀 v2：defconfig 后 V=s 单包预编 prepare（解包+补丁+kconfig），
        # 失败即熔断（exit 1），15 分钟暴露问题，省 3 小时陪葬编译。
        make defconfig -j1 >/dev/null 2>&1
        if ! make package/kernel/mac80211/prepare V=s -j1 > /tmp/m82.log 2>&1; then
                echo "⚠️ mac80211 canary prepare 失败 —— 诊断输出（尾部120行）："
                tail -n 120 /tmp/m82.log
                echo "⚠️ canary 熔断：补丁链存在未修复问题，中止构建"
                exit 1
        else
                echo "✓ mac80211 canary prepare 通过（补丁链健康）"
        fi
        ;;
esac

#===irq-tune（MT7988 以太网中断分核 + TX XPS，2026-11-18）：WIFI/CS 两线通用，包内自带 rc.d 自启===
case "$WRT_CONFIG" in
  MEDIATEK-*)
        echo "CONFIG_PACKAGE_irq-tune=y" >> ./.config
        ;;
esac

#引入私有扩展配置
if [ -f "$GITHUB_WORKSPACE/Config/PRIVATE.txt" ]; then
        echo "Applying private configurations from PRIVATE.txt..."
        cat $GITHUB_WORKSPACE/Config/PRIVATE.txt >> ./.config
fi

#手动调整的插件
if [ -n "$WRT_PACKAGE" ]; then
        echo -e "$WRT_PACKAGE" >> ./.config
fi

#高通平台调整
DTS_PATH="./target/linux/qualcommax/dts/"
if [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* ]]; then
        #无WIFI配置调整Q6大小
        if [[ "$WRT_WIFI" == "WIFI-NO" ]]; then
                find $DTS_PATH -type f ! -iname '*nowifi*' -exec sed -i 's/ipq\(6018\|8074\).dtsi/ipq\1-nowifi.dtsi/g' {} +
                echo "qualcommax set up nowifi successfully!"
        fi
fi

#dae eBPF kernel support stack (kmod-sched-bpf/kmod-xdp-sockets-diag/kmod-veth + BTF)
#2026-11-19: 按源码树实际内核版本自适应（VIKINGYFY@owrt=6.18 / chasey-dev@25.12=6.12，daede 需 BTF）
KCF=$(ls -1 target/linux/mediatek/filogic/config-6.* 2>/dev/null | sort -V | tail -1)
KCF=${KCF:-target/linux/mediatek/filogic/config-6.18}
if ! grep -q "^CONFIG_BPF_SYSCALL=y" $KCF 2>/dev/null; then
cat >> $KCF <<'BPFEO'
CONFIG_BPF=y
CONFIG_BPF_SYSCALL=y
CONFIG_BPF_JIT=y
CONFIG_BPF_UNPRIV_DEFAULT_OFF=y
CONFIG_CGROUP_BPF=y
CONFIG_NET_SCHED=y
CONFIG_NET_CLS_BPF=y
CONFIG_NET_CLS_ACT=y
CONFIG_XDP_SOCKETS=y
CONFIG_XDP_SOCKETS_DIAG=y
CONFIG_VETH=y
CONFIG_DEBUG_INFO=y
# CONFIG_DEBUG_INFO_REDUCED is not set
CONFIG_DEBUG_INFO_BTF=y
BPFEO
fi

#===qualcommbe CMA 提至 256MB（2026-11-22，恩山 gubin_nt 实测）===
#ath12k 三颗 QCN9274 经 dma_alloc_coherent 各需 ~28MB 连续内存（合计 ~241MB），
#尺寸不足时 probe 报 qmi dma allocation failed → 无线全灭。实测两树现状：
#V大树 config-6.18 自带 CMA 栈但 SIZE=128MB、lede 只有 64MB（#12 守卫只查
#CONFIG_CMA=y 存在性而误跳过，实为尺寸问题）。此为内核层配置，须改
#target/linux/qualcommbe/config-6.* 分片（种子 .config 里 raw 键会被丢弃）。
QCCF=$(ls -1 target/linux/qualcommbe/config-6.* 2>/dev/null | sort -V | tail -1)
if [ -n "$QCCF" ] && ! grep -q "^CONFIG_CMA_SIZE_MBYTES=256" "$QCCF"; then
        if grep -q "^CONFIG_CMA_SIZE_MBYTES=" "$QCCF"; then
                sed -i 's/^CONFIG_CMA_SIZE_MBYTES=.*/CONFIG_CMA_SIZE_MBYTES=256/' "$QCCF"
        else
                sed -i '/^CONFIG_CMA=y/a CONFIG_DMA_CMA=y\nCONFIG_CMA_SIZE_MBYTES=256\nCONFIG_CMA_SIZE_SEL_MBYTES=y' "$QCCF"
        fi
        echo "qualcommbe: CMA 提至 256MB → $QCCF（gubin 实测三颗 QCN9274 需 ~241MB）"
fi


#===RTL8261BE 10G PHY LED（2026-11-22，移植自 OneNAS auto-gen 743 补丁）===
#SBE1V1K 的 10G 口 PHY = RTL8261BE，上游 realtek 驱动 ID 表无 LED ops → 10G 灯死。
#V大 751 系只覆盖 RTL8221B/RTL8226B-CG；743 的目标表项（RTL8254B/8261BE/N/
#8264/8264B）与其零重叠、hunk 区域零重叠，可安全叠加。phylib 硬件灯路线：
#驱动 ops 自动注册，无需 DTS 改动。守卫以 V大树 751-03 为血统标记，他树跳过。
if [ -f target/linux/generic/hack-6.18/751-03-net-phy-realtek-enable-RTL8226B-CG-hardware-LEDs.patch ] \
   && [ ! -f target/linux/generic/hack-6.18/743-net-phy-realtek-add-rtl826x-led-support.patch ]; then
cat > target/linux/generic/hack-6.18/743-net-phy-realtek-add-rtl826x-led-support.patch <<'RTL826XLED'
--- a/drivers/net/phy/realtek/realtek_main.c
+++ b/drivers/net/phy/realtek/realtek_main.c
@@ -3811,6 +3811,133 @@ static int rtl826x_set_tunable(struct phy_device *phydev,
        return 0;
 }
 
+/* Per-LED mode register pair: link-speed qualifier (L) and flags (H) */
+#define RTL826X_LED_L(n)               (21 + (n) * 2)
+#define RTL826X_LED_L_100M             BIT(8)
+#define RTL826X_LED_L_500M             BIT(7)
+#define RTL826X_LED_L_1G               BIT(6)
+#define RTL826X_LED_L_2P5G             BIT(4)
+#define RTL826X_LED_L_5G               BIT(2)
+#define RTL826X_LED_L_10G              BIT(0)
+#define RTL826X_LED_L_LINK_MASK                (RTL826X_LED_L_100M | \
+                                        RTL826X_LED_L_500M | \
+                                        RTL826X_LED_L_1G | \
+                                        RTL826X_LED_L_2P5G | \
+                                        RTL826X_LED_L_5G | \
+                                        RTL826X_LED_L_10G)
+
+#define RTL826X_LED_H(n)               (22 + (n) * 2)
+#define RTL826X_LED_H_LINK_EN          BIT(9)
+#define RTL826X_LED_H_TX_ACT           BIT(3)
+#define RTL826X_LED_H_RX_ACT           BIT(2)
+
+#define RTL826X_LED_NUM                        6
+
+static const unsigned long rtl826x_led_rules =
+       BIT(TRIGGER_NETDEV_LINK) |
+       BIT(TRIGGER_NETDEV_LINK_100) |
+       BIT(TRIGGER_NETDEV_LINK_1000) |
+       BIT(TRIGGER_NETDEV_LINK_2500) |
+       BIT(TRIGGER_NETDEV_LINK_5000) |
+       BIT(TRIGGER_NETDEV_LINK_10000) |
+       BIT(TRIGGER_NETDEV_RX) |
+       BIT(TRIGGER_NETDEV_TX);
+
+static int rtl826x_led_hw_is_supported(struct phy_device *phydev, u8 index,
+                                      unsigned long rules)
+{
+       if (index >= RTL826X_LED_NUM)
+               return -EINVAL;
+
+       if (rules & ~rtl826x_led_rules)
+               return -EOPNOTSUPP;
+
+       return 0;
+}
+
+static int rtl826x_led_hw_control_get(struct phy_device *phydev, u8 index,
+                                     unsigned long *rules)
+{
+       int l, h;
+
+       if (index >= RTL826X_LED_NUM)
+               return -EINVAL;
+
+       l = phy_read_mmd(phydev, MDIO_MMD_VEND1, RTL826X_LED_L(index));
+       if (l < 0)
+               return l;
+
+       h = phy_read_mmd(phydev, MDIO_MMD_VEND1, RTL826X_LED_H(index));
+       if (h < 0)
+               return h;
+
+       *rules = 0;
+
+       /* Speed qualifiers only drive the LED with the link enable set */
+       if (!(h & RTL826X_LED_H_LINK_EN)) {
+               l = 0;
+       } else if ((l & RTL826X_LED_L_LINK_MASK) == RTL826X_LED_L_LINK_MASK) {
+               *rules |= BIT(TRIGGER_NETDEV_LINK);
+               l = 0;
+       }
+
+       if (l & RTL826X_LED_L_100M)
+               *rules |= BIT(TRIGGER_NETDEV_LINK_100);
+       if (l & RTL826X_LED_L_1G)
+               *rules |= BIT(TRIGGER_NETDEV_LINK_1000);
+       if (l & RTL826X_LED_L_2P5G)
+               *rules |= BIT(TRIGGER_NETDEV_LINK_2500);
+       if (l & RTL826X_LED_L_5G)
+               *rules |= BIT(TRIGGER_NETDEV_LINK_5000);
+       if (l & RTL826X_LED_L_10G)
+               *rules |= BIT(TRIGGER_NETDEV_LINK_10000);
+
+       if (h & RTL826X_LED_H_RX_ACT)
+               *rules |= BIT(TRIGGER_NETDEV_RX);
+       if (h & RTL826X_LED_H_TX_ACT)
+               *rules |= BIT(TRIGGER_NETDEV_TX);
+
+       return 0;
+}
+
+static int rtl826x_led_hw_control_set(struct phy_device *phydev, u8 index,
+                                     unsigned long rules)
+{
+       u16 l = 0, h = 0;
+       int ret;
+
+       if (index >= RTL826X_LED_NUM)
+               return -EINVAL;
+
+       if (rules & BIT(TRIGGER_NETDEV_LINK))
+               l |= RTL826X_LED_L_LINK_MASK;
+       if (rules & BIT(TRIGGER_NETDEV_LINK_100))
+               l |= RTL826X_LED_L_100M;
+       if (rules & BIT(TRIGGER_NETDEV_LINK_1000))
+               l |= RTL826X_LED_L_1G;
+       if (rules & BIT(TRIGGER_NETDEV_LINK_2500))
+               l |= RTL826X_LED_L_2P5G;
+       if (rules & BIT(TRIGGER_NETDEV_LINK_5000))
+               l |= RTL826X_LED_L_5G;
+       if (rules & BIT(TRIGGER_NETDEV_LINK_10000))
+               l |= RTL826X_LED_L_10G;
+
+       /* Link rules only light the LED with the enable flag set */
+       if (l)
+               h |= RTL826X_LED_H_LINK_EN;
+
+       if (rules & BIT(TRIGGER_NETDEV_RX))
+               h |= RTL826X_LED_H_RX_ACT;
+       if (rules & BIT(TRIGGER_NETDEV_TX))
+               h |= RTL826X_LED_H_TX_ACT;
+
+       ret = phy_write_mmd(phydev, MDIO_MMD_VEND1, RTL826X_LED_L(index), l);
+       if (ret < 0)
+               return ret;
+
+       return phy_write_mmd(phydev, MDIO_MMD_VEND1, RTL826X_LED_H(index), h);
+}
+
 static struct phy_driver realtek_drvs[] = {
        {
                PHY_ID_MATCH_EXACT(0x00008201),
@@ -4178,6 +4305,9 @@ static struct phy_driver realtek_drvs[] = {
                .get_wol        = rtl826x_get_wol,
                .get_tunable    = rtl826x_get_tunable,
                .set_tunable    = rtl826x_set_tunable,
+               .led_hw_is_supported = rtl826x_led_hw_is_supported,
+               .led_hw_control_get = rtl826x_led_hw_control_get,
+               .led_hw_control_set = rtl826x_led_hw_control_set,
        }, {
                .name           = "RTL8254B 5Gbps PHY",
                .config_init    = rtl826x_config_init,
@@ -4195,6 +4325,9 @@ static struct phy_driver realtek_drvs[] = {
                .get_wol        = rtl826x_get_wol,
                .get_tunable    = rtl826x_get_tunable,
                .set_tunable    = rtl826x_set_tunable,
+               .led_hw_is_supported = rtl826x_led_hw_is_supported,
+               .led_hw_control_get = rtl826x_led_hw_control_get,
+               .led_hw_control_set = rtl826x_led_hw_control_set,
        }, {
                .name           = "RTL8261BE 10Gbps PHY",
                .config_init    = rtl826x_config_init,
@@ -4213,6 +4346,9 @@ static struct phy_driver realtek_drvs[] = {
                .get_wol        = rtl826x_get_wol,
                .get_tunable    = rtl826x_get_tunable,
                .set_tunable    = rtl826x_set_tunable,
+               .led_hw_is_supported = rtl826x_led_hw_is_supported,
+               .led_hw_control_get = rtl826x_led_hw_control_get,
+               .led_hw_control_set = rtl826x_led_hw_control_set,
        }, {
                .name           = "RTL8261N 10Gbps PHY",
                .config_init    = rtl826x_config_init,
@@ -4231,6 +4367,9 @@ static struct phy_driver realtek_drvs[] = {
                .get_wol        = rtl826x_get_wol,
                .get_tunable    = rtl826x_get_tunable,
                .set_tunable    = rtl826x_set_tunable,
+               .led_hw_is_supported = rtl826x_led_hw_is_supported,
+               .led_hw_control_get = rtl826x_led_hw_control_get,
+               .led_hw_control_set = rtl826x_led_hw_control_set,
        }, {
                PHY_ID_MATCH_EXACT(RTL_8264),
                .name           = "RTL8264 10Gbps PHY",
@@ -4248,6 +4387,9 @@ static struct phy_driver realtek_drvs[] = {
                .get_wol        = rtl826x_get_wol,
                .get_tunable    = rtl826x_get_tunable,
                .set_tunable    = rtl826x_set_tunable,
+               .led_hw_is_supported = rtl826x_led_hw_is_supported,
+               .led_hw_control_get = rtl826x_led_hw_control_get,
+               .led_hw_control_set = rtl826x_led_hw_control_set,
        }, {
                .name           = "RTL8264B 10Gbps PHY",
                .config_init    = rtl826x_config_init,
@@ -4265,6 +4407,9 @@ static struct phy_driver realtek_drvs[] = {
                .get_wol        = rtl826x_get_wol,
                .get_tunable    = rtl826x_get_tunable,
                .set_tunable    = rtl826x_set_tunable,
+               .led_hw_is_supported = rtl826x_led_hw_is_supported,
+               .led_hw_control_get = rtl826x_led_hw_control_get,
+               .led_hw_control_set = rtl826x_led_hw_control_set,
        },
 };
 
RTL826XLED
KDIR=$(ls -d build_dir/target-*/linux-qualcommbe_ipq95xx/linux-6.18* 2>/dev/null | head -1)
if [ -n "$KDIR" ]; then
  rm -rf "$KDIR"
  echo "RTL8261 10G PHY LED 补丁已注入（hack-6.18/743）+ 内核目录已重置（强制重打补丁链，防缓存跳过）"
else
  echo "RTL8261 10G PHY LED 补丁已注入（hack-6.18/743，10G 灯激活）"
fi
fi
