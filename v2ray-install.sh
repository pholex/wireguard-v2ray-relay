#!/bin/bash

# V2Ray 完整安装脚本
# 按顺序执行 step1, step2, step3

set -e

echo "=== V2Ray 完整安装脚本 ==="
echo "将按顺序执行："
echo "1. V2Ray 安装和配置 (step1)"
echo "2. TCP 透明代理配置 (step2)"
echo "3. UDP 透明代理配置 (step3)"
echo ""

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo "此脚本需要 root 权限运行"
    echo "请使用: sudo bash $0"
    exit 1
fi

# 检查脚本文件是否存在
STEP1_SCRIPT="v2ray-install-step1-core.sh"
STEP2_SCRIPT="v2ray-install-step2-enable-tcp-proxy.sh"
STEP3_SCRIPT="v2ray-install-step3-enable-udp-proxy.sh"

for script in "$STEP1_SCRIPT" "$STEP2_SCRIPT" "$STEP3_SCRIPT"; do
    if [ ! -f "$script" ]; then
        echo "✗ 未找到脚本文件: $script"
        exit 1
    fi
done

echo "✓ 所有脚本文件已找到"
echo ""

# 执行 Step 1: V2Ray 安装和配置
echo "🚀 开始执行 Step 1: V2Ray 安装和配置"
echo "=================================================="
bash "$STEP1_SCRIPT"
if [ $? -ne 0 ]; then
    echo "✗ Step 1 执行失败"
    exit 1
fi
echo "✓ Step 1 执行完成"
echo ""

# 执行 Step 2: TCP 透明代理配置
echo "🚀 开始执行 Step 2: TCP 透明代理配置"
echo "=================================================="
bash "$STEP2_SCRIPT"
if [ $? -ne 0 ]; then
    echo "✗ Step 2 执行失败"
    exit 1
fi
echo "✓ Step 2 执行完成"
echo ""

# 执行 Step 3: UDP 透明代理配置
echo "🚀 开始执行 Step 3: UDP 透明代理配置"
echo "=================================================="
bash "$STEP3_SCRIPT"
if [ $? -ne 0 ]; then
    echo "✗ Step 3 执行失败"
    exit 1
fi
echo "✓ Step 3 执行完成"
echo ""

echo "🎉 V2Ray 完整安装成功！"
echo ""
echo "📋 安装总结："
echo "- V2Ray 服务: 已安装并运行"
echo "- SOCKS5 代理: 127.0.0.1:7890"
echo "- TCP 透明代理: 端口 60001"
echo "- UDP 透明代理: 端口 60002"
echo "- WireGuard 客户端流量自动通过代理"
echo ""
echo "🔧 管理命令："
echo "- 查看 V2Ray 状态: systemctl status v2ray"
echo "- 查看 V2Ray 日志: journalctl -u v2ray -f"
echo "- 查看 TCP 规则: iptables -t nat -L V2RAY -n -v"
echo "- 查看 UDP 规则: iptables -t mangle -L V2RAY_MARK -n -v"
