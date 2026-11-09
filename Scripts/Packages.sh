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
UPDATE_PACKAGE "argon" "sbwml/luci-theme-argon" "openwrt-25.12"
UPDATE_PACKAGE "aurora" "eamonxg/luci-theme-aurora" "master"
UPDATE_PACKAGE "aurora-config" "eamonxg/luci-app-aurora-config" "master"
UPDATE_PACKAGE "fluent" "LazuliKao/luci-theme-fluent" "main"
UPDATE_PACKAGE "footstrap" "VizzleTF/luci-theme-footstrap" "main"
UPDATE_PACKAGE "kucat" "sirpdboy/luci-theme-kucat" "master"
UPDATE_PACKAGE "kucat-config" "sirpdboy/luci-app-kucat-config" "master"
UPDATE_PACKAGE "shadcn" "eamonxg/luci-theme-shadcn" "main"
UPDATE_PACKAGE "vantage" "anothaDev/luci-theme-vantage" "main"

UPDATE_PACKAGE "momo" "nikkinikki-org/OpenWrt-momo" "main"
UPDATE_PACKAGE "nikki" "nikkinikki-org/OpenWrt-nikki" "main"
UPDATE_PACKAGE "openclash" "vernesong/OpenClash" "dev" "pkg"
UPDATE_PACKAGE "passwall" "Openwrt-Passwall/openwrt-passwall" "main" "pkg"
UPDATE_PACKAGE "passwall2" "Openwrt-Passwall/openwrt-passwall2" "main" "pkg"

UPDATE_PACKAGE "diskmanager" "4IceG/luci-app-mini-diskmanager" "main"
UPDATE_PACKAGE "easytier" "EasyTier/luci-app-easytier" "main"
UPDATE_PACKAGE "lucky" "gdy666/luci-app-lucky" "main"
UPDATE_PACKAGE "qmodem" "FUjr/QModem" "main"
UPDATE_PACKAGE "viking" "VIKINGYFY/packages" "main" "" "axonhub gecoosac miniupnpd sing-box luci-app-homeproxy luci-app-timewol luci-app-upnp luci-app-wolplus luci-app-wolultra"

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
        HASH=$(curl -fsSL --retry 3 --connect-timeout 15 "$1" | sha256sum | cut -d ' ' -f 1)
        [ -n "$HASH" ] || HASH=skip
        echo "$HASH"
}

#生成内置包Makefile：把预编译ipk的data.tar.gz原样装入rootfs
#参数：包名 版本 描述 依赖 ipk解包命令(external make语法) conffiles列表 额外架构头部 编译期patch命令(可选,在root解包后执行)
BCYYT_INJECT() {
        local PKG_NAME=$1
        local PKG_VER=$2
        local PKG_TITLE=$3
        local PKG_DEPS=$4
        local PKG_UNPACK=$5
        local PKG_CONFFILES=$6
        local PKG_HEADER=$7
        local PKG_PATCH=$8
        local PKG_DIR="./package/bcyyt/$PKG_NAME"

        mkdir -p "$PKG_DIR"

        cat > "$PKG_DIR/Makefile" <<EOF
# SPDX-License-Identifier: MIT
# auto-generated by Scripts/Packages.sh from gitee.com/bcyyt/my-openwrt
# 不要手动编辑：每次CI运行都会重新生成

include \$(TOPDIR)/rules.mk

PKG_NAME:=$PKG_NAME
PKG_VERSION:=$PKG_VER
$PKG_HEADER
include \$(INCLUDE_DIR)/package.mk

define Package/$PKG_NAME
  SECTION:=luci
  CATEGORY:=LuCI
  TITLE:=$PKG_TITLE
  URL:=https://gitee.com/bcyyt/my-openwrt
  DEPENDS:=$PKG_DEPS
  PKGARCH:=all
endef

define Build/Prepare
        rm -rf \$(PKG_BUILD_DIR)
        mkdir -p \$(PKG_BUILD_DIR)/ipk \$(PKG_BUILD_DIR)/root
        $PKG_UNPACK
        tar -C \$(PKG_BUILD_DIR)/root -xzf \$(PKG_BUILD_DIR)/ipk/data.tar.gz
        $PKG_PATCH
endef

define Build/Compile
endef

define Package/$PKG_NAME/conffiles
$PKG_CONFFILES
endef

define Package/$PKG_NAME/install
        \$(CP) \$(PKG_BUILD_DIR)/root/. \$(1)/
endef

\$(eval \$(call BuildPackage,$PKG_NAME))
EOF

        echo "$PKG_NAME $PKG_VER has been generated into package/bcyyt/$PKG_NAME/!"
}

#===iptv-auth：版本与下载地址来自version.json，始终跟随OTA仓最新版===
IPTV_VER=$(curl -fsSL --retry 3 --connect-timeout 15 "$BCYYT_RAW/iptv-auth/version.json" | jq -r ".version" 2>/dev/null)
[ -n "$IPTV_VER" ] || IPTV_VER="2.3.70-r15"
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
SYSKEEP_VER=$(curl -fsSL --retry 3 --connect-timeout 15 "$BCYYT_API/luci-app-syskeep" | jq -r ".[].name" 2>/dev/null | grep -E "^luci-app-syskeep_.*_x86_64\.ipk$" | sed "s/luci-app-syskeep_//;s/_x86_64.ipk//" | sort -V | tail -1)
[ -n "$SYSKEEP_VER" ] || SYSKEEP_VER="1.0.35-r0"
echo "luci-app-syskeep latest version: $SYSKEEP_VER"

SYSKEEP_HASH=$(BCYYT_SHA256 "$BCYYT_RAW/luci-app-syskeep/luci-app-syskeep_${SYSKEEP_VER}_x86_64.ipk")

BCYYT_INJECT "luci-app-syskeep" "$SYSKEEP_VER" \
        "LuCI 保留升级：刷机保留配置、分区和插件清单，开机重装apk" \
        "+luci-base +luci-compat" \
        "tar -C \$(PKG_BUILD_DIR)/ipk -xzf \$(DL_DIR)/\$(PKG_SOURCE)" \
        "/etc/syskeep/custom-apks.txt
/etc/syskeep/datadir.sh" \
        "PKG_SOURCE:=luci-app-syskeep_\$(PKG_VERSION)_x86_64.ipk
PKG_SOURCE_URL:=$BCYYT_RAW/luci-app-syskeep
PKG_HASH:=$SYSKEEP_HASH"

#===luci-app-statusfw（状态与防火墙）：剔除状态页保留快捷方式（状态信息由Vantage仪表盘承担），版本跟随OTA仓最新版===
STATUSFW_VER=$(curl -fsSL --retry 3 --connect-timeout 15 "$BCYYT_API/luci-app-statusfw" | jq -r ".[].name" 2>/dev/null | grep -E "^luci-app-statusfw_.*_x86_64\.ipk$" | sed "s/luci-app-statusfw_//;s/_x86_64.ipk//" | sort -V | tail -1)
[ -n "$STATUSFW_VER" ] || STATUSFW_VER="5.0.15"
echo "luci-app-statusfw latest version: $STATUSFW_VER"

STATUSFW_HASH=$(BCYYT_SHA256 "$BCYYT_RAW/luci-app-statusfw/luci-app-statusfw_${STATUSFW_VER}_x86_64.ipk")

BCYYT_INJECT "luci-app-statusfw" "$STATUSFW_VER" \
        "LuCI 状态与防火墙：快捷方式、端口转发、规则管理、安全监测、系统日志（状态页已剔除，由仪表盘承担）" \
        "+luci-base +luci-compat +python3 +nftables +firewall4" \
        "tar -C \$(PKG_BUILD_DIR)/ipk -xzf \$(DL_DIR)/\$(PKG_SOURCE)" \
        "/etc/config/statusfw-net
/etc/config/fwmanager
/etc/config/statusmon" \
        "PKG_SOURCE:=luci-app-statusfw_\$(PKG_VERSION)_x86_64.ipk
PKG_SOURCE_URL:=$BCYYT_RAW/luci-app-statusfw
PKG_HASH:=$STATUSFW_HASH" \
        "bash $GITHUB_WORKSPACE/Scripts/statusfw-patch.sh \$(PKG_BUILD_DIR)"

#引入私有扩展脚本
if [ -f "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh" ]; then
        source "$GITHUB_WORKSPACE/Scripts/PRIVATE.sh"
fi
