# WireGuard 安装和配置指南

本指南适用于 Ubuntu Server 22.04 LTS 和 24.04 LTS。

## 快速安装（推荐）

### 使用自动化脚本

```bash
# 交互模式（可自定义配置）
sudo bash wireguard-install.sh

# 自动模式（使用默认配置）
sudo bash wireguard-install.sh -y
```

**默认配置：**
- 监听端口：51820
- VPN 网段：10.0.8.0/24
- 客户端数量：2

脚本会自动：
- 检测云服务商环境
- 安装 WireGuard 和必要工具（unzip、sshpass、jq）
- 生成服务器和客户端密钥
- 创建配置文件
- 启动服务并配置防火墙
- 生成客户端配置文件到 `private/` 目录

## 手动安装（可选）

如需手动安装，可参考以下步骤：

### 1. 更新软件包列表
```bash
sudo apt update
```

### 2. 安装 WireGuard
```bash
sudo apt install -y wireguard
```

这会自动安装:
- wireguard (1.0.20210914-1ubuntu2)
- wireguard-tools (1.0.20210914-1ubuntu2)

### 3. 启用 IP 转发
```bash
# 临时启用
sudo sysctl -w net.ipv4.ip_forward=1

# 永久启用
echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

## 二、生成密钥

### 服务器密钥
```bash
# 生成服务器私钥
wg genkey | sudo tee /etc/wireguard/server_private.key

# 生成服务器公钥
sudo cat /etc/wireguard/server_private.key | wg pubkey | sudo tee /etc/wireguard/server_public.key
```

### 客户端密钥
为每个客户端生成一对密钥：

```bash
# 客户端1
wg genkey | tee client1_private.key | wg pubkey > client1_public.key

# 客户端2
wg genkey | tee client2_private.key | wg pubkey > client2_public.key

# 更多客户端以此类推...
```

## 三、配置服务器

### 创建服务器配置文件
```bash
sudo nano /etc/wireguard/wg0.conf
```

### 服务器配置模板
```ini
[Interface]
PrivateKey = <服务器私钥>
Address = 10.0.8.1/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

[Peer]
PublicKey = <客户端1公钥>
AllowedIPs = 10.0.8.2/32

[Peer]
PublicKey = <客户端2公钥>
AllowedIPs = 10.0.8.3/32
```

说明:
- `<服务器私钥>`: 填入 `/etc/wireguard/server_private.key` 的内容
- `<客户端公钥>`: 填入对应客户端的公钥
- `Address`: VPN 内网网段，可自定义（如 10.0.8.0/24）
- `eth0`: 根据实际网卡名称修改，用 `ip addr` 查看

### 设置权限
```bash
sudo chmod 600 /etc/wireguard/wg0.conf
```

## 四、启动 WireGuard 服务

### 启动服务
```bash
sudo systemctl start wg-quick@wg0
```

### 设置开机自启
```bash
sudo systemctl enable wg-quick@wg0
```

### 查看服务状态
```bash
sudo systemctl status wg-quick@wg0
```

### 查看连接状态
```bash
sudo wg show
```

## 五、客户端配置

### 客户端配置模板
```ini
[Interface]
PrivateKey = <客户端私钥>
Address = <客户端VPN地址>/24
DNS = 8.8.8.8, 8.8.4.4

[Peer]
PublicKey = <服务器公钥>
Endpoint = <服务器公网IP>:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
```

说明:
- `<客户端私钥>`: 该客户端的私钥
- `<客户端VPN地址>`: 如 10.0.8.2、10.0.8.3 等
- `<服务器公钥>`: 填入 `/etc/wireguard/server_public.key` 的内容
- `<服务器公网IP>`: 服务器的公网 IP 地址
- `AllowedIPs = 0.0.0.0/0`: 全局代理，如只访问内网可改为 `10.0.8.0/24`
- `DNS`: 可选，根据需要修改

## 六、常用管理命令

### 重启服务
```bash
sudo systemctl restart wg-quick@wg0
```

### 停止服务
```bash
sudo systemctl stop wg-quick@wg0
```

### 查看连接状态
```bash
sudo wg show
```

### 重新加载配置
```bash
sudo wg syncconf wg0 <(wg-quick strip wg0)
```

## 七、配置说明

### Interface 配置项
- `PrivateKey`: 本机的私钥
- `Address`: VPN 内网地址
- `ListenPort`: 监听端口(仅服务器)
- `DNS`: DNS 服务器(仅客户端)
- `PostUp/PostDown`: 启动/停止时执行的命令(仅服务器)

### Peer 配置项
- `PublicKey`: 对端的公钥
- `Endpoint`: 对端的地址和端口(客户端连接服务器时使用)
- `AllowedIPs`: 允许的 IP 范围
  - 服务器端: 客户端的 VPN IP (如 10.0.8.2/32)
  - 客户端: 0.0.0.0/0 表示全局代理
- `PersistentKeepalive`: 心跳间隔(秒)

## 八、防火墙配置

如果使用云服务器,需要在安全组中开放:
- UDP 端口 51820（默认端口，如修改了 `ListenPort` 则开放对应端口）

## 九、故障排查

### 查看日志
```bash
sudo journalctl -u wg-quick@wg0 -f
```

### 检查接口状态
```bash
ip addr show wg0
```

### 检查路由
```bash
ip route
```

### 测试连接
```bash
ping 10.0.8.1  # 从客户端 ping 服务器
```

---
文档更新时间: 2025-12-03
