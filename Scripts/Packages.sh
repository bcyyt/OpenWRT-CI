#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

#安装和更新软件包
UPDATE_PACKAGE() {
        local PKG_NAME=$1
        local PKG_REPO=$2
        local PKG_BRANCH=$3
        local PKG_SPECIAL=$4
        local PKG_LIST=("$PKG_NAME" $5)  # 第5个参数为自定义名称列表
        local REPO_NAME=${PKG_REPO#*/}
        local REPO_PATH="./package/$REPO_NAME"

        echo " "

        # 删除本地可能存在的不同名称的软件包
        for NAME in "${PKG_LIST[@]}"; do
                # 查找匹配的目录
                echo "Search directory: $NAME"
                local FOUND_DIRS=$(find ./feeds/luci/ ./feeds/packages/ -maxdepth 3 -type d -iname "*$NAME*" 2>/dev/null)

                # 删除找到的目录
                if [ -n "$FOUND_DIRS" ]; then
                        while read -r DIR; do
                                rm -rf "$DIR"
                                echo "Delete directory: $DIR"
                        done <<< "$FOUND_DIRS"
                else
                        echo "Not fonud directory: $NAME"
                fi
        done

        # 克隆 GitHub 仓库
        git clone --depth=1 --single-branch --branch $PKG_BRANCH "https://github.com/$PKG_REPO.git" $REPO_PATH

        # 处理克隆的仓库
        if [[ "$PKG_SPECIAL" == "pkg" ]]; then
                find $REPO_PATH/*/ -maxdepth 3 -type d -iname "*$PKG_NAME*" -prune -exec cp -rf {} ./package \;
                rm -rf $REPO_PATH
        fi
}

# 调用示例
# UPDATE_PACKAGE "OpenAppFilter" "destan19/OpenAppFilter" "master" "" "custom_name1 custom_name2"
# UPDATE_PACKAGE "open-app-filter" "destan19/OpenAppFilter" "master" "" "luci-app-appfilter oaf" 这样会把原有的open-app-filter，luci-app-appfilter，oaf相关组件删除，不会出现coremark错误。

# UPDATE_PACKAGE "包名" "项目地址" "项目分支" "pkg，可选，从大杂烩中单独提取包名插件"
# 2026-11-28: QCB 线主题切 Carbon（官方 luci feed 自带），Argon 下载与登录页
# CSS 修复仅在 argon 线守卫执行；carbon 线跳过（Handles.sh 的 argon FIX 亦自动缺席）
if [ "$WRT_THEME" = "argon" ]; then
UPDATE_PACKAGE "argon" "sbwml/luci-theme-argon" "openwrt-25.12"
#===argon 登录页手机键盘弹起防遮挡（2026-11-27 SBE1V1K 实机验证，详 TROUBLESHOOTING.md 坑6）===
#根因: 登录页 footer absolute bottom:0, Android 键盘弹起压缩视口时压住密码框;
#      主题原 resize 脚本查询 .ftc 但登录页无该元素, 属空操作。
#修复: 媒体查询——手机且视口被压缩(键盘弹起)时 footer 让位隐藏, 键盘收起立即恢复
#      (文字保留); 平时 pointer-events:none 保证任何情况下不拦截输入框点击。
ARGON_CSS=./package/luci-theme-argon/htdocs/luci-static/argon/css/cascade.css
[ -f "$ARGON_CSS" ] && cat >> "$ARGON_CSS" <<'ARGON_FIX'
/* === 登录页手机键盘弹起防遮挡（实机验证 2026-11-27） === */
@media (max-width:600px) and (max-height:520px){ .login-page footer{display:none!important} }
@media (max-width:600px){ .login-page footer{pointer-events:none} }
ARGON_FIX
fi
#===Carbon 主题（QCB-CARBON 线, 2026-11-28）：feed 已下架该主题,以实机验证版
#(1.2.0-r1, SBE1V1K 全天实机回归过的文件集)静态注入成包——不 clone 不依赖外部源,
#feed 滚动/上游删包不影响构建确定性; uci-defaults 注册主题并设默认 mediaurlbase;
#Handles.sh 的 theme-carbon-badges FIX 构建期注入徽章载入行(menu-carbon 加载后)===
if [ "$WRT_THEME" = "carbon" ]; then
CB_DIR="./package/luci-theme-carbon"
mkdir -p "$CB_DIR/files"
cp -a "$GITHUB_WORKSPACE/Scripts/carbon-theme/." "$CB_DIR/files/"
cp "$GITHUB_WORKSPACE/Scripts/inject/carbon.Makefile" "$CB_DIR/Makefile"
WRT_ROOT=$PWD
(cd "$CB_DIR" && make --no-print-directory -f Makefile TOPDIR="$WRT_ROOT" INCLUDE_DIR="$WRT_ROOT/include" -n >/dev/null 2>/tmp/cb_syntax.err) \
        && echo "carbon Makefile syntax: OK" \
        || { echo "carbon Makefile syntax FAILED:"; head -5 /tmp/cb_syntax.err; echo "FATAL: carbon 主题包 Makefile 语法错误，提前终止避免浪费整轮编译"; exit 1; }
fi
[ -f "$ARGON_CSS" ] && grep -q 'login-page footer{display:none' "$ARGON_CSS" && \
        echo "argon: 登录页手机键盘防遮挡 CSS 已追加（坑6）"
UPDATE_PACKAGE "aurora" "eamonxg/luci-theme-aurora" "master"
UPDATE_PACKAGE "aurora-config" "eamonxg/luci-app-aurora-config" "master"
UPDATE_PACKAGE "fluent" "LazuliKao/luci-theme-fluent" "main"
UPDATE_PACKAGE "footstrap" "VizzleTF/luci-theme-footstrap" "main"
UPDATE_PACKAGE "kucat" "sirpdboy/luci-theme-kucat" "master"
UPDATE_PACKAGE "kucat-config" "sirpdboy/luci-app-kucat-config" "master"
UPDATE_PACKAGE "shadcn" "eamonxg/luci-theme-shadcn" "main"
#2026-11-21: Vantage 主题仅 v 主题线注入；非 v 主题线（LEDE/S20P 等）跳过克隆，
#Handles.sh 三处 vantage 补丁随 FIX [ -d ] 守卫自动缺席跳过
[ "$WRT_THEME" = "vantage" ] && UPDATE_PACKAGE "vantage" "anothaDev/luci-theme-vantage" "main"

UPDATE_PACKAGE "momo" "nikkinikki-org/OpenWrt-momo" "main"
UPDATE_PACKAGE "nikki" "nikkinikki-org/OpenWrt-nikki" "main"
UPDATE_PACKAGE "openclash" "vernesong/OpenClash" "dev" "pkg"
UPDATE_PACKAGE "passwall" "Openwrt-Passwall/openwrt-passwall" "main" "pkg"
UPDATE_PACKAGE "passwall2" "Openwrt-Passwall/openwrt-passwall2" "main" "pkg"

#===daede（kenzok8 增强版 daed，pin 上游 dae/daed master 候选滚动线）：MTK 两线 + IPQ95XX(owrt) 两线替换官方 daed 包源===
# main HEAD 滚动 pin 上游候选（v2026.11.21-75323da 基准，晚于官方 daed v2.1.1 tag，
# 与 dae 核心 v2.1.3 同代；每个候选过 16 SDK 目标门禁）。go.mod 要求 Go>=1.27：
# 构建依赖显式切换到 feed 自带 golang1.27（chasey-dev 25.12 / immortalwrt-packages master 已验证）
# 2026-11-24: IPQ95XX(owrt) 两线并入——官方 immortalwrt-packages feed 的 daed 停在 1.27.0；
# LEDE-IPQ95XX 线无源码包，继续走 OpenClash ipk 注入不动
if [[ "$WRT_CONFIG" == MEDIATEK-S20P-* || "$WRT_CONFIG" == MEDIATEK-WIFI-* || "$WRT_CONFIG" == IPQ95XX* ]]; then
        find ./feeds/luci/ ./feeds/packages/ -maxdepth 3 -type d -iname '*daed*' -exec rm -rf {} + 2>/dev/null
        git clone -q https://github.com/kenzok8/openwrt-daede.git ./package/openwrt-daede
        rm -rf ./package/openwrt-daede/.git
        sed -i 's|golang/host|golang1.27/host|' ./package/openwrt-daede/daed/Makefile
        echo "daede main(2026.11.21+滚动, IPQ95XX 扩展) + golang1.27 applied"
fi

UPDATE_PACKAGE "diskmanager" "4IceG/luci-app-mini-diskmanager" "main"
UPDATE_PACKAGE "easytier" "EasyTier/luci-app-easytier" "main"
UPDATE_PACKAGE "lucky" "gdy666/luci-app-lucky" "main"
UPDATE_PACKAGE "qmodem" "FUjr/QModem" "main"
UPDATE_PACKAGE "viking" "VIKINGYFY/packages" "main" "" "axonhub gecoosac miniupnpd luci-app-timewol luci-app-upnp luci-app-wolplus luci-app-wolultra"

UPDATE_PACKAGE "diskman" "sbwml/luci-app-diskman" "main"
UPDATE_PACKAGE "mosdns" "sbwml/luci-app-mosdns" "v5" "" "v2dat"
UPDATE_PACKAGE "openlist2" "sbwml/luci-app-openlist2" "main"
UPDATE_PACKAGE "qbittorrent" "sbwml/luci-app-qbittorrent" "master" "" "qt6base qt6tools rblibtorrent"
UPDATE_PACKAGE "quickfile" "sbwml/luci-app-quickfile" "main"

UPDATE_PACKAGE "ddns-go" "sirpdboy/luci-app-ddns-go" "main"
UPDATE_PACKAGE "netspeedtest" "sirpdboy/netspeedtest" "main" "" "homebox ookla-speedtest"
UPDATE_PACKAGE "netwizard" "sirpdboy/luci-app-netwizard" "main"
UPDATE_PACKAGE "partexp" "sirpdboy/luci-app-partexp" "main"
UPDATE_PACKAGE "timecontrol" "sirpdboy/luci-app-timecontrol" "main"

UPDATE_PACKAGE "natmapt" "muink/openwrt-natmapt" "master"
UPDATE_PACKAGE "stuntman" "muink/openwrt-stuntman" "master"
UPDATE_PACKAGE "luci-app-natmapt" "muink/luci-app-natmapt" "master"

UPDATE_PACKAGE "airpi3000m-fancontrol" "LianXia233/luci-app-airpi3000m-fancontrol" "main"
UPDATE_PACKAGE "chfs" "LianXia233/luci-app-chfs" "main"
UPDATE_PACKAGE "fm350" "LianXia233/luci-app-fm350" "main"
UPDATE_PACKAGE "h5000m-netmode" "LianXia233/luci-app-h5000m-netmode" "main"
UPDATE_PACKAGE "mt5700" "LianXia233/luci-app-mt5700" "main"
UPDATE_PACKAGE "mt5700m" "LianXia233/luci-app-mt5700m" "main"
UPDATE_PACKAGE "netmonitor" "LianXia233/luci-app-netmonitor" "main"
UPDATE_PACKAGE "qmodem-generic" "LianXia233/luci-app-qmodem-generic" "main"

#更新软件包版本
UPDATE_VERSION() {
        local PKG_NAME=$1
        local PKG_MARK=${2:-false}
        local PKG_FILES=$(find ./package/ ./feeds/packages/ -maxdepth 3 -type f -wholename "*/$PKG_NAME/Makefile")

        if [ -z "$PKG_FILES" ]; then
                echo "$PKG_NAME not found!"
                return
        fi

        echo -e "\n$PKG_NAME version update has started!"

        for PKG_FILE in $PKG_FILES; do
                local PKG_REPO=$(grep -Po "PKG_SOURCE_URL:=https://.*github.com/\K[^/]+/[^/]+(?=.*)" $PKG_FILE)
                local PKG_TAG=$(curl -sL "https://api.github.com/repos/$PKG_REPO/releases" | jq -r "map(select(.prerelease == $PKG_MARK)) | first | .tag_name")

                local OLD_VER=$(grep -Po "PKG_VERSION:=\K.*" "$PKG_FILE")
                local OLD_URL=$(grep -Po "PKG_SOURCE_URL:=\K.*" "$PKG_FILE")
                local OLD_FILE=$(grep -Po "PKG_SOURCE:=\K.*" "$PKG_FILE")
                local OLD_HASH=$(grep -Po "PKG_HASH:=\K.*" "$PKG_FILE")

                local PKG_URL=$([[ "$OLD_URL" == *"releases"* ]] && echo "${OLD_URL%/}/$OLD_FILE" || echo "${OLD_URL%/}")

                local NEW_VER=$(echo $PKG_TAG | sed -E 's/[^0-9]+/\./g; s/^\.|\.$//g')
                local NEW_URL=$(echo $PKG_URL | sed "s/\$(PKG_VERSION)/$NEW_VER/g; s/\$(PKG_NAME)/$PKG_NAME/g")
                local NEW_HASH=$(curl -sL "$NEW_URL" | sha256sum | cut -d ' ' -f 1)

                echo "old version: $OLD_VER $OLD_HASH"
                echo "new version: $NEW_VER $NEW_HASH"

                if [[ "$NEW_VER" =~ ^[0-9].* ]] && dpkg --compare-versions "$OLD_VER" lt "$NEW_VER"; then
                        sed -i "s/PKG_VERSION:=.*/PKG_VERSION:=$NEW_VER/g" "$PKG_FILE"
                        sed -i "s/PKG_HASH:=.*/PKG_HASH:=$NEW_HASH/g" "$PKG_FILE"
                        echo "$PKG_FILE version has been updated!"
                else
                        echo "$PKG_FILE version is already the latest!"
                fi
        done
}

#UPDATE_VERSION "软件包名" "测试版，true，可选，默认为否"
#UPDATE_VERSION "sing-box"

#从bcyyt的gitee公开OTA仓拉取预编译ipk并内置为固件包（iptv-auth、保留升级luci-app-syskeep）
#公开仓免令牌可访问，无需任何凭据
BCYYT_RAW="https://gitee.com/bcyyt/my-openwrt/raw/main/packages"
BCYYT_API="https://gitee.com/api/v5/repos/bcyyt/my-openwrt/contents/packages"

#下载并计算sha256，失败时输出skip
BCYYT_SHA256() {
        local HASH
        HASH=$(curl -fsSL --retry 3 --connect-timeout 15 "$1" 2>/dev/null | sha256sum | cut -d ' ' -f 1)
        # curl失败时sha256sum会输出空输入哈希，误当合法值导致下载校验必败，识别并降级为skip
        [ "$HASH" = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ] && HASH=skip
        [ -n "$HASH" ] || HASH=skip
        echo "$HASH"
}

#生成内置包Makefile：把预编译ipk的data.tar.gz原样装入rootfs
#参数：包名 版本 描述 依赖 ipk解包命令(external make语法) conffiles列表 额外架构头部 编译期patch命令(可选,在root解包后执行)
BCYYT_INJECT() {
        description="prebuilt ipk inject: static skeleton + printf line-by-line inc (no heredoc)"
        local PKG_NAME=$1
        local PKG_VER=$2
        local PKG_TITLE=$3
        local PKG_DEPS=$4
        local PKG_CONFFILES=$6
        local PKG_HEADER=$7
        local PKG_PATCH=$8
        local PKG_DIR="./package/bcyyt/$PKG_NAME"

        mkdir -p "$PKG_DIR"
        cp "$GITHUB_WORKSPACE/Scripts/inject/inject-common.Makefile" "$PKG_DIR/Makefile"

        {
                printf '%s\n' \
                        "PKG_NAME:=$PKG_NAME" \
                        "PKG_VERSION:=$PKG_VER"
                printf '%s\n' "$PKG_HEADER" | sed '/^$/d'
                printf '%s\n' \
                        "define Package/$PKG_NAME" \
                        "  SECTION:=luci" \
                        "  CATEGORY:=LuCI" \
                        "  TITLE:=$PKG_TITLE" \
                        "  URL:=https://gitee.com/bcyyt/my-openwrt" \
                        "  DEPENDS:=$PKG_DEPS" \
                        "  PKGARCH:=all" \
                        "endef" \
                        "define Package/$PKG_NAME/conffiles"
                printf '%s\n' "$PKG_CONFFILES" | sed '/^$/d'
                printf '%s\n' "endef"
                if [ -n "$PKG_PATCH" ]; then
                        printf '%s\n' \
                                "define Build/Prepare" \
                                "\trm -rf \$(PKG_BUILD_DIR)" \
                                "\tmkdir -p \$(PKG_BUILD_DIR)/ipk \$(PKG_BUILD_DIR)/root" \
                                "\ttar -C \$(PKG_BUILD_DIR)/ipk -xzf \$(DL_DIR)/\$(PKG_SOURCE)" \
                                "\ttar -C \$(PKG_BUILD_DIR)/root -xzf \$(PKG_BUILD_DIR)/ipk/data.tar.gz"
                        printf '\t%s\n' "$PKG_PATCH"
                        printf '%s\n' "endef"
                fi
        } > "$PKG_DIR/inject.inc"

        echo "$PKG_NAME $PKG_VER has been generated into $PKG_DIR/!"

        # 语法自检（包目录内执行，include 才能解析）
        local WRT_ROOT=$PWD
        (cd "$PKG_DIR" && make --no-print-directory -f Makefile TOPDIR="$WRT_ROOT" INCLUDE_DIR="$WRT_ROOT/include" -n >/dev/null 2>/tmp/inject_syntax.err) || { echo "$PKG_NAME Makefile syntax FAILED:"; head -5 /tmp/inject_syntax.err; }
}

#===iptv-auth：版本与下载地址来自version.json，始终跟随OTA仓最新版===
# 容错：OTA 仓只更新了 apk、尚未上传对应 ipk 时（version.json 已指向新版本但 ipk 404），
# 自动回退到「最近一个三架构 ipk 齐全」的历史版本，避免编译失败；ipk 补传后自动跟上。
IPTV_RAW_VER=$(curl -fsSL --retry 3 --connect-timeout 15 "$BCYYT_RAW/iptv-auth/version.json" | jq -r ".version" 2>/dev/null)
[ -n "$IPTV_RAW_VER" ] || IPTV_RAW_VER="2.3.80-r5"
iptv_ipk_ok() { curl -fsIL --retry 3 --connect-timeout 10 "$BCYYT_RAW/iptv-auth/iptv-auth_${1}_aarch64.ipk" > /dev/null 2>&1; }
IPTV_VER="$IPTV_RAW_VER"
if ! iptv_ipk_ok "$IPTV_VER"; then
        echo "iptv-auth $IPTV_VER ipk missing on OTA repo (apk-only release), falling back..."
        for IPTV_FALLBACK in $(curl -fsSL --retry 3 --connect-timeout 15 "$BCYYT_RAW/iptv-auth/version.json" | jq -r ".changelogs[].version" 2>/dev/null) 2.3.80-r5 2.3.80-r3; do
                if iptv_ipk_ok "$IPTV_FALLBACK"; then IPTV_VER="$IPTV_FALLBACK"; break; fi
        done
        [ "$IPTV_VER" != "$IPTV_RAW_VER" ] && echo "iptv-auth ipk fallback: $IPTV_RAW_VER -> $IPTV_VER (upload r${IPTV_RAW_VER##*-r} ipk to restore)"
fi
echo "iptv-auth latest version: $IPTV_VER"

IPTV_HASH_x86_64=$(BCYYT_SHA256 "$BCYYT_RAW/iptv-auth/iptv-auth_${IPTV_VER}_x86_64.ipk")
IPTV_HASH_aarch64=$(BCYYT_SHA256 "$BCYYT_RAW/iptv-auth/iptv-auth_${IPTV_VER}_aarch64.ipk")
IPTV_HASH_armv7=$(BCYYT_SHA256 "$BCYYT_RAW/iptv-auth/iptv-auth_${IPTV_VER}_armv7.ipk")

BCYYT_INJECT "iptv-auth" "$IPTV_VER" \
        "IPTV auth + M3U/EPG + C replay daemon + rtp2httpd live proxy + STB sniffer + OTA update detection" \
        "+luci-base +luci-compat +python3 +ca-bundle @(x86_64||aarch64||arm)" \
        "tar -C \$(PKG_BUILD_DIR)/ipk -xzf \$(DL_DIR)/\$(PKG_SOURCE)" \
        "/etc/config/iptv-auth
/etc/config/stbsniffer
/etc/sysctl.d/15-iptv-auth.conf" \
        "IPTV_ARCH:=x86_64
ifeq (\$(ARCH),aarch64)
  IPTV_ARCH:=aarch64
endif
ifeq (\$(ARCH),arm)
  IPTV_ARCH:=armv7
endif
PKG_SOURCE:=iptv-auth_\$(PKG_VERSION)_\$(IPTV_ARCH).ipk
PKG_SOURCE_URL:=$BCYYT_RAW/iptv-auth
ifeq (\$(ARCH),x86_64)
  PKG_HASH:=$IPTV_HASH_x86_64
endif
ifeq (\$(ARCH),aarch64)
  PKG_HASH:=$IPTV_HASH_aarch64
endif
ifeq (\$(ARCH),arm)
  PKG_HASH:=$IPTV_HASH_armv7
endif"

#===luci-app-syskeep（保留升级）：版本来自gitee目录列表，始终跟随OTA仓最新版===
# 仅x86_64：OTA仓只发布x86_64 ipk，其 /lib/upgrade/syskeep-hook.sh 是X86专属逻辑
# （GPT分区表/grub/EFI/ONIE检查），曾因无架构限制被装入aarch64固件并覆盖
# mediatek的platform_check_image，导致S20P刷机报 is_onie_install: not found /
# Invalid image type。参照iptv-auth做法用 @x86_64 依赖限定目标架构。
SYSKEEP_VER=$(curl -fsSL --retry 3 --connect-timeout 15 "$BCYYT_API/luci-app-syskeep" | jq -r ".[].name" 2>/dev/null | grep -E "^luci-app-syskeep_.*_x86_64\.ipk$" | sed "s/luci-app-syskeep_//;s/_x86_64.ipk//" | sort -V | tail -1)
[ -n "$SYSKEEP_VER" ] || SYSKEEP_VER="1.0.35-r0"
echo "luci-app-syskeep latest version: $SYSKEEP_VER"

SYSKEEP_HASH=$(BCYYT_SHA256 "$BCYYT_RAW/luci-app-syskeep/luci-app-syskeep_${SYSKEEP_VER}_x86_64.ipk")

BCYYT_INJECT "luci-app-syskeep" "$SYSKEEP_VER" \
        "LuCI 保留升级：刷机保留配置、分区和插件清单，开机重装apk（仅X86）" \
        "+luci-base +luci-compat @x86_64" \
        "tar -C \$(PKG_BUILD_DIR)/ipk -xzf \$(DL_DIR)/\$(PKG_SOURCE)" \
        "/etc/syskeep/custom-apks.txt
/etc/syskeep/datadir.sh" \
        "PKG_SOURCE:=luci-app-syskeep_\$(PKG_VERSION)_x86_64.ipk
PKG_SOURCE_URL:=$BCYYT_RAW/luci-app-syskeep
PKG_HASH:=$SYSKEEP_HASH"

#===luci-app-natfrp（SakuraFrp 启动器）：官方 launcher-openwrt 目录直取，三架构ipk===
# 官方源：nya.globalslb.net/natfrp/client/launcher-openwrt/<版本>/luci-app-natfrp_<arch>.ipk
# 自包含包（natfrp-frpc + natfrp-service 二进制 + LuCI 界面 + init 服务），依赖仅 luci-compat
# 容错：最新版本目录缺某架构 ipk 时自动回退到最近一个三架构齐全的历史版本
NATFRP_BASE="https://nya.globalslb.net/natfrp/client/launcher-openwrt"
NATFRP_VER=""
for v in $(curl -fsSL --retry 3 --connect-timeout 15 "$NATFRP_BASE/" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+/' | tr -d '/' | sort -rV); do
        if curl -fsIL --retry 2 --connect-timeout 10 "$NATFRP_BASE/$v/luci-app-natfrp_arm64.ipk" >/dev/null 2>&1 \
           && curl -fsIL --retry 2 --connect-timeout 10 "$NATFRP_BASE/$v/luci-app-natfrp_amd64.ipk" >/dev/null 2>&1 \
           && curl -fsIL --retry 2 --connect-timeout 10 "$NATFRP_BASE/$v/luci-app-natfrp_armv7.ipk" >/dev/null 2>&1; then
                NATFRP_VER="$v"; break
        fi
done
[ -n "$NATFRP_VER" ] || NATFRP_VER="3.1.9"
echo "luci-app-natfrp latest version: $NATFRP_VER"

NATFRP_HASH_x86_64=$(BCYYT_SHA256 "$NATFRP_BASE/$NATFRP_VER/luci-app-natfrp_amd64.ipk")
NATFRP_HASH_aarch64=$(BCYYT_SHA256 "$NATFRP_BASE/$NATFRP_VER/luci-app-natfrp_arm64.ipk")
NATFRP_HASH_armv7=$(BCYYT_SHA256 "$NATFRP_BASE/$NATFRP_VER/luci-app-natfrp_armv7.ipk")

BCYYT_INJECT "luci-app-natfrp" "$NATFRP_VER" \
        "SakuraFrp 启动器：frpc 内网穿透客户端 + 后台服务 + LuCI 管理界面" \
        "+luci-base +luci-compat @(x86_64||aarch64||arm)" \
        "tar -C \$(PKG_BUILD_DIR)/ipk -xzf \$(DL_DIR)/\$(PKG_SOURCE)" \
        "/etc/config/natfrp" \
        "NATFRP_ARCH:=amd64
ifeq (\$(ARCH),aarch64)
  NATFRP_ARCH:=arm64
endif
ifeq (\$(ARCH),arm)
  NATFRP_ARCH:=armv7
endif
PKG_SOURCE:=luci-app-natfrp_\$(NATFRP_ARCH).ipk
PKG_SOURCE_URL:=$NATFRP_BASE/$NATFRP_VER
ifeq (\$(ARCH),x86_64)
  PKG_HASH:=$NATFRP_HASH_x86_64
endif
ifeq (\$(ARCH),aarch64)
  PKG_HASH:=$NATFRP_HASH_aarch64
endif
ifeq (\$(ARCH),arm)
  PKG_HASH:=$NATFRP_HASH_armv7
endif"

#===zte-wifi（ZTE mesh 无线客户端详情）：自编组件独立成包（原先随 statusfw-patch 注入，statusfw 已按需求删除）===
ZTE_DIR="./package/bcyyt/zte-wifi"
mkdir -p "$ZTE_DIR/files"
cp "$GITHUB_WORKSPACE/Scripts/inject/zte-wifi.Makefile" "$ZTE_DIR/Makefile"
for zf in zte-wifi.py zte-initd zteinfo-cgi.sh zte-wifi-view.js zte-menu.json zte-acl.json zte-default-config; do
        cp "$GITHUB_WORKSPACE/Scripts/$zf" "$ZTE_DIR/files/$zf" || echo "zte-wifi: $zf missing"
done
#语法自检（包目录内执行）
WRT_ROOT=$PWD
(cd "$ZTE_DIR" && make --no-print-directory -f Makefile TOPDIR="$WRT_ROOT" INCLUDE_DIR="$WRT_ROOT/include" -n >/dev/null 2>/tmp/zte_syntax.err) \
        && echo "zte-wifi Makefile syntax: OK" \
        || { echo "zte-wifi Makefile syntax FAILED:"; head -5 /tmp/zte_syntax.err; }

#===luci-app-openclash（Clash 客户端）：vernesong 官方 release ipk 预编译注入（替代 dae 的弹性方案）===
OC_REL=$(curl -fsSL --retry 3 --connect-timeout 15 "https://api.github.com/repos/vernesong/OpenClash/releases/latest" 2>/dev/null)
OC_TAG=$(echo "$OC_REL" | jq -r '.tag_name' 2>/dev/null)
OC_ASSET=$(echo "$OC_REL" | jq -r '.assets[].name' 2>/dev/null | grep -E '^luci-app-openclash_.*_all\.ipk$' | head -1)
if [ -z "$OC_TAG" ] || [ -z "$OC_ASSET" ]; then
        echo "OpenClash release API miss, falling back to pinned version"
        OC_TAG="v0.48.002"
        OC_ASSET="luci-app-openclash_0.48.002_all.ipk"
fi
OC_VER=$(echo "$OC_ASSET" | sed -E "s/^luci-app-openclash_(.*)_all\.ipk$/\1/")
echo "OpenClash latest version: $OC_VER"
OC_BASE="https://github.com/vernesong/OpenClash/releases/download/$OC_TAG"
OC_HASH=$(BCYYT_SHA256 "$OC_BASE/$OC_ASSET")
OC_DIR="./package/bcyyt/luci-app-openclash"
mkdir -p "$OC_DIR"
cp "$GITHUB_WORKSPACE/Scripts/inject/openclash.Makefile" "$OC_DIR/Makefile"
printf '%s\n' \
        "PKG_VERSION:=$OC_VER" \
        "PKG_SOURCE:=$OC_ASSET" \
        "PKG_SOURCE_URL:=$OC_BASE" \
        "PKG_HASH:=$OC_HASH" > "$OC_DIR/openclash.inc"
WRT_ROOT=$PWD
(cd "$OC_DIR" && make --no-print-directory -f Makefile TOPDIR="$WRT_ROOT" INCLUDE_DIR="$WRT_ROOT/include" -n >/dev/null 2>/tmp/oc_syntax.err) \
        && echo "openclash Makefile syntax: OK" \
        || { echo "openclash Makefile syntax FAILED:"; head -5 /tmp/oc_syntax.err; }

#===luci-app-statusmon（仪表盘运行时后端）：自编组件独立成包（原先随 statusfw-patch 注入，statusfw 已按需求删除）===
# statusmon v4.48 = 系统状态/快捷方式数据源；statusppe = PPE+CPU 采样；statusflow = 客户端速率+今日流量+24h 曲线；seriesmon = 曲线端点
#2026-11-21: 仅 v 主题线注入（服务于 Vantage 仪表盘；LEDE/S20P 等非 v 线不编入，同 11-19 S20P 展示层取消决策）
if [ "$WRT_THEME" = "vantage" ]; then
SM_DIR="./package/bcyyt/luci-app-statusmon"
mkdir -p "$SM_DIR/files"
cp "$GITHUB_WORKSPACE/Scripts/inject/statusmon.Makefile" "$SM_DIR/Makefile"
for sf in statusmon statusppe-worker.sh statusppe-initd statusppe-cgi.sh statusflow-worker.sh statusflow-initd statusflow-cgi.sh seriesmon-cgi.sh; do
        cp "$GITHUB_WORKSPACE/Scripts/$sf" "$SM_DIR/files/$sf" || echo "statusmon: $sf missing"
done
WRT_ROOT=$PWD
(cd "$SM_DIR" && make --no-print-directory -f Makefile TOPDIR="$WRT_ROOT" INCLUDE_DIR="$WRT_ROOT/include" -n >/dev/null 2>/tmp/sm_syntax.err) \
        && echo "statusmon Makefile syntax: OK" \
        || { echo "statusmon Makefile syntax FAILED:"; head -5 /tmp/sm_syntax.err; }
fi

#===luci-app-statusmon-dash（S20P-612 专用：全功能状态监控仪表盘页 + 同源后端）===
# 2026-11-19: 612 线"原生独立页面"方案落地——三环/PPE卡/24h曲线，数据与概览同源；
# 618 线的 luci-app-statusmon 纯后端维持原状，两包 CONFLICTS 互斥永不共存
SMD_DIR="./package/bcyyt/luci-app-statusmon-dash"
mkdir -p "$SMD_DIR/files"
cp "$GITHUB_WORKSPACE/Scripts/inject/statusmon-dash.Makefile" "$SMD_DIR/Makefile"
for sf in statusmon-dash-cgi statusppe-worker-dash.sh statusppe-cgi.sh statusppe-initd \
          statusmon-dash-controller.lua statusmon-dash-view.htm fwmanager-common-head.htm statusmon-dash-ucid; do
        cp "$GITHUB_WORKSPACE/Scripts/$sf" "$SMD_DIR/files/$sf" || echo "statusmon-dash: $sf missing"
done
#语法自检（包目录内执行）
WRT_ROOT=$PWD
(cd "$SMD_DIR" && make --no-print-directory -f Makefile TOPDIR="$WRT_ROOT" INCLUDE_DIR="$WRT_ROOT/include" -n >/dev/null 2>/tmp/smd_syntax.err) \
        && echo "statusmon-dash Makefile syntax: OK" \
        || { echo "statusmon-dash Makefile syntax FAILED:"; head -5 /tmp/smd_syntax.err; }

#===luci-app-adash（QCB 线：PPE/CPU 曲线数据后端 + Carbon 徽章层，2026-11-28 减配）===
# 页面已裁撤（controller/view 不装）；保留 CGI+cron 数据端点喂 Carbon 徽章
# （PPE 第四环/绑定明细/CPU 3h-24h 曲线/IPv6 修复, Scripts/carbon-bcyyt.js）
# 与 vantage 的 statusmon 注入主题互斥，不共存
if [[ "$WRT_THEME" = "argon" || "$WRT_THEME" = "carbon" ]] && [[ "$WRT_CONFIG" == IPQ95XX* ]]; then
AD_DIR="./package/bcyyt/luci-app-adash"
mkdir -p "$AD_DIR/files"
cp "$GITHUB_WORKSPACE/Scripts/inject/adash.Makefile" "$AD_DIR/Makefile"
for sf in adash-cgi carbon-bcyyt.js adash-ucid adash-sysctl.conf; do
        cp "$GITHUB_WORKSPACE/Scripts/$sf" "$AD_DIR/files/$sf" || echo "adash: $sf missing"
done
WRT_ROOT=$PWD
(cd "$AD_DIR" && make --no-print-directory -f Makefile TOPDIR="$WRT_ROOT" INCLUDE_DIR="$WRT_ROOT/include" -n >/dev/null 2>/tmp/ad_syntax.err) \
        && echo "adash Makefile syntax: OK" \
        || { echo "adash Makefile syntax FAILED:"; head -5 /tmp/ad_syntax.err; echo "FATAL: adash 已启用但 Makefile 语法错误，提前终止避免浪费整轮编译"; exit 1; }
fi

#===irq-tune（MT7988 以太网中断分核 + TX 队列 XPS）：自编组件独立成包（2026-11-18）===
# boot 期一次性调优：eth 中断向量按核摊开 + TX 队列 XPS；rc.d 符号链接随包内置自启
# 仅 MediaTek 目标启用（Settings.sh），其它平台脚本自动跳过无副作用
IT_DIR="./package/bcyyt/irq-tune"
mkdir -p "$IT_DIR/files"
cp "$GITHUB_WORKSPACE/Scripts/inject/irq-tune.Makefile" "$IT_DIR/Makefile"
cp "$GITHUB_WORKSPACE/Scripts/irq-tune-initd" "$IT_DIR/files/irq-tune-initd"
WRT_ROOT=$PWD
(cd "$IT_DIR" && make --no-print-directory -f Makefile TOPDIR="$WRT_ROOT" INCLUDE_DIR="$WRT_ROOT/include" -n >/dev/null 2>/tmp/it_syntax.err) \
        && echo "irq-tune Makefile syntax: OK" \
        || { echo "irq-tune Makefile syntax FAILED:"; head -5 /tmp/it_syntax.err; }

#引入私有扩展脚本
if [ -f "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh" ]; then
        source "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh"
fi
