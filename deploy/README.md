# 前后端分离博客项目自动化部署文档

## 项目概述

本项目是一个前后端分离的博客系统，包含：
- **前端**: Vue 3 + Vite
- **后端**: Spring Boot 2.7.18
- **部署端口**: 10013（固定）
- **目标服务器**: 49.235.161.106

## 目录结构

```
deploy/
├── config/
│   └── env.sh              # 环境配置文件
├── scripts/
│   ├── utils.sh            # 工具函数库
│   ├── build-frontend.sh   # 前端构建脚本
│   ├── build-backend.sh    # 后端构建脚本
│   ├── deploy-frontend.sh  # 前端部署脚本
│   ├── deploy-backend.sh   # 后端部署脚本
│   ├── nginx-manager.sh    # Nginx 配置管理
│   ├── rollback.sh         # 回滚脚本
│   └── test-deployment.sh  # 部署测试脚本
├── logs/                   # 日志目录
├── backup/                 # 本地备份目录
├── deploy.sh               # 主部署脚本 (Linux/Mac)
└── deploy.ps1              # 主部署脚本 (Windows)
```

## 服务器目录结构（以端口 10013 为标识）

```
/opt/apps/blog-10013/           # 应用根目录
├── app/
│   ├── backend/                # 后端应用
│   │   ├── user-management-1.0.0.jar
│   │   ├── start-10013.sh
│   │   ├── stop-10013.sh
│   │   └── status-10013.sh
│   └── frontend/               # 前端静态文件
│       ├── index.html
│       └── assets/
├── logs/                       # 日志目录
│   ├── app.log
│   ├── startup.log
│   ├── nginx-access.log
│   └── nginx-error.log
├── tmp/                        # 临时文件
├── backup/                     # 备份目录
└── .deployment                 # 部署标记文件
```

## 前置要求

### 本地环境
- Java 8+
- Maven 3.6+
- Node.js 16+
- npm 8+
- SSH 客户端
- tar 命令（用于压缩文件）

### 服务器环境
- Linux 服务器（CentOS/Ubuntu）
- Nginx 已安装
- Java 8+ 运行环境
- SSH 服务（端口 22）
- 具有 root 权限的 SSH 密钥

## 配置说明

### 1. SSH 密钥配置

确保本地有 SSH 私钥文件 `~/.ssh/id_rsa`，并且服务器已添加对应的公钥：

```bash
# 生成密钥（如果没有）
ssh-keygen -t rsa -b 4096

# 复制公钥到服务器
ssh-copy-id -p 22 root@49.235.161.106
```

### 2. 环境变量配置

编辑 `deploy/config/env.sh` 修改配置：

```bash
# 服务器配置
export SERVER_IP="49.235.161.106"
export SERVER_USER="root"
export SERVER_PORT="22"
export SSH_KEY="~/.ssh/id_rsa"

# 端口配置（固定 10013，请勿修改）
export APP_PORT="10013"
```

## 使用方法

### Linux/Mac 环境

```bash
# 进入部署目录
cd deploy

# 执行完整部署
./deploy.sh full

# 仅部署后端
./deploy.sh backend

# 仅部署前端
./deploy.sh frontend

# 仅更新 Nginx 配置
./deploy.sh nginx

# 查看服务状态
./deploy.sh status

# 查看日志
./deploy.sh logs

# 停止服务
./deploy.sh stop

# 重启服务
./deploy.sh restart

# 执行测试
./deploy.sh test

# 回滚到上一版本
./deploy.sh rollback

# 创建备份
./deploy.sh backup

# 清理临时文件
./deploy.sh clean
```

### Windows 环境 (PowerShell)

```powershell
# 进入部署目录
cd deploy

# 执行完整部署
.\deploy.ps1 full

# 仅部署后端
.\deploy.ps1 backend

# 仅部署前端
.\deploy.ps1 frontend

# 查看服务状态
.\deploy.ps1 status

# 执行测试
.\deploy.ps1 test
```

## 部署流程

### 完整部署流程

1. **环境检查**
   - 检查本地 Java/Maven/Node.js 环境
   - 检查 SSH 连接

2. **端口安全检查**
   - 检测端口 10013 占用情况
   - 仅终止本项目关联进程
   - 不影响其他端口（10011/10012）的服务

3. **后端构建**
   - 修改 `application.properties` 使用端口 10013
   - 执行 Maven 构建
   - 生成启动/停止/状态脚本

4. **前端构建**
   - 修改 `vite.config.js` 使用端口 10013
   - 执行 npm 构建
   - 生成生产环境静态文件

5. **后端部署**
   - 创建远程目录结构
   - 备份现有版本
   - 上传 JAR 包和脚本
   - 优雅启动服务
   - 健康检查

6. **前端部署**
   - 上传构建产物
   - 解压到目标目录

7. **Nginx 配置**
   - 生成端口 10013 专属配置
   - 配置 API 代理到后端
   - 配置静态文件服务
   - 重载 Nginx

8. **部署测试**
   - 端口监听测试
   - API 连通性测试
   - 前端页面访问测试
   - 生成测试报告

## 端口隔离说明

本项目严格遵循端口隔离原则：

- **10011 端口实例**: 完全独立，本脚本不操作
- **10012 端口实例**: 完全独立，本脚本不操作
- **10013 端口实例**: 本脚本仅操作此端口

所有文件、目录、进程都以 `10013` 或 `blog-10013` 为标识，确保多实例并行不冲突。

## 回滚机制

每次部署会自动创建备份：

```bash
# 查看可用备份
./deploy/scripts/rollback.sh list

# 回滚后端
./deploy/scripts/rollback.sh backend

# 回滚前端
./deploy/scripts/rollback.sh frontend

# 回滚 Nginx 配置
./deploy/scripts/rollback.sh nginx

# 完整回滚
./deploy/scripts/rollback.sh all
```

## 日志查看

### 本地日志
```bash
# 查看部署日志
tail -f deploy/logs/deploy-*.log

# 查看测试报告
cat deploy/logs/test-report-*.txt

# 查看部署报告
cat deploy/logs/deploy-report-*.txt
```

### 服务器日志
```bash
# 应用日志
tail -f /opt/apps/blog-10013/logs/app.log

# Nginx 访问日志
tail -f /opt/apps/blog-10013/logs/nginx-access.log

# Nginx 错误日志
tail -f /opt/apps/blog-10013/logs/nginx-error.log

# 启动日志
tail -f /opt/apps/blog-10013/logs/startup.log
```

## 故障排查

### 1. SSH 连接失败

```bash
# 测试 SSH 连接
ssh -p 22 -i ~/.ssh/id_rsa root@49.235.161.106

# 检查密钥权限
chmod 600 ~/.ssh/id_rsa
```

### 2. 端口被占用

```bash
# 查看端口占用
ssh root@49.235.161.106 "netstat -tlnp | grep 10013"

# 手动停止进程
ssh root@49.235.161.106 "kill -15 <PID>"
```

### 3. 服务启动失败

```bash
# 查看启动日志
ssh root@49.235.161.106 "tail -n 50 /opt/apps/blog-10013/logs/startup.log"

# 检查 Java 进程
ssh root@49.235.161.106 "ps aux | grep java"
```

### 4. Nginx 配置错误

```bash
# 测试配置语法
ssh root@49.235.161.106 "nginx -t"

# 查看 Nginx 错误
ssh root@49.235.161.106 "tail -n 20 /var/log/nginx/error.log"
```

## 安全说明

1. **端口安全**: 仅操作端口 10013，不影响其他端口服务
2. **进程安全**: 仅终止本项目关联进程，通过工作目录验证
3. **备份安全**: 每次部署自动备份，支持快速回滚
4. **日志安全**: 日志文件权限设置为 644，目录权限 755

## 访问地址

部署完成后，可通过以下地址访问：

```
http://49.235.161.106:10013
```

## 技术支持

如有问题，请检查：
1. 服务器 SSH 连接是否正常
2. 端口 10013 是否被其他非本项目进程占用
3. Nginx 是否正确安装并运行
4. Java 环境是否正确配置

## 更新记录

- v1.0.0 (2026-04-13)
  - 初始版本
  - 支持完整部署流程
  - 支持回滚机制
  - 支持自动化测试
