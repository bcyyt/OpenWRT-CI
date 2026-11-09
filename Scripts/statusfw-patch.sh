#!/bin/bash
# SPDX-License-Identifier: MIT
# luci-app-statusfw 编译期改造（由 Scripts/Packages.sh 在 Build/Prepare 阶段调用）
# 参数：$1 = PKG_BUILD_DIR（内含 root/ 已解包的固件根文件系统）
#
# 改造内容（快捷方式与 Vantage 仪表盘融合为一个一级页面）：
#   1) 「状态监控」纯状态页替换为轻量快捷方式页（仅保留 URL 直达可用，菜单不显示）
#   2) 「状态与防火墙」一级菜单默认页改指向「网络」页；页内 tab 移除快捷方式项
#      —— 快捷入口由 Vantage 仪表盘底部的快捷方式条承担（见 vantage-shortcuts-patch.py）
#   3) 剔除内嵌文件管理器（由 feed 版 luci-app-filemanager 提供，避免文件冲突）
set -e
ROOT="$1/root"

[ -d "$ROOT" ] || { echo "statusfw-patch: root dir not found: $ROOT" >&2; exit 1; }

# 1) 快捷方式页替换状态监控页（URL 直达仍可用）
cp "$GITHUB_WORKSPACE/Scripts/statusfw-shortcuts.htm" \
   "$ROOT/usr/lib/lua/luci/view/statusmon/status.htm"

# 2) 一级菜单默认页改指向「网络」；页内 tab 移除「状态监控/快捷方式」项
sed -i 's/alias("admin", "statusfw", "monitor")/alias("admin", "statusfw", "network")/g' \
   "$ROOT/usr/lib/lua/luci/controller/statusmon.lua"
sed -i '/{ "monitor", /d' "$ROOT/usr/lib/lua/luci/view/fwmanager/nav.htm"
sed -i 's/leaf = "monitor"/leaf = "network"/g' "$ROOT/usr/lib/lua/luci/view/fwmanager/nav.htm"

# 3) 剔除内嵌文件管理器相关文件（保留 feed 版 luci-app-filemanager）
rm -rf "$ROOT/www/luci-static/resources/view/system/filemanager" \
       "$ROOT/usr/share/luci/menu.d/luci-app-filemanager.json" \
       "$ROOT/usr/share/rpcd/acl.d/luci-app-filemanager.json" \
       "$ROOT/etc/uci-defaults/luci-i18n-filemanager-zh-cn" \
       "$ROOT/lib/apk/packages/luci-app-filemanager.list" \
       "$ROOT/lib/apk/packages/luci-i18n-filemanager-zh-cn.list"
rm -f  "$ROOT/www/luci-static/resources/view/system/filemanager.js" \
       "$ROOT/usr/lib/lua/luci/i18n/filemanager.zh-cn.lmo"

echo "statusfw patch done: shortcuts merged into dashboard, status charts removed, embedded filemanager removed"
