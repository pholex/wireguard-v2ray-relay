#!/bin/bash

# WireGuard 安装和配置脚本
# 适用于 Ubuntu Server 22.04 LTS

set -e

# 解析命令行参数
AUTO_YES=true  # 默认自动模式
SHOW_HELP=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -i|--interactive)
            AUTO_YES=false
            shift
            ;;
        -h|--help)
            SHOW_HELP=true
            shift
            ;;
        *)
            echo "未知参数: $1"
            SHOW_HELP=true
            shift
            ;;
    esac
done

# 显示帮助信息
if [ "$SHOW_HELP" = true ]; then
    echo "WireGuard 安装和配置脚本"
    echo ""
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -i, --interactive    启用交互模式，允许自定义配置"
    echo "  -h, --help          显示此帮助信息"
    echo ""
    echo "默认行为:"
    echo "  - 自动模式（无交互）"
    echo "  - 端口: 51820"
    echo "  - 网段: 10.0.8.0/24"
    echo "  - 客户端数量: 2"
    echo ""
    echo "示例:"
    echo "  $0                   # 自动安装（推荐）"
    echo "  $0 --interactive     # 交互式安装，可自定义配置"
    exit 0
fi

echo "=== WireGuard 安装和配置脚本 ==="
echo ""

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo "此脚本需要 root 权限运行"
    echo "请使用: sudo bash $0"
    exit 1
fi

# 检查系统版本
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        echo "⚠ 警告: 此脚本针对 Ubuntu 22.04 LTS 优化"
        if [ "$AUTO_YES" = false ]; then
            read -p "是否继续? (y/n): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 1
            fi
        else
            echo "自动模式: 继续执行"
        fi
    fi
fi

# 检测云服务商环境
echo "=== 检测云服务商环境 ==="
CLOUD_PROVIDER="unknown"
if curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/instance-id >/dev/null 2>&1; then
    CLOUD_PROVIDER="aws"
    echo "检测到 AWS EC2 环境"
elif curl -s --connect-timeout 2 http://metadata.tencentyun.com/latest/meta-data/instance-id >/dev/null 2>&1; then
    # 检测腾讯云服务类型
    INSTANCE_TYPE=$(curl -s --connect-timeout 2 http://metadata.tencentyun.com/latest/meta-data/instance/instance-type 2>/dev/null || echo "unknown")
    if echo "$INSTANCE_TYPE" | grep -q "^lh"; then
        CLOUD_PROVIDER="tencent-lighthouse"
        echo "检测到腾讯云 Lighthouse 环境"
    else
        CLOUD_PROVIDER="tencent-cvm"
        echo "检测到腾讯云 CVM 环境"
    fi
else
    echo "未检测到已知云服务商环境"
fi

# 配置参数
if [ "$AUTO_YES" = false ]; then
    echo "=== 交互式配置 ==="
    read -p "WireGuard 监听端口 [默认: 51820]: " WG_PORT
    WG_PORT=${WG_PORT:-51820}

    read -p "VPN 内网网段 [默认: 10.0.8.0/24]: " VPN_SUBNET
    VPN_SUBNET=${VPN_SUBNET:-10.0.8.0/24}

    read -p "需要创建几个客户端配置? [默认: 2]: " CLIENT_COUNT
    CLIENT_COUNT=${CLIENT_COUNT:-2}
else
    echo "=== 自动配置 ==="
    WG_PORT=51820
    VPN_SUBNET="10.0.8.0/24"
    CLIENT_COUNT=2
    echo "使用默认配置（如需自定义请使用 --interactive 参数）"
fi

# 提取网段前缀
VPN_PREFIX=$(echo $VPN_SUBNET | cut -d'/' -f1 | cut -d'.' -f1-3)
SERVER_IP="${VPN_PREFIX}.1"

echo ""
echo "配置信息:"
echo "- 监听端口: $WG_PORT"
echo "- VPN 网段: $VPN_SUBNET"
echo "- 服务器 IP: $SERVER_IP"
echo "- 客户端数量: $CLIENT_COUNT"
echo ""
if [ "$AUTO_YES" = false ]; then
    read -p "确认配置? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "已取消"
        exit 1
    fi
else
    echo "自动确认配置"
fi

# 一、安装 WireGuard 和必要工具
echo "=== 安装 WireGuard 和必要工具 ==="

# 检查内核 WireGuard 支持
echo "检查内核 WireGuard 支持..."
KERNEL_HAS_WG=false
if [ -d "/sys/module/wireguard" ] || modinfo wireguard >/dev/null 2>&1; then
    KERNEL_HAS_WG=true
    echo "✓ 内核已支持 WireGuard"
else
    echo "⚠ 内核不支持 WireGuard，需要 DKMS 编译"
fi

# 检查是否已安装
if command -v wg &> /dev/null; then
    echo "✓ WireGuard 工具已安装"
    wg --version
else
    echo "正在安装 WireGuard..."
    
    apt update
    
    # 根据内核支持情况选择安装包
    if [ "$KERNEL_HAS_WG" = true ]; then
        echo "安装 WireGuard 工具包（内核已支持）..."
        apt install -y wireguard-tools
    else
        echo "安装完整 WireGuard 包（包含 DKMS）..."
        apt install -y wireguard
    fi
    
    # 验证安装
    if command -v wg &> /dev/null; then
        echo "✓ WireGuard 安装完成"
    else
        echo "✗ WireGuard 安装失败"
        exit 1
    fi
fi

# 检查并安装 unzip（V2Ray 安装需要）
if ! command -v unzip &> /dev/null; then
    echo "正在安装 unzip（V2Ray 安装需要）..."
    apt install -y unzip
    echo "✓ unzip 安装完成"
else
    echo "✓ unzip 已安装"
fi

# 检查并安装 sshpass（远程管理需要）
if ! command -v sshpass &> /dev/null; then
    echo "正在安装 sshpass（远程管理需要）..."
    apt install -y sshpass
    echo "✓ sshpass 安装完成"
else
    echo "✓ sshpass 已安装"
fi

# 检查并安装 jq（JSON 解析需要）
if ! command -v jq &> /dev/null; then
    echo "正在安装 jq（JSON 解析需要）..."
    apt install -y jq
    echo "✓ jq 安装完成"
else
    echo "✓ jq 已安装"
fi

echo ""

# 二、启用 IP 转发
echo "=== 启用 IP 转发 ==="

if grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
    echo "✓ IP 转发已启用"
else
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
    sysctl -p
    echo "✓ IP 转发已启用"
fi

echo ""

# 三、生成密钥
echo "=== 生成密钥 ==="

# 创建密钥目录
mkdir -p /etc/wireguard
chmod 700 /etc/wireguard

# 生成服务器密钥
if [ ! -f /etc/wireguard/server_private.key ]; then
    wg genkey | tee /etc/wireguard/server_private.key | wg pubkey > /etc/wireguard/server_public.key
    chmod 600 /etc/wireguard/server_private.key
    echo "✓ 服务器密钥已生成"
else
    echo "✓ 服务器密钥已存在"
fi

SERVER_PRIVATE_KEY=$(cat /etc/wireguard/server_private.key)
SERVER_PUBLIC_KEY=$(cat /etc/wireguard/server_public.key)

# 创建 private 目录用于存储客户端配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRIVATE_DIR="$SCRIPT_DIR/private"
mkdir -p "$PRIVATE_DIR"

# 生成客户端密钥
declare -a CLIENT_PRIVATE_KEYS
declare -a CLIENT_PUBLIC_KEYS

for i in $(seq 1 $CLIENT_COUNT); do
    if [ ! -f "$PRIVATE_DIR/client${i}_private.key" ]; then
        wg genkey | tee "$PRIVATE_DIR/client${i}_private.key" | wg pubkey > "$PRIVATE_DIR/client${i}_public.key"
        chmod 600 "$PRIVATE_DIR/client${i}_private.key"
        echo "✓ 客户端 $i 密钥已生成"
    else
        echo "✓ 客户端 $i 密钥已存在"
    fi
    
    CLIENT_PRIVATE_KEYS[$i]=$(cat "$PRIVATE_DIR/client${i}_private.key")
    CLIENT_PUBLIC_KEYS[$i]=$(cat "$PRIVATE_DIR/client${i}_public.key")
done

echo ""

# 四、获取网卡名称
echo "=== 检测网卡 ==="
DEFAULT_INTERFACE=$(ip route | grep default | awk '{print $5}' | head -1)
if [ -z "$DEFAULT_INTERFACE" ]; then
    echo "⚠ 无法自动检测网卡，使用 eth0"
    DEFAULT_INTERFACE="eth0"
else
    echo "检测到默认网卡: $DEFAULT_INTERFACE"
fi

if [ "$AUTO_YES" = false ]; then
    read -p "使用此网卡? (y/n) [默认: y]: " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]] && [[ ! -z $REPLY ]]; then
        read -p "请输入网卡名称: " DEFAULT_INTERFACE
    fi
else
    echo "自动使用默认网卡"
fi
echo "使用网卡: $DEFAULT_INTERFACE"
echo ""

# 五、创建服务器配置
echo "=== 创建服务器配置 ==="

cat > /etc/wireguard/wg0.conf << EOF
[Interface]
PrivateKey = $SERVER_PRIVATE_KEY
Address = $SERVER_IP/24
ListenPort = $WG_PORT
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o $DEFAULT_INTERFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o $DEFAULT_INTERFACE -j MASQUERADE

EOF

# 添加客户端 Peer 配置
for i in $(seq 1 $CLIENT_COUNT); do
    CLIENT_IP="${VPN_PREFIX}.$((i+1))"
    cat >> /etc/wireguard/wg0.conf << EOF
[Peer]
PublicKey = ${CLIENT_PUBLIC_KEYS[$i]}
AllowedIPs = $CLIENT_IP/32

EOF
done

chmod 600 /etc/wireguard/wg0.conf

# 备份到 private 目录
cp /etc/wireguard/wg0.conf "$PRIVATE_DIR/server-wg0.conf"

echo "✓ 服务器配置已创建"
echo "  配置文件: /etc/wireguard/wg0.conf"
echo "  备份文件: $PRIVATE_DIR/server-wg0.conf"
echo ""

# 六、启动 WireGuard 服务
echo "=== 启动 WireGuard 服务 ==="

systemctl enable wg-quick@wg0
systemctl restart wg-quick@wg0

sleep 2

if systemctl is-active --quiet wg-quick@wg0; then
    echo "✓ WireGuard 服务已启动"
else
    echo "✗ WireGuard 服务启动失败"
    systemctl status wg-quick@wg0 --no-pager -l
    exit 1
fi

echo ""

# 七、配置防火墙
echo "=== 配置防火墙 ==="

# 检查 UFW 是否启用
if command -v ufw &> /dev/null && ufw status | grep -q "Status: active"; then
    echo "检测到 UFW 已启用，配置防火墙规则..."
    ufw allow $WG_PORT/udp comment "WireGuard"
    echo "✓ UFW 规则已添加"
else
    echo "✓ UFW 未启用，使用 iptables 规则"
fi

echo "⚠ 请确保云服务器安全组开放 UDP $WG_PORT 端口"
echo ""

# 八、生成客户端配置文件
echo "=== 生成客户端配置文件 ==="

# 获取服务器公网 IP
SERVER_PUBLIC_IP=""
echo "获取服务器公网 IP..."

# 尝试多种方法获取公网 IP
if [ -z "$SERVER_PUBLIC_IP" ]; then
    SERVER_PUBLIC_IP=$(curl -s --connect-timeout 5 ifconfig.me 2>/dev/null || echo "")
fi
if [ -z "$SERVER_PUBLIC_IP" ]; then
    SERVER_PUBLIC_IP=$(curl -s --connect-timeout 5 icanhazip.com 2>/dev/null || echo "")
fi
if [ -z "$SERVER_PUBLIC_IP" ]; then
    SERVER_PUBLIC_IP=$(curl -s --connect-timeout 5 ipinfo.io/ip 2>/dev/null || echo "")
fi

# 如果仍然无法获取，使用默认值
if [ -z "$SERVER_PUBLIC_IP" ]; then
    echo "⚠ 无法自动获取公网 IP，请手动修改客户端配置文件中的 Endpoint"
    SERVER_PUBLIC_IP="YOUR_SERVER_IP"
else
    echo "✓ 检测到公网 IP: $SERVER_PUBLIC_IP"
fi

for i in $(seq 1 $CLIENT_COUNT); do
    CLIENT_IP="${VPN_PREFIX}.$((i+1))"
    
    cat > "$PRIVATE_DIR/client${i}.conf" << EOF
[Interface]
PrivateKey = ${CLIENT_PRIVATE_KEYS[$i]}
Address = $CLIENT_IP/24
DNS = 8.8.8.8, 8.8.4.4

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $SERVER_PUBLIC_IP:$WG_PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
    
    chmod 600 "$PRIVATE_DIR/client${i}.conf"
    echo "✓ 客户端 $i 配置已生成: $PRIVATE_DIR/client${i}.conf"
done

echo ""

# 九、显示连接状态
echo "=== WireGuard 状态 ==="
wg show
echo ""

# 十、显示摘要信息
echo "=== 安装完成 ==="
echo ""
echo "服务器信息:"
echo "- 公网 IP: $SERVER_PUBLIC_IP"
echo "- 监听端口: $WG_PORT"
echo "- VPN IP: $SERVER_IP"
echo "- 服务器公钥: $SERVER_PUBLIC_KEY"
echo ""
echo "客户端配置文件:"
for i in $(seq 1 $CLIENT_COUNT); do
    echo "- 客户端 $i: $PRIVATE_DIR/client${i}.conf"
done
echo ""
echo "管理命令:"
echo "- 查看状态: sudo systemctl status wg-quick@wg0"
echo "- 查看连接: sudo wg show"
echo "- 重启服务: sudo systemctl restart wg-quick@wg0"
echo "- 查看日志: sudo journalctl -u wg-quick@wg0 -f"
echo ""
echo "防火墙配置:"
echo "- 请确保云服务器安全组开放 UDP $WG_PORT 端口"
echo ""
echo "客户端使用:"
echo "1. 将客户端配置文件传输到客户端设备"
echo "2. 使用 WireGuard 客户端导入配置文件"
echo "3. 连接 VPN"
echo ""
echo "下载配置文件到本地:"
echo "# 从远程服务器下载所有配置文件"
echo "scp -r root@$SERVER_PUBLIC_IP:$PRIVATE_DIR ./private/"
echo ""
echo "# 或单独下载客户端配置"
for i in $(seq 1 $CLIENT_COUNT); do
    echo "scp root@$SERVER_PUBLIC_IP:$PRIVATE_DIR/client${i}.conf ./private/"
done
echo ""
