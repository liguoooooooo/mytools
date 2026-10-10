#!/bin/bash

# ===== 二手 MacBook 验机工具 =====

echo "===== 二手 MacBook 验机工具 ====="
echo ""

echo "==== 设备信息 ===="
echo "  机型: $(sysctl -n hw.model 2>/dev/null)"
echo "  芯片: $(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
echo "  系统: macOS $(sw_vers -productVersion 2>/dev/null) ($(uname -m))"
echo "  序列号: $(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Serial Number/ {print $2}')"
echo "  硬件UUID: $(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Hardware UUID/ {print $2}')"
echo "  内存: $(sysctl -n hw.memsize 2>/dev/null | awk '{print $1/1024/1024/1024 " GB"}')"
echo "  激活锁状态: $(nvram ActivationLockState 2>/dev/null | awk '{print $2}')"
echo "  固件版本: $(system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/System Firmware Version/ {print $2}')"
echo "  系统构建: $(sw_vers -buildVersion 2>/dev/null)"

# DEP / MDM 检查
DEP_STATUS="No"
system_profiler SPConfigurationProfileDataType 2>/dev/null | grep -i "MDM" >/dev/null && DEP_STATUS="Yes"
echo "  监管锁(DEP/MDM): DEP=${DEP_STATUS} / MDM=${DEP_STATUS}"
echo ""

echo "==== 电池健康 ===="
BATTERY_INFO=$(system_profiler SPPowerDataType 2>/dev/null)
echo "  循环次数: $(echo "$BATTERY_INFO" | awk -F': ' '/Cycle Count/ {print $2}')"
echo "  最大容量: $(echo "$BATTERY_INFO" | awk -F': ' '/Maximum Capacity/ {print $2}')"
echo "  电池状态: $(echo "$BATTERY_INFO" | awk -F': ' '/Condition/ {print $2}')"
echo ""

echo "==== SSD 健康 (SMART) ===="
diskutil info disk0 2>/dev/null | grep -E "Device / Media Name|SMART Status|Disk Size"
echo ""

echo "==== 内存 / CPU ===="
echo "  CPU: $(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
echo "  逻辑核心: $(sysctl -n hw.ncpu 2>/dev/null)"
echo "  内存: $(sysctl -n hw.memsize 2>/dev/null | awk '{print $1/1024/1024/1024 " GB"}')"
echo ""

echo "==== 网络 / 蓝牙 ===="
networksetup -listallhardwareports 2>/dev/null | grep -A 2 "Wi-Fi"
echo ""

echo "==== 屏幕信息 ===="
system_profiler SPDisplaysDataType 2>/dev/null | grep -E "Resolution|Metal"
echo ""

echo "==== 存储、接口与系统硬件清单 ===="
diskutil list / 2>/dev/null | head -n 10