# 腾讯云 CVM 部署指南

## 环境说明

腾讯云 CVM 相比阿里云 ECS 有以下优势：
- **无内核升级问题** - 安装 WireGuard 不会触发内核升级
- **网络环境更好** - 对 GitHub 访问限制较少
- **部署更简单** - 无需预安装脚本，可直接运行主安装

## 快速部署

### 方式 1: 一键部署（推荐）

```bash
# 1. 配置环境变量
cp .env.example .env
# 编辑 .env 填入腾讯云服务器信息

# 2. 直接执行主安装
sudo bash wireguard-install.sh -y
sudo bash v2ray-install.sh
```

### 方式 2: 远程自动化部署

```bash
# 1. 配置环境变量（在本地）
cp .env.example .env
# 编辑 .env 填入实际服务器信息

# 2. 加载环境变量
source .env

# 3. 上传脚本和配置
sshpass -p "$DEPLOY_SERVER_PASS" scp -o StrictHostKeyChecking=no *.sh .env $DEPLOY_SERVER_USER@$DEPLOY_SERVER_IP:~/

# 4. 远程执行安装（无需预安装）
sshpass -p "$DEPLOY_SERVER_PASS" ssh -o StrictHostKeyChecking=no $DEPLOY_SERVER_USER@$DEPLOY_SERVER_IP "sudo bash ~/wireguard-install.sh -y"
sshpass -p "$DEPLOY_SERVER_PASS" ssh -o StrictHostKeyChecking=no $DEPLOY_SERVER_USER@$DEPLOY_SERVER_IP "sudo bash ~/v2ray-install.sh"

# 5. 下载配置文件
sshpass -p "$DEPLOY_SERVER_PASS" scp -o StrictHostKeyChecking=no -r $DEPLOY_SERVER_USER@$DEPLOY_SERVER_IP:~/private ./
```

## 腾讯云特定配置

### .env 配置示例

```bash
# 腾讯云服务器信息
DEPLOY_SERVER_IP=43.143.118.68
DEPLOY_SERVER_USER=ubuntu
DEPLOY_SERVER_PASS=your_password

# V2Ray 上游服务器配置
UPSTREAM_SERVER=your_upstream_server
UPSTREAM_PORT=443
UPSTREAM_USER_ID=your_uuid
UPSTREAM_ALTER_ID=0
UPSTREAM_SECURITY=auto
UPSTREAM_NETWORK=tcp
UPSTREAM_TLS_SECURITY=tls
UPSTREAM_TLS_SERVER_NAME=your_domain

# 代理启动命令（通常不需要，腾讯云网络较好）
# PROXY_STARTUP_CMD="sshpass -p 'password' ssh -D 1080 -N -f -o StrictHostKeyChecking=no user@proxy-server"
```

### 安全组配置

**必须开放的端口：**
- **UDP 51820** - WireGuard VPN 端口

**腾讯云控制台配置：**
1. 登录腾讯云控制台
2. 进入 CVM 实例管理
3. 点击实例 ID 进入详情页
4. 选择"安全组"标签
5. 编辑安全组规则
6. 添加入站规则：
   - 协议：UDP
   - 端口：51820
   - 源：0.0.0.0/0
   - 策略：允许

## 网络优势

### GitHub 访问

腾讯云 CVM 通常可以直接访问 GitHub：
- ✅ 无需代理即可下载 V2Ray 安装脚本
- ✅ 下载速度通常 >100KB/s
- ✅ 很少出现网络超时问题

### 智能检测

V2Ray 安装脚本会自动检测网络环境：

**网络良好时：**
```bash
=== 环境检查 ===
检查 1080 端口状态...
✗ 未检测到 1080 端口代理
检测 V2Ray 安装脚本可访问性...
测试 GitHub 下载速度...
✓ 下载速度正常 (150.2 KB/s)
✓ V2Ray 安装条件满足
```

**网络受限时：**
- 自动尝试启动代理（如果配置了 `PROXY_STARTUP_CMD`）
- 提供详细的错误信息和解决建议

## 部署流程对比

### 腾讯云 vs 阿里云

| 项目 | 腾讯云 CVM | 阿里云 ECS |
|------|------------|------------|
| **预安装脚本** | ❌ 不需要 | ✅ 推荐使用 |
| **内核升级** | ❌ 不会触发 | ⚠️ 可能触发 |
| **GitHub 访问** | ✅ 通常正常 | ⚠️ 可能受限 |
| **部署步骤** | 2 步 | 3-4 步 |
| **重启需求** | ❌ 不需要 | ⚠️ 可能需要 |

### 简化的部署命令

**腾讯云（2 条命令）：**
```bash
sudo bash wireguard-install.sh -y
sudo bash v2ray-install.sh
```

**阿里云（3-4 条命令）：**
```bash
sudo bash aliyun-pre-install.sh  # 预安装
sudo reboot                      # 重启
sudo bash wireguard-install.sh -y
sudo bash v2ray-install.sh
```

## 性能优化

### 实例规格建议

**最低配置：**
- CPU: 1 核
- 内存: 1GB
- 带宽: 1Mbps

**推荐配置：**
- CPU: 2 核
- 内存: 2GB
- 带宽: 5Mbps

### 地域选择

**推荐地域：**
- **香港** - 延迟低，网络质量好
- **新加坡** - 稳定性高
- **东京** - 速度快

**避免地域：**
- 国内地域（网络限制较多）

## 故障排除

### 常见问题

**1. SSH 连接失败**
```bash
# 检查安全组是否开放 22 端口
# 检查实例是否正常运行
# 确认用户名和密码正确
```

**2. WireGuard 安装失败**
```bash
# 检查系统版本
lsb_release -a

# 更新系统
sudo apt update && sudo apt upgrade -y
```

**3. V2Ray 网络检测失败**
```bash
# 手动测试网络
curl -I https://github.com

# 检查 DNS 解析
nslookup github.com
```

### 日志查看

**系统日志：**
```bash
sudo journalctl -f
```

**WireGuard 日志：**
```bash
sudo journalctl -u wg-quick@wg0 -f
```

**V2Ray 日志：**
```bash
sudo journalctl -u v2ray -f
```

## 管理维护

### 服务管理

**WireGuard：**
```bash
sudo systemctl status wg-quick@wg0
sudo systemctl restart wg-quick@wg0
sudo wg show
```

**V2Ray：**
```bash
sudo systemctl status v2ray
sudo systemctl restart v2ray
```

### 配置备份

**重要文件备份：**
```bash
# WireGuard 配置
sudo cp -r /etc/wireguard/ ~/backup/
cp -r ~/private/ ~/backup/

# V2Ray 配置
sudo cp /usr/local/etc/v2ray/config.json ~/backup/

# 环境配置
cp .env ~/backup/
```

### 监控脚本

**创建监控脚本：**
```bash
#!/bin/bash
# monitor.sh - 服务监控脚本

echo "=== 服务状态检查 ==="
systemctl is-active wg-quick@wg0 && echo "✓ WireGuard 运行正常" || echo "✗ WireGuard 异常"
systemctl is-active v2ray && echo "✓ V2Ray 运行正常" || echo "✗ V2Ray 异常"

echo "=== 端口监听检查 ==="
ss -tlnp | grep -q ":51820" && echo "✓ WireGuard 端口正常" || echo "✗ WireGuard 端口异常"
ss -tlnp | grep -q ":7890" && echo "✓ V2Ray SOCKS5 正常" || echo "✗ V2Ray SOCKS5 异常"

echo "=== 网络连通性检查 ==="
curl -s --connect-timeout 5 ip-api.com >/dev/null && echo "✓ 网络连通正常" || echo "✗ 网络连通异常"
```

## 总结

腾讯云 CVM 部署 WireGuard + V2Ray 双层代理具有以下优势：

- **部署简单** - 无需预安装脚本
- **网络稳定** - GitHub 访问通常无问题
- **维护方便** - 不涉及内核升级问题
- **性价比高** - 香港等地域价格合理

推荐作为 WireGuard + V2Ray 部署的首选云服务商。
