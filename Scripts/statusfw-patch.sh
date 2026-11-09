#!/bin/bash
# SPDX-License-Identifier: MIT
# luci-app-statusfw 编译期改造（由 Scripts/Packages.sh 在 Build/Prepare 阶段调用）
# 参数：$1 = PKG_BUILD_DIR（内含 root/ 已解包的固件根文件系统）
#
# 改造内容：
#   1) 「状态监控」页替换为「快捷方式」页：纯状态区块剔除，
#      状态信息由 Vantage 仪表盘（admin/dashboard）承担
#   2) 一级菜单与页内 tab 改名「状态监控」→「快捷方式」
#   3) 剔除内嵌文件管理器（由 feed 版 luci-app-filemanager 提供，避免文件冲突）
set -e
ROOT="$1/root"

[ -d "$ROOT" ] || { echo "statusfw-patch: root dir not found: $ROOT" >&2; exit 1; }

# 1) 快捷方式页替换状态监控页
cp "$GITHUB_WORKSPACE/Scripts/statusfw-shortcuts.htm" \
   "$ROOT/usr/lib/lua/luci/view/statusmon/status.htm"

# 2) 菜单与 tab 改名（entry 标题与 nav.htm 选项卡）
sed -i 's/"状态监控"/"快捷方式"/g' \
   "$ROOT/usr/lib/lua/luci/controller/statusmon.lua"
sed -i 's/{ "monitor", "状态监控", "M3 12h4l3-9 4 18 3-9h4" }/{ "monitor", "快捷方式", "M13 2L3 14h9l-1 8 10-12h-9l1-8z" }/' \
   "$ROOT/usr/lib/lua/luci/view/fwmanager/nav.htm"

# 3) 剔除内嵌文件管理器相关文件（保留 feed 版 luci-app-filemanager）
rm -rf "$ROOT/www/luci-static/resources/view/system/filemanager" \
       "$ROOT/usr/share/luci/menu.d/luci-app-filemanager.json" \
       "$ROOT/usr/share/rpcd/acl.d/luci-app-filemanager.json" \
       "$ROOT/etc/uci-defaults/luci-i18n-filemanager-zh-cn" \
       "$ROOT/lib/apk/packages/luci-app-filemanager.list" \
       "$ROOT/lib/apk/packages/luci-i18n-filemanager-zh-cn.list"
rm -f  "$ROOT/www/luci-static/resources/view/system/filemanager.js" \
       "$ROOT/usr/lib/lua/luci/i18n/filemanager.zh-cn.lmo"

echo "statusfw patch done: shortcuts page installed, status charts removed, embedded filemanager removed"
