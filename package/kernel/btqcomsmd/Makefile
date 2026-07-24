include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk

PKG_NAME:=kmod-btqcomsmd
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define KernelPackage/btqcomsmd
  SUBMENU:=Bluetooth Support
  TITLE:=Qualcomm WCNSS SMD Bluetooth support
  DEPENDS:=+kmod-bluetooth
  KCONFIG:=CONFIG_BT_QCOMSMD
  FILES:=$(LINUX_DIR)/drivers/bluetooth/btqcomsmd.ko
  AUTOLOAD:=$(call AutoProbe,btqcomsmd)
endef

define KernelPackage/btqcomsmd/description
 Kernel support for Qualcomm WCNSS Bluetooth connected through SMD.
endef

$(eval $(call KernelPackage,btqcomsmd))
