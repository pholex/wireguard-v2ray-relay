#!/bin/bash

# 阿里云 ECS 预安装脚本
# 
# 问题说明：
# 在阿里云 ECS 上安装 wireguard-tools 时，由于包依赖关系会自动安装：
# - linux-firmware (Linux 固件包)
# - amd64-microcode (AMD 微码更新) 
# - linux-image-realtime (实时内核)
# 这些组件会触发内核升级，可能中断主安装流程
#
# 解决方案：
# 1. 先运行此脚本预安装这些组件
# 2. 重启系统到新内核（推荐）
# 3. 再运行 wireguard-install.sh 进行配置
#
# 使用方法：
# sudo bash aliyun-pre-install.sh
# sudo reboot
# sudo bash wireguard-install.sh

set -e

# 禁用交互式提示
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

echo "=== 阿里云 ECS 预安装 ==="

# 检测阿里云环境
if ! curl -s --connect-timeout 3 http://100.100.100.200/latest/meta-data/instance-id >/dev/null 2>&1; then
    echo "❌ 非阿里云 ECS 环境，无需运行此脚本"
    echo "💡 其他云服务商请直接运行: sudo bash wireguard-install.sh"
    exit 1
fi

echo "✓ 检测到阿里云 ECS 环境"

# 检查 WireGuard 是否已安装
if command -v wg &> /dev/null; then
    echo "✓ WireGuard 工具已安装，无需预安装"
    echo "💡 可以直接运行主安装脚本: sudo bash wireguard-install.sh"
    exit 0
fi

echo "预安装 WireGuard 相关组件（会触发内核升级）"

# 预配置 iptables-persistent 避免交互式提示
echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections

# 更新并安装 WireGuard 工具和相关组件（会触发内核升级）
apt update && apt install -y wireguard-tools unzip jq sshpass iptables-persistent

echo "✓ 预安装完成"
echo ""
echo "📋 下一步操作："
echo "1. 重启系统: sudo reboot"
echo "2. 运行主安装: sudo bash wireguard-install.sh"
