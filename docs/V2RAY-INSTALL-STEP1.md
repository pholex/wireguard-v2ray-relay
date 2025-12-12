# V2Ray 安装配置指南 (Step 1)

## 前提条件

- 已安装并配置 WireGuard 服务端（参考 [WIREGUARD-SETUP-GUIDE.md](WIREGUARD-SETUP-GUIDE.md)）
- Ubuntu Server 22.04 LTS
- 已有可用的上游 V2Ray 服务器

## 配置准备

### 1. 配置上游服务器信息

复制环境变量模板：
```bash
cp .env.example .env
```

编辑 `.env` 文件，配置上游服务器信息：
```bash
# 部署服务器
DEPLOY_SERVER_IP=<服务器IP>
DEPLOY_SERVER_USER=<用户名>
DEPLOY_SERVER_PASS=<服务器密码>

# V2Ray 上游服务器配置
UPSTREAM_SERVER=<上游服务器地址>
UPSTREAM_PORT=<端口>
UPSTREAM_USER_ID=<用户ID>
UPSTREAM_ALTER_ID=0
UPSTREAM_SECURITY=auto
UPSTREAM_NETWORK=tcp
UPSTREAM_TLS_SECURITY=tls
UPSTREAM_TLS_SERVER_NAME=<TLS域名>
```

**重要说明：**
- 必须配置 `UPSTREAM_SERVER`、`UPSTREAM_PORT`、`UPSTREAM_USER_ID`
- 其他参数有默认值，可根据实际情况调整
- 脚本会自动从 `.env` 读取配置，无需手动修改脚本

## 架构说明

```
客户端 → WireGuard隧道 → 云服务器 → V2Ray代理 → 上游服务器
```

- WireGuard 提供加密隧道
- V2Ray 提供 SOCKS5 代理服务
- 客户端通过 WireGuard 访问服务器的 V2Ray 代理

## 一、使用自动化脚本安装

### 运行安装脚本

```bash
sudo bash v2ray-install-step1.sh
```

脚本会自动：
- 检查环境和依赖
- 从 `.env` 读取上游服务器配置
- 下载并安装 V2Ray
- 生成配置文件
- 启动并配置服务
- 设置系统级代理

### 脚本功能特性

- **智能代理检测**：自动检测 1080 端口代理，加速安装
- **环境适配**：支持 AWS EC2 环境特殊配置
- **配置验证**：验证配置文件语法正确性
- **服务管理**：自动启动服务并检查状态
- **系统代理**：配置全局代理环境变量

## 二、手动安装（可选）

如需手动安装，可参考以下步骤：

### 使用官方脚本安装

```bash
bash <(curl -L https://raw.githubusercontent.com/v2fly/fhs-install-v2ray/master/install-release.sh)
```

安装完成后会自动：
- 安装 V2Ray 二进制到 `/usr/local/bin/v2ray`
- 创建配置目录 `/usr/local/etc/v2ray/`
- 创建 systemd 服务 `v2ray.service`

### 创建配置文件

创建 `/usr/local/etc/v2ray/config.json`（需要替换实际的上游服务器信息）：

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

### 配置说明

**需要替换的占位符：**
- `上游服务器地址`：上游 V2Ray 服务器的地址
- `UUID`：V2Ray 用户 ID
- `域名`：TLS 域名

**路由规则：**
- Docker、Google、YouTube 域名走代理
- 国内域名和 IP 直连
- 内网地址直连
- 其他流量走代理

**入站配置：**
- SOCKS5 代理监听 `0.0.0.0:7890`
- 支持 UDP

## 三、启动 V2Ray 服务

```bash
# 启用开机自启
sudo systemctl enable v2ray

# 启动服务
sudo systemctl start v2ray

# 查看状态
sudo systemctl status v2ray
```

## 四、验证安装

### 检查端口监听

```bash
sudo ss -tlnp | grep 7890
```

应该看到 V2Ray 监听在 7890 端口。

### 测试代理

```bash
# 从服务器本地测试
curl --socks5 127.0.0.1:7890 ip-api.com
```

应该返回上游服务器的 IP 信息。

## 五、客户端使用

### 连接 WireGuard

使用 WireGuard 客户端连接到服务器（参考 WIREGUARD-SETUP-GUIDE.md 中的客户端配置）。

### 配置代理

**方式1：终端环境变量**

```bash
export http_proxy=socks5://10.0.8.1:7890
export https_proxy=socks5://10.0.8.1:7890
```

**方式2：应用程序配置**

在浏览器或其他应用程序中配置：
- 代理类型：SOCKS5
- 代理地址：10.0.8.1（WireGuard 服务器内网地址）
- 代理端口：7890

### 验证代理

```bash
# 测试代理
curl ip-api.com

# 应显示上游服务器的 IP 地址
```

## 六、常用管理命令

### 查看服务状态

```bash
sudo systemctl status v2ray
```

### 重启服务

```bash
sudo systemctl restart v2ray
```

### 查看日志

```bash
sudo journalctl -u v2ray -f
```

### 测试配置文件

```bash
sudo /usr/local/bin/v2ray test -config /usr/local/etc/v2ray/config.json
```

## 七、故障排查

### V2Ray 服务无法启动

```bash
# 查看详细日志
sudo journalctl -u v2ray -n 50

# 测试配置文件
sudo /usr/local/bin/v2ray test -config /usr/local/etc/v2ray/config.json
```

### 端口未监听

```bash
# 检查端口占用
sudo ss -tlnp | grep 7890

# 检查防火墙
sudo iptables -L -n | grep 7890
```

### 代理不可用

```bash
# 从服务器本地测试
curl --socks5 127.0.0.1:7890 ip-api.com

# 从 WireGuard 客户端测试
curl --socks5 10.0.8.1:7890 ip-api.com

# 检查 WireGuard 连接
ping 10.0.8.1
```

## 八、下一步

完成基础安装后，可以继续配置透明代理：

- **Step 2**：配置 TCP 透明代理（参考 [v2ray-install-step2-enable-tcp-proxy.md](v2ray-install-step2-enable-tcp-proxy.md)）
- **Step 3**：配置 UDP 透明代理（参考 [v2ray-install-step3-enable-udp-proxy.md](v2ray-install-step3-enable-udp-proxy.md)）

透明代理可以让 WireGuard 客户端的所有流量自动通过代理，无需手动配置每个应用程序。

## 九、注意事项

- 定期更新 V2Ray 版本
- 监控服务器资源使用
- 备份配置文件
- 注意上游服务器的流量限制
- SOCKS5 代理监听在所有接口（0.0.0.0），仅通过 WireGuard 内网访问

---
文档创建时间: 2025-12-04
