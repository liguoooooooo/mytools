#!/bin/bash
# ============================================================
# 二手 MacBook 验机脚本
# 用法:
#   ./macbook-check.sh            # 自动采集可通过终端读取的信息
#   ./macbook-check.sh --bench    # 自动采集 + 可选磁盘测速(写入约1GB临时数据)
# 输出: 同目录下 macbook-check-report-<时间戳>.md
# 依赖: smartctl(可选), ffmpeg(可选); 其余用系统自带命令
# ============================================================
set -u
LANG=C

# ---------------- 初始化 ----------------
AUTO=1
BENCH=0
for a in "$@"; do
  case "$a" in
    --auto) AUTO=1 ;;
    --bench) BENCH=1 ;;
    *) echo "未知参数: $a"; exit 1 ;;
  esac
done

IS_TTY=0; [ -t 0 ] && IS_TTY=1
TS=$(date +%Y%m%d-%H%M%S)
# macOS 自带 bash 3.2 不支持 ${var,,}, 用函数替代
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
# Apple Silicon 检测
if [ "$(sysctl -n hw.optional.arm64 2>/dev/null)" = "1" ]; then IS_AS=1; else IS_AS=0; fi
REPORT="macbook-check-report-${TS}.md"
DIR="$(cd "$(dirname "$0")" && pwd)"
REPORT="$DIR/$REPORT"

RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; CYAN=$'\033[36m'; NC=$'\033[0m'
ok()   { echo "${GREEN}[PASS]${NC} $1"; }
bad()  { echo "${RED}[FAIL]${NC} $1"; }
warn() { echo "${YELLOW}[WARN]${NC} $1"; }
info() { echo "${CYAN}[INFO]${NC} $1"; }
hdr()  { echo; echo "${CYAN}==== $1 ====${NC}"; }

REPORT_RESULTS=()   # "项目|数据|状态"
add_result() { REPORT_RESULTS+=("$1|$2|$3"); }
# 写报告正文(同时可显示)
wlog() { printf '%s\n' "$*" >>"$REPORT"; }

# 初始化报告文件
cat >"$REPORT" <<EOF
# MacBook 验机报告

- **验机时间**: $(date '+%Y-%m-%d %H:%M:%S')
- **验机模式**: 终端自动采集(不执行人工交互测试)
- **报告生成**: macbook-check.sh

---

## 1. 设备概况

EOF

# ---------------- 1. 设备信息 ----------------
sec_device() {
  hdr "设备信息"
  local sp
  sp=$(system_profiler SPHardwareDataType 2>/dev/null)
  local hwmodel osver arch
  MODEL=$(echo "$sp" | awk -F': ' '/Model Name/{print $2; exit}')
  CHIP=$(echo "$sp" | awk -F': ' '/Chip/{print $2; exit}')
  SN=$(echo "$sp" | awk -F': ' '/Serial Number/{print $2; exit}')
  UUID=$(echo "$sp" | awk -F': ' '/Hardware UUID/{print $2; exit}')
  MEM=$(echo "$sp" | awk -F': ' '/Memory/{print $2; exit}')
  AL=$(echo "$sp" | awk -F': ' '/Activation Lock Status/{print $2; exit}')

  hwmodel=$(sysctl -n hw.model 2>/dev/null)
  osver=$(sw_vers -productVersion 2>/dev/null)
  arch=$(uname -m)

  echo "  机型: ${MODEL:-未知} ($hwmodel)"
  echo "  芯片: ${CHIP:-未知}"
  echo "  系统: macOS $osver ($arch)"
  echo "  序列号: ${SN:-未知}"
  echo "  硬件UUID: ${UUID:-未知}"
  echo "  内存: ${MEM:-未知}"
  echo "  激活锁状态: ${AL:-未知(需完整版 system_profiler)}"
  local bootrom smc build
  bootrom=$(echo "$sp" | awk -F': ' '/System Firmware Version/{print $2; exit}')
  smc=$(echo "$sp" | awk -F': ' '/SMC Version/{print $2; exit}')
  build=$(sw_vers -buildVersion 2>/dev/null)
  echo "  固件版本: ${bootrom:-未知} / SMC ${smc:-不适用或未知}"
  echo "  系统构建: ${build:-未知}"

  wlog "- 机型: ${MODEL:-未知} ($hwmodel)"
  wlog "- 芯片: ${CHIP:-未知}"
  wlog "- 系统: macOS $osver ($arch)"
  wlog "- 序列号: ${SN:-未知}"
  wlog "- 硬件UUID: ${UUID:-未知}"
  wlog "- 内存: ${MEM:-未知}"
  wlog "- 激活锁状态: ${AL:-未知}"
  wlog "- 固件版本: ${bootrom:-未知} / SMC ${smc:-不适用或未知}"
  wlog "- 系统构建: ${build:-未知}"

  # 激活锁判定(二手验机必查: 必须 Disabled)
  case "$(lower "${AL:-}")" in
    *disabled*) add_result "激活锁/查找我的Mac" "$AL" "PASS" ;;
    *enabled*)  add_result "激活锁/查找我的Mac" "$AL" "FAIL" ;;
    *) add_result "激活锁/查找我的Mac" "${AL:-未知}" "MANUAL" ;;
  esac

  # 监管锁 / MDM 检查(二手验机必查: 均需 No)
  local enr dep mdm
  enr=$(profiles status -type enrollment 2>/dev/null)
  dep=$(echo "$enr" | awk -F': ' '/Enrolled via DEP/{print $2; exit}')
  mdm=$(echo "$enr" | awk -F': ' '/MDM enrollment/{print $2; exit}')
  echo "  监管锁(DEP/MDM): DEP=${dep:-未知} / MDM=${mdm:-未知}"
  wlog "- 监管锁(DEP/MDM): DEP=${dep:-未知} / MDM=${mdm:-未知}"
  if [ "$(lower "$dep")" = "no" ] && [ "$(lower "$mdm")" = "no" ]; then
    add_result "监管锁/MDM" "DEP:${dep:-未知} / MDM:${mdm:-未知}" "PASS"
  elif [ "$(lower "$dep")" = "yes" ] || [ "$(lower "$mdm")" = "yes" ]; then
    add_result "监管锁/MDM" "DEP:${dep:-未知} / MDM:${mdm:-未知}" "FAIL"
  else
    add_result "监管锁/MDM" "DEP:${dep:-未知} / MDM:${mdm:-未知}" "MANUAL"
  fi
}

# ---------------- 2. 电池 ----------------
sec_battery() {
  hdr "电池健康"
  local sp cc maxc cond
  sp=$(system_profiler SPPowerDataType 2>/dev/null)
  cc=$(echo "$sp" | awk -F': ' '/Cycle Count/{print $2; exit}')
  maxc=$(echo "$sp" | awk -F': ' '/Maximum Capacity/{print $2; exit}')
  cond=$(echo "$sp" | awk -F': ' '/Condition/{print $2; exit}')
  [ -z "$cc" ] && cc="未知"; [ -z "$maxc" ] && maxc="未知"; [ -z "$cond" ] && cond="未知"

  # 优先使用 macOS 报告的最大容量；ioreg 作为可选补充。
  local health="" design=""
  if [[ "$maxc" =~ ^[0-9]+%$ ]]; then health="$maxc"; fi
  if [ "$IS_AS" = "1" ]; then
    local ro
    ro=$(sudo -n ioreg -rn AppleSmartBattery 2>/dev/null)
    if [ -n "$ro" ]; then
      design=$(echo "$ro" | awk -F'=' '/"DesignCapacity"/{gsub(/[^0-9]/,"",$2);print $2;exit}')
      local mc
      mc=$(echo "$ro" | awk -F'=' '/"MaxCapacity"/{gsub(/[^0-9]/,"",$2);print $2;exit}')
      if [ -n "$design" ] && [ -n "$mc" ] && [ "$design" -gt 0 ] 2>/dev/null; then
        health=$(awk "BEGIN{printf \"%.1f%%\", $mc*100/$design}")
      fi
    fi
  else
    local dc2 mc2
    dc2=$(ioreg -rn AppleSmartBattery 2>/dev/null | awk -F'=' '/"DesignCapacity"/{gsub(/[^0-9]/,"",$2);print $2;exit}')
    mc2=$(ioreg -rn AppleSmartBattery 2>/dev/null | awk -F'=' '/"MaxCapacity"/{gsub(/[^0-9]/,"",$2);print $2;exit}')
    if [ -n "$dc2" ] && [ -n "$mc2" ] && [ "$dc2" -gt 0 ] 2>/dev/null; then
      health=$(awk "BEGIN{printf \"%.1f%%\", $mc2*100/$dc2}")
    fi
  fi

  echo "  循环次数: $cc"
  echo "  最大容量: $maxc"
  echo "  电池状态: $cond"
  [ -n "$health" ] && echo "  健康度(实测): $health"
  [ -z "$health" ] && [ "$IS_AS" = "1" ] && echo "  健康度: 需 sudo 查看, 可运行 sudo ioreg -rn AppleSmartBattery"

  wlog ""
  wlog "## 2. 电池健康"
  wlog ""
  wlog "- 循环次数: $cc"
  wlog "- 最大容量: $maxc"
  wlog "- 电池状态: $cond"
  [ -n "$health" ] && wlog "- 健康度(实测): $health"
  [ -z "$health" ] && wlog "- 健康度: 未获取(需 sudo)"

  # 判定
  case "$(lower "$cond")" in
    *normal*) add_result "电池状态" "$cond" "PASS" ;;
    *poor*|*failed*) add_result "电池状态" "$cond" "FAIL" ;;
    *fair*) add_result "电池状态" "$cond" "WARN" ;;
    *) add_result "电池状态" "$cond" "MANUAL" ;;
  esac
  if [[ "$cc" =~ ^[0-9]+$ ]]; then
    if [ "$cc" -gt 1000 ]; then add_result "电池循环次数" "$cc" "WARN"
    else add_result "电池循环次数" "$cc" "PASS"; fi
  else
    add_result "电池循环次数" "$cc" "MANUAL"
  fi
  if [ -n "$health" ]; then
    local hv
    hv=$(echo "$health" | tr -d '%')
    if awk "BEGIN{exit !($hv >= 80)}"; then add_result "电池健康度" "$health" "PASS"
    elif awk "BEGIN{exit !($hv >= 60)}"; then add_result "电池健康度" "$health" "WARN"
    else add_result "电池健康度" "$health" "FAIL"; fi
  else
    add_result "电池健康度" "$maxc" "MANUAL"
  fi
}

# ---------------- 3. SSD 健康 ----------------
sec_ssd() {
  hdr "SSD 健康 (SMART)"
  local dev=""
  for d in disk0 disk1; do
    if smartctl -i /dev/$d >/dev/null 2>&1; then dev=$d; break; fi
  done
  if [ -z "$dev" ]; then
    echo "  smartctl 未找到 SSD 或无权限, 跳过 SMART 检测"
    wlog ""
    wlog "## 3. SSD 健康 (SMART)"
    wlog ""
    wlog "- 未检测到 SMART 数据(smartctl 不可用或无权限)"
    add_result "SSD SMART" "未获取" "MANUAL"
    return
  fi

  local sa
  sa=$(smartctl -a /dev/$dev 2>/dev/null)
  local model du dw pct temp phon pcyc unsafe errs health
  model=$(echo "$sa" | awk -F': +' '/Model Number/{print $2; exit}')
  du=$(echo "$sa" | awk -F': +' '/Data Units Read/{print $2; exit}')
  dw=$(echo "$sa" | awk -F': +' '/Data Units Written/{print $2; exit}')
  pct=$(echo "$sa" | awk -F': +' '/Percentage Used/{print $2; exit}')
  temp=$(echo "$sa" | awk -F': +' '/Temperature/{print $2; exit}')
  phon=$(echo "$sa" | awk -F': +' '/Power On Hours/{print $2; exit}')
  pcyc=$(echo "$sa" | awk -F': +' '/Power Cycles/{print $2; exit}')
  unsafe=$(echo "$sa" | awk -F': +' '/Unsafe Shutdowns/{print $2; exit}')
  errs=$(echo "$sa" | awk -F': +' '/Media and Data Integrity Errors/{print $2; exit}')
  health=$(echo "$sa" | awk -F': +' '/SMART overall-health/{print $2; exit}')

  echo "  型号: ${model:-未知}"
  echo "  累计读取: ${du:-未知}"
  echo "  累计写入: ${dw:-未知}"
  echo "  寿命消耗: ${pct:-未知}"
  echo "  温度: ${temp:-未知}"
  echo "  通电时长: ${phon:-未知} 小时 / 通电 $([ -n "$pcyc" ] && echo "$pcyc" || echo 未知) 次"
  echo "  非正常关机: ${unsafe:-未知}"
  echo "  介质/数据错误: ${errs:-未知}"
  echo "  整体健康: ${health:-未知}"

  wlog ""
  wlog "## 3. SSD 健康 (SMART)"
  wlog ""
  wlog "- 型号: ${model:-未知}"
  wlog "- 累计读取: ${du:-未知}"
  wlog "- 累计写入: ${dw:-未知}"
  wlog "- 寿命消耗: ${pct:-未知}"
  wlog "- 温度: ${temp:-未知}"
  wlog "- 通电时长: ${phon:-未知} 小时 / 通电 ${pcyc:-未知} 次"
  wlog "- 非正常关机: ${unsafe:-未知}"
  wlog "- 介质/数据错误: ${errs:-未知}"
  wlog "- 整体健康: ${health:-未知}"

  # 判定
  case "$(lower "$health")" in
    *passed*) add_result "SSD 整体健康" "${health:-未知}" "PASS" ;;
    *) add_result "SSD 整体健康" "${health:-未知}" "MANUAL" ;;
  esac
  local pctn
  pctn=$(echo "$pct" | tr -cd '0-9')
  if [ -n "$pctn" ]; then
    if [ "$pctn" -lt 50 ]; then add_result "SSD 寿命消耗" "$pct" "PASS"
    elif [ "$pctn" -lt 90 ]; then add_result "SSD 寿命消耗" "$pct" "WARN"
    else add_result "SSD 寿命消耗" "$pct" "FAIL"; fi
  else add_result "SSD 寿命消耗" "${pct:-未知}" "MANUAL"; fi
  if [[ "$errs" =~ ^[0-9]+ ]] && [ "$errs" -gt 0 ]; then
    add_result "SSD 介质错误" "$errs" "FAIL"
  else
    add_result "SSD 介质错误" "${errs:-未知}" "PASS"
  fi
  if [ -n "$unsafe" ] && [ "$unsafe" -gt 10 ] 2>/dev/null; then
    add_result "非正常关机次数" "$unsafe" "WARN"
  else
    add_result "非正常关机次数" "${unsafe:-未知}" "PASS"
  fi
}

# ---------------- 4. 内存 / CPU ----------------
sec_memcpu() {
  hdr "内存 / CPU"
  local meminfo cpu cores
  meminfo=$(system_profiler SPMemoryDataType 2>/dev/null)
  cpu=$(sysctl -n machdep.cpu.brand_string 2>/dev/null)
  cores=$(sysctl -n hw.logicalcpu 2>/dev/null)
  local memsize memtype ecctype
  memsize=$(echo "$meminfo" | awk '/Memory:/{if($2){print $2" "$3; exit}}')
  [ -z "$memsize" ] && memsize="$MEM"
  memtype=$(echo "$meminfo" | awk -F': ' '/Type/{print $2; exit}')
  ecctype=$(echo "$meminfo" | awk -F': ' '/ECC/{print $2; exit}')

  echo "  CPU: ${CHIP:-${cpu:-未知}}"
  echo "  逻辑核心: ${cores:-未知}"
  echo "  内存: ${memsize:-未知} ${memtype:-}"
  [ -n "$ecctype" ] && echo "  ECC: $ecctype"
  wlog ""
  wlog "## 4. 内存 / CPU"
  wlog ""
  wlog "- CPU: ${CHIP:-${cpu:-未知}} (逻辑核心 ${cores:-未知})"
  wlog "- 内存: ${memsize:-未知} ${memtype:-}"
  [ -n "$ecctype" ] && wlog "- ECC: $ecctype"
  add_result "CPU" "${CHIP:-未知} / ${cores:-未知} 核" "INFO"
  add_result "内存容量" "${memsize:-未知}" "INFO"
}

# ---------------- 终端可读取的硬件清单与系统状态 ----------------
sec_inventory() {
  hdr "存储、接口与系统硬件清单"
  local disks rootinfo usb thunderbolt camera audio power pressure swap
  disks=$(diskutil list 2>/dev/null)
  rootinfo=$(diskutil info / 2>/dev/null | awk -F': *' '/Device Identifier|Device Node|Part of Whole|Protocol|Disk Size|Solid State|SMART Status|Volume Name|File System Personality|Free Space/{print "- " $1 ": " $2}')
  usb=$(system_profiler SPUSBDataType 2>/dev/null)
  thunderbolt=$(system_profiler SPThunderboltDataType 2>/dev/null)
  camera=$(system_profiler SPCameraDataType 2>/dev/null)
  audio=$(system_profiler SPAudioDataType 2>/dev/null)
  power=$(pmset -g batt 2>/dev/null | tr '\n' ' ')
  pressure=$(memory_pressure 2>/dev/null | awk -F': *' '/System-wide memory free percentage/{print $2; exit}')
  [ -n "$pressure" ] && pressure="剩余内存比例 ${pressure}"
  swap=$(sysctl -n vm.swapusage 2>/dev/null)
  echo "  根卷/存储: ${rootinfo:-未读取到}"
  echo "  USB 设备: $(echo "$usb" | awk '/^[[:space:]]*[A-Za-z0-9].*:$/{n++} END{print n+0}') 项已枚举"
  echo "  Thunderbolt: $(echo "$thunderbolt" | awk -F': *' '/Domain UUID|Link Status|Current Link Width|Current Link Speed/{printf "%s%s; ",$1,$2}' | head -c 300)"
  echo "  摄像头: $(echo "$camera" | awk -F': *' '/Model ID|Unique ID|Camera Name/{printf "%s%s; ",$1,$2}' | head -c 300)"
  echo "  音频设备: $(echo "$audio" | awk -F': *' '/Default Output Device|Default Input Device|Manufacturer|Output Source|Input Source/{printf "%s%s; ",$1,$2}' | head -c 300)"
  echo "  电源: ${power:-未知}"
  echo "  内存压力: ${pressure:-未知}; Swap: ${swap:-未知}"
  wlog ""
  wlog "## 5. 存储、接口与系统硬件清单"
  wlog ""
  wlog "### 根卷与磁盘分区"
  wlog "${rootinfo:-未读取到}"
  wlog '```text'; wlog "${disks:-未读取到}"; wlog '```'
  wlog "### USB 设备"; wlog '```text'; wlog "${usb:-未读取到}"; wlog '```'
  wlog "### Thunderbolt 设备"; wlog '```text'; wlog "${thunderbolt:-未读取到}"; wlog '```'
  wlog "### 摄像头设备"; wlog '```text'; wlog "${camera:-未读取到}"; wlog '```'
  wlog "### 音频设备"; wlog '```text'; wlog "${audio:-未读取到}"; wlog '```'
  wlog "- 电源: ${power:-未知}"
  wlog "- 内存压力: ${pressure:-未知}; Swap: ${swap:-未知}"
  add_result "内置存储识别" "$(echo "$rootinfo" | tr '\n' ' ' | cut -c1-180)" "INFO"
  add_result "USB/雷电/摄像头/音频枚举" "设备清单见报告；枚举结果不代表功能或质量已实测" "INFO"
  add_result "当前供电状态" "${power:-未知}" "INFO"
  add_result "内存压力/Swap" "${pressure:-未知}; ${swap:-未知}" "INFO"
}

sec_logs() {
  hdr "近期硬件异常日志"
  local errors
  errors=$(log show --last 7d --style compact --predicate '(eventMessage CONTAINS[c] "panic" OR eventMessage CONTAINS[c] "thermal" OR eventMessage CONTAINS[c] "shutdown cause" OR eventMessage CONTAINS[c] "I/O error")' 2>/dev/null | grep -Ei 'panic|thermal|shutdown cause|I/O error' | tail -40)
  echo "  最近 7 天匹配记录: $(echo "$errors" | awk 'NF{n++} END{print n+0}')"
  wlog ""
  wlog "## 6. 最近 7 天硬件异常日志"
  wlog ""
  wlog '```text'; wlog "${errors:-未发现匹配关键词(不代表硬件绝对正常)}"; wlog '```'
  if [ -n "$errors" ]; then add_result "近期异常日志" "$(echo "$errors" | wc -l | tr -d ' ') 条记录，详见报告" "WARN"
  else add_result "近期异常日志" "无匹配项" "INFO"; fi
}

# ---------------- 5. 网络 / 蓝牙 ----------------
sec_net() {
  hdr "网络 / 蓝牙"
  local hwports bt
  hwports=$(networksetup -listallhardwareports 2>/dev/null)
  local wifiname wifiaddr btchip btfw
  wifiname=$(echo "$hwports" | awk -F': ' '/Wi-Fi/{found=1} found && /Hardware Port/{print $2; exit}')
  wifiaddr=$(echo "$hwports" | awk -F': ' '/Wi-Fi/{found=1} found && /Ethernet Address/{print $2; exit}')
  bt=$(system_profiler SPBluetoothDataType 2>/dev/null)
  btchip=$(echo "$bt" | awk -F': ' '/Chipset/{print $2; exit}')
  btfw=$(echo "$bt" | awk -F': ' '/Firmware Version/{print $2; exit}')

  echo "  Wi-Fi 网卡: ${wifiname:-未知} (${wifiaddr:-未知})"
  echo "  蓝牙: ${btchip:-未知} (固件 ${btfw:-未知})"
  wlog ""
  wlog "## 5. 网络 / 蓝牙"
  wlog ""
  wlog "- Wi-Fi 网卡: ${wifiname:-未知} (${wifiaddr:-未知})"
  wlog "- 蓝牙: ${btchip:-未知} (固件 ${btfw:-未知})"
  add_result "Wi-Fi 网卡" "${wifiname:-未知}" "INFO"
  add_result "蓝牙版本" "${btchip:-未知} ${btfw:-未知}" "INFO"
}

# ---------------- 6. 屏幕 ----------------
sec_display() {
  hdr "屏幕信息"
  local disp gpu bi_res
  disp=$(system_profiler SPDisplaysDataType 2>/dev/null)
  gpu=$(echo "$disp" | awk -F': ' '/Chipset Model/{print $2; exit}')
  # 优先取内置屏分辨率(验机以内置屏为准), 无内置则取主屏
  bi_res=$(echo "$disp" | awk '
    /Display Type:.*Built-in/ { bi=1; next }
    bi && /Resolution:/ { sub(/^ +Resolution: /, ""); print; exit }
  ')
  [ -z "$bi_res" ] && bi_res=$(echo "$disp" | awk -F': ' '/Resolution/{print $2; exit}')
  local ext_disp
  ext_disp=$(echo "$disp" | awk -F': ' '/Resolution/{print $2; exit}')
  echo "  内置屏幕: ${bi_res:-未知}"
  [ -n "$ext_disp" ] && echo "  主显示(当前): $ext_disp"
  echo "  GPU: ${gpu:-未知}"
  wlog ""
  wlog "## 6. 屏幕信息"
  wlog ""
  wlog "- 内置屏幕: ${bi_res:-未知}"
  [ -n "$ext_disp" ] && wlog "- 主显示(当前): $ext_disp"
  wlog "- GPU: ${gpu:-未知}"
  add_result "内置屏幕分辨率" "${bi_res:-未知}" "INFO"
}

# ---------------- 10. 磁盘读写测速 ----------------
disk_bench() {
  local do_bench=0
  [ "$BENCH" = 1 ] && do_bench=1
  [ "$do_bench" = 0 ] && {
    wlog ""
    wlog "## 10. 磁盘读写速度"
    wlog ""
    wlog "- 未执行(使用 --bench 可选择执行，会写入约 1GB 临时数据)"
    add_result "磁盘读写速度" "未执行(可选 --bench)" "INFO"
    return
  }
  hdr "磁盘读写测速"
  local f=/tmp/mbc_speed_test
  local write_out wrate read_out rrate
  write_out=$(dd if=/dev/zero of="$f" bs=1m count=1024 2>&1)
  wrate=$(echo "$write_out" | awk '/bytes transferred/{print $(NF-2), "MB/s"}')
  sync
  read_out=$(dd if="$f" of=/dev/null bs=1m 2>&1)
  rrate=$(echo "$read_out" | awk '/bytes transferred/{print $(NF-2), "MB/s"}')
  rm -f "$f"
  # 换算: dd 输出 "1073741824 bytes transferred in 0.5 secs (2147483648 bytes/sec)"
  local wrb rrb
  wrb=$(echo "$write_out" | awk '/bytes transferred/{gsub(/[(),]/,"",$(NF-1)); printf "%.0f", $(NF-1)/1048576; exit}')
  rrb=$(echo "$read_out" | awk '/bytes transferred/{gsub(/[(),]/,"",$(NF-1)); printf "%.0f", $(NF-1)/1048576; exit}')
  echo "  写入速度: ${wrb} MB/s"
  echo "  读取速度: ${rrb} MB/s"
  wlog ""
  wlog "## 10. 磁盘读写速度"
  wlog ""
  wlog "- 顺序写入: ${wrb} MB/s (1GB)"
  wlog "- 顺序读取: ${rrb} MB/s"
  add_result "顺序写入速度" "${wrb} MB/s" "INFO"
  add_result "顺序读取速度" "${rrb} MB/s" "INFO"
}

# ---------------- 汇总 ----------------
summary() {
  hdr "验机结论汇总"
  local pass=0 fail=0 warn=0 manual=0
  for r in "${REPORT_RESULTS[@]}"; do
    local item data st
    item="${r%%|*}"; rest="${r#*|}"; data="${rest%%|*}"; st="${rest#*|}"
    case "$st" in
      PASS) pass=$((pass+1)); s="$GREEN" ;;
      FAIL) fail=$((fail+1)); s="$RED" ;;
      WARN) warn=$((warn+1)); s="$YELLOW" ;;
      MANUAL) manual=$((manual+1)); s="$YELLOW" ;;
      *) s="$CYAN" ;;
    esac
    printf "  %b[%s]%b  %-28s %s\n" "$s" "$st" "$NC" "$item" "$data"
  done

  wlog ""
  wlog "## 11. 验机结论汇总"
  wlog ""
  wlog "| 项目 | 数据 | 结论 |"
  wlog "|---|---|---|"
  for r in "${REPORT_RESULTS[@]}"; do
    item="${r%%|*}"; rest="${r#*|}"; data="${rest%%|*}"; st="${rest#*|}"
    wlog "| $item | $data | $st |"
  done

  local final
  if [ "$fail" -gt 0 ]; then
    final="存在 $fail 项异常, 建议谨慎购买或要求卖家处理"
    wlog ""
    wlog "> **综合结论**: 存在 $fail 项 FAIL 异常, $warn 项警告, 建议谨慎购买或要求卖家处理。"
  elif [ "$warn" -gt 0 ]; then
    final="存在 $warn 项警告, 建议关注相应部件"
    wlog ""
    wlog "> **综合结论**: 无 FAIL 异常, 但有 $warn 项警告, 建议关注相应部件。"
  elif [ "$manual" -gt 0 ]; then
    final="自动采集未发现明确异常, $manual 项数据不可用"
    wlog ""
    wlog "> **综合结论**: 自动采集未发现 FAIL，但有 $manual 项数据不可用；请结合报告中的权限/工具限制判断。"
  else
    final="全部通过"
    wlog ""
    wlog "> **综合结论**: 全部检查项通过。"
  fi
  echo
  info "$final"
  echo "  报告已生成: $REPORT"
  wlog ""
  wlog "---"
  wlog "*报告由 macbook-check.sh 自动生成*"
}

# ---------------- 主流程 ----------------
echo "===== 二手 MacBook 验机工具 ====="
sec_device
sec_battery
sec_ssd
sec_memcpu
sec_net
sec_display
sec_inventory
sec_logs
disk_bench
summary
