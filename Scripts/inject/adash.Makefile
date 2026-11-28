# SPDX-License-Identifier: MIT
# luci-app-adash: PPE/CPU 曲线数据后端 + Carbon 徽章注入层（2026-11-28 减配改造）
# 原为 Argon 独立状态监控页面；2026-11-28 起 Carbon 主题接管界面：
#   - 页面已裁撤（controller/view 不再安装，菜单不注册，登录落点=Carbon 概览）
#   - 保留 /www/cgi-bin/adash（PPE/host/nh/sys_hist 数据端点，25s/60s 视图缓存）
#   - 保留 cron(1/min) nft 计数累计 + sys_hist 采样（CPU 曲线 3h/24h 数据源）
#   - 保留 21-adash-conntrack.sysctl（nf_conntrack 容量调优）
#   - 新增 carbon-bcyyt.js 注入 Carbon 资源卡：PPE 第四环+绑定明细、
#     CPU 环点击 3h/24h 历史曲线、IPv6 显示不全修复（v3.0）
# 与 luci-app-statusmon（vantage 后端）/ statusmon-dash（S20P）CONFLICTS 互斥
# Files land in ./files/ via Scripts/Packages.sh (no download, static injection)

# $(CURDIR) points at the buildroot root during recipes, and $(MAKEFILE_LIST)
# grows with every include, so resolve the package directory before rules.mk
PKG_DIR:=$(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-adash
PKG_VERSION:=1.1.0
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-adash
  SECTION:=luci
  CATEGORY:=LuCI
  TITLE:=PPE/CPU hist backend + Carbon badges (QCB-CARBON line)
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
	# carbon-bcyyt.js: Carbon 徽章层（PPE 环/CPU 曲线/IPv6 修复），由 footer.ut 注入行载入
	$(INSTALL_DIR) $(1)/www/luci-static/resources
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/carbon-bcyyt.js $(1)/www/luci-static/resources/carbon-bcyyt.js
	$(INSTALL_DIR) $(1)/etc/uci-defaults
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/adash-ucid $(1)/etc/uci-defaults/99_adash-cron
	$(INSTALL_DIR) $(1)/etc/sysctl.d
	# 序号必须 >11：上游 11-nf-conntrack.conf(established=7440) 与本文件同目录，
	# sysctl 按文件名倒序加载、后加载者覆盖前者；11-adash 字典序早于 11-nf
	# 被压住，实测新固件仍 7440。改 21-adash 保证在 11-nf 之后加载生效
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/adash-sysctl.conf $(1)/etc/sysctl.d/21-adash-conntrack.conf
endef

$(eval $(call BuildPackage,luci-app-adash))
