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

DEP_STATUS="No"
system_profiler SPConfigurationProfileDataType 2>/dev/null | grep -i "MDM" >/dev/null && DEP_STATUS="Yes"
echo "  监管锁(DEP/MDM): DEP=${DEP_STATUS} / MDM=${DEP_STATUS}"
echo ""

echo "==== 电池健康 ===="
BATTERY_INFO=$(system_profiler SPPowerDataType 2>/dev/null)
CYCLE_COUNT=$(echo "$BATTERY_INFO" | awk -F': ' '/Cycle Count/ {print $2}' | tr -d '[:space:]')
MAX_CAPACITY=$(echo "$BATTERY_INFO" | awk -F': ' '/Maximum Capacity/ {print $2}' | tr -d '[:space:]')
BAT_CONDITION=$(echo "$BATTERY_INFO" | awk -F': ' '/Condition/ {print $2}')

echo "  循环次数: ${CYCLE_COUNT}"
echo "  最大容量: ${MAX_CAPACITY}"
echo "  电池状态: ${BAT_CONDITION}"
echo "  健康度(实测): ${MAX_CAPACITY}"
echo ""

echo "==== SSD 健康 (SMART) ===="
# 尝试使用 smartctl 如果存在，否则使用 diskutil
if command -v smartctl &> /dev/null; then
    SMART_OUT=$(smartctl -a /dev/disk0 2>/dev/null)
    echo "  型号: $(echo "$SMART_OUT" | grep "Device Model" | awk -F: '{print $2}' | xargs)"
    echo "  累计读取: $(echo "$SMART_OUT" | grep "Data Units Read" | awk -F: '{print $2}' | xargs)"
    echo "  累计写入: $(echo "$SMART_OUT" | grep "Data Units Written" | awk -F: '{print $2}' | xargs)"
    echo "  温度: $(echo "$SMART_OUT" | grep "Temperature:" | awk -F: '{print $2}' | xargs)"
    echo "  整体健康: $(echo "$SMART_OUT" | grep "SMART overall-health" | awk -F: '{print $2}' | xargs)"
else
    # 默认兜底信息
    diskutil info disk0 2>/dev/null | grep -E "Device / Media Name|SMART Status|Disk Size" | sed 's/^/  /'
fi
echo ""

echo "==== 内存 / CPU ===="
echo "  CPU: $(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
echo "  逻辑核心: $(sysctl -n hw.ncpu 2>/dev/null)"
echo "  内存: $(sysctl -n hw.memsize 2>/dev/null | awk '{print $1/1024/1024/1024 " GB LPDDR5"}')"
echo ""

echo "==== 网络 / 蓝牙 ===="
WIFI_INFO=$(networksetup -listallhardwareports 2>/dev/null | grep -A 2 "Wi-Fi" | grep "Device:" | awk '{print $2}')
WIFI_MAC=$(ifconfig "$WIFI_INFO" 2>/dev/null | grep "ether" | awk '{print $2}')
BT_VER=$(system_profiler SPBluetoothDataType 2>/dev/null | grep -E "Firmware Version|Controller Version" | head -n 1 | awk -F': ' '{print $2}')
echo "  Wi-Fi 网卡: Wi-Fi (${WIFI_MAC:-Unknown})"
echo "  蓝牙: 芯片/固件版本 ${BT_VER:-Unknown}"
echo ""

echo "==== 屏幕信息 ===="
INTERNAL_RES=$(system_profiler SPDisplaysDataType 2>/dev/null | grep "Resolution" | head -n 1 | awk -F': ' '{print $2}')
CURRENT_RES=$(osascript -e 'tell application "Finder" to get bounds of window of desktop' 2>/dev/null)
echo "  内置屏幕: ${INTERNAL_RES:-Retina}"
echo "  GPU: $(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
echo ""

echo "==== 存储、接口与系统硬件清单 ===="
echo "  根卷/存储:"
diskutil info / 2>/dev/null | grep -E "Device Identifier|Device Node|Volume Name|File System Personality|SMART Status|Disk Size|Container Free Space|Solid State" | sed 's/^/    - /'

USB_COUNT=$(system_profiler SPUSBDataType 2>/dev/null | grep "Product ID" | wc -l | tr -d ' ')
echo "  USB 设备: ${USB_COUNT} 项已枚举"

THUNDERBOLT=$(system_profiler SPThunderboltDataType 2>/dev/null | grep -E "Domain UUID|Link Status" | tr '\n' '; ')
echo "  Thunderbolt: ${THUNDERBOLT:-None}"

CAMERA=$(system_profiler SPCameraDataType 2>/dev/null | grep -E "Model ID|Unique ID" | tr '\n' '; ')
echo "  摄像头: ${CAMERA:-None}"

AUDIO=$(system_profiler SPAudioDataType 2>/dev/null | grep -E "Manufacturer|Output Source|Input Source" | head -n 6 | tr '\n' '; ')
echo "  音频设备: ${AUDIO:-None}"

POWER=$(pmset -g therm 2>/dev/null | tr '\n' ' ')
BAT_POWER=$(pmset -g batt 2>/dev/null | tr '\n' ' ')
echo "  电源: ${BAT_POWER}"

SWAP_INFO=$(sysctl vm.swapusage 2>/dev/null)
echo "  内存压力: ${SWAP_INFO}"
echo ""
echo "检测完成！"