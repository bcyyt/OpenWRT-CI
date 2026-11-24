# luci-app-fcdash: 仿 FanchmWrt 布局仪表盘（数据源复用 /cgi-bin/adash）
include $(TOPDIR)/rules.mk
PKG_NAME:=luci-app-fcdash
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKGARCH:=all
include $(INCLUDE_DIR)/package.mk
define Package/luci-app-fcdash
  SECTION:=luci
  CATEGORY:=LuCI
  TITLE:=FC dashboard (FanchmWrt-style)
  DEPENDS:=+luci-base +luci-app-adash
endef
define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./files/. $(PKG_BUILD_DIR)/
endef
define Build/Compile
endef
define Package/luci-app-fcdash/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/fcdash
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/fcdash-view.htm $(1)/usr/lib/lua/luci/view/fcdash/dash.htm
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/fcdash-controller.lua $(1)/usr/lib/lua/luci/controller/fcdash.lua
endef
$(eval $(call BuildPackage,luci-app-fcdash))
