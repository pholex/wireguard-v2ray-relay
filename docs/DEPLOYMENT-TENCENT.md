# 腾讯云部署指南

## 快速部署

### 1. 准备工作

**创建腾讯云实例**：

**Lighthouse（推荐，已测试通过）**：
- **服务器类型**: 腾讯云 Lighthouse 轻量应用服务器
- **配置**: 2核 4GB 内存
- **系统盘**: 60GB SSD
- **操作系统**: Ubuntu Server 22.04 LTS 64bit
- **带宽**: 200 Mbps
- **地域**: 建议选择网络质量好的地区

**配置安全组**：
- 开放 UDP 51820 端口（WireGuard）
- 开放 SSH 22 端口

### 2. 配置环境变量

```bash
# 复制配置模板
cp .env.example .env

# 编辑配置文件
vim .env
```

**关键配置**：
```bash
# 部署服务器（腾讯云 Lighthouse 或 CVM）
DEPLOY_SERVER_IP=<腾讯云实例公网IP>
DEPLOY_SERVER_USER=ubuntu
DEPLOY_SERVER_PASS=<服务器密码>

# V2Ray 上游服务器配置
UPSTREAM_SERVER=<上游服务器地址>
UPSTREAM_PORT=<端口>
UPSTREAM_USER_ID=<用户ID>
# ... 其他配置

# 代理启动命令（简化版本）
PROXY_STARTUP_CMD="sshpass -p '<密码>' ssh -D 1080 -N -f -o StrictHostKeyChecking=no ubuntu@<代理服务器>"
```

### 3. 一键部署

```bash
# 1. 上传脚本
scp *.sh .env ubuntu@<服务器IP>:~/

# 2. SSH 登录
ssh ubuntu@<服务器IP>

# 3. 安装 WireGuard
sudo bash wireguard-install.sh

# 4. 安装 V2Ray（一键完成）
sudo bash v2ray-install.sh

# 5. 下载配置文件
exit
scp -r ubuntu@<服务器IP>:~/private ./
```

### 4. 验证部署

**连接测试**：
1. 导入 WireGuard 客户端配置
2. 连接 VPN
3. 访问 `curl ip-api.com` 验证代理

## 故障排除

### 常见问题

**1. 代理启动失败**
```bash
# 检查代理服务器连通性
ping <代理服务器IP>

# 测试 SSH 连接
ssh ubuntu@<代理服务器IP>

# 手动启动代理测试
sshpass -p '<密码>' ssh -D 1080 -N -f ubuntu@<代理服务器IP>
```

**2. V2Ray 服务异常**
```bash
# 查看服务状态
sudo systemctl status v2ray

# 查看日志
sudo journalctl -u v2ray -f

# 重启服务
sudo systemctl restart v2ray
```

**3. 透明代理不工作**
```bash
# 检查 iptables 规则
sudo iptables -t nat -L V2RAY -n -v
sudo iptables -t mangle -L V2RAY_MARK -n -v

# 检查端口监听
sudo netstat -tlnp | grep -E "(60001|60002)"
```

## 性能优化

### 网络优化

**BBR 加速**：
```bash
# 启用 BBR
echo 'net.core.default_qdisc=fq' | sudo tee -a /etc/sysctl.conf
echo 'net.ipv4.tcp_congestion_control=bbr' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

**系统优化**：
```bash
# 增加文件描述符限制
echo '* soft nofile 65535' | sudo tee -a /etc/security/limits.conf
echo '* hard nofile 65535' | sudo tee -a /etc/security/limits.conf
```
