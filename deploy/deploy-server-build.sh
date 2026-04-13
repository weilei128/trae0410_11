#!/bin/bash
# ============================================================
# 服务器端构建部署脚本 - 端口 10013 实例
# 在服务器上执行构建，避免本地环境依赖
# ============================================================

set -e

# 配置
SERVER_IP="49.235.161.106"
SERVER_USER="root"
SERVER_PORT="22"
APP_PORT="10013"
APP_NAME="blog-${APP_PORT}"
REMOTE_BASE_DIR="/opt/apps/${APP_NAME}"
LOCAL_PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local color=""
    
    case "$level" in
        "INFO")  color="${BLUE}" ;;
        "SUCCESS") color="${GREEN}" ;;
        "WARN")  color="${YELLOW}" ;;
        "ERROR") color="${RED}" ;;
    esac
    
    echo -e "${color}[${timestamp}] [${level}] ${message}${NC}"
}

# 执行远程命令
remote_exec() {
    ssh -p "${SERVER_PORT}" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        "${SERVER_USER}@${SERVER_IP}" "$1"
}

# 上传文件
remote_upload() {
    local local_path="$1"
    local remote_path="$2"
    scp -P "${SERVER_PORT}" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        -r "$local_path" "${SERVER_USER}@${SERVER_IP}:${remote_path}"
}

# 显示部署信息
show_deploy_info() {
    log "INFO" "=========================================="
    log "INFO" "     博客项目自动化部署（服务器端构建）"
    log "INFO" "=========================================="
    log "INFO" "目标端口: ${APP_PORT}"
    log "INFO" "目标服务器: ${SERVER_IP}"
    log "INFO" "应用名称: ${APP_NAME}"
    log "INFO" "=========================================="
    log "INFO" ""
}

# 检查 SSH 连接
check_ssh() {
    log "INFO" "检查 SSH 连接..."
    if ! remote_exec "echo 'SSH OK'" > /dev/null 2>&1; then
        log "ERROR" "无法连接到服务器 ${SERVER_IP}:${SERVER_PORT}"
        log "ERROR" "请确保 SSH 密钥已配置"
        exit 1
    fi
    log "SUCCESS" "SSH 连接正常"
}

# 准备服务器环境
prepare_server() {
    log "INFO" "准备服务器环境..."
    
    remote_exec "
        # 创建目录结构
        mkdir -p ${REMOTE_BASE_DIR}/{app,logs,tmp,backup,source}
        
        # 检查 Java
        if ! command -v java &> /dev/null; then
            echo '安装 Java...'
            apt-get update && apt-get install -y openjdk-8-jdk || yum install -y java-1.8.0-openjdk
        fi
        
        # 检查 Maven
        if ! command -v mvn &> /dev/null; then
            echo '安装 Maven...'
            apt-get install -y maven || yum install -y maven
        fi
        
        # 检查 Node.js
        if ! command -v node &> /dev/null; then
            echo '安装 Node.js...'
            curl -fsSL https://deb.nodesource.com/setup_20.x | bash - || true
            apt-get install -y nodejs || yum install -y nodejs
        fi
        
        # 检查 Nginx
        if ! command -v nginx &> /dev/null; then
            echo '安装 Nginx...'
            apt-get install -y nginx || yum install -y nginx
        fi
        
        echo '环境准备完成'
        java -version 2>&1 | head -1
        mvn -version 2>&1 | head -1
        node -v 2>&1
    "
    
    log "SUCCESS" "服务器环境准备完成"
}

# 上传源代码
upload_source() {
    log "INFO" "上传源代码..."
    
    # 压缩项目
    local temp_archive="/tmp/blog-source-${APP_PORT}.tar.gz"
    cd "${LOCAL_PROJECT_DIR}"
    
    # 排除不需要的文件
    tar -czf "${temp_archive}" \
        --exclude='.git' \
        --exclude='node_modules' \
        --exclude='target' \
        --exclude='dist' \
        --exclude='deploy/logs' \
        --exclude='deploy/backup' \
        --exclude='deploy/tmp' \
        -C "${LOCAL_PROJECT_DIR}" .
    
    # 上传到服务器
    remote_upload "${temp_archive}" "${REMOTE_BASE_DIR}/source/"
    
    # 解压
    remote_exec "
        cd ${REMOTE_BASE_DIR}/source && \
        tar -xzf blog-source-${APP_PORT}.tar.gz && \
        rm -f blog-source-${APP_PORT}.tar.gz
    "
    
    rm -f "${temp_archive}"
    
    log "SUCCESS" "源代码上传完成"
}

# 在服务器上构建后端
build_backend_on_server() {
    log "INFO" "在服务器上构建后端..."
    
    remote_exec "
        cd ${REMOTE_BASE_DIR}/source/backend
        
        # 修改端口配置
        cat > src/main/resources/application.properties << EOF
server.port=${APP_PORT}
server.servlet.context-path=/

# 日志配置
logging.file.name=${REMOTE_BASE_DIR}/logs/app.log
logging.level.root=INFO
logging.level.com.example=DEBUG

# 用户数据文件路径
user.data.file=${REMOTE_BASE_DIR}/app/users.json
EOF
        
        # 构建
        mvn clean package -DskipTests -q
        
        if [ ! -f target/user-management-1.0.0.jar ]; then
            echo '构建失败'
            exit 1
        fi
        
        echo '后端构建成功'
    "
    
    log "SUCCESS" "后端构建完成"
}

# 在服务器上构建前端
build_frontend_on_server() {
    log "INFO" "在服务器上构建前端..."
    
    remote_exec "
        cd ${REMOTE_BASE_DIR}/source/frontend
        
        # 修改 vite 配置
        cat > vite.config.js << 'EOF'
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],
  server: {
    port: ${APP_PORT},
    proxy: {
      '/api': {
        target: 'http://localhost:${APP_PORT}',
        changeOrigin: true
      }
    }
  },
  build: {
    outDir: 'dist',
    assetsDir: 'assets',
    sourcemap: false
  }
})
EOF
        
        # 安装依赖并构建
        npm ci --silent 2>/dev/null || npm install --silent
        npm run build
        
        if [ ! -d dist ] || [ ! -f dist/index.html ]; then
            echo '前端构建失败'
            exit 1
        fi
        
        echo '前端构建成功'
    "
    
    log "SUCCESS" "前端构建完成"
}

# 部署应用
deploy_application() {
    log "INFO" "部署应用..."
    
    # 停止现有服务
    local pid=$(remote_exec "netstat -tlnp 2>/dev/null | grep ':${APP_PORT}' | awk '{print \$7}' | cut -d'/' -f1 | head -1" || echo "")
    if [ -n "$pid" ] && [ "$pid" != "" ]; then
        log "INFO" "停止现有服务 (PID: ${pid})..."
        remote_exec "kill -15 ${pid} 2>/dev/null || true"
        sleep 2
    fi
    
    # 部署后端
    log "INFO" "部署后端..."
    remote_exec "
        # 备份
        if [ -f ${REMOTE_BASE_DIR}/app/backend/user-management-1.0.0.jar ]; then
            cp ${REMOTE_BASE_DIR}/app/backend/user-management-1.0.0.jar \
               ${REMOTE_BASE_DIR}/backup/backend-$(date +%Y%m%d-%H%M%S).jar 2>/dev/null || true
        fi
        
        # 复制新构建
        mkdir -p ${REMOTE_BASE_DIR}/app/backend
        cp ${REMOTE_BASE_DIR}/source/backend/target/user-management-1.0.0.jar \
           ${REMOTE_BASE_DIR}/app/backend/
        
        # 创建启动脚本
        cat > ${REMOTE_BASE_DIR}/app/backend/start-${APP_PORT}.sh << EOF
#!/bin/bash
APP_DIR="\$(cd "\$(dirname "\$0")" && pwd)"
nohup java -jar -Xms256m -Xmx512m -XX:+UseG1GC "\${APP_DIR}/user-management-1.0.0.jar" > "${REMOTE_BASE_DIR}/logs/startup.log" 2>&1 &
echo \$! > "${REMOTE_BASE_DIR}/tmp/app.pid"
echo "应用已启动，PID: \$!"
EOF
        chmod +x ${REMOTE_BASE_DIR}/app/backend/start-${APP_PORT}.sh
        
        # 启动
        cd ${REMOTE_BASE_DIR}/app/backend && ./start-${APP_PORT}.sh
    "
    
    # 等待启动
    sleep 5
    
    # 部署前端
    log "INFO" "部署前端..."
    remote_exec "
        # 备份
        if [ -d ${REMOTE_BASE_DIR}/app/frontend ] && [ "\$(ls -A ${REMOTE_BASE_DIR}/app/frontend 2>/dev/null)" ]; then
            tar -czf ${REMOTE_BASE_DIR}/backup/frontend-$(date +%Y%m%d-%H%M%S).tar.gz \
                -C ${REMOTE_BASE_DIR}/app/frontend . 2>/dev/null || true
        fi
        
        # 复制新构建
        rm -rf ${REMOTE_BASE_DIR}/app/frontend/*
        cp -r ${REMOTE_BASE_DIR}/source/frontend/dist/* ${REMOTE_BASE_DIR}/app/frontend/
        
        # 设置权限
        chmod -R 755 ${REMOTE_BASE_DIR}/app/frontend
    "
    
    log "SUCCESS" "应用部署完成"
}

# 配置 Nginx
configure_nginx() {
    log "INFO" "配置 Nginx..."
    
    remote_exec "
        # 生成 Nginx 配置
        cat > /etc/nginx/conf.d/${APP_NAME}.conf << 'EOF'
upstream backend_${APP_PORT} {
    server 127.0.0.1:${APP_PORT};
    keepalive 32;
}

server {
    listen ${APP_PORT};
    server_name _;
    
    access_log ${REMOTE_BASE_DIR}/logs/nginx-access.log;
    error_log ${REMOTE_BASE_DIR}/logs/nginx-error.log warn;
    
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css application/json application/javascript text/xml;
    
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|otf)$ {
        root ${REMOTE_BASE_DIR}/app/frontend;
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }
    
    location /api/ {
        proxy_pass http://backend_${APP_PORT};
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
    }
    
    location / {
        root ${REMOTE_BASE_DIR}/app/frontend;
        index index.html;
        try_files \$uri \$uri/ /index.html;
    }
}
EOF
        
        # 测试并重载
        nginx -t && nginx -s reload
    "
    
    log "SUCCESS" "Nginx 配置完成"
}

# 健康检查
health_check() {
    log "INFO" "执行健康检查..."
    
    local max_attempts=20
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local response=$(remote_exec "curl -s -o /dev/null -w '%{http_code}' http://localhost:${APP_PORT}/api/users 2>/dev/null || echo '000'")
        
        if [ "$response" = "200" ]; then
            log "SUCCESS" "健康检查通过 (HTTP 200)"
            return 0
        fi
        
        log "INFO" "健康检查尝试 ${attempt}/${max_attempts}..."
        sleep 3
        attempt=$((attempt + 1))
    done
    
    log "ERROR" "健康检查失败"
    return 1
}

# 执行测试
run_tests() {
    log "INFO" "执行部署测试..."
    
    # 测试端口
    local port_check=$(remote_exec "netstat -tlnp 2>/dev/null | grep ':${APP_PORT}' | wc -l")
    if [ "$port_check" -gt 0 ]; then
        log "SUCCESS" "端口 ${APP_PORT} 监听正常"
    else
        log "ERROR" "端口 ${APP_PORT} 未监听"
        return 1
    fi
    
    # 测试 API
    local api_response=$(remote_exec "curl -s -o /dev/null -w '%{http_code}' http://localhost:${APP_PORT}/api/users 2>/dev/null || echo '000'")
    if [ "$api_response" = "200" ]; then
        log "SUCCESS" "API 测试通过 (HTTP 200)"
    else
        log "WARN" "API 测试返回 HTTP ${api_response}"
    fi
    
    # 测试前端
    local frontend_response=$(remote_exec "curl -s -o /dev/null -w '%{http_code}' http://localhost:${APP_PORT}/ 2>/dev/null || echo '000'")
    if [ "$frontend_response" = "200" ]; then
        log "SUCCESS" "前端测试通过 (HTTP 200)"
    else
        log "WARN" "前端测试返回 HTTP ${frontend_response}"
    fi
    
    log "SUCCESS" "测试完成"
}

# 生成部署报告
generate_report() {
    log "INFO" "生成部署报告..."
    
    local report_file="${REMOTE_BASE_DIR}/logs/deploy-report-$(date +%Y%m%d-%H%M%S).txt"
    
    remote_exec "
        cat > ${report_file} << EOF
========================================
       部署报告
========================================
部署时间: $(date '+%Y-%m-%d %H:%M:%S')
目标端口: ${APP_PORT}
目标服务器: ${SERVER_IP}
应用名称: ${APP_NAME}

目录结构:
  应用目录: ${REMOTE_BASE_DIR}/app
  日志目录: ${REMOTE_BASE_DIR}/logs
  备份目录: ${REMOTE_BASE_DIR}/backup

访问地址:
  http://${SERVER_IP}:${APP_PORT}

状态检查:
  端口监听: $(netstat -tlnp 2>/dev/null | grep ':${APP_PORT}' | wc -l) 个进程
  API 状态: $(curl -s -o /dev/null -w '%{http_code}' http://localhost:${APP_PORT}/api/users 2>/dev/null || echo '000')
  页面状态: $(curl -s -o /dev/null -w '%{http_code}' http://localhost:${APP_PORT}/ 2>/dev/null || echo '000')

========================================
部署状态: 成功
========================================
EOF
        cat ${report_file}
    "
}

# 清理
cleanup() {
    log "INFO" "清理临时文件..."
    remote_exec "rm -rf ${REMOTE_BASE_DIR}/source"
    log "SUCCESS" "清理完成"
}

# 主函数
main() {
    show_deploy_info
    
    check_ssh
    prepare_server
    upload_source
    build_backend_on_server
    build_frontend_on_server
    deploy_application
    configure_nginx
    health_check
    run_tests
    generate_report
    cleanup
    
    log "SUCCESS" "=========================================="
    log "SUCCESS" "     部署成功完成！"
    log "SUCCESS" "=========================================="
    log "INFO" "访问地址: http://${SERVER_IP}:${APP_PORT}"
    log "INFO" "日志路径: ${REMOTE_BASE_DIR}/logs/"
}

# 执行
main "$@"
