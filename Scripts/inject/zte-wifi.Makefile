# SPDX-License-Identifier: MIT
# zte-wifi: ZTE mesh wireless client details (self-made, standalone)
# Files land in ./files/ via Scripts/Packages.sh (no download, static injection)

include $(TOPDIR)/rules.mk

PKG_NAME:=zte-wifi
PKG_VERSION:=5.3
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk

PKG_DIR:=$(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

define Package/zte-wifi
  SECTION:=luci
  CATEGORY:=LuCI
  TITLE:=ZTE mesh wireless client details
  URL:=https://gitee.com/bcyyt/my-openwrt
  DEPENDS:=+luci-base +rpcd +python3
  PKGARCH:=all
endef

define Package/zte-wifi/conffiles
/etc/config/zte-wifi
endef

define Build/Prepare
	rm -rf $(PKG_BUILD_DIR)
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) $(PKG_DIR)/files/. $(PKG_BUILD_DIR)/
endef

define Build/Compile
endef

define Package/zte-wifi/install
	$(INSTALL_DIR) $(1)/usr/lib
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/zte-wifi.py $(1)/usr/lib/zte-wifi.py
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/zte-initd $(1)/etc/init.d/zte-wifi
	$(INSTALL_DIR) $(1)/www/cgi-bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/zteinfo-cgi.sh $(1)/www/cgi-bin/zteinfo
	$(INSTALL_DIR) $(1)/www/luci-static/resources/view
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/zte-wifi-view.js $(1)/www/luci-static/resources/view/zte-wifi.js
	$(INSTALL_DIR) $(1)/usr/share/luci/menu.d
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/zte-menu.json $(1)/usr/share/luci/menu.d/luci-app-zte-wifi.json
	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/zte-acl.json $(1)/usr/share/rpcd/acl.d/luci-app-zte-wifi.json
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) $(PKG_BUILD_DIR)/zte-default-config $(1)/etc/config/zte-wifi
endef

$(eval $(call BuildPackage,zte-wifi))
