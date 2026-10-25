# WCUltra - Theos tweak Makefile
# 构建: 在装有 Theos + iOS SDK 的 macOS/Linux 上执行 `make package`
# 可选: export THEOS_DEVICE_IP=<设备IP> 后 `make install` 直接安装

TARGET := iphone:clang:latest:14.0
ARCHS := arm64 arm64e
INSTALL_TARGET_PROCESSES = WeChat

# 若设备是 rootless (iOS 15+ / Dopamine 等), 取消下面一行注释
# THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = WCUltra

WCUltra_FILES = Tweak.xm
WCUltra_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
WCUltra_FRAMEWORKS = UIKit Foundation CoreGraphics

include $(THEOS_MAKE_PATH)/tweak.mk
