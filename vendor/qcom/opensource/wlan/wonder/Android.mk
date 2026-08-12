# Android Makefile for wonder modules

# LOCAL_PATH is a relative path to root build directory.
LOCAL_PATH := $(call my-dir)
LOCAL_MODULE_DDK_BUILD := true
LOCAL_MODULE_DDK_ALLOW_UNSAFE_HEADERS := true
LOCAL_MODULE_KO_DIRS := wonder.ko

BOARD_COMMON_DIR ?= device/qcom/common
DLKM_DIR := $(TOP)/$(BOARD_COMMON_DIR)/dlkm

# Sourcing all files is for better incremental compilation.
WONDER_SRC_FILES := \
        $(wildcard $(LOCAL_PATH)/*) \
        $(wildcard $(LOCAL_PATH)/*/*) \

# Module.symvers needs to be generated as a intermediate module so that
# other modules which depend on WLAN platform modules can set local
# dependencies to it.

########################### Module.symvers ############################
#include $(CLEAR_VARS)
#LOCAL_SRC_FILES           := $(WONDER_SRC_FILES)
#LOCAL_MODULE              := wlan-platform-module-symvers
#LOCAL_MODULE_STEM         := Module.symvers
#LOCAL_MODULE_KBUILD_NAME  := Module.symvers
#LOCAL_MODULE_PATH         := $(KERNEL_MODULES_OUT)
#include $(DLKM_DIR)/Build_external_kernelmodule.mk

# Below are for Android build system to recognize each module name, so
# they can be installed properly. Since Kbuild is used to compile these
# modules, invoking any of them will cause other modules to be compiled
# as well if corresponding flags are added in KBUILD_OPTIONS from upper
# level Makefiles like wlan.mk.

################################ cnss2 ################################
include $(CLEAR_VARS)
ifeq ($(TARGET_KERNEL_DLKM_SECURE_MSM_OVERRIDE), true)
LOCAL_REQUIRED_MODULES := sec-module-symvers
LOCAL_ADDITIONAL_DEPENDENCIES += $(call intermediates-dir-for,DLKM,sec-module-symvers)/Module.symvers
endif #TARGET_KERNEL_DLKM_SECURE_MSM_OVERRIDE
LOCAL_SRC_FILES           := $(WONDER_SRC_FILES)
LOCAL_MODULE              := wonder.ko
LOCAL_MODULE_KBUILD_NAME  := wonder.ko
LOCAL_MODULE_TAGS         := optional
LOCAL_MODULE_DEBUG_ENABLE := true
LOCAL_MODULE_PATH         := $(KERNEL_MODULES_OUT)
include $(DLKM_DIR)/Build_external_kernelmodule.mk

