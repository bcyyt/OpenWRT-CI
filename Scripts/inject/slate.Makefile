# luci-theme-slate：暗色科技主题（fork bootstrap 壳 + 皮肤）
include $(TOPDIR)/rules.mk
PKG_NAME:=luci-theme-slate
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKGARCH:=all
include $(INCLUDE_DIR)/package.mk
define Package/luci-theme-slate
  SECTION:=luci
  CATEGORY:=LuCI
  TITLE:=Slate dark tech theme
  DEPENDS:=+luci-base
endef
define Build/Prepare
        mkdir -p $(PKG_BUILD_DIR)
        $(CP) ./files/. $(PKG_BUILD_DIR)/
endef
define Build/Compile
endef
define Package/luci-theme-slate/install
        $(INSTALL_DIR) $(1)/usr/share/ucode/luci/template/themes/slate
        $(INSTALL_DATA) $(PKG_BUILD_DIR)/slate-header.ut $(1)/usr/share/ucode/luci/template/themes/slate/header.ut
        $(INSTALL_DATA) $(PKG_BUILD_DIR)/slate-footer.ut $(1)/usr/share/ucode/luci/template/themes/slate/footer.ut
        $(INSTALL_DATA) $(PKG_BUILD_DIR)/slate-sysauth.ut $(1)/usr/share/ucode/luci/template/themes/slate/sysauth.ut
        $(INSTALL_DIR) $(1)/www/luci-static/slate
        $(INSTALL_DATA) $(PKG_BUILD_DIR)/slate-cascade.css $(1)/www/luci-static/slate/cascade.css
        $(INSTALL_DATA) $(PKG_BUILD_DIR)/slate-mobile.css $(1)/www/luci-static/slate/mobile.css
endef
$(eval $(call BuildPackage,luci-theme-slate))
