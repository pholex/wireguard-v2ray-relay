# V2Ray TCP 透明代理配置指南

本指南用于在腾讯云服务器上配置 V2Ray TCP 透明代理,使 WireGuard 客户端的 TCP 流量(HTTP/HTTPS)自动通过代理。

## 前提条件

- 已配置 WireGuard 服务端
- 已安装 V2Ray
- V2Ray 配置文件路径: `/usr/local/etc/v2ray/config.json`

## 一、备份原配置

```bash
sudo cp /usr/local/etc/v2ray/config.json /usr/local/etc/v2ray/config.json.backup
```

## 二、修改 V2Ray 配置

在 `inbounds` 数组中添加 dokodemo-door 入站:

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
        "network": "tcp",
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
```

应该看到:
- `:::7890` (SOCKS5 代理)
- `:::60001` (透明代理)

## 四、配置 iptables 规则

### 1. 创建 V2RAY 链

```bash
sudo iptables -t nat -N V2RAY
```

### 2. 排除保留地址

```bash
sudo iptables -t nat -A V2RAY -d 0.0.0.0/8 -j RETURN
sudo iptables -t nat -A V2RAY -d 10.0.0.0/8 -j RETURN
sudo iptables -t nat -A V2RAY -d 127.0.0.0/8 -j RETURN
sudo iptables -t nat -A V2RAY -d 169.254.0.0/16 -j RETURN
sudo iptables -t nat -A V2RAY -d 172.16.0.0/12 -j RETURN
sudo iptables -t nat -A V2RAY -d 192.168.0.0/16 -j RETURN
sudo iptables -t nat -A V2RAY -d 224.0.0.0/4 -j RETURN
sudo iptables -t nat -A V2RAY -d 240.0.0.0/4 -j RETURN
```

### 3. 重定向到透明代理端口

```bash
sudo iptables -t nat -A V2RAY -p tcp -j REDIRECT --to-ports 60001
```

### 4. 应用到 WireGuard 流量

```bash
sudo iptables -t nat -A PREROUTING -i wg0 -p tcp -j V2RAY
```

### 5. 验证规则

```bash
sudo iptables -t nat -L V2RAY -n -v
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

## 六、验证透明代理

### 从 WireGuard 客户端测试

连接 WireGuard 后,访问任意网站或执行:

```bash
curl ip-api.com
```

应该显示代理服务器的 IP 地址,而不是 Lighthouse 实例的 IP。

### 查看 iptables 统计

```bash
sudo iptables -t nat -L V2RAY -n -v
```

查看 `pkts` 和 `bytes` 列,应该有流量通过。

## 七、故障排查

### 查看 V2Ray 日志

```bash
sudo journalctl -u v2ray -f
```

### 检查端口监听

```bash
sudo netstat -tlnp | grep -E "7890|60001"
```

### 测试透明代理端口

```bash
# 从 WireGuard 客户端
telnet 10.0.8.1 60001
```

### 清除 iptables 规则(如需重新配置)

```bash
sudo iptables -t nat -F V2RAY
sudo iptables -t nat -X V2RAY
```

## 八、工作原理

1. WireGuard 客户端发起 TCP 连接
2. 数据包到达 Lighthouse 实例的 wg0 接口
3. iptables PREROUTING 规则匹配,进入 V2RAY 链
4. 检查目标地址,非保留地址的流量重定向到 60001 端口
5. V2Ray dokodemo-door 接收流量
6. 根据路由规则决定直连或代理
7. 通过上游 VMess 服务器转发到目标

## 九、注意事项

- 本配置只处理 TCP 流量（HTTP/HTTPS 等）
- UDP 流量（QUIC、DNS 等）需要额外配置 TPROXY（参考 V2RAY-INSTALL-STEP3-ENABLE-UDP-PROXY.md）
- 保留地址(内网、本地)不会被代理
- 规则对已连接的客户端立即生效,无需重连
- 重启后规则自动加载(已安装 iptables-persistent)
- 系统级代理(`/etc/environment`)不影响 WireGuard 客户端

---
文档创建时间: 2025-12-03
