# SPDX-License-Identifier: MIT
# honk - prebuilt ipk inject, static template (values injected via honk.inc)

include $(TOPDIR)/rules.mk

include honk.inc

include $(INCLUDE_DIR)/package.mk

define Package/honk
  SECTION:=luci
  CATEGORY:=LuCI
  TITLE:=honk - eBPF transparent proxy engine (dae-compatible), Rust+Aya
  URL:=https://gitee.com/bcyyt/my-openwrt
  DEPENDS:=+kmod-sched-core +kmod-sched-bpf +kmod-veth +kmod-nft-queue +ca-bundle +v2ray-geoip +v2ray-geosite @(aarch64||x86_64)
  PKGARCH:=all
endef

define Package/honk/conffiles
/etc/honk/config.dae
endef

define Build/Prepare
	rm -rf $(PKG_BUILD_DIR)
	mkdir -p $(PKG_BUILD_DIR)/ipk $(PKG_BUILD_DIR)/root
	tar -C $(PKG_BUILD_DIR)/ipk -xzf $(DL_DIR)/$(PKG_SOURCE)
	tar -C $(PKG_BUILD_DIR)/root -xzf $(PKG_BUILD_DIR)/ipk/data.tar.gz
endef

define Build/Compile
endef

define Package/honk/install
	$(CP) $(PKG_BUILD_DIR)/root/. $(1)/
endef

$(eval $(call BuildPackage,honk))
