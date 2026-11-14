#!/bin/bash
# SPDX-License-Identifier: MIT
# luci-app-statusfw 编译期改造（由 Scripts/Packages.sh 在 Build/Prepare 阶段调用）
# 参数：$1 = PKG_BUILD_DIR（内含 root/ 已解包的固件根文件系统）
#
# 改造内容（快捷方式与 Vantage 仪表盘融合为一个一级页面）：
#   1) 「状态监控」纯状态页替换为轻量快捷方式页（仅保留 URL 直达可用，菜单不显示）
#   2) 一级菜单改名「网络与防火墙」，默认页改指向「网络」页；页内 tab 移除快捷方式项
#      —— 快捷入口由 Vantage 仪表盘顶部的快捷方式条承担（见 vantage-shortcuts-patch.py）
#   3) 页面风格对齐 Vantage：fwm-* 颜色接入主题变量，亮暗模式自动跟随
#   4) PPE 硬件 offload 占用数据源：root 采样守护 + procd 服务 + nobody CGI
#   5) 剔除内嵌文件管理器（由 feed 版 luci-app-filemanager 提供，避免文件冲突）
set -e
ROOT="$1/root"

[ -d "$ROOT" ] || { echo "statusfw-patch: root dir not found: $ROOT" >&2; exit 1; }

# 1) 快捷方式页替换状态监控页（URL 直达仍可用）
cp "$GITHUB_WORKSPACE/Scripts/statusfw-shortcuts.htm" \
   "$ROOT/usr/lib/lua/luci/view/statusmon/status.htm"

# 2) 菜单改名「状态与防火墙」→「网络与防火墙」；默认页指向「网络」；tab 移除快捷方式项
sed -i 's/"状态与防火墙"/"网络与防火墙"/g' \
   "$ROOT/usr/lib/lua/luci/controller/statusmon.lua"
sed -i 's/<span>状态与防火墙<\/span>/<span>网络与防火墙<\/span>/' \
   "$ROOT/usr/lib/lua/luci/view/fwmanager/page_head.htm"
sed -i 's/alias("admin", "statusfw", "monitor")/alias("admin", "statusfw", "network")/g' \
   "$ROOT/usr/lib/lua/luci/controller/statusmon.lua"
sed -i '/{ "monitor", /d' "$ROOT/usr/lib/lua/luci/view/fwmanager/nav.htm"
sed -i 's/leaf = "monitor"/leaf = "network"/g' "$ROOT/usr/lib/lua/luci/view/fwmanager/nav.htm"

# 3) 风格对齐 Vantage 仪表盘：fwm-* 变量接入主题变量（亮暗模式自动跟随）
FWM="$ROOT/usr/lib/lua/luci/view/fwmanager/common_head.htm"
sed -i \
  -e 's/--fwm-p:#2563eb;--fwm-pd:#1d4ed8;--fwm-pb:#eff6ff;/--fwm-p:var(--accent);--fwm-pd:var(--accent-hover);--fwm-pb:var(--accent-soft);/' \
  -e 's/--fwm-sb:#f0fdf4;/--fwm-sb:rgba(22,163,74,.1);/' \
  -e 's/--fwm-wb:#fffbeb;/--fwm-wb:rgba(217,119,6,.12);/' \
  -e 's/--fwm-db:#fef2f2;/--fwm-db:rgba(220,38,38,.1);/' \
  -e 's/--fwm-g50:#f8fafc;--fwm-g100:#f1f5f9;--fwm-g200:#e2e8f0;--fwm-g400:#94a3b8;--fwm-g600:#475569;--fwm-g800:#1e293b;/--fwm-g50:var(--s2);--fwm-g100:var(--s3);--fwm-g200:var(--line);--fwm-g400:var(--text-3);--fwm-g600:var(--text-2);--fwm-g800:var(--text);/' \
  -e 's/--fwm-mono:"SFMono-Regular",Consolas,"Liberation Mono",Menlo,monospace;/--fwm-mono:var(--mono);/' \
  -e 's/background:linear-gradient(135deg,var(--fwm-p),#0ea5e9);display:flex;align-items:center;justify-content:center;box-shadow:0 4px 12px rgba(37,99,235,.28)/background:var(--accent-soft);display:flex;align-items:center;justify-content:center;box-shadow:none/' \
  -e 's/stroke:#fff;fill:none/stroke:var(--accent);fill:none/' \
  -e 's/background:linear-gradient(135deg,var(--fwm-p),var(--fwm-pd));color:#fff/background:var(--accent-soft);color:var(--accent-text)/' \
  -e 's/box-shadow:0 2px 6px rgba(37,99,235,.25)/box-shadow:none/' \
  -e 's/\.fwm-nav a\.on{background:var(--fwm-p);color:#fff/.fwm-nav a.on{background:var(--fwm-p);color:var(--accent-ink)/' \
  -e 's/\.fwm-btn\.pri{background:var(--fwm-p);border-color:var(--fwm-p);color:#fff}/.fwm-btn.pri{background:var(--fwm-p);border-color:var(--fwm-p);color:var(--accent-ink)}/' \
  -e 's/background:#fff;/background:var(--s1);/g' \
  -e 's/background:#fffdf5}/background:rgba(217,119,6,.08)}/' \
  -e 's/border-radius:12px/border-radius:var(--r-lg,8px)/g' \
  -e 's/font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif/font-family:var(--font)/' \
  "$FWM"

# 4) PPE 硬件 offload 采样三件套（仪表盘 CPU 卡片显示；root 守护采样 debugfs，nobody CGI 转发）
install -m 755 "$GITHUB_WORKSPACE/Scripts/statusppe-worker.sh" \
   "$ROOT/usr/lib/statusppe-worker.sh"
install -m 755 "$GITHUB_WORKSPACE/Scripts/statusppe-initd" \
   "$ROOT/etc/init.d/statusppe"
install -m 755 "$GITHUB_WORKSPACE/Scripts/statusppe-cgi.sh" \
   "$ROOT/www/cgi-bin/statusppe"

# 5) 剔除内嵌文件管理器相关文件（保留 feed 版 luci-app-filemanager）
rm -rf "$ROOT/www/luci-static/resources/view/system/filemanager" \
       "$ROOT/usr/share/luci/menu.d/luci-app-filemanager.json" \
       "$ROOT/usr/share/rpcd/acl.d/luci-app-filemanager.json" \
       "$ROOT/etc/uci-defaults/luci-i18n-filemanager-zh-cn" \
       "$ROOT/lib/apk/packages/luci-app-filemanager.list" \
       "$ROOT/lib/apk/packages/luci-i18n-filemanager-zh-cn.list"
rm -f  "$ROOT/www/luci-static/resources/view/system/filemanager.js" \
       "$ROOT/usr/lib/lua/luci/i18n/filemanager.zh-cn.lmo"

# 6) statusflow：每客户端实时双向速率 + 今日/累计流量采样（root 守护 + procd 服务 + nobody CGI，
#    conntrack orig/reply 差分 + PPE bind 硬件卸载按比重拆向，跨天统计持久化 /etc/statusflow/）
install -m 755 "$GITHUB_WORKSPACE/Scripts/statusflow-worker.sh" \
   "$ROOT/usr/lib/statusflow-worker.sh"
install -m 755 "$GITHUB_WORKSPACE/Scripts/statusflow-initd" \
   "$ROOT/etc/init.d/statusflow"
install -m 755 "$GITHUB_WORKSPACE/Scripts/statusflow-cgi.sh" \
   "$ROOT/www/cgi-bin/statusflow"

# 7) seriesmon：仪表盘 24h 曲线端点（转发 worker 的 series.jsonl，v5 起 worker 自带采样）
install -m 755 "$GITHUB_WORKSPACE/Scripts/seriesmon-cgi.sh" \
   "$ROOT/www/cgi-bin/seriesmon"

# 8) zte-wifi：中兴 mesh 无线客户端详情（ZXSLC 协议采集守护 + CGI + 前端徽标）
#    可选功能：固件不带密码配置（安全），存在 /etc/zte-wifi.conf 时 initd 才启动守护；
#    配置路径写入 sysupgrade.conf，跨升级保留。
install -m 755 "$GITHUB_WORKSPACE/Scripts/zte-wifi.py" \
   "$ROOT/usr/lib/zte-wifi.py"
install -m 755 "$GITHUB_WORKSPACE/Scripts/zte-initd" \
   "$ROOT/etc/init.d/zte-wifi"
install -m 755 "$GITHUB_WORKSPACE/Scripts/zteinfo-cgi.sh" \
   "$ROOT/www/cgi-bin/zteinfo"
touch "$ROOT/etc/sysupgrade.conf"
grep -q '^/etc/zte-wifi\.conf$' "$ROOT/etc/sysupgrade.conf" 2>/dev/null || \
   echo "/etc/zte-wifi.conf" >> "$ROOT/etc/sysupgrade.conf"

echo "statusfw patch done: shortcuts + statusflow v5.3 (24h charts + zte mesh wifi) + seriesmon installed"
