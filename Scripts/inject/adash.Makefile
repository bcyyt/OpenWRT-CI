# SPDX-License-Identifier: MIT
# luci-app-adash: 低 CPU 状态监控仪表盘（QCB-ARGON 线专用，Argon 主题）
# fork statusmon-dash v9 页面 + v4.49 后端，低 CPU 改造：
#   - 无常驻采样（statusppe worker 移除）：CPU=视图请求间差分，PPE=60s 视图缓存
#   - conntrack 客户端聚合/协议统计=30s 视图缓存（无人查看零成本）
#   - cron(1/min) 仅 nft 计数累计 + sys_hist 采样
# fwm 设计系统 common_head 为页面依赖（包内自带）
# 与 luci-app-statusmon（vantage 后端）/ statusmon-dash（S20P）CONFLICTS 互斥
# Files land in ./files/ via Scripts/Packages.sh (no download, static injection)

# $(CURDIR) points at the buildroot root during recipes, and $(MAKEFILE_LIST)
# grows with every include, so resolve the package directory before rules.mk
PKG_DIR:=$(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-adash
PKG_VERSION:=1.0.0
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-adash
  SECTION:=luci
  CATEGORY:=LuCI
  TITLE:=Low-CPU status dashboard (Argon, QCB-ARGON line)
  MAINTAINER:=bcyyt
  DEPENDS:=+jsonfilter
  CONFLICTS:=luci-app-statusmon
endef

define Build/Prepare
        rm -rf $(PKG_BUILD_DIR)
        mkdir -p $(PKG_BUILD_DIR)
        $(CP) $(PKG_DIR)/files/. $(PKG_BUILD_DIR)/
endef

define Build/Compile
endef

define Package/luci-app-adash/install
	$(INSTALL_DIR) $(1)/www/cgi-bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/adash-cgi $(1)/www/cgi-bin/adash
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/adash-controller.lua $(1)/usr/lib/lua/luci/controller/adash.lua
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/adash
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/adash-view.htm $(1)/usr/lib/lua/luci/view/adash/status.htm
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/fwmanager
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/fwmanager-common-head.htm $(1)/usr/lib/lua/luci/view/fwmanager/common_head.htm
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/adash-ucid $(1)/etc/uci-defaults/99_adash-cron
endef

$(eval $(call BuildPackage,luci-app-adash))
