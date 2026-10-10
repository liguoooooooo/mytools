#!/bin/bash

# =================================================================
# 脚本名称: uninstall_aliyun_aegis.sh
# 说明: 阿里云 ECS 云盾（Aegis）一键卸载清理脚本
# 注意: 执行前请确保已在阿里云后台关闭“客户端自保护”
# =================================================================

# 检查是否以 root 权限运行
if [ "$(id -u)" -ne 0 ]; then
    echo "错误: 请以 root 权限运行此脚本！"
    exit 1
fi

echo ""
echo "      开始卸载阿里云云盾 (Aegis)         "
echo ""

# 1. 卸载内核驱动
echo "[1/4] 正在卸载内核驱动..."
rmmod AliYunDunProp 2>/dev/null
rmmod AliYunDunSec 2>/dev/null

# 2. 解除文件锁与强制杀死进程
echo "[2/4] 正在解除文件锁定并终止相关进程..."
chattr -R -i /usr/local/aegis 2>/dev/null
systemctl stop aegis 2>/dev/null

pkill -9 -f AliYunDun 2>/dev/null
pkill -9 -f AliSecCheck 2>/dev/null
pkill -9 -f aegis 2>/dev/null

# 3. 删除程序目录与自启服务
echo "[3/4] 正在清理程序目录与开机自启项..."
rm -rf /usr/local/aegis
rm -rf /usr/local/cloudmonitor
rm -rf /usr/local/share/aliyun-assist

rm -f /etc/systemd/system/aegis.service
rm -f /etc/init.d/aegis

# 刷新 systemd 配置
systemctl daemon-reload 2>/dev/null

# 4. 验证卸载结果
echo "[4/4] 正在验证清理结果..."
echo "------------------------------------------"
REMAINING_PROCESSES=$(ps -ef | grep -E 'AliYunDun|aegis' | grep -v grep)

if [ -z "$REMAINING_PROCESSES" ]; then
    echo "✔ 验证通过：未发现残留云盾进程，卸载成功！"
else
    echo "⚠ 警告：检测到仍有相关进程运行，请检查阿里云后台“客户端自保护”是否已完全关闭："
    echo "$REMAINING_PROCESSES"
fi

echo ""
echo "提示: 建议立即执行 'reboot' 重启系统以释放资源。"
echo ""
