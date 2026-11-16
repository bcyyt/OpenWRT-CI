# SPDX-License-Identifier: MIT
# luci-app-openclash - prebuilt ipk inject, static template (values injected via openclash.inc)

include $(TOPDIR)/rules.mk

include openclash.inc

include $(INCLUDE_DIR)/package.mk

define Package/luci-app-openclash
  SECTION:=luci
  CATEGORY:=LuCI
  TITLE:=OpenClash - Clash client with LuCI management
  URL:=https://github.com/vernesong/OpenClash
  DEPENDS:=+luci-base +bash +curl +ca-bundle +ipset +ip-full +libcap +kmod-tun +coreutils-nohup
  PKGARCH:=all
endef

define Package/luci-app-openclash/conffiles
/etc/config/openclash
endef

define Build/Prepare
        rm -rf $(PKG_BUILD_DIR)
        mkdir -p $(PKG_BUILD_DIR)/ipk $(PKG_BUILD_DIR)/root
        tar -C $(PKG_BUILD_DIR)/ipk -xzf $(DL_DIR)/$(PKG_SOURCE)
        tar -C $(PKG_BUILD_DIR)/root -xzf $(PKG_BUILD_DIR)/ipk/data.tar.gz
endef

define Build/Compile
endef

define Package/luci-app-openclash/install
        $(CP) $(PKG_BUILD_DIR)/root/. $(1)/
endef

$(eval $(call BuildPackage,luci-app-openclash))
