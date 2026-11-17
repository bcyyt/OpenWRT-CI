# SPDX-License-Identifier: MIT
# luci-app-statusmon: 仪表盘运行时后端（自编，standalone）
# 组成：statusmon v4.48 = 系统状态/快捷方式数据源 CGI（无额外依赖，服务自动检测）
#      + statusppe = PPE 硬件表项 + CPU USR/SYS 采样（5s，/sys/kernel/debug/ppe{0,1}/entries）
#      + statusflow = 每客户端实时速率 + 今日/累计流量 + 24h CPU/WAN 曲线采样（2s 节拍，30s series 点）
#      + seriesmon = 24h 曲线数据端点（转发 series.jsonl）
# Files land in ./files/ via Scripts/Packages.sh (no download, static injection)

# $(CURDIR) points at the buildroot root during recipes, and $(MAKEFILE_LIST)
# grows with every include, so resolve the package directory before rules.mk
PKG_DIR:=$(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-statusmon
PKG_VERSION:=4.48
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-statusmon
  SECTION:=luci
  CATEGORY:=LuCI
  TITLE:=Dashboard runtime: statusmon + statusppe + statusflow + seriesmon
  DEPENDS:=+jsonfilter
  PKGARCH:=all
endef

define Build/Prepare
	rm -rf $(PKG_BUILD_DIR)
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) $(PKG_DIR)/files/. $(PKG_BUILD_DIR)/
endef

define Build/Compile
endef

define Package/luci-app-statusmon/install
	$(INSTALL_DIR) $(1)/www/cgi-bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/statusmon $(1)/www/cgi-bin/statusmon
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/statusppe-cgi.sh $(1)/www/cgi-bin/statusppe
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/statusflow-cgi.sh $(1)/www/cgi-bin/statusflow
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/seriesmon-cgi.sh $(1)/www/cgi-bin/seriesmon
	$(INSTALL_DIR) $(1)/usr/lib
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/statusppe-worker.sh $(1)/usr/lib/statusppe-worker.sh
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/statusflow-worker.sh $(1)/usr/lib/statusflow-worker.sh
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/statusppe-initd $(1)/etc/init.d/statusppe
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/statusflow-initd $(1)/etc/init.d/statusflow
endef

$(eval $(call BuildPackage,luci-app-statusmon))
