#!/bin/bash

# V2Ray 透明代理配置脚本
# 前提: 已安装 WireGuard 和 V2Ray

echo "=== V2Ray 透明代理配置脚本 ==="
echo ""

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo "此脚本需要 root 权限运行"
    echo "请使用: sudo bash $0"
    exit 1
fi

# 检查 V2Ray 是否已安装
if [ ! -f "/usr/local/bin/v2ray" ]; then
    echo "✗ V2Ray 未安装，请先运行 install-v2ray.sh"
    exit 1
fi

# 检查 WireGuard 是否运行
if ! systemctl is-active --quiet wg-quick@wg0; then
    echo "✗ WireGuard 服务未运行"
    exit 1
fi

echo "✓ 环境检查通过"
echo ""

# 备份原配置
echo "=== 备份 V2Ray 配置 ==="
if [ -f "/usr/local/etc/v2ray/config.json" ]; then
    cp /usr/local/etc/v2ray/config.json /usr/local/etc/v2ray/config.json.backup.$(date +%Y%m%d_%H%M%S)
    echo "✓ 配置已备份"
else
    echo "✗ 配置文件不存在"
    exit 1
fi

echo ""

# 读取现有配置中的上游服务器信息
echo "=== 读取现有配置 ==="
UPSTREAM_ADDRESS=$(grep -A 20 '"outbounds"' /usr/local/etc/v2ray/config.json | grep '"address"' | head -1 | sed 's/.*"\(.*\)".*/\1/')
UPSTREAM_PORT=$(grep -A 20 '"outbounds"' /usr/local/etc/v2ray/config.json | grep '"port"' | head -1 | sed 's/.*: \(.*\),/\1/')
UPSTREAM_ID=$(grep -A 20 '"outbounds"' /usr/local/etc/v2ray/config.json | grep '"id"' | head -1 | sed 's/.*"\(.*\)".*/\1/')
SERVER_NAME=$(grep -A 20 '"outbounds"' /usr/local/etc/v2ray/config.json | grep '"serverName"' | head -1 | sed 's/.*"\(.*\)".*/\1/')

echo "上游服务器: $UPSTREAM_ADDRESS:$UPSTREAM_PORT"
echo "UUID: $UPSTREAM_ID"
echo "SNI: $SERVER_NAME"
echo ""

# 生成新配置
echo "=== 生成新配置 ==="
cat > /usr/local/etc/v2ray/config.json << EOF
{
  "dns": {
    "servers": [
      {
        "address": "8.8.8.8",
        "domains": ["geosite:geolocation-!cn"]
      },
      {
        "address": "223.5.5.5",
        "domains": ["geosite:cn"]
      },
      "8.8.8.8"
    ]
  },
  "routing": {
    "rules": [
      {
        "type": "field",
        "domain": ["domain:docker.com", "domain:docker.io", "domain:google.com", "domain:youtube.com"],
        "outboundTag": "proxy"
      },
      {
        "type": "field",
        "domain": ["geosite:cn"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "ip": ["geoip:cn", "geoip:private"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "network": "tcp,udp",
        "outboundTag": "proxy"
      }
    ]
  },
  "inbounds": [
    {
      "port": 7890,
      "protocol": "socks",
      "settings": {
        "udp": true
      }
    },
    {
      "port": 60001,
      "protocol": "dokodemo-door",
      "settings": {
        "network": "tcp",
        "followRedirect": true
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
  ],
  "outbounds": [
    {
      "tag": "proxy",
      "protocol": "vmess",
      "settings": {
        "vnext": [{
          "address": "$UPSTREAM_ADDRESS",
          "port": $UPSTREAM_PORT,
          "users": [{
            "id": "$UPSTREAM_ID",
            "alterId": 0,
            "security": "auto"
          }]
        }]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "serverName": "$SERVER_NAME"
        }
      }
    },
    {
      "tag": "direct",
      "protocol": "freedom"
    }
  ]
}
EOF

echo "✓ 配置文件已更新"
echo ""

# 重启 V2Ray
echo "=== 重启 V2Ray 服务 ==="
systemctl restart v2ray
sleep 2

if ! systemctl is-active --quiet v2ray; then
    echo "✗ V2Ray 服务启动失败"
    systemctl status v2ray --no-pager -l
    exit 1
fi

echo "✓ V2Ray 服务已重启"
echo ""

# 检查端口监听
echo "=== 检查端口监听 ==="
if netstat -tlnp 2>/dev/null | grep -q ":60001 " || ss -tlnp 2>/dev/null | grep -q ":60001 "; then
    echo "✓ 透明代理端口 60001 正在监听"
else
    echo "✗ 透明代理端口 60001 未监听"
    exit 1
fi

if netstat -tlnp 2>/dev/null | grep -q ":7890 " || ss -tlnp 2>/dev/null | grep -q ":7890 "; then
    echo "✓ SOCKS5 端口 7890 正在监听"
else
    echo "✗ SOCKS5 端口 7890 未监听"
    exit 1
fi

echo ""

# 配置 iptables 规则
echo "=== 配置 iptables 规则 ==="

# 检查 V2RAY 链是否已存在
if iptables -t nat -L V2RAY -n >/dev/null 2>&1; then
    echo "V2RAY 链已存在，清除旧规则..."
    iptables -t nat -F V2RAY
    iptables -t nat -D PREROUTING -i wg0 -p tcp -j V2RAY 2>/dev/null || true
    iptables -t nat -X V2RAY
fi

# 创建 V2RAY 链
iptables -t nat -N V2RAY

# 排除保留地址
iptables -t nat -A V2RAY -d 0.0.0.0/8 -j RETURN
iptables -t nat -A V2RAY -d 10.0.0.0/8 -j RETURN
iptables -t nat -A V2RAY -d 127.0.0.0/8 -j RETURN
iptables -t nat -A V2RAY -d 169.254.0.0/16 -j RETURN
iptables -t nat -A V2RAY -d 172.16.0.0/12 -j RETURN
iptables -t nat -A V2RAY -d 192.168.0.0/16 -j RETURN
iptables -t nat -A V2RAY -d 224.0.0.0/4 -j RETURN
iptables -t nat -A V2RAY -d 240.0.0.0/4 -j RETURN

# 重定向到透明代理端口
iptables -t nat -A V2RAY -p tcp -j REDIRECT --to-ports 60001

# 应用到 WireGuard 流量
iptables -t nat -A PREROUTING -i wg0 -p tcp -j V2RAY

echo "✓ iptables 规则已配置"
echo ""

# 保存 iptables 规则
echo "=== 保存 iptables 规则 ==="

# 检查 iptables-persistent 是否已安装
if ! dpkg -l | grep -q iptables-persistent; then
    echo "安装 iptables-persistent..."
    env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY apt install -y iptables-persistent >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "✓ iptables-persistent 已安装"
    else
        echo "⚠ iptables-persistent 安装失败，规则重启后会丢失"
    fi
fi

netfilter-persistent save
echo "✓ iptables 规则已保存"
echo ""

# 验证配置
echo "=== 验证配置 ==="
echo "iptables V2RAY 链规则:"
iptables -t nat -L V2RAY -n -v | head -12
echo ""

echo "=== 配置完成 ==="
echo ""
echo "透明代理已启用:"
echo "- SOCKS5 代理: 0.0.0.0:7890"
echo "- TCP 透明代理: 0.0.0.0:60001"
echo "- WireGuard 客户端流量自动通过代理"
echo ""
echo "测试方法:"
echo "1. 连接 WireGuard"
echo "2. 访问 http://ip-api.com 查看出口 IP"
echo ""
echo "管理命令:"
echo "- 查看 V2Ray 状态: systemctl status v2ray"
echo "- 查看 V2Ray 日志: journalctl -u v2ray -f"
echo "- 查看 iptables 规则: iptables -t nat -L V2RAY -n -v"
echo ""
