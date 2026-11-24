# luci-app-slatebox：科技风工具仪表盘（全新构建，非 adash）
include $(TOPDIR)/rules.mk
PKG_NAME:=luci-app-slatebox
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKGARCH:=all
include $(INCLUDE_DIR)/package.mk
define Package/luci-app-slatebox
  SECTION:=luci
  CATEGORY:=LuCI
  TITLE:=SlateBox tech dashboard with tools
  DEPENDS:=+luci-base +curl +etherwake
endef
define Build/Prepare
        mkdir -p $(PKG_BUILD_DIR)
        $(CP) ./files/. $(PKG_BUILD_DIR)/
endef
define Build/Compile
endef
define Package/luci-app-slatebox/install
        $(INSTALL_DIR) $(1)/www/cgi-bin
        $(INSTALL_BIN) $(PKG_BUILD_DIR)/slatebox-cgi $(1)/www/cgi-bin/slatebox
        $(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
        $(INSTALL_DATA) $(PKG_BUILD_DIR)/slatebox-controller.lua $(1)/usr/lib/lua/luci/controller/slatebox.lua
        $(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/slatebox
        $(INSTALL_DATA) $(PKG_BUILD_DIR)/slatebox-dash.htm $(1)/usr/lib/lua/luci/view/slatebox/dash.htm
endef
$(eval $(call BuildPackage,luci-app-slatebox))
