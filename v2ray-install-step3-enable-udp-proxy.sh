#!/bin/bash

# V2Ray UDP 透明代理配置脚本
# 前提: 已配置 TCP 透明代理

echo "=== V2Ray UDP 透明代理配置脚本 ==="
echo ""

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo "此脚本需要 root 权限运行"
    echo "请使用: sudo bash $0"
    exit 1
fi

# 检查 V2Ray 是否已安装
if [ ! -f "/usr/local/bin/v2ray" ]; then
    echo "✗ V2Ray 未安装"
    exit 1
fi

# 检查 TCP 透明代理是否已配置
if ! iptables -t nat -L V2RAY -n >/dev/null 2>&1; then
    echo "✗ TCP 透明代理未配置，请先运行 v2ray-install-step2-enable-tcp-proxy.sh"
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
cp /usr/local/etc/v2ray/config.json /usr/local/etc/v2ray/config.json.backup.$(date +%Y%m%d_%H%M%S)
echo "✓ 配置已备份"
echo ""

# 读取现有配置中的上游服务器信息
echo "=== 读取现有配置 ==="

# 使用 jq 解析配置
UPSTREAM_ADDRESS=$(jq -r '.outbounds[0].settings.vnext[0].address' /usr/local/etc/v2ray/config.json 2>/dev/null)
UPSTREAM_PORT=$(jq -r '.outbounds[0].settings.vnext[0].port' /usr/local/etc/v2ray/config.json 2>/dev/null)
UPSTREAM_ID=$(jq -r '.outbounds[0].settings.vnext[0].users[0].id' /usr/local/etc/v2ray/config.json 2>/dev/null)
SERVER_NAME=$(jq -r '.outbounds[0].streamSettings.tlsSettings.serverName' /usr/local/etc/v2ray/config.json 2>/dev/null)

# 检查解析结果
if [ -z "$UPSTREAM_ADDRESS" ] || [ "$UPSTREAM_ADDRESS" = "null" ] || [ -z "$UPSTREAM_PORT" ] || [ "$UPSTREAM_PORT" = "null" ]; then
    echo "✗ 无法解析上游服务器配置"
    echo "请检查 V2Ray 配置文件格式是否正确"
    exit 1
fi

echo "上游服务器: $UPSTREAM_ADDRESS:$UPSTREAM_PORT"
echo "UUID: ${UPSTREAM_ID:0:8}..."
echo "SNI: $SERVER_NAME"
echo ""

# 生成新配置（添加 TPROXY 支持）
echo "=== 更新配置添加 TPROXY 支持 ==="
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
    },
    {
      "port": 60002,
      "protocol": "dokodemo-door",
      "settings": {
        "network": "udp",
        "followRedirect": true
      },
      "streamSettings": {
        "sockopt": {
          "tproxy": "tproxy"
        }
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

# 验证配置语法
echo "验证配置语法..."
if ! /usr/local/bin/v2ray test -config /usr/local/etc/v2ray/config.json; then
    echo "✗ 配置文件语法错误，恢复备份"
    BACKUP_FILE=$(ls -t /usr/local/etc/v2ray/config.json.backup.* | head -1)
    if [ -n "$BACKUP_FILE" ]; then
        cp "$BACKUP_FILE" /usr/local/etc/v2ray/config.json
        echo "已恢复备份: $BACKUP_FILE"
    fi
    exit 1
fi

echo "✓ 配置语法验证通过"
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

# 检查端口监听（支持 IPv4 和 IPv6）
echo "检查端口监听..."
# 等待服务完全启动
sleep 3

UDP_PORT_CHECK=false
for i in {1..5}; do
    if ss -ulnp 2>/dev/null | grep -q ":60002"; then
        UDP_PORT_CHECK=true
        break
    fi
    echo "等待 UDP 端口启动... ($i/5)"
    sleep 2
done

if [ "$UDP_PORT_CHECK" = true ]; then
    echo "✓ UDP 透明代理端口 60002 正在监听"
else
    echo "✗ UDP 透明代理端口 60002 未监听"
    echo "调试信息:"
    echo "V2Ray 服务状态:"
    systemctl status v2ray --no-pager -l | head -10
    echo "所有 V2Ray UDP 监听端口:"
    ss -ulnp 2>/dev/null | grep v2ray || echo "  未找到"
    exit 1
fi

echo ""

# 检查 TPROXY 内核模块
echo "=== 检查 TPROXY 支持 ==="
if ! lsmod | grep -q xt_TPROXY; then
    echo "加载 TPROXY 模块..."
    modprobe xt_TPROXY
    if [ $? -eq 0 ]; then
        echo "✓ TPROXY 模块已加载"
    else
        echo "✗ TPROXY 模块加载失败"
        exit 1
    fi
else
    echo "✓ TPROXY 模块已加载"
fi
echo ""

# 配置 UDP iptables 规则
echo "=== 配置 UDP iptables 规则 ==="

# 检查 V2RAY_MARK 链是否已存在
if iptables -t mangle -L V2RAY_MARK -n >/dev/null 2>&1; then
    echo "V2RAY_MARK 链已存在，清除旧规则..."
    iptables -t mangle -F V2RAY_MARK
    iptables -t mangle -D PREROUTING -i wg0 -p udp -j V2RAY_MARK 2>/dev/null || true
    iptables -t mangle -X V2RAY_MARK
fi

# 创建 V2RAY_MARK 链
iptables -t mangle -N V2RAY_MARK

# 排除保留地址
iptables -t mangle -A V2RAY_MARK -d 0.0.0.0/8 -j RETURN
iptables -t mangle -A V2RAY_MARK -d 10.0.0.0/8 -j RETURN
iptables -t mangle -A V2RAY_MARK -d 127.0.0.0/8 -j RETURN
iptables -t mangle -A V2RAY_MARK -d 169.254.0.0/16 -j RETURN
iptables -t mangle -A V2RAY_MARK -d 172.16.0.0/12 -j RETURN
iptables -t mangle -A V2RAY_MARK -d 192.168.0.0/16 -j RETURN
iptables -t mangle -A V2RAY_MARK -d 224.0.0.0/4 -j RETURN
iptables -t mangle -A V2RAY_MARK -d 240.0.0.0/4 -j RETURN

# UDP 流量 TPROXY
iptables -t mangle -A V2RAY_MARK -p udp -j TPROXY --on-port 60002 --tproxy-mark 1

# 应用到 WireGuard UDP 流量
iptables -t mangle -A PREROUTING -i wg0 -p udp -j V2RAY_MARK

echo "✓ UDP iptables 规则已配置"

# 验证规则是否生效
if ! iptables -t mangle -C PREROUTING -i wg0 -p udp -j V2RAY_MARK 2>/dev/null; then
    echo "✗ UDP iptables 规则未正确应用"
    exit 1
fi

echo "✓ UDP iptables 规则验证通过"
echo ""

# 配置策略路由
echo "=== 配置策略路由 ==="

# 删除旧规则（如果存在）
ip rule del fwmark 1 table 100 2>/dev/null || true
ip route del local 0.0.0.0/0 dev lo table 100 2>/dev/null || true

# 添加新规则
ip rule add fwmark 1 table 100
ip route add local 0.0.0.0/0 dev lo table 100

echo "✓ 策略路由已配置"

# 验证策略路由
if ! ip rule show | grep -q "fwmark 0x1"; then
    echo "✗ 策略路由规则未正确应用"
    exit 1
fi

if ! ip route show table 100 | grep -q "local default"; then
    echo "✗ 策略路由表未正确配置"
    exit 1
fi

echo "✓ 策略路由验证通过"
echo ""

# 创建持久化脚本
echo "=== 创建策略路由持久化脚本 ==="
cat > /etc/network/if-up.d/v2ray-tproxy << 'SCRIPT_EOF'
#!/bin/bash
ip rule add fwmark 1 table 100 2>/dev/null || true
ip route add local 0.0.0.0/0 dev lo table 100 2>/dev/null || true
SCRIPT_EOF

chmod +x /etc/network/if-up.d/v2ray-tproxy
echo "✓ 持久化脚本已创建"
echo ""

# 保存 iptables 规则
echo "=== 保存 iptables 规则 ==="
netfilter-persistent save
echo "✓ iptables 规则已保存"
echo ""

# 验证配置
echo "=== 验证配置 ==="
echo "TCP 规则 (nat 表):"
iptables -t nat -L V2RAY -n -v | head -12
echo ""
echo "UDP 规则 (mangle 表):"
iptables -t mangle -L V2RAY_MARK -n -v | head -12
echo ""
echo "策略路由:"
ip rule show | grep "fwmark 0x1"
ip route show table 100
echo ""

echo "=== 配置完成 ==="
echo ""
echo "UDP 透明代理已启用:"
echo "- TCP 透明代理: REDIRECT -> 端口 60001 (nat 表)"
echo "- UDP 透明代理: TPROXY -> 端口 60002 (mangle 表)"
echo "- WireGuard 客户端 TCP/UDP 流量自动通过代理"
echo ""
echo "测试方法:"
echo "1. 连接 WireGuard"
echo "2. 测试 DNS: dig @8.8.8.8 google.com"
echo "3. 测试 HTTP/3: curl --http3 https://www.google.com -I"
echo ""
echo "管理命令:"
echo "- 查看 V2Ray 状态: systemctl status v2ray"
echo "- 查看 V2Ray 日志: journalctl -u v2ray -f"
echo "- 查看 TCP 规则: iptables -t nat -L V2RAY -n -v"
echo "- 查看 UDP 规则: iptables -t mangle -L V2RAY_MARK -n -v"
echo "- 查看策略路由: ip rule show; ip route show table 100"
echo ""
