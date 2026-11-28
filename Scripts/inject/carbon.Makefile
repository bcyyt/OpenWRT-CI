# SPDX-License-Identifier: MIT
# luci-theme-carbon: Apple 风格 LuCI 主题（QCB-CARBON 线默认主题）
# 来源: ImmortalWrt snapshot feed 的 luci-theme-carbon 1.2.0-r1（已从 feed 下架）,
#       本包文件取自 SBE1V1K 实机安装集——与 2026-11-28 全天实机回归验证的
#       文件一字不差(PPE 第四环/CPU 3h-24h 曲线/IPv6 修复均在界面上跑通过)。
# 静态注入(同 adash 模式): 文件树在 Scripts/carbon-theme/, Packages.sh 装配,
#       不 clone 不依赖外部源, feed 滚动/上游删包均不影响构建确定性。
# 徽章层: Handles.sh 的 theme-carbon-badges FIX 在构建期向 footer.ut 注入
#       carbon-bcyyt.js 载入行(脚本本体由 luci-app-adash 包安装)。
# Files land in ./files/ via Scripts/Packages.sh (no download, static injection)

# $(CURDIR) points at the buildroot root during recipes, and $(MAKEFILE_LIST)
# grows with every include, so resolve the package directory before rules.mk
PKG_DIR:=$(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-theme-carbon
PKG_VERSION:=1.2.0
PKG_RELEASE:=1
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/luci-theme-carbon
  SECTION:=luci
  CATEGORY:=LuCI
  TITLE:=Carbon Theme (Apple-style, beginner friendly)
  MAINTAINER:=bcyyt
  DEPENDS:=+luci-base
endef

define Build/Prepare
	rm -rf $(PKG_BUILD_DIR)
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) $(PKG_DIR)/files/. $(PKG_BUILD_DIR)/
endef

define Build/Compile
endef

define Package/luci-theme-carbon/install
# 按顶层数据目录显式拷贝: $(1)(ipkg 根)位于 $(PKG_BUILD_DIR) 内, 整树
# $(CP) $(PKG_BUILD_DIR)/. $(1)/ 会 "copy a directory into itself" 报错
# (2026-11-28 run 46114139694 实测教训); $(CP)=-fpR 保留执行位(rpcd/uci-defaults 0755)
	$(INSTALL_DIR) $(1)/etc $(1)/usr $(1)/www
	$(CP) $(PKG_BUILD_DIR)/etc/. $(1)/etc/
	$(CP) $(PKG_BUILD_DIR)/usr/. $(1)/usr/
	$(CP) $(PKG_BUILD_DIR)/www/. $(1)/www/
endef

$(eval $(call BuildPackage,luci-theme-carbon))
