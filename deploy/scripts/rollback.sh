#!/bin/bash
# ============================================================
# 回滚脚本
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config/env.sh"
source "${SCRIPT_DIR}/utils.sh"

# 显示可用的备份
list_backups() {
    log "INFO" "可用的备份列表:"
    
    remote_exec "
        echo '=== 后端备份 ==='
        ls -lt ${REMOTE_BACKUP_DIR}/backend-*.tar.gz 2>/dev/null | head -5 || echo '无后端备份'
        
        echo ''
        echo '=== 前端备份 ==='
        ls -lt ${REMOTE_BACKUP_DIR}/frontend-*.tar.gz 2>/dev/null | head -5 || echo '无前端备份'
        
        echo ''
        echo '=== Nginx 配置备份 ==='
        ls -lt ${REMOTE_BACKUP_DIR}/nginx-*.conf 2>/dev/null | head -5 || echo '无 Nginx 备份'
    "
}

# 回滚后端
rollback_backend() {
    local backup_file="$1"
    
    if [ -z "$backup_file" ]; then
        # 获取最新的备份
        backup_file=$(remote_exec "ls -t ${REMOTE_BACKUP_DIR}/backend-*.tar.gz 2>/dev/null | head -1")
        if [ -z "$backup_file" ]; then
            log "ERROR" "没有找到可用的后端备份"
            return 1
        fi
    fi
    
    log "INFO" "回滚后端到: ${backup_file}"
    
    # 停止当前服务
    local pid=$(check_port_usage)
    if [ -n "$pid" ]; then
        safe_stop_process "$pid" 30
    fi
    
    # 备份当前版本（以防回滚失败）
    remote_exec "
        if [ -f ${REMOTE_APP_DIR}/backend/${JAR_NAME} ]; then
            CURRENT_BACKUP=\"${REMOTE_BACKUP_DIR}/backend-pre-rollback-\$(date +%Y%m%d-%H%M%S).tar.gz\"
            tar -czf \${CURRENT_BACKUP} -C ${REMOTE_APP_DIR}/backend . 2>/dev/null || true
            echo \"当前版本已备份: \${CURRENT_BACKUP}\"
        fi
    "
    
    # 恢复备份
    remote_exec "
        rm -rf ${REMOTE_APP_DIR}/backend/*
        tar -xzf ${backup_file} -C ${REMOTE_APP_DIR}/backend
        chmod +x ${REMOTE_APP_DIR}/backend/*.sh
    "
    
    # 启动服务
    remote_exec "cd ${REMOTE_APP_DIR}/backend && ./start-${APP_PORT}.sh"
    
    # 健康检查
    if wait_for_service "${HEALTH_CHECK_URL}" "${HEALTH_CHECK_TIMEOUT}"; then
        log "SUCCESS" "后端回滚成功"
        return 0
    else
        log "ERROR" "后端回滚失败，服务未启动"
        return 1
    fi
}

# 回滚前端
rollback_frontend() {
    local backup_file="$1"
    
    if [ -z "$backup_file" ]; then
        # 获取最新的备份
        backup_file=$(remote_exec "ls -t ${REMOTE_BACKUP_DIR}/frontend-*.tar.gz 2>/dev/null | head -1")
        if [ -z "$backup_file" ]; then
            log "ERROR" "没有找到可用的前端备份"
            return 1
        fi
    fi
    
    log "INFO" "回滚前端到: ${backup_file}"
    
    # 恢复备份
    remote_exec "
        rm -rf ${REMOTE_APP_DIR}/frontend/*
        tar -xzf ${backup_file} -C ${REMOTE_APP_DIR}/frontend
        chown -R www-data:www-data ${REMOTE_APP_DIR}/frontend 2>/dev/null || chown -R root:root ${REMOTE_APP_DIR}/frontend
        chmod -R 755 ${REMOTE_APP_DIR}/frontend
    "
    
    # 重载 Nginx
    remote_exec "nginx -s reload 2>/dev/null || true"
    
    log "SUCCESS" "前端回滚成功"
}

# 回滚 Nginx 配置
rollback_nginx() {
    local backup_file="$1"
    
    if [ -z "$backup_file" ]; then
        # 获取最新的备份
        backup_file=$(remote_exec "ls -t ${REMOTE_BACKUP_DIR}/nginx-*.conf 2>/dev/null | head -1")
        if [ -z "$backup_file" ]; then
            log "ERROR" "没有找到可用的 Nginx 备份"
            return 1
        fi
    fi
    
    log "INFO" "回滚 Nginx 配置到: ${backup_file}"
    
    # 恢复配置
    remote_exec "
        cp ${backup_file} ${NGINX_CONF_DIR}/${NGINX_CONF_NAME}
        nginx -t && nginx -s reload
    "
    
    log "SUCCESS" "Nginx 配置回滚成功"
}

# 主函数
case "${1:-}" in
    list)
        list_backups
        ;;
    backend)
        rollback_backend "${2:-}"
        ;;
    frontend)
        rollback_frontend "${2:-}"
        ;;
    nginx)
        rollback_nginx "${2:-}"
        ;;
    all)
        log "INFO" "执行完整回滚..."
        rollback_backend "${2:-}"
        rollback_frontend "${2:-}"
        rollback_nginx "${2:-}"
        log "SUCCESS" "完整回滚完成"
        ;;
    *)
        echo "用法: $0 {list|backend|frontend|nginx|all} [备份文件路径]"
        echo ""
        echo "命令说明:"
        echo "  list              - 列出所有可用备份"
        echo "  backend [file]    - 回滚后端（默认使用最新备份）"
        echo "  frontend [file]   - 回滚前端（默认使用最新备份）"
        echo "  nginx [file]      - 回滚 Nginx 配置（默认使用最新备份）"
        echo "  all [file]        - 回滚所有组件"
        exit 1
        ;;
esac
