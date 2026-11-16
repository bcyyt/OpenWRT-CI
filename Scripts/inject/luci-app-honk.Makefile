# SPDX-License-Identifier: MIT
# luci-app-honk - prebuilt ipk inject, static template (values injected via honk-luci.inc)

include $(TOPDIR)/rules.mk

include honk-luci.inc

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-honk
  SECTION:=luci
  CATEGORY:=LuCI
  TITLE:=LuCI page and Doona control panel for honk
  URL:=https://gitee.com/bcyyt/my-openwrt
  DEPENDS:=+luci-base +luci-compat +honk
  PKGARCH:=all
endef

define Package/luci-app-honk/conffiles
/etc/config/honk
endef

define Build/Prepare
	rm -rf $(PKG_BUILD_DIR)
	mkdir -p $(PKG_BUILD_DIR)/ipk $(PKG_BUILD_DIR)/root
	tar -C $(PKG_BUILD_DIR)/ipk -xzf $(DL_DIR)/$(PKG_SOURCE)
	tar -C $(PKG_BUILD_DIR)/root -xzf $(PKG_BUILD_DIR)/ipk/data.tar.gz
endef

define Build/Compile
endef

define Package/luci-app-honk/install
	$(CP) $(PKG_BUILD_DIR)/root/. $(1)/
endef

$(eval $(call BuildPackage,luci-app-honk))
