# SPDX-License-Identifier: MIT
# luci-app-statusmon-dash: 全功能状态监控仪表盘页（S20P-612 专用）
# 组成：v9 仪表盘页（三环 CPU/内存/PPE + 24h 曲线 + 后台零轮询）
#      + statusmon v4.49 后端 = ubus 同源复用 + 25s 响应缓存 + 滚动均值统一口径
#      + statusppe worker = PPE 表项/绑定 + CPU 概览同源采样（ubus getCPUUsage）
#      + fwm 设计系统 common_head（页面依赖，包内自带，fwmanager 已不在 612 线）
# 与 luci-app-statusmon（618 线纯后端）CONFLICTS 互斥；无 statusflow/seriesmon 依赖
# Files land in ./files/ via Scripts/Packages.sh (no download, static injection)

# $(CURDIR) points at the buildroot root during recipes, and $(MAKEFILE_LIST)
# grows with every include, so resolve the package directory before rules.mk
PKG_DIR:=$(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-statusmon-dash
PKG_VERSION:=1.0.0
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-statusmon-dash
  SECTION:=luci
  CATEGORY:=LuCI
  TITLE:=Status dashboard: rings + PPE + 24h charts (overview-aligned)
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

define Package/luci-app-statusmon-dash/install
	$(INSTALL_DIR) $(1)/www/cgi-bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/statusmon-dash-cgi $(1)/www/cgi-bin/statusmon
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/statusppe-cgi.sh $(1)/www/cgi-bin/statusppe
	$(INSTALL_DIR) $(1)/usr/lib
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/statusppe-worker-dash.sh $(1)/usr/lib/statusppe-worker.sh
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/statusmon-dash-controller.lua $(1)/usr/lib/lua/luci/controller/statusmon.lua
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/statusmon
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/statusmon-dash-view.htm $(1)/usr/lib/lua/luci/view/statusmon/status.htm
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/fwmanager
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/fwmanager-common-head.htm $(1)/usr/lib/lua/luci/view/fwmanager/common_head.htm
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/statusppe-initd $(1)/etc/init.d/statusppe
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/statusmon-dash-ucid $(1)/etc/uci-defaults/99_statusmon-dash-cron
endef

$(eval $(call BuildPackage,luci-app-statusmon-dash))
