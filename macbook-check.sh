#!/bin/bash

# ===== 二手 MacBook 验机工具 =====

echo "===== 二手 MacBook 验机工具 ====="
echo ""

# ---------- 设备信息 ----------
echo "==== 设备信息 ===="
HW_INFO=$(system_profiler SPHardwareDataType 2>/dev/null)
MODEL_NAME=$(echo "$HW_INFO" | awk -F': ' '/Model Name/ {print $2}')
MODEL_ID=$(echo "$HW_INFO" | awk -F': ' '/Model Identifier/ {print $2}')
echo "  机型: ${MODEL_NAME:-未知机型} (${MODEL_ID:-$(sysctl -n hw.model 2>/dev/null)})"
echo "  芯片: $(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
echo "  系统: macOS $(sw_vers -productVersion 2>/dev/null) ($(uname -m))"
echo "  序列号: $(echo "$HW_INFO" | awk -F': ' '/Serial Number/ {print $2}')"
echo "  硬件UUID: $(echo "$HW_INFO" | awk -F': ' '/Hardware UUID/ {print $2}')"
echo "  内存: $(sysctl -n hw.memsize 2>/dev/null | awk '{printf "%.0f GB", $1/1024/1024/1024}')"
echo "  激活锁状态: $(echo "$HW_INFO" | awk -F': ' '/Activation Lock Status/ {print $2}')"

# 监管锁 DEP / MDM
MDM_STATUS="否"
system_profiler SPConfigurationProfileDataType 2>/dev/null | grep -qi "MDM" && MDM_STATUS="是"
echo "  监管锁(DEP/MDM): ${MDM_STATUS}"

echo "  固件版本: $(echo "$HW_INFO" | awk -F': ' '/System Firmware Version/ {print $2}')"
echo "  系统构建: $(sw_vers -buildVersion 2>/dev/null)"
echo ""

# ---------- 电池健康 ----------
echo "==== 电池健康 ===="
BATTERY_INFO=$(system_profiler SPPowerDataType 2>/dev/null)
BAT_CYCLE=$(echo "$BATTERY_INFO" | awk -F': ' '/Cycle Count/ {print $2}' | tr -d '[:space:]')
BAT_MAXCAP=$(echo "$BATTERY_INFO" | awk -F': ' '/Maximum Capacity/ {print $2}' | tr -d '[:space:]')
BAT_COND=$(echo "$BATTERY_INFO" | awk -F': ' '/Condition/ {gsub(/^ +| +$/, "", $2); print $2}' | head -n 1)
echo "  循环次数: ${BAT_CYCLE:-未知}"
echo "  最大容量: ${BAT_MAXCAP:-未知}"
echo "  电池状态: ${BAT_COND:-未知}"
echo ""

# ---------- SSD 健康 (SMART) ----------
echo "==== SSD 健康 (SMART) ===="
if command -v smartctl >/dev/null 2>&1; then
    # 注意：smartctl 即使成功也可能返回非零退出码（如 4），故不以退出码判断
    SMART_OUT=$(smartctl -a /dev/disk0 2>/dev/null)
else
    SMART_OUT=""
fi
if [ -n "$SMART_OUT" ]; then
    # 取「字段名: 值」形式字段的值
    sf() { echo "$SMART_OUT" | grep -m1 -E "^$1:" | sed -E 's/^[^:]*:[[:space:]]*//; s/[[:space:]]+$//'; }

    echo "  型号: $(sf 'Model Number')"
    echo "  累计读取: $(sf 'Data Units Read')"
    echo "  累计写入: $(sf 'Data Units Written')"
    echo "  寿命消耗: $(sf 'Percentage Used')"
    echo "  通电时长: $(sf 'Power On Hours') 小时 / 通电 $(sf 'Power Cycles') 次"
    echo "  非正常关机: $(sf 'Unsafe Shutdowns')"
    echo "  介质/数据错误: $(sf 'Media and Data Integrity Errors')"
    echo "  温度: $(sf 'Temperature')"
    echo "  整体健康: $(echo "$SMART_OUT" | awk -F': ' '/SMART overall-health/ {print $2}')"
else
    # 未安装 smartctl 时回退 diskutil
    DISK0_INFO=$(diskutil info disk0 2>/dev/null)
    echo "  型号: $(echo "$DISK0_INFO" | awk -F': ' '/Device \/ Media Name/ {sub(/^ +/, "", $2); print $2}')"
    echo "  SMART: $(echo "$DISK0_INFO" | awk -F': ' '/SMART Status/ {sub(/^ +/, "", $2); print $2}')"
    echo "  容量: $(echo "$DISK0_INFO" | awk -F': ' '/Disk Size/ {sub(/ \(.*/, "", $2); sub(/^ +/, "", $2); print $2}')"
    echo "  （未安装 smartctl，仅显示基础信息；安装后可看寿命/读写量：brew install smartmontools）"
fi
echo ""

# ---------- 内存 / CPU ----------
echo "==== 内存 / CPU ===="
echo "  CPU: $(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
echo "  逻辑核心: $(sysctl -n hw.ncpu 2>/dev/null)"
echo "  内存: $(sysctl -n hw.memsize 2>/dev/null | awk '{printf "%.0f GB", $1/1024/1024/1024}')"
echo ""

# ---------- 网络 / 蓝牙 ----------
echo "==== 网络 / 蓝牙 ===="
WIFI_DEV=$(networksetup -listallhardwareports 2>/dev/null | grep -A 2 "Wi-Fi" | grep "Device:" | awk '{print $2}' | head -n 1)
# 用 networksetup 取硬件 MAC；ifconfig 在开启「私有 Wi-Fi 地址」时返回的是随机化地址
WIFI_MAC=$(networksetup -getmacaddress "${WIFI_DEV:-en0}" 2>/dev/null | awk '{print $3}')
BT_INFO=$(system_profiler SPBluetoothDataType 2>/dev/null)
BT_CHIPSET=$(echo "$BT_INFO" | awk -F': ' '/Chipset/ {gsub(/^ +| +$/, "", $2); print $2; exit}')
BT_FW=$(echo "$BT_INFO" | awk -F': ' '/Firmware Version/ {gsub(/^ +| +$/, "", $2); print $2; exit}')
echo "  Wi-Fi 网卡: Wi-Fi (${WIFI_MAC:-未知})"
echo "  蓝牙: ${BT_CHIPSET:-未知}${BT_FW:+ (固件 ${BT_FW})}"
echo ""

# ---------- 屏幕信息 ----------
echo "==== 屏幕信息 ===="
DISPLAYS=$(system_profiler SPDisplaysDataType 2>/dev/null | awk '
    function flush() {
        if (name == "") return
        if (is_main)    { print "  主显示(当前): " res; printed = 1 }
        if (is_builtin) { print "  内置屏幕: " res; printed = 1 }
        if (is_main == 0 && is_builtin == 0 && first == "") first = res
    }
    /^        [^ ].*:$/ {
        flush()
        name = $0; sub(/^ +/, "", name); sub(/:$/, "", name)
        res = ""; is_main = 0; is_builtin = 0; next
    }
    /^ *Resolution:/ { res = $0; sub(/^ *Resolution: */, "", res) }
    /Main Display: Yes/ { is_main = 1 }
    /Display Type: Built-in/ { is_builtin = 1 }
    /Connection Type: Internal/ { is_builtin = 1 }
    END {
        flush()
        if (!printed && first != "") print "  屏幕: " first
    }
')
if [ -n "$DISPLAYS" ]; then
    echo "$DISPLAYS"
else
    echo "  屏幕: 未检测到"
fi
echo "  GPU: $(system_profiler SPDisplaysDataType 2>/dev/null | awk -F': ' '/Chipset Model/ {print $2; exit}')"
echo ""

# ---------- 存储、接口与外设 ----------
echo "==== 存储、接口与外设 ===="
STORAGE=$(diskutil info / 2>/dev/null | awk -F': ' '
    /^ *Device Identifier/       { gsub(/^ +| +$/, "", $2); id = $2 }
    /^ *Volume Name/             { gsub(/^ +| +$/, "", $2); vn = $2 }
    /^ *File System Personality/ { gsub(/^ +| +$/, "", $2); fs = $2 }
    /^ *SMART Status/            { gsub(/^ +| +$/, "", $2); smart = $2 }
    /^ *Solid State/             { gsub(/^ +| +$/, "", $2); ssd = $2 }
    /^ *Disk Size/               { sub(/ \(.*/, "", $2); gsub(/^ +| +$/, "", $2); size = $2 }
    /^ *Container Free Space/    { sub(/ \(.*/, "", $2); gsub(/^ +| +$/, "", $2); free = $2 }
    END {
        printf "  存储: %s | %s | %s | %s（可用 %s）| 固态 %s | SMART %s\n", id, vn, fs, size, free, ssd, smart
    }
')
echo "$STORAGE"

USB_COUNT=$(system_profiler SPUSBDataType 2>/dev/null | grep -c "Product ID")
echo "  USB 设备: ${USB_COUNT} 项已枚举"

TB=$(system_profiler SPThunderboltDataType 2>/dev/null | awk '
    /Bus [0-9]+:/ { bus = $0; sub(/^.*Bus /, "", bus); sub(/:.*/, "", bus); st = ""; ls = ""; sp = "" }
    /^ *Status: /      { st = $0; sub(/^ *Status: */, "", st) }
    /^ *Link Status: / { ls = $0; sub(/^ *Link Status: */, "", ls) }
    /^ *Speed: /       { sp = $0; sub(/^ *Speed: */, "", sp); printf "    Bus %s: %s | Link %s | %s\n", bus, st, ls, sp }
')
if [ -n "$TB" ]; then
    echo "  Thunderbolt:"
    echo "$TB"
else
    echo "  Thunderbolt: 未检测到"
fi

CAM=$(system_profiler SPCameraDataType 2>/dev/null | awk '
    /^    [^ ].*:$/ { dev = $0; sub(/^ +/, "", dev); sub(/:$/, "", dev) }
    /Model ID:/    { if (dev != "") printf "%s%s", (cnt++ ? "；" : ""), dev }
')
echo "  摄像头: ${CAM:-未检测到}"

AUDIO=$(system_profiler SPAudioDataType 2>/dev/null | awk '
    function flush() {
        if (name == "") return
        key = name " (" (man == "" ? "未知厂商" : man) ")"
        if (!(key in seen)) { seen[key] = 1; order[++oc] = key }
        if (has_out) outk[key] = 1
        if (has_in)  ink[key]  = 1
        name = ""; man = ""; has_out = 0; has_in = 0
    }
    /^        [^ ].*:$/ { flush(); name = $0; sub(/^ +/, "", name); sub(/:$/, "", name); next }
    /^ *Manufacturer:/ { man = $0; sub(/^ *Manufacturer: */, "", man) }
    /Output Source:|Default Output Device:/ { has_out = 1 }
    /Input Source:|Default Input Device:/   { has_in = 1 }
    END {
        flush()
        for (i = 1; i <= oc; i++) {
            k = order[i]
            d = (outk[k] && ink[k]) ? "输入/输出" : (outk[k] ? "输出" : (ink[k] ? "输入" : "未知"))
            printf "    %s — %s\n", k, d
        }
    }
')
if [ -n "$AUDIO" ]; then
    echo "  音频设备:"
    echo "$AUDIO"
else
    echo "  音频设备: 未检测到"
fi

# 电源
PMSET_BATT=$(pmset -g batt 2>/dev/null)
PWR_SRC=$(echo "$PMSET_BATT" | sed -nE "s/.*from '([^']*)'.*/\1/p" | head -n 1)
PWR_PCT=$(echo "$PMSET_BATT" | grep -oE "[0-9]+%" | head -n 1)
PWR_STATE=$(echo "$PMSET_BATT" | sed -nE 's/.*[0-9]+%; *//p' | sed -E 's/ *present:.*//' | head -n 1)
echo "  电源: ${PWR_SRC:-未知} | 电量 ${PWR_PCT:-未知} | ${PWR_STATE:-未知}"

# 内存压力 / Swap
SWAP_RAW=$(sysctl -n vm.swapusage 2>/dev/null)
SWAP_FMT=$(echo "$SWAP_RAW" | sed -E 's/.*total = ([0-9.]+[A-Z]) *used = ([0-9.]+[A-Z]) *free = ([0-9.]+[A-Z]).*/Swap 共 \1 \/ 已用 \2 \/ 可用 \3/')
[ "$SWAP_FMT" = "$SWAP_RAW" ] && SWAP_FMT="未检测到"
echo "  内存压力: ${SWAP_FMT}"
echo ""
echo "检测完成！"
