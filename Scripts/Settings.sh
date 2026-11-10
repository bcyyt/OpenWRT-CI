#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

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

#===内核rmem_max默认64M：IPTV UDP组播流接收缓冲（开机由/etc/init.d/sysctl加载，字母序99最后生效，覆盖包内置的15-iptv-auth.conf下限值）===
mkdir -p ./package/base-files/files/etc/sysctl.d
echo "net.core.rmem_max=67108864" > ./package/base-files/files/etc/sysctl.d/99-rmem.conf

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
