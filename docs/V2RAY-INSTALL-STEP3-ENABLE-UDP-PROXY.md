# V2Ray UDP 透明代理配置指南

本指南用于在腾讯云服务器上配置 V2Ray UDP 透明代理,使 WireGuard 客户端的 UDP 流量(如 QUIC、DNS)也能通过代理。

## 前提条件

- 已配置 WireGuard 服务端
- 已安装 V2Ray
- 已配置 TCP 透明代理(参考 V2RAY-INSTALL-STEP2-ENABLE-TCP-PROXY.md)
- V2Ray 配置文件路径: `/usr/local/etc/v2ray/config.json`
- 内核支持 TPROXY (Ubuntu 22.04 默认支持)

## 一、备份原配置

```bash
sudo cp /usr/local/etc/v2ray/config.json /usr/local/etc/v2ray/config.json.backup
```

## 二、修改 V2Ray 配置

添加独立的 UDP 透明代理入站（TCP 和 UDP 使用不同端口）:

**TCP 透明代理入站（端口 60001）:**
```json
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
```

**UDP 透明代理入站（端口 60002）:**
```json
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
```

完整配置示例:

```json
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
          "address": "上游服务器地址",
          "port": 443,
          "users": [{
            "id": "UUID",
            "alterId": 0,
            "security": "auto"
          }]
        }]
      },
      "streamSettings": {
        "network": "tcp",
        "security": "tls",
        "tlsSettings": {
          "serverName": "域名"
        }
      }
    },
    {
      "tag": "direct",
      "protocol": "freedom"
    }
  ]
}
```

## 三、重启 V2Ray 服务

```bash
sudo systemctl restart v2ray
sudo systemctl status v2ray
```

验证端口监听:

```bash
sudo netstat -tlnp | grep v2ray
sudo netstat -ulnp | grep v2ray
```

应该看到:
- `:::7890` (SOCKS5 代理)
- `:::60001` (TCP 透明代理)
- `:::60002` (UDP 透明代理)

## 四、配置 iptables 规则

### 1. 保留 TCP 规则(已配置)

TCP 透明代理规则保持不变,继续使用 nat 表的 REDIRECT。

### 2. 创建 UDP 处理链

```bash
sudo iptables -t mangle -N V2RAY_MARK
```

### 3. 排除保留地址

```bash
sudo iptables -t mangle -A V2RAY_MARK -d 0.0.0.0/8 -j RETURN
sudo iptables -t mangle -A V2RAY_MARK -d 10.0.0.0/8 -j RETURN
sudo iptables -t mangle -A V2RAY_MARK -d 127.0.0.0/8 -j RETURN
sudo iptables -t mangle -A V2RAY_MARK -d 169.254.0.0/16 -j RETURN
sudo iptables -t mangle -A V2RAY_MARK -d 172.16.0.0/12 -j RETURN
sudo iptables -t mangle -A V2RAY_MARK -d 192.168.0.0/16 -j RETURN
sudo iptables -t mangle -A V2RAY_MARK -d 224.0.0.0/4 -j RETURN
sudo iptables -t mangle -A V2RAY_MARK -d 240.0.0.0/4 -j RETURN
```

### 4. UDP 流量 TPROXY

```bash
sudo iptables -t mangle -A V2RAY_MARK -p udp -j TPROXY --on-port 60002 --tproxy-mark 1
```

### 5. 应用到 WireGuard UDP 流量

```bash
sudo iptables -t mangle -A PREROUTING -i wg0 -p udp -j V2RAY_MARK
```

### 6. 配置策略路由

```bash
# 添加路由规则
sudo ip rule add fwmark 1 table 100

# 添加本地路由
sudo ip route add local 0.0.0.0/0 dev lo table 100
```

### 7. 验证规则

```bash
# 查看 mangle 表规则
sudo iptables -t mangle -L V2RAY_MARK -n -v

# 查看路由策略
ip rule show

# 查看路由表
ip route show table 100
```

## 五、保存 iptables 规则

### 安装 iptables-persistent

```bash
# 临时取消代理(apt 不支持 socks5)
sudo env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY apt install -y iptables-persistent
```

### 保存规则

```bash
sudo netfilter-persistent save
```

规则保存在:
- `/etc/iptables/rules.v4` (IPv4)
- `/etc/iptables/rules.v6` (IPv6)

## 六、验证 UDP 透明代理

### 测试 DNS over UDP

```bash
# 从 WireGuard 客户端
dig @8.8.8.8 google.com
```

### 测试 QUIC (HTTP/3)

```bash
# 使用 curl 测试 HTTP/3
curl --http3 https://www.google.com -I
```

### 查看 iptables 统计

```bash
# TCP 流量统计
sudo iptables -t nat -L V2RAY -n -v

# UDP 流量统计
sudo iptables -t mangle -L V2RAY_MARK -n -v
```

查看 `pkts` 和 `bytes` 列,应该有 UDP 流量通过。

## 七、故障排查

### 查看 V2Ray 日志

```bash
sudo journalctl -u v2ray -f
```

### 检查 TPROXY 支持

```bash
# 检查内核模块
lsmod | grep xt_TPROXY

# 如果没有,加载模块
sudo modprobe xt_TPROXY
```

### 检查路由策略

```bash
ip rule show | grep 100
ip route show table 100
```

### 测试 UDP 端口

```bash
# 从 WireGuard 客户端测试 DNS
nc -u 8.8.8.8 53
```

### 清除 UDP 规则(如需重新配置)

```bash
# 删除 mangle 规则
sudo iptables -t mangle -F V2RAY_MARK
sudo iptables -t mangle -X V2RAY_MARK

# 删除路由策略
sudo ip rule del fwmark 1 table 100
sudo ip route del local 0.0.0.0/0 dev lo table 100
```

## 八、工作原理

### TCP 流量 (REDIRECT)
1. WireGuard 客户端发起 TCP 连接
2. iptables nat 表 REDIRECT 到端口 60001
3. V2Ray dokodemo-door (TCP) 接收并转发

### UDP 流量 (TPROXY)
1. WireGuard 客户端发起 UDP 连接
2. iptables mangle 表打标记 (fwmark 1)
3. 策略路由将标记流量路由到本地
4. TPROXY 将流量转发到端口 60002
5. V2Ray dokodemo-door (UDP) 接收并转发

## 九、注意事项

- UDP 透明代理需要内核 TPROXY 支持
- TPROXY 比 REDIRECT 更复杂,需要配置策略路由
- TCP 和 UDP 使用不同端口（60001 和 60002）避免冲突
- TCP 使用 REDIRECT（效率更高），UDP 使用 TPROXY（必需）
- 适用于 QUIC、DNS、游戏等 UDP 应用
- 保留地址(内网、本地)不会被代理
- 重启后需要重新配置策略路由(建议添加到启动脚本)
- 规则对已连接的客户端立即生效,无需重连

## 十、持久化策略路由

创建启动脚本 `/etc/network/if-up.d/v2ray-tproxy`:

```bash
#!/bin/bash
ip rule add fwmark 1 table 100
ip route add local 0.0.0.0/0 dev lo table 100
```

设置执行权限:

```bash
sudo chmod +x /etc/network/if-up.d/v2ray-tproxy
```

---
文档创建时间: 2025-12-04
