# 阿里云 ECS 部署指南

## 问题说明

在阿里云 ECS 上安装 WireGuard 时，由于包依赖关系会自动安装以下组件：
- `linux-firmware` - Linux 固件包
- `amd64-microcode` - AMD 微码更新
- `firmware-sof-signed` - 音频固件
- `linux-image-realtime` - 实时内核
- `iptables-persistent` - 防火墙规则持久化

这些组件会触发内核升级，可能影响安装流程。

## 解决方案

### 方案 1: 预安装脚本（推荐）

**步骤 1: 运行预安装脚本**
```bash
# 上传预安装脚本
scp aliyun-pre-install.sh root@<服务器IP>:~/

# 运行预安装脚本
ssh root@<服务器IP>
sudo bash aliyun-pre-install.sh
```

**步骤 2: 重启服务器（推荐）**
```bash
# 如果安装了新内核，建议重启
sudo reboot
```

**步骤 3: 运行主安装脚本**
```bash
# 现在可以正常运行主安装脚本，不会再触发内核升级
sudo bash wireguard-install.sh -y
sudo bash v2ray-install.sh
```

### 方案 2: 一键部署（自动处理）

```bash
# 1. 配置环境变量
cp .env.example .env
# 编辑 .env 填入服务器信息

# 2. 运行预安装
source .env
sshpass -p "$DEPLOY_SERVER_PASS" scp -o StrictHostKeyChecking=no aliyun-pre-install.sh $DEPLOY_SERVER_USER@$DEPLOY_SERVER_IP:~/
sshpass -p "$DEPLOY_SERVER_PASS" ssh -o StrictHostKeyChecking=no $DEPLOY_SERVER_USER@$DEPLOY_SERVER_IP "sudo bash ~/aliyun-pre-install.sh"

# 3. 重启服务器
sshpass -p "$DEPLOY_SERVER_PASS" ssh -o StrictHostKeyChecking=no $DEPLOY_SERVER_USER@$DEPLOY_SERVER_IP "sudo reboot"

# 4. 等待重启完成（约 1-2 分钟）
sleep 120

# 5. 运行主安装
sshpass -p "$DEPLOY_SERVER_PASS" scp -o StrictHostKeyChecking=no *.sh .env $DEPLOY_SERVER_USER@$DEPLOY_SERVER_IP:~/
sshpass -p "$DEPLOY_SERVER_PASS" ssh -o StrictHostKeyChecking=no $DEPLOY_SERVER_USER@$DEPLOY_SERVER_IP "sudo bash ~/wireguard-install.sh -y"
sshpass -p "$DEPLOY_SERVER_PASS" ssh -o StrictHostKeyChecking=no $DEPLOY_SERVER_USER@$DEPLOY_SERVER_IP "sudo bash ~/v2ray-install.sh"

# 6. 下载配置文件
sshpass -p "$DEPLOY_SERVER_PASS" scp -o StrictHostKeyChecking=no -r $DEPLOY_SERVER_USER@$DEPLOY_SERVER_IP:~/private ./
```

## 预安装脚本功能

`aliyun-pre-install.sh` 脚本会：

1. **环境检测**: 确认是阿里云 ECS 环境
2. **预安装组件**: 
   - linux-firmware
   - amd64-microcode  
   - firmware-sof-signed
   - wireguard-tools (无推荐包)
   - iptables-persistent (防火墙规则持久化)
   - 基础工具 (unzip, jq, sshpass)
3. **内核检测**: 检查是否安装了新内核
4. **重启提醒**: 如有新内核，提醒重启

## 智能网络处理

V2Ray 安装脚本现在具备智能网络检测功能：

1. **检测现有代理**: 自动检测 1080 端口代理
2. **网络可达性测试**: 检测 GitHub 访问速度
3. **自动启动代理**: 网络受限时从 .env 读取代理命令自动启动
4. **重试机制**: 代理启动后重新检测网络

### .env 配置示例

```bash
# 代理启动命令（当网络受限时使用）
PROXY_STARTUP_CMD="sshpass -p 'password' ssh -D 1080 -N -f -o StrictHostKeyChecking=no user@proxy-server"
```

## 优势

- **避免中断**: 预先处理内核升级，主安装过程不会被打断
- **更稳定**: 在已知环境下安装，减少意外情况
- **智能网络**: 自动处理网络限制问题
- **一键部署**: 支持完全自动化部署
- **兼容性**: 新旧内核都支持 WireGuard

## 注意事项

1. **新内核优势**: realtime 内核延迟更低，但对网络代理影响不大
2. **旧内核兼容**: 继续使用原内核也完全可以正常工作
3. **重启时机**: 可以在完成所有安装后统一重启
4. **安全组**: 确保开放 UDP 51820 端口

## 故障排除

**如果预安装脚本检测失败**:
```bash
# 手动检查阿里云环境
curl -s --connect-timeout 3 http://100.100.100.200/latest/meta-data/instance-id

# 如果无响应，可能不是阿里云 ECS，直接运行主脚本即可
```

**如果网络检测失败**:
```bash
# 检查 .env 文件中的 PROXY_STARTUP_CMD 配置
# 确保代理服务器可访问
```
```

**步骤 3: 运行主安装脚本**
```bash
# 现在可以正常运行主安装脚本，不会再触发内核升级
sudo bash wireguard-install.sh -y
sudo bash v2ray-install-step1.sh
sudo bash v2ray-install-step2-enable-tcp-proxy.sh
sudo bash v2ray-install-step3-enable-udp-proxy.sh
```

### 方案 2: 一键部署（自动处理）

```bash
# 1. 配置环境变量
cp .env.example .env
# 编辑 .env 填入服务器信息

# 2. 运行预安装
source .env
sshpass -p "$DEPLOY_SERVER_PASS" scp -o StrictHostKeyChecking=no aliyun-pre-install.sh $DEPLOY_SERVER_USER@$DEPLOY_SERVER_IP:~/
sshpass -p "$DEPLOY_SERVER_PASS" ssh -o StrictHostKeyChecking=no $DEPLOY_SERVER_USER@$DEPLOY_SERVER_IP "sudo bash ~/aliyun-pre-install.sh"

# 3. 重启服务器
sshpass -p "$DEPLOY_SERVER_PASS" ssh -o StrictHostKeyChecking=no $DEPLOY_SERVER_USER@$DEPLOY_SERVER_IP "sudo reboot"

# 4. 等待重启完成（约 1-2 分钟）
sleep 120

# 5. 运行主安装
sshpass -p "$DEPLOY_SERVER_PASS" scp -o StrictHostKeyChecking=no *.sh .env $DEPLOY_SERVER_USER@$DEPLOY_SERVER_IP:~/
sshpass -p "$DEPLOY_SERVER_PASS" ssh -o StrictHostKeyChecking=no $DEPLOY_SERVER_USER@$DEPLOY_SERVER_IP "sudo bash ~/wireguard-install.sh -y"
sshpass -p "$DEPLOY_SERVER_PASS" ssh -o StrictHostKeyChecking=no $DEPLOY_SERVER_USER@$DEPLOY_SERVER_IP "sudo bash ~/v2ray-install-step1.sh"
sshpass -p "$DEPLOY_SERVER_PASS" ssh -o StrictHostKeyChecking=no $DEPLOY_SERVER_USER@$DEPLOY_SERVER_IP "sudo bash ~/v2ray-install-step2-enable-tcp-proxy.sh"
sshpass -p "$DEPLOY_SERVER_PASS" ssh -o StrictHostKeyChecking=no $DEPLOY_SERVER_USER@$DEPLOY_SERVER_IP "sudo bash ~/v2ray-install-step3-enable-udp-proxy.sh"

# 6. 下载配置文件
sshpass -p "$DEPLOY_SERVER_PASS" scp -o StrictHostKeyChecking=no -r $DEPLOY_SERVER_USER@$DEPLOY_SERVER_IP:~/private ./
```

## 预安装脚本功能

`aliyun-pre-install.sh` 脚本会：

1. **环境检测**: 确认是阿里云 ECS 环境
2. **预安装组件**: 
   - linux-firmware
   - amd64-microcode  
   - firmware-sof-signed
   - wireguard-tools (无推荐包)
   - 基础工具 (unzip, jq, sshpass)
3. **内核检测**: 检查是否安装了新内核
4. **重启提醒**: 如有新内核，提醒重启

## 优势

- **避免中断**: 预先处理内核升级，主安装过程不会被打断
- **更稳定**: 在已知环境下安装，减少意外情况
- **可选重启**: 可以选择是否重启到新内核
- **兼容性**: 新旧内核都支持 WireGuard

## 注意事项

1. **新内核优势**: realtime 内核延迟更低，但对网络代理影响不大
2. **旧内核兼容**: 继续使用原内核也完全可以正常工作
3. **重启时机**: 可以在完成所有安装后统一重启
4. **安全组**: 确保开放 UDP 51820 端口

## 故障排除

**如果预安装脚本检测失败**:
```bash
# 手动检查阿里云环境
curl -s --connect-timeout 3 http://100.100.100.200/latest/meta-data/instance-id

# 如果无响应，可能不是阿里云 ECS，直接运行主脚本即可
```

**如果仍然触发内核升级**:
```bash
# 可以继续安装，WireGuard 在新旧内核上都能正常工作
# 或者安装完成后重启
sudo reboot
```
