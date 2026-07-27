#!/bin/bash
# DIY脚本
# https://github.com/P3TERX/Actions-OpenWrt
# 文件名: diy-part1.sh
# 功能说明: OpenWrt DIY脚本第1部分（更新feeds之前）
# 版权: (c) 2019-2024 P3TERX <https://p3terx.com>
# 基于 MIT 开源协议，详见 /LICENSE

# 取消注释一个源
# sed -i 's/^#\(.*helloworld\)/\1/' feeds.conf.default

# 添加第三方 feed 源（small-package 包含 openclash/passwall/ssr-plus 等常用插件）
echo 'src-git smpackage https://github.com/kenzok8/small-package' >> feeds.conf.default
# 添加第三方源，iStore 应用商店，编译时包名输入 luci-app-store
echo 'src-git store https://github.com/linkease/istore.git;main' >> feeds.conf.default

# The MSM8916 UFI003 device tree exposes board Bluetooth as qcom,wcnss-bt.
# Upstream does not package btqcomsmd.ko, so create the package before
# feeds/configuration are processed.
mkdir -p package/kernel/btqcomsmd
cat > package/kernel/btqcomsmd/Makefile << 'EOF'
include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk

PKG_NAME:=kmod-btqcomsmd
PKG_RELEASE:=1

include $(INCLUDE_DIR)/package.mk

define KernelPackage/btqcomsmd
  SUBMENU:=Bluetooth Support
  TITLE:=Qualcomm WCNSS SMD Bluetooth support
  DEPENDS:=+kmod-bluetooth
  KCONFIG:= \
	CONFIG_QCOM_WCNSS_CTRL \
	CONFIG_BT_QCA \
	CONFIG_BT_QCOMSMD
  FILES:= \
	$(LINUX_DIR)/drivers/bluetooth/btqca.ko \
	$(LINUX_DIR)/drivers/bluetooth/btqcomsmd.ko
  AUTOLOAD:=$(call AutoProbe,btqca btqcomsmd)
endef

define KernelPackage/btqcomsmd/description
 Kernel support for Qualcomm WCNSS Bluetooth connected through SMD.
endef

# The modules are built by the kernel tree; this package only installs them.
# Keep this explicit no-op: an empty definition falls back to the default
# package build and attempts make in an empty PKG_BUILD_DIR.
define Build/Compile
	true
endef

$(eval $(call KernelPackage,btqcomsmd))
EOF


# OpenClash代理
# git clone --depth 1 https://github.com/vernesong/OpenClash.git OpenClash

# turboacc网络加速（需要用户在页面选择 luci-app-turboacc 后，由编译脚本自动执行，此处不再无条件运行）
# curl -sSL https://raw.githubusercontent.com/mufeng05/turboacc/main/add_turboacc.sh -o add_turboacc.sh && bash add_turboacc.sh

# 调试
# sed -i 's|src-git-full openstick https://github.com/lkiuyu/openstick-feeds.git|src-git-full openstick https://github.com/xuxin1955/openstick-feeds|g' feeds.conf.default



