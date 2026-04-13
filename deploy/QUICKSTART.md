# 快速开始指南

## 环境要求

### 本地环境
- Java 8 或更高版本
- Maven 3.6 或更高版本
- Node.js 16 或更高版本
- OpenSSH 客户端

### 服务器环境
- Linux 服务器（已配置好 Java 和 Nginx）
- SSH 密钥认证已配置

## 快速部署步骤

### 1. 配置 SSH 密钥

确保你可以免密码登录服务器：

```bash
# 测试 SSH 连接
ssh root@49.235.161.106
```

### 2. 执行部署

#### Windows 用户

双击运行或在命令行执行：

```cmd
cd deploy
deploy.bat
```

#### Linux/Mac 用户

```bash
cd deploy
chmod +x deploy.sh scripts/*.sh
./deploy.sh
```

### 3. 访问应用

部署完成后，访问：

```
http://49.235.161.106:10013
```

## 常用命令

### 查看状态
```bash
# Windows
deploy.bat status

# Linux/Mac
./deploy.sh status
```

### 查看日志
```bash
# Linux/Mac
./deploy.sh logs

# 或者直接 SSH 到服务器查看
tail -f /opt/apps/blog-10013/logs/app.log
```

### 仅部署后端
```bash
# Windows
deploy.bat backend

# Linux/Mac
./deploy.sh backend
```

### 仅部署前端
```bash
# Windows
deploy.bat frontend

# Linux/Mac
./deploy.sh frontend
```

### 回滚
```bash
# Linux/Mac
./deploy.sh rollback
```

## 故障排查

### 问题1: SSH 连接失败

**解决方案**:
```bash
# 生成 SSH 密钥
ssh-keygen -t rsa

# 复制公钥到服务器
ssh-copy-id root@49.235.161.106
```

### 问题2: 端口被占用

**解决方案**:
脚本会自动检测并停止占用端口 10013 的本项目进程。如果端口被其他服务占用，请手动处理：

```bash
# SSH 到服务器查看
ssh root@49.235.161.106 "netstat -tlnp | grep 10013"

# 如果不是本项目进程，请手动停止或更换端口
```

### 问题3: 构建失败

**检查环境**:
```bash
java -version
mvn -version
node -v
npm -v
```

确保所有命令都能正常执行。

### 问题4: Nginx 配置错误

**检查 Nginx**:
```bash
ssh root@49.235.161.106 "nginx -t"
```

## 目录说明

### 本地目录
- `deploy/scripts/` - 部署脚本
- `deploy/logs/` - 部署日志
- `deploy/config/` - 配置文件

### 服务器目录
- `/opt/apps/blog-10013/app/backend/` - 后端应用
- `/opt/apps/blog-10013/app/frontend/` - 前端文件
- `/opt/apps/blog-10013/logs/` - 日志文件
- `/opt/apps/blog-10013/backup/` - 备份文件

## 安全说明

1. **端口隔离**: 仅操作端口 10013，不影响其他端口服务
2. **进程安全**: 仅终止本项目关联进程
3. **自动备份**: 每次部署自动备份，支持回滚

## 技术支持

如有问题，请查看详细文档：[README.md](README.md)
