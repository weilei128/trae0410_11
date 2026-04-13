#!/bin/bash
# ============================================================
# Nginx 配置管理脚本
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config/env.sh"
source "${SCRIPT_DIR}/utils.sh"

# 生成 Nginx 配置
generate_nginx_config() {
    log "INFO" "生成 Nginx 配置..."
    
    # 生成唯一的 upstream 名称
    local upstream_name="backend_${APP_PORT}"
    
    cat << EOF
# ============================================================
# Nginx 配置 - ${APP_NAME}
# 端口: ${APP_PORT}
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
# ============================================================

# 后端服务 upstream
upstream ${upstream_name} {
    server 127.0.0.1:${BACKEND_PORT};
    keepalive 32;
}

# HTTP 服务器
server {
    listen ${APP_PORT};
    server_name _;
    
    # 日志配置
    access_log ${NGINX_ACCESS_LOG};
    error_log ${NGINX_ERROR_LOG} warn;
    
    # Gzip 压缩
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript;
    
    # 静态文件缓存
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|otf)$ {
        root ${REMOTE_APP_DIR}/frontend;
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }
    
    # API 代理
    location /api/ {
        proxy_pass http://${upstream_name};
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
        
        proxy_buffering on;
        proxy_buffer_size 4k;
        proxy_buffers 8 4k;
    }
    
    # 前端静态文件
    location / {
        root ${REMOTE_APP_DIR}/frontend;
        index index.html;
        try_files \$uri \$uri/ /index.html;
        
        # HTML 文件不缓存
        location ~* \.html$ {
            expires -1;
            add_header Cache-Control "no-cache, no-store, must-revalidate";
            add_header Pragma "no-cache";
        }
    }
    
    # 健康检查端点
    location /nginx-health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
}
EOF
}

# 部署 Nginx 配置
deploy_nginx_config() {
    log "INFO" "=========================================="
    log "INFO" "部署 Nginx 配置 - 端口 ${APP_PORT}"
    log "INFO" "=========================================="
    
    # 生成配置
    local config_content=$(generate_nginx_config)
    
    # 保存到临时文件
    local temp_config="${SCRIPT_DIR}/../tmp/${NGINX_CONF_NAME}"
    mkdir -p "$(dirname "$temp_config")"
    echo "$config_content" > "$temp_config"
    
    # 测试配置语法
    log "INFO" "测试 Nginx 配置语法..."
    remote_exec "echo '$(echo "$config_content" | base64 -w0)' | base64 -d > /tmp/${NGINX_CONF_NAME}"
    
    local test_result=$(remote_exec "nginx -t -c /tmp/${NGINX_CONF_NAME} 2>&1 || echo 'FAILED'")
    
    if echo "$test_result" | grep -q "FAILED"; then
        log "ERROR" "Nginx 配置语法错误:"
        log "ERROR" "$test_result"
        exit 1
    fi
    
    log "SUCCESS" "Nginx 配置语法正确"
    
    # 备份现有配置
    log "INFO" "备份现有 Nginx 配置..."
    remote_exec "
        if [ -f ${NGINX_CONF_DIR}/${NGINX_CONF_NAME} ]; then
            cp ${NGINX_CONF_DIR}/${NGINX_CONF_NAME} ${REMOTE_BACKUP_DIR}/nginx-$(date +%Y%m%d-%H%M%S).conf
        fi
    "
    
    # 部署配置
    log "INFO" "部署 Nginx 配置..."
    remote_upload "$temp_config" "${NGINX_CONF_DIR}/${NGINX_CONF_NAME}"
    
    # 重载 Nginx
    log "INFO" "重载 Nginx..."
    remote_exec "nginx -s reload 2>/dev/null || nginx"
    
    # 验证 Nginx 状态
    sleep 2
    local nginx_status=$(remote_exec "systemctl is-active nginx 2>/dev/null || service nginx status 2>&1 | grep -q running && echo 'active' || echo 'inactive'")
    
    if [ "$nginx_status" = "active" ]; then
        log "SUCCESS" "Nginx 重载成功"
    else
        log "WARN" "Nginx 状态检查返回: ${nginx_status}"
        log "INFO" "尝试启动 Nginx..."
        remote_exec "nginx 2>/dev/null || true"
    fi
    
    # 清理临时文件
    rm -f "$temp_config"
    remote_exec "rm -f /tmp/${NGINX_CONF_NAME}"
    
    log "SUCCESS" "Nginx 配置部署完成"
    log "INFO" "配置文件: ${NGINX_CONF_DIR}/${NGINX_CONF_NAME}"
    log "INFO" "访问地址: http://${SERVER_IP}:${APP_PORT}"
}

# 移除 Nginx 配置
remove_nginx_config() {
    log "INFO" "移除 Nginx 配置..."
    
    remote_exec "
        if [ -f ${NGINX_CONF_DIR}/${NGINX_CONF_NAME} ]; then
            mv ${NGINX_CONF_DIR}/${NGINX_CONF_NAME} ${REMOTE_BACKUP_DIR}/nginx-removed-$(date +%Y%m%d-%H%M%S).conf
            nginx -s reload 2>/dev/null || true
            echo 'Nginx 配置已移除'
        else
            echo 'Nginx 配置不存在'
        fi
    "
}

# 显示 Nginx 配置
show_nginx_config() {
    log "INFO" "当前 Nginx 配置:"
    remote_exec "cat ${NGINX_CONF_DIR}/${NGINX_CONF_NAME} 2>/dev/null || echo '配置不存在'"
}

# 检查 Nginx 状态
check_nginx_status() {
    log "INFO" "检查 Nginx 状态..."
    
    local status=$(remote_exec "systemctl is-active nginx 2>/dev/null || echo 'unknown'")
    local port_check=$(remote_exec "netstat -tlnp 2>/dev/null | grep ':${APP_PORT}' | grep nginx | wc -l")
    
    log "INFO" "Nginx 服务状态: ${status}"
    log "INFO" "端口 ${APP_PORT} 监听: ${port_check}"
    
    if [ "$status" = "active" ] && [ "$port_check" -gt 0 ]; then
        log "SUCCESS" "Nginx 运行正常"
        return 0
    else
        log "WARN" "Nginx 可能未正常运行"
        return 1
    fi
}

# 主函数
case "${1:-}" in
    deploy)
        deploy_nginx_config
        ;;
    remove)
        remove_nginx_config
        ;;
    show)
        show_nginx_config
        ;;
    check)
        check_nginx_status
        ;;
    *)
        echo "用法: $0 {deploy|remove|show|check}"
        exit 1
        ;;
esac
