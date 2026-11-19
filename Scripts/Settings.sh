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
for f in /etc/config/daed /etc/config/natfrp /etc/daed /etc/natfrp; do
        [ -e "$f" ] || continue
        grep -qxF "$f" /etc/sysupgrade.conf 2>/dev/null || echo "$f" >> /etc/sysupgrade.conf
done
exit 0
KEEPCONF

cat > ./package/base-files/files/etc/uci-defaults/99-datadisk <<'DATADISK'
#!/bin/sh
DEV="/dev/mmcblk0p6"
MNT="/mnt/data"
[ -b "$DEV" ] || exit 0
mkdir -p "$MNT"
mount | grep -q " on $MNT " && exit 0
UUID=$(blkid -s UUID -o value "$DEV" 2>/dev/null)
if [ -z "$UUID" ]; then
        command -v mkfs.ext4 >/dev/null 2>&1 || exit 0
        mkfs.ext4 -L data "$DEV" >/dev/null 2>&1 || exit 0
        UUID=$(blkid -s UUID -o value "$DEV" 2>/dev/null)
        [ -n "$UUID" ] || exit 0
fi
if ! uci -q show fstab 2>/dev/null | grep -q "$UUID"; then
        touch /etc/config/fstab
        uci -q batch <<UCI >/dev/null 2>&1
add fstab mount
set fstab.@mount[-1].target='$MNT'
set fstab.@mount[-1].uuid='$UUID'
set fstab.@mount[-1].enabled='1'
commit fstab
UCI
fi
block mount >/dev/null 2>&1
mount | grep -q " on $MNT " || mount "$DEV" "$MNT" 2>/dev/null
exit 0
DATADISK


#===DNS 上游固化（2026-11-19）：dnsmasq → AliDNS 双上游并发 + 大缓存，开机首启/升级后自动生效===
# 注：daed 在跑时 dnsmasq 上游仅作兜底（dae 劫持分流），daed 停机时直接走 223.5.5.5/223.6.6.6
cat > ./package/base-files/files/etc/uci-defaults/99-dns-tune <<'DNSTUNE'
#!/bin/sh
uci -q batch <<UCI >/dev/null 2>&1
delete dhcp.@dnsmasq[0].server
add_list dhcp.@dnsmasq[0].server='223.5.5.5'
add_list dhcp.@dnsmasq[0].server='223.6.6.6'
set dhcp.@dnsmasq[0].noresolv='1'
set dhcp.@dnsmasq[0].allservers='1'
set dhcp.@dnsmasq[0].cachesize='8000'
set dhcp.@dnsmasq[0].min_cache_ttl='3600'
set dhcp.@dnsmasq[0].use_stale_cache='3600'
set dhcp.@dnsmasq[0].nonegcache='1'
commit dhcp
UCI
exit 0
DNSTUNE

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
# 仅 MEDIATEK-WIFI-*（VIKINGYFY 源，无 statusfw）；CS 线 statusfw 自带 statusmon 系组件，跳过防文件冲突
# 2026-11-19: S20P-612 线（Argon）取消全部主题注入件——statusmon/zte-wifi 的展示层原绑 Vantage 仪表盘，
# Argon 下无效且数据裸奔，待后续以"原生独立页面"方案重做后再启用
case "$WRT_CONFIG" in
  MEDIATEK-WIFI-*)
        echo "CONFIG_PACKAGE_luci-app-statusmon=y" >> ./.config
        echo "CONFIG_PACKAGE_zte-wifi=y" >> ./.config
        # 2026-11-18: daed 全面接管代理，openclash 移出固件（运行时也可 apk del）
        ;;
esac

#===daede 前端切换（2026-11-19）：S20P-612 线 daed 包源已在 Packages.sh 替换为 kenzok8/openwrt-daede===
#官方 luci-app-daed 关闭防双管理，改用 luci-app-daede（UCI 统一管 dae/daed，可热切换）
case "$WRT_CONFIG" in
  MEDIATEK-S20P-*)
        echo "CONFIG_PACKAGE_luci-app-daed=n" >> ./.config
        echo "CONFIG_PACKAGE_luci-app-daede=y" >> ./.config
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
