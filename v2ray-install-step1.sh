#!/bin/bash

# V2Ray 代理安装脚本
# 适用于 Amazon Linux 2023 / Ubuntu

echo "=== V2Ray 代理安装脚本 ==="
echo ""

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then
    echo "此脚本需要 root 权限运行"
    echo "请使用: sudo bash $0"
    exit 1
fi

# 设置系统级代理函数
setup_system_proxy() {
    local proxy_url="$1"
    local no_proxy_list="localhost,127.0.0.1,::1,169.254.169.254"
    
    # 如果是 AWS EC2，添加 AWS 特定域名
    if curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/instance-id >/dev/null 2>&1; then
        no_proxy_list="$no_proxy_list,amazonaws.com,amazonaws.com.cn,compute.internal,ec2.internal"
    fi
    
    echo "设置系统级代理: $proxy_url"
    
    # 设置到 /etc/environment
    if [ ! -f "/etc/environment" ] || [ ! -s "/etc/environment" ]; then
        tee /etc/environment <<EOF
http_proxy=$proxy_url
https_proxy=$proxy_url
HTTP_PROXY=$proxy_url
HTTPS_PROXY=$proxy_url
no_proxy=$no_proxy_list
NO_PROXY=$no_proxy_list
EOF
    else
        sed -i '/^http_proxy=/d' /etc/environment
        sed -i '/^https_proxy=/d' /etc/environment
        sed -i '/^HTTP_PROXY=/d' /etc/environment
        sed -i '/^HTTPS_PROXY=/d' /etc/environment
        sed -i '/^no_proxy=/d' /etc/environment
        sed -i '/^NO_PROXY=/d' /etc/environment
        
        tee -a /etc/environment <<EOF
http_proxy=$proxy_url
https_proxy=$proxy_url
HTTP_PROXY=$proxy_url
HTTPS_PROXY=$proxy_url
no_proxy=$no_proxy_list
NO_PROXY=$no_proxy_list
EOF
    fi

    # 设置systemd系统级代理
    mkdir -p /etc/systemd/system.conf.d
    tee /etc/systemd/system.conf.d/proxy.conf <<EOF
[Manager]
DefaultEnvironment="http_proxy=$proxy_url"
DefaultEnvironment="https_proxy=$proxy_url"
DefaultEnvironment="HTTP_PROXY=$proxy_url"
DefaultEnvironment="HTTPS_PROXY=$proxy_url"
DefaultEnvironment="no_proxy=$no_proxy_list"
DefaultEnvironment="NO_PROXY=$no_proxy_list"
EOF

    systemctl daemon-reexec
    
    # 立即生效当前会话
    source /etc/environment
    export http_proxy="$proxy_url"
    export https_proxy="$proxy_url"
    export HTTP_PROXY="$proxy_url"
    export HTTPS_PROXY="$proxy_url"
    export no_proxy="$no_proxy_list"
    export NO_PROXY="$no_proxy_list"
}

# 清理系统级代理函数
cleanup_system_proxy() {
    local proxy_url="$1"
    
    echo "清理系统级代理配置: $proxy_url"
    
    if [ -f "/etc/environment" ] && [ -n "$proxy_url" ]; then
        escaped_url=$(echo "$proxy_url" | sed 's/[.*^$()+?{|/]/\\&/g')
        sed -i "/^http_proxy=$escaped_url$/d" /etc/environment
        sed -i "/^https_proxy=$escaped_url$/d" /etc/environment
        sed -i "/^HTTP_PROXY=$escaped_url$/d" /etc/environment
        sed -i "/^HTTPS_PROXY=$escaped_url$/d" /etc/environment
        sed -i "/^no_proxy=/d" /etc/environment
        sed -i "/^NO_PROXY=/d" /etc/environment
        
        if [ ! -s "/etc/environment" ]; then
            rm /etc/environment
        fi
    fi
    
    if [ -f "/etc/systemd/system.conf.d/proxy.conf" ]; then
        rm /etc/systemd/system.conf.d/proxy.conf
    fi
    
    systemctl daemon-reexec
    unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY no_proxy NO_PROXY
}

# 环境检查
echo "=== 环境检查 ==="
echo "检查 1080 端口状态..."
TEMP_PROXY=""

if netstat -tlnp 2>/dev/null | grep -q ":1080 " || ss -tlnp 2>/dev/null | grep -q ":1080 "; then
    echo "✓ 检测到 1080 端口有服务监听"
    echo "测试代理连接..."
    PROXY_TEST_RESULT=$(curl --socks5 127.0.0.1:1080 --connect-timeout 10 -s ip-api.com 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$PROXY_TEST_RESULT" ]; then
        echo "✓ 1080 端口代理可用，代理IP: $PROXY_TEST_RESULT"
        echo "设置临时代理加速安装..."
        
        if [ -f "/etc/environment" ] && [ -s "/etc/environment" ]; then
            cp /etc/environment /etc/environment.backup.v2ray
        fi
        
        setup_system_proxy "socks5://127.0.0.1:1080"
        TEMP_PROXY="socks5://127.0.0.1:1080"
    else
        echo "✗ 1080 端口代理不可用"
    fi
else
    echo "✗ 未检测到 1080 端口代理"
fi

echo ""

# 检查 V2Ray 是否已安装
if [ -f "/usr/local/bin/v2ray" ]; then
    echo "检测到 V2Ray 已安装"
    echo "V2Ray 版本: $(/usr/local/bin/v2ray version | head -1)"
    echo ""
    echo "是否重新安装？"
    echo "1. 重新安装"
    echo "2. 仅重启服务"
    echo "0. 退出"
    read -p "请选择 (0-2, 默认 2): " REINSTALL
    
    if [ -z "$REINSTALL" ]; then
        REINSTALL=2
    fi
    
    case $REINSTALL in
        0)
            echo "退出脚本"
            if [ -n "$TEMP_PROXY" ]; then
                cleanup_system_proxy "$TEMP_PROXY"
            fi
            exit 0
            ;;
        1)
            echo "开始重新安装..."
            ;;
        2)
            echo "重启 V2Ray 服务..."
            
            # 检查配置文件是否存在
            if [ ! -f "/usr/local/etc/v2ray/config.json" ]; then
                echo "✗ 配置文件不存在，需要重新安装"
                echo "开始重新安装..."
            else
                systemctl stop v2ray 2>/dev/null || true
                systemctl start v2ray
                sleep 3
                
                if systemctl is-active --quiet v2ray && (netstat -tlnp 2>/dev/null | grep -q ":7890 " || ss -tlnp 2>/dev/null | grep -q ":7890 "); then
                    echo "✓ V2Ray 服务重启成功"
                    
                    if [ -n "$TEMP_PROXY" ]; then
                        cleanup_system_proxy "$TEMP_PROXY"
                    fi
                    
                    setup_system_proxy "socks5://127.0.0.1:7890"
                    
                    echo ""
                    echo "=== 配置完成 ==="
                    echo "V2Ray 代理地址: socks5://127.0.0.1:7890"
                    exit 0
                else
                    echo "✗ V2Ray 服务重启失败，继续重新安装..."
                fi
            fi
            ;;
        *)
            echo "无效选择，退出"
            if [ -n "$TEMP_PROXY" ]; then
                cleanup_system_proxy "$TEMP_PROXY"
            fi
            exit 1
            ;;
    esac
fi

# 安装 V2Ray
echo "=== 安装 V2Ray ==="
if [ -n "$TEMP_PROXY" ]; then
    echo "使用代理下载 V2Ray..."
    bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh) -p "$TEMP_PROXY"
else
    echo "直接下载 V2Ray..."
    bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)
fi

if [ $? -ne 0 ] || [ ! -f "/usr/local/bin/v2ray" ]; then
    echo "✗ V2Ray 安装失败"
    echo "可能原因:"
    echo "- 网络连接问题"
    echo "- GitHub 访问受限"
    
    if [ -n "$TEMP_PROXY" ]; then
        echo "清理临时代理..."
        cleanup_system_proxy "$TEMP_PROXY"
    fi
    
    exit 1
fi

echo "✓ V2Ray 安装成功"
echo ""

# 配置 V2Ray
echo "=== 配置 V2Ray ==="

# 加载环境变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/.env" ]; then
    echo "加载配置文件: $SCRIPT_DIR/.env"
    source "$SCRIPT_DIR/.env"
else
    echo "✗ 未找到 .env 配置文件"
    echo "请复制 .env.example 为 .env 并配置上游服务器信息"
    echo "cp .env.example .env"
    exit 1
fi

# 检查必需配置
if [ -z "$UPSTREAM_SERVER" ] || [ -z "$UPSTREAM_PORT" ] || [ -z "$UPSTREAM_USER_ID" ]; then
    echo "✗ 缺少必需的上游服务器配置"
    echo "请在 .env 文件中配置:"
    echo "- UPSTREAM_SERVER (上游服务器地址)"
    echo "- UPSTREAM_PORT (端口)"
    echo "- UPSTREAM_USER_ID (用户ID)"
    exit 1
fi

# 设置默认值
UPSTREAM_ALTER_ID=${UPSTREAM_ALTER_ID:-0}
UPSTREAM_SECURITY=${UPSTREAM_SECURITY:-"auto"}
UPSTREAM_NETWORK=${UPSTREAM_NETWORK:-"tcp"}
UPSTREAM_TLS_SECURITY=${UPSTREAM_TLS_SECURITY:-"tls"}
UPSTREAM_TLS_SERVER_NAME=${UPSTREAM_TLS_SERVER_NAME:-"$UPSTREAM_SERVER"}

echo "上游服务器配置:"
echo "- 地址: $UPSTREAM_SERVER:$UPSTREAM_PORT"
echo "- 用户ID: ${UPSTREAM_USER_ID:0:8}..."
echo "- TLS域名: $UPSTREAM_TLS_SERVER_NAME"

# 检查是否为 AWS EC2 实例
IS_AWS_EC2=false
if curl -s --connect-timeout 2 http://169.254.169.254/latest/meta-data/instance-id >/dev/null 2>&1; then
    IS_AWS_EC2=true
    echo "检测到 AWS EC2 实例，将配置 AWS 域名直连"
else
    echo "非 AWS EC2 实例，跳过 AWS 域名直连配置"
fi

# 生成路由规则
ROUTING_RULES='['
if [ "$IS_AWS_EC2" = true ]; then
    ROUTING_RULES+='
      {
        "type": "field",
        "domain": ["domain:amazon.com", "domain:amazonaws.com", "domain:amazonaws.com.cn", "domain:compute.internal", "domain:ec2.internal"],
        "outboundTag": "direct"
      },'
fi

ROUTING_RULES+='
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
    ]'

tee /usr/local/etc/v2ray/config.json << EOF
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
    "rules": $ROUTING_RULES
  },
  "inbounds": [{
    "port": 7890,
    "protocol": "socks",
    "settings": {
      "udp": true
    }
  }],
  "outbounds": [
    {
      "tag": "proxy",
      "protocol": "vmess",
      "settings": {
        "vnext": [{
          "address": "$UPSTREAM_SERVER",
          "port": $UPSTREAM_PORT,
          "users": [{
            "id": "$UPSTREAM_USER_ID",
            "alterId": $UPSTREAM_ALTER_ID,
            "security": "$UPSTREAM_SECURITY"
          }]
        }]
      },
      "streamSettings": {
        "network": "$UPSTREAM_NETWORK",
        "security": "$UPSTREAM_TLS_SECURITY",
        "tlsSettings": {
          "serverName": "$UPSTREAM_TLS_SERVER_NAME"
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

echo "✓ 配置文件已创建"
echo ""

# 启动 V2Ray 服务
echo "=== 启动 V2Ray 服务 ==="
systemctl enable v2ray
systemctl start v2ray

sleep 3

if ! systemctl is-active --quiet v2ray; then
    echo "✗ V2Ray 服务启动失败"
    systemctl status v2ray --no-pager -l
    
    if [ -n "$TEMP_PROXY" ]; then
        echo "清理临时代理..."
        cleanup_system_proxy "$TEMP_PROXY"
    fi
    
    exit 1
fi

# 检查端口监听
echo "检查代理端口..."
for i in {1..10}; do
    if netstat -tlnp 2>/dev/null | grep -q ":7890 " || ss -tlnp 2>/dev/null | grep -q ":7890 "; then
        echo "✓ V2Ray 端口 7890 正在监听"
        break
    fi
    if [ $i -eq 10 ]; then
        echo "✗ V2Ray 端口 7890 未监听"
        systemctl status v2ray --no-pager -l
        
        if [ -n "$TEMP_PROXY" ]; then
            echo "清理临时代理..."
            cleanup_system_proxy "$TEMP_PROXY"
        fi
        
        exit 1
    fi
    sleep 1
done

echo ""

# 设置系统代理
echo "=== 设置系统代理 ==="
if [ -n "$TEMP_PROXY" ]; then
    echo "清理临时代理..."
    cleanup_system_proxy "$TEMP_PROXY"
fi

setup_system_proxy "socks5://127.0.0.1:7890"

# 测试代理连接
echo ""
echo "测试代理连接..."
PROXY_TEST_RESULT=$(curl --socks5 127.0.0.1:7890 --connect-timeout 10 -s ip-api.com 2>/dev/null)
if [ $? -eq 0 ] && [ -n "$PROXY_TEST_RESULT" ]; then
    echo "✓ 代理连接测试成功"
    echo "代理IP: $PROXY_TEST_RESULT"
else
    echo "⚠ 代理连接测试失败，但服务已启动"
fi

echo ""
echo "=== 安装完成 ==="
echo ""
echo "V2Ray 代理地址: socks5://127.0.0.1:7890"
echo ""
echo "系统级代理已配置:"
echo "- /etc/environment (全局环境变量)"
echo "- /etc/systemd/system.conf.d/proxy.conf (systemd 服务)"
echo ""
echo "当前会话使用代理:"
echo "export http_proxy=socks5://127.0.0.1:7890"
echo "export https_proxy=socks5://127.0.0.1:7890"
echo ""
echo "服务管理命令:"
echo "- 查看状态: systemctl status v2ray"
echo "- 重启服务: systemctl restart v2ray"
echo "- 查看日志: journalctl -u v2ray -f"
echo ""
