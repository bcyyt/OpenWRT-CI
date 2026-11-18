# SPDX-License-Identifier: MIT
# irq-tune: MT7988 ethernet IRQ affinity + TX queue XPS (self-made, standalone)
# boot 期一次性执行（无守护）；rc.d 符号链接随包内置，无需 uci-defaults enable。
# Files land in ./files/ via Scripts/Packages.sh (no download, static injection)

# $(CURDIR) points at the buildroot root during recipes, and $(MAKEFILE_LIST)
# grows with every include, so resolve the package directory before rules.mk
# (OpenWrt's built-in PKG_DIR points at $(TOPDIR)/include, not this package).
PKG_DIR:=$(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

include $(TOPDIR)/rules.mk

PKG_NAME:=irq-tune
PKG_VERSION:=1.0
PKGARCH:=all

include $(INCLUDE_DIR)/package.mk


define Package/irq-tune
  SECTION:=base
  CATEGORY:=Base system
  TITLE:=MT7988 ethernet IRQ affinity and TX XPS tuning
  URL:=https://gitee.com/bcyyt/my-openwrt
  PKGARCH:=all
endef

define Build/Prepare
	rm -rf $(PKG_BUILD_DIR)
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) $(PKG_DIR)/files/. $(PKG_BUILD_DIR)/
endef

define Build/Compile
endef

define Package/irq-tune/install
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/irq-tune-initd $(1)/etc/init.d/irq-tune
	$(INSTALL_DIR) $(1)/etc/rc.d
	ln -s ../init.d/irq-tune $(1)/etc/rc.d/S99irq-tune
endef

$(eval $(call BuildPackage,irq-tune))
