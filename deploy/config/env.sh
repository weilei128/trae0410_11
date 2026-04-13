#!/bin/bash
# ============================================================
# 部署环境配置 - 端口 10013 实例
# ============================================================

# 服务器配置
export SERVER_IP="49.235.161.106"
export SERVER_USER="root"
export SERVER_PORT="22"
export SSH_KEY="~/.ssh/id_rsa"

# 端口配置（固定 10013）
export APP_PORT="10013"
export FRONTEND_PORT="10013"
export BACKEND_PORT="10013"

# 项目名称
export PROJECT_NAME="blog"
export APP_NAME="${PROJECT_NAME}-${APP_PORT}"

# 服务器端目录结构（以端口为唯一标识）
export REMOTE_BASE_DIR="/opt/apps/${APP_NAME}"
export REMOTE_APP_DIR="${REMOTE_BASE_DIR}/app"
export REMOTE_LOG_DIR="${REMOTE_BASE_DIR}/logs"
export REMOTE_TMP_DIR="${REMOTE_BASE_DIR}/tmp"
export REMOTE_BACKUP_DIR="${REMOTE_BASE_DIR}/backup"
export REMOTE_NGINX_DIR="${REMOTE_BASE_DIR}/nginx"

# Nginx 配置
export NGINX_CONF_DIR="/etc/nginx/conf.d"
export NGINX_CONF_NAME="${APP_NAME}.conf"
export NGINX_ACCESS_LOG="${REMOTE_LOG_DIR}/nginx-access.log"
export NGINX_ERROR_LOG="${REMOTE_LOG_DIR}/nginx-error.log"

# 本地构建输出目录
export LOCAL_BUILD_DIR="./dist"
export LOCAL_BACKEND_TARGET="./backend/target"

# 应用配置
export JAR_NAME="user-management-1.0.0.jar"
export JAR_PATH="${LOCAL_BACKEND_TARGET}/${JAR_NAME}"

# 健康检查配置
export HEALTH_CHECK_URL="http://localhost:${APP_PORT}/api/users"
export HEALTH_CHECK_TIMEOUT="60"
export HEALTH_CHECK_INTERVAL="3"

# 日志配置
export LOG_FILE="./deploy/logs/deploy-${APP_PORT}-$(date +%Y%m%d-%H%M%S).log"
export MAX_LOG_DAYS="30"

# 回滚配置
export MAX_BACKUP_COUNT="5"

# 颜色定义
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m' # No Color
