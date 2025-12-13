# V2Ray 一键安装指南

## 概述

`v2ray-install.sh` 是 V2Ray 的一键安装脚本，按顺序自动执行以下三个步骤：

1. **V2Ray 核心安装** (`v2ray-install-step1-core.sh`)
2. **TCP 透明代理配置** (`v2ray-install-step2-enable-tcp-proxy.sh`)
3. **UDP 透明代理配置** (`v2ray-install-step3-enable-udp-proxy.sh`)

## 使用方法

### 基本用法

```bash
sudo bash v2ray-install.sh
```

### 前提条件

1. **WireGuard 已安装**: 透明代理需要 `wg0` 网卡
2. **配置文件存在**: 需要 `.env` 文件包含上游服务器信息
3. **Root 权限**: 需要 sudo 权限执行

### 配置要求

**必需的 .env 配置：**
```bash
# V2Ray 上游服务器配置
UPSTREAM_SERVER=<上游服务器地址>
UPSTREAM_PORT=<端口>
UPSTREAM_USER_ID=<用户ID>
UPSTREAM_TLS_SERVER_NAME=<TLS域名>

# 可选：代理启动命令（网络受限时使用）
PROXY_STARTUP_CMD="sshpass -p '<密码>' ssh -D 1080 -N -f -o StrictHostKeyChecking=no <用户>@<代理服务器>"
```

## 安装流程

### Step 1: V2Ray 核心安装

**功能：**
- 智能网络检测
- 自动下载安装 V2Ray
- 生成配置文件
- 启动 V2Ray 服务

**智能特性：**
- 检测 1080 端口现有代理
- 测试 GitHub 访问速度
- 网络受限时自动启动代理

### Step 2: TCP 透明代理

**功能：**
- 配置 dokodemo-door (TCP)
- 设置 iptables nat 规则
- 安装 iptables-persistent
- 重启 V2Ray 服务

**端口：**
- TCP 透明代理端口：60001

### Step 3: UDP 透明代理

**功能：**
- 配置 dokodemo-door (UDP)
- 设置 iptables mangle 规则
- 配置策略路由
- 加载 TPROXY 模块

**端口：**
- UDP 透明代理端口：60002

## 安装结果

### 服务配置

**V2Ray 监听端口：**
- SOCKS5 代理：7890
- TCP 透明代理：60001
- UDP 透明代理：60002

**iptables 规则：**
- TCP：nat 表 REDIRECT 规则
- UDP：mangle 表 TPROXY 规则

**系统代理：**
- 全局环境变量配置
- systemd 服务代理配置

### 验证安装

**检查服务状态：**
```bash
systemctl status v2ray
```

**检查端口监听：**
```bash
ss -tlnp | grep v2ray  # TCP 端口
ss -ulnp | grep v2ray  # UDP 端口
```

**检查 iptables 规则：**
```bash
iptables -t nat -L V2RAY -n -v      # TCP 规则
iptables -t mangle -L V2RAY_MARK -n -v  # UDP 规则
```

## 错误处理

### 常见问题

**1. 网络访问受限**
```
✗ V2Ray 安装条件不满足
  - GitHub 无法访问
  - 下载速度过慢（需要 >50KB/s）
```

**解决方案：**
- 配置 `.env` 中的 `PROXY_STARTUP_CMD`
- 或使用其他网络环境

**2. WireGuard 未安装**
```
✗ 未找到 wg0 网卡
```

**解决方案：**
```bash
sudo bash wireguard-install.sh -y
```

**3. 配置文件缺失**
```
✗ 未找到 .env 配置文件
```

**解决方案：**
```bash
cp .env.example .env
# 编辑 .env 填入实际配置
```

### 日志查看

**V2Ray 日志：**
```bash
journalctl -u v2ray -f
```

**错误日志：**
```bash
tail -f /var/log/v2ray/error.log
```

## 管理命令

**服务管理：**
```bash
systemctl start v2ray     # 启动
systemctl stop v2ray      # 停止
systemctl restart v2ray   # 重启
systemctl status v2ray    # 状态
```

**配置管理：**
```bash
# 查看配置
cat /usr/local/etc/v2ray/config.json

# 验证配置
v2ray test -config /usr/local/etc/v2ray/config.json
```

**网络测试：**
```bash
# 测试代理
curl --socks5 127.0.0.1:7890 ip-api.com

# 测试透明代理（需要 WireGuard 客户端连接）
curl ip-api.com
```

## 卸载

如需卸载 V2Ray：

```bash
# 停止服务
systemctl stop v2ray
systemctl disable v2ray

# 删除文件
rm -rf /usr/local/bin/v2ray
rm -rf /usr/local/etc/v2ray
rm -rf /var/log/v2ray
rm -f /etc/systemd/system/v2ray.service*

# 清理 iptables 规则
iptables -t nat -F V2RAY
iptables -t nat -X V2RAY
iptables -t mangle -F V2RAY_MARK
iptables -t mangle -X V2RAY_MARK

# 重新加载 systemd
systemctl daemon-reload
```
