#!/bin/bash

# =================================================================
# 脚本名称: uninstall_aliyun_aegis.sh
# 说明: 阿里云 ECS 云盾（Aegis）一键卸载清理脚本
# 注意: 执行前请确保已在阿里云后台关闭“客户端自保护”
# 用法: sudo bash uninstall_aliyun_aegis.sh [-v|--verbose]
# =================================================================

# 参数解析
VERBOSE=0
for arg in "$@"; do
    case "$arg" in
        -v|--verbose) VERBOSE=1 ;;
        -h|--help)
            echo "用法: sudo bash $0 [-v|--verbose]"
            echo "  -v, --verbose   显示每条命令的执行情况与错误详情（默认只提示失败项）"
            exit 0
            ;;
        *)
            # 注意：变量后紧跟中文字符时必须用 ${arg}，否则 shell 会把中文字的首字节
            #       当成变量名的一部分，导致变量展开为空、并吞掉该首字节
            echo "未知参数: ${arg}（可用 -h 查看用法）"
            exit 1
            ;;
    esac
done

# 检查是否以 root 权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo "错误: 请以 root 权限运行此脚本！"
    exit 1
fi

TOTAL_STEPS=4
FAILURES=0

# 分步回显（带时间戳），便于事后按时间核对每一步的耗时
step() {
    printf '[%s/%s] %s %s\n' "$1" "$TOTAL_STEPS" "$(date '+%H:%M:%S')" "$2"
}

# 关键操作：成功静默，失败必须提示并计入 FAILURES
must() {
    local desc="$1"; shift
    local out
    if out=$("$@" 2>&1); then
        [ "$VERBOSE" -eq 1 ] && echo "        · $desc"
    else
        echo "        ⚠ $desc 失败: ${out:-未知错误}"
        FAILURES=$((FAILURES + 1))
    fi
}

# 可选操作：目标不存在/无匹配属正常情况，仅在 verbose 下提示
try() {
    local desc="$1"; shift
    local out
    if out=$("$@" 2>&1); then
        [ "$VERBOSE" -eq 1 ] && echo "        · $desc"
    else
        [ "$VERBOSE" -eq 1 ] && echo "        · $desc 跳过（${out:-无匹配，属正常}）"
    fi
}

echo ""
echo "      开始卸载阿里云云盾 (Aegis)         "
echo ""

# 1. 卸载内核驱动（云盾靠内核模块防止自己被 kill，这一步最关键）
step 1 "正在卸载内核驱动..."
try "卸载内核驱动 AliYunDunProp" rmmod AliYunDunProp
try "卸载内核驱动 AliYunDunSec" rmmod AliYunDunSec

# 2. 解除文件锁与强制杀死进程
step 2 "正在解除文件锁定并终止相关进程..."
try "解除 aegis 目录文件锁" chattr -R -i /usr/local/aegis
try "停止 aegis 服务" systemctl stop aegis

try "终止 AliYunDun 进程" pkill -9 -f AliYunDun
try "终止 AliSecCheck 进程" pkill -9 -f AliSecCheck
# 注意：不能用 `pkill -f aegis`——本脚本文件名含 "aegis"，会连脚本自己一起杀掉，
#       故改用云盾安装路径匹配（客户端进程都跑在 /usr/local/aegis 下）
try "终止 aegis 客户端进程" pkill -9 -f /usr/local/aegis

# 3. 删除程序目录与自启服务
step 3 "正在清理程序目录与开机自启项..."
must "删除 /usr/local/aegis" rm -rf /usr/local/aegis
must "删除 /usr/local/cloudmonitor" rm -rf /usr/local/cloudmonitor
must "删除 /usr/local/share/aliyun-assist" rm -rf /usr/local/share/aliyun-assist

must "删除 aegis.service" rm -f /etc/systemd/system/aegis.service
must "删除 /etc/init.d/aegis" rm -f /etc/init.d/aegis

# 刷新 systemd 配置
try "刷新 systemd 配置" systemctl daemon-reload

# 4. 验证卸载结果
step 4 "正在验证清理结果..."
echo "------------------------------------------"
# 注意：脚本自身文件名含 "aegis"，直接匹配会把自己也算成残留进程（永远报警告），
#       故过滤掉自身进程名；用 [X] 形式书写，避免匹配到 grep 进程本身
RESIDUAL_PATTERN='[A]liYunDun|[A]liSecCheck|[a]egis'
REMAINING_PROCESSES=$(ps -eo pid,args 2>/dev/null \
    | grep -E "$RESIDUAL_PATTERN" \
    | grep -vF "$(basename "$0")")

if [ -z "$REMAINING_PROCESSES" ]; then
    echo "✔ 验证通过：未发现残留云盾进程，卸载成功！"
else
    echo "⚠ 警告：检测到仍有相关进程运行，请检查阿里云后台“客户端自保护”是否已完全关闭："
    echo "$REMAINING_PROCESSES"
    FAILURES=$((FAILURES + 1))
fi

echo ""
if [ "$FAILURES" -eq 0 ]; then
    echo "提示: 建议立即执行 'reboot' 重启系统以释放资源。"
else
    echo "注意: 以上有 $FAILURES 项未按预期完成（见 ⚠ 提示），建议核对后再执行 'reboot'。"
    echo "提示: 如需查看每条命令的详细情况，可用 -v 参数重跑：sudo bash $0 -v"
fi
echo ""
