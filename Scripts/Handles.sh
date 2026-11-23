#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

FEEDS_PATH="./feeds"
PACKAGE_PATH="./package"

#修补命令统一入口：FIX <名称> <守卫目录> <命令...>
#守卫目录不存在时直接跳过，保证在 bash -e 下不中断
FIX() {
        local NAME=$1
        local GUARD=$2
        shift 2

        [ -d "$GUARD" ] || return 0

        echo " "
        if "$@"; then
                echo "$NAME has been fixed!"
        else
                echo "$NAME fix failed; continuing!"
        fi
}

#修改argon主题字体和颜色
FIX "theme-argon" "$PACKAGE_PATH/luci-theme-argon" sed -i \
        "s/primary '.*'/primary '#31a1a1'/g; s/'0.2'/'0.5'/g; s/'none'/'bing'/g; s/'600'/'normal'/g" \
        "$PACKAGE_PATH/luci-theme-argon/luci-app-argon-config/root/etc/config/argon"

#修改aurora菜单式样
FIX "theme-aurora" "$PACKAGE_PATH/luci-app-aurora-config" find \
        "$PACKAGE_PATH/luci-app-aurora-config/root/usr/share/aurora/" -type f -name '*.template' -exec sed -i \
        "s/nav_type '.*'/nav_type 'dropdown'/g; s/struct_radius_base '.*'/struct_radius_base '0.125rem'/g" {} +

#修改vantage进度条标签字体（anothaDev/luci-theme-vantage#52）
FIX "theme-vantage" "$PACKAGE_PATH/luci-theme-vantage" sed -i \
        -e '/^\/\* progress bars: thin track/,$ { /^\.cbi-progressbar::before {/,/^}/ { s/^[[:space:]]*font: 500 var(--fs-micro)\/1\.2 var(--mono);/\tfont: inherit; line-height: normal;/; } }' \
        "$PACKAGE_PATH/luci-theme-vantage/luci-theme-vantage/htdocs/luci-static/vantage/vantage.css"

#statusfw 快捷方式条注入 Vantage 仪表盘（网格下方独立区块，不参与 tile 布局）
FIX "vantage-statusfw-shortcuts" "$PACKAGE_PATH/luci-theme-vantage" python3 \
        "$GITHUB_WORKSPACE/Scripts/vantage-shortcuts-patch.py" \
        "$PACKAGE_PATH/luci-theme-vantage/luci-app-vantage/htdocs/luci-static/resources/view/vantage/overview.js"

#修改mini-diskmanager菜单位置
FIX "mini-diskmanager" "$PACKAGE_PATH/luci-app-mini-diskmanager" sed -i "s/services/system/g" \
        "$PACKAGE_PATH/luci-app-mini-diskmanager/luci-app-mini-diskmanager/root/usr/share/luci/menu.d/luci-app-mini-diskmanager.json"

#修改natmapt菜单位置
FIX "natmapt" "$PACKAGE_PATH/luci-app-natmapt" sed -i "s/network/services/g" \
        "$PACKAGE_PATH/luci-app-natmapt/root/usr/share/luci/menu.d/luci-app-natmap.json"

#statusflow 每客户端实时双向速率/今日累计流量 + 客户端列表分页注入 Vantage 仪表盘
#（数据源 conntrack orig/reply + PPE bind 融合；运行时三件套由 statusfw-patch.sh 装入 statusfw 包）
FIX "vantage-statusflow" "$PACKAGE_PATH/luci-theme-vantage" python3 \
        "$GITHUB_WORKSPACE/Scripts/vantage-statusflow-patch.py" \
        "$PACKAGE_PATH/luci-theme-vantage/luci-app-vantage/htdocs/luci-static/resources/view/vantage/overview.js" \
        "$PACKAGE_PATH/luci-theme-vantage/luci-app-vantage/htdocs/luci-static/resources/vantage/app.css"

#IPQ95XX 线专属：上游 qcom_ppe 为单引擎（6.18 debugfs 单目录 /sys/kernel/debug/ppe/，
#无 ppe0/ppe1 分目录），仪表盘 CPU 卡片 PPE 行去掉常驻的 PPE1 槽位——
#单引擎只显示 "PPE"；双引擎设备(ppe1.t>0)保持 PPE0+PPE1 原样；其他线不注入
if [[ "${WRT_CONFIG,,}" == ipq95xx* ]]; then
FIX "vantage-ppe-single" "$PACKAGE_PATH/luci-theme-vantage" python3 \
        "$GITHUB_WORKSPACE/Scripts/vantage-ppe-patch.py" \
        "$PACKAGE_PATH/luci-theme-vantage/luci-app-vantage/htdocs/luci-static/resources/view/vantage/overview.js"
fi

#IPQ95XX-WIFI-NO 线专属：无线栈已剥离，但 LuCI 菜单/仪表盘均以 /etc/config/wireless 的
#@wifi-device uci 依赖决定无线页显示 —— sysupgrade 保留设置会把旧固件的 wireless 配置
#恢复进来造成残显（2026-11-23 实机复现）。镜像内置 uci-defaults 首启清理，仅 WIFI-NO 线生效。
if [[ "$WRT_CONFIG" == *WIFI-NO* ]]; then
FIX "base-files-wifino-cleanup" "$PACKAGE_PATH/base-files" sh -c "mkdir -p $PACKAGE_PATH/base-files/files/etc/uci-defaults && printf '#!/bin/sh\n# WIFI-NO 线: 清理 sysupgrade 保留设置恢复进来的 wireless 配置(无线栈已剥离, 残留配置致菜单/仪表盘无线残显)\nrm -f /etc/config/wireless\nexit 0\n' > $PACKAGE_PATH/base-files/files/etc/uci-defaults/99-wifino-cleanup"
fi

#uHTTPd HTTP(S) 访问页补全：固件精简版只剩 redirect_https，补回 HTTP/HTTPS 监听编辑字段
#（main + luci 双实例 DynamicList；2026-11-20 S20P 实机验证通过）
#（luci-mod-system 是 feeds 包：源码树在 ./feeds/luci/modules/，feeds install 后 package/feeds 下为符号链接；
#  2026-11-20 构建实复现原 $PACKAGE_PATH/feeds/... 路径不存在，被守卫静默跳过致补丁未编入）
FIX "luci-mod-system-uhttpd-view" "$FEEDS_PATH/luci/modules/luci-mod-system" cp \
        "$GITHUB_WORKSPACE/Scripts/uhttpd-view.js" \
        "$FEEDS_PATH/luci/modules/luci-mod-system/htdocs/luci-static/resources/view/system/uhttpd.js"
