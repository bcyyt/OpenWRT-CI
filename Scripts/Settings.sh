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

#配置文件修改
echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-$WRT_THEME=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-$WRT_THEME-config=y" >> ./.config

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
