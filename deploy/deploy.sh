#!/bin/bash
# ============================================================
# 主部署脚本 - 端口 10013 实例
# 前后端分离博客项目自动化部署
# ============================================================

set -e

# 脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载配置和工具函数
source "${SCRIPT_DIR}/config/env.sh"
source "${SCRIPT_DIR}/scripts/utils.sh"

# 部署开始时间
DEPLOY_START_TIME=$(date +%s)
DEPLOY_VERSION=$(date +%Y%m%d-%H%M%S)

# 显示帮助信息
show_help() {
    cat << EOF
前后端分离博客项目自动化部署脚本

用法: $0 [选项] [命令]

命令:
    full          执行完整部署（构建+部署+测试）[默认]
    backend       仅部署后端
    frontend      仅部署前端
    nginx         仅更新 Nginx 配置
    stop          停止服务
    restart       重启服务
    status        查看服务状态
    logs          查看日志
    test          执行测试
    rollback      回滚到上一版本
    backup        创建备份
    clean         清理临时文件

选项:
    -h, --help    显示帮助信息
    -v, --version 显示版本信息
    -y, --yes     自动确认，不提示

示例:
    $0                    # 执行完整部署
    $0 backend           # 仅部署后端
    $0 frontend          # 仅部署前端
    $0 rollback          # 回滚到上一版本
    $0 logs              # 查看实时日志

EOF
}

# 显示版本信息
show_version() {
    echo "部署脚本版本: 1.0.0"
    echo "目标端口: ${APP_PORT}"
    echo "目标服务器: ${SERVER_IP}"
}

# 初始化日志
init_logging() {
    mkdir -p "$(dirname "$LOG_FILE")"
    echo "========================================" > "$LOG_FILE"
    echo "部署日志 - 版本: ${DEPLOY_VERSION}" >> "$LOG_FILE"
    echo "开始时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$LOG_FILE"
    echo "========================================" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
}

# 显示部署信息
show_deploy_info() {
    log "INFO" "=========================================="
    log "INFO" "     博客项目自动化部署"
    log "INFO" "=========================================="
    log "INFO" "部署版本: ${DEPLOY_VERSION}"
    log "INFO" "目标端口: ${APP_PORT}"
    log "INFO" "目标服务器: ${SERVER_IP}"
    log "INFO" "应用名称: ${APP_NAME}"
    log "INFO" "=========================================="
    log "INFO" ""
}

# 执行完整部署
deploy_full() {
    show_deploy_info
    
    log "INFO" "开始完整部署流程..."
    
    # 步骤1: 检查环境
    log "INFO" "[1/8] 检查部署环境..."
    check_environment
    
    # 步骤2: 检查端口并停止现有服务
    log "INFO" "[2/8] 检查端口占用..."
    local existing_pid=$(check_port_usage)
    if [ -n "$existing_pid" ]; then
        log "INFO" "发现现有服务，准备停止..."
        safe_stop_process "$existing_pid" 30
    fi
    
    # 步骤3: 构建后端
    log "INFO" "[3/8] 构建后端应用..."
    "${SCRIPT_DIR}/scripts/build-backend.sh"
    
    # 步骤4: 构建前端
    log "INFO" "[4/8] 构建前端应用..."
    "${SCRIPT_DIR}/scripts/build-frontend.sh"
    
    # 步骤5: 部署后端
    log "INFO" "[5/8] 部署后端应用..."
    "${SCRIPT_DIR}/scripts/deploy-backend.sh"
    
    # 步骤6: 部署前端
    log "INFO" "[6/8] 部署前端应用..."
    "${SCRIPT_DIR}/scripts/deploy-frontend.sh"
    
    # 步骤7: 配置 Nginx
    log "INFO" "[7/8] 配置 Nginx..."
    "${SCRIPT_DIR}/scripts/nginx-manager.sh" deploy
    
    # 步骤8: 测试验证
    log "INFO" "[8/8] 执行部署测试..."
    "${SCRIPT_DIR}/scripts/test-deployment.sh" all
    
    # 生成部署报告
    generate_deploy_report
    
    log "SUCCESS" "=========================================="
    log "SUCCESS" "     部署成功完成！"
    log "SUCCESS" "=========================================="
    log "INFO" "访问地址: http://${SERVER_IP}:${APP_PORT}"
    log "INFO" "日志文件: ${LOG_FILE}"
}

# 仅部署后端
deploy_backend_only() {
    show_deploy_info
    
    log "INFO" "开始后端部署..."
    
    check_environment
    "${SCRIPT_DIR}/scripts/build-backend.sh"
    "${SCRIPT_DIR}/scripts/deploy-backend.sh"
    
    log "SUCCESS" "后端部署完成"
}

# 仅部署前端
deploy_frontend_only() {
    show_deploy_info
    
    log "INFO" "开始前端部署..."
    
    check_environment
    "${SCRIPT_DIR}/scripts/build-frontend.sh"
    "${SCRIPT_DIR}/scripts/deploy-frontend.sh"
    "${SCRIPT_DIR}/scripts/nginx-manager.sh" deploy
    
    log "SUCCESS" "前端部署完成"
}

# 检查环境
check_environment() {
    log "INFO" "检查本地环境..."
    
    # 检查必要命令
    local required_commands=("ssh" "scp" "curl")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log "ERROR" "缺少必要命令: ${cmd}"
            exit 1
        fi
    done
    
    # 检查 SSH 连接
    log "INFO" "检查 SSH 连接..."
    if ! ssh -p "${SERVER_PORT}" -i "${SSH_KEY}" -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
            "${SERVER_USER}@${SERVER_IP}" "echo 'SSH OK'" &> /dev/null; then
        log "ERROR" "无法连接到服务器 ${SERVER_IP}:${SERVER_PORT}"
        log "ERROR" "请检查 SSH 密钥和网络连接"
        exit 1
    fi
    
    log "SUCCESS" "环境检查通过"
}

# 停止服务
stop_service() {
    log "INFO" "停止服务..."
    
    local pid=$(check_port_usage)
    if [ -n "$pid" ]; then
        safe_stop_process "$pid" 30
    else
        log "INFO" "服务未运行"
    fi
    
    # 停止 Nginx（仅停止当前端口的配置）
    log "INFO" "移除 Nginx 配置..."
    "${SCRIPT_DIR}/scripts/nginx-manager.sh" remove
}

# 重启服务
restart_service() {
    log "INFO" "重启服务..."
    stop_service
    sleep 2
    
    # 启动后端
    remote_exec "cd ${REMOTE_APP_DIR}/backend && ./start-${APP_PORT}.sh"
    sleep 3
    
    # 检查状态
    local status=$(check_service_status "${HEALTH_CHECK_URL}")
    if [ "$status" = "running" ]; then
        log "SUCCESS" "服务重启成功"
    else
        log "ERROR" "服务重启失败"
        exit 1
    fi
}

# 查看状态
show_status() {
    log "INFO" "=========================================="
    log "INFO" "服务状态 - 端口 ${APP_PORT}"
    log "INFO" "=========================================="
    
    # 检查端口
    local port_status=$(remote_exec "netstat -tlnp 2>/dev/null | grep ':${APP_PORT}' | head -3 || echo '未监听'")
    log "INFO" "端口状态:"
    echo "$port_status" | while read line; do
        log "INFO" "  ${line}"
    done
    
    # 检查进程
    log "INFO" ""
    log "INFO" "进程状态:"
    remote_exec "ps aux | grep -E '${APP_NAME}|${JAR_NAME}' | grep -v grep || echo '无相关进程'"
    
    # 检查服务健康
    log "INFO" ""
    log "INFO" "健康检查:"
    local health=$(check_service_status "${HEALTH_CHECK_URL}")
    log "INFO" "  服务状态: ${health}"
    
    # 显示部署标记
    log "INFO" ""
    log "INFO" "部署信息:"
    local marker=$(get_deployment_marker)
    echo "$marker" | while read line; do
        log "INFO" "  ${line}"
    done
}

# 查看日志
show_logs() {
    local lines="${1:-50}"
    log "INFO" "显示最近 ${lines} 行日志..."
    
    remote_exec "
        echo '=== 应用日志 ===' && \
        tail -n ${lines} ${REMOTE_LOG_DIR}/app.log 2>/dev/null || echo '无应用日志' && \
        echo '' && \
        echo '=== Nginx 错误日志 ===' && \
        tail -n ${lines} ${NGINX_ERROR_LOG} 2>/dev/null || echo '无 Nginx 错误日志'
    "
}

# 创建备份
create_backup() {
    log "INFO" "创建备份..."
    
    local backup_name="manual-${DEPLOY_VERSION}"
    
    remote_exec "
        # 备份后端
        if [ -f ${REMOTE_APP_DIR}/backend/${JAR_NAME} ]; then
            tar -czf ${REMOTE_BACKUP_DIR}/backend-${backup_name}.tar.gz -C ${REMOTE_APP_DIR}/backend . 2>/dev/null || true
        fi
        
        # 备份前端
        if [ -d ${REMOTE_APP_DIR}/frontend ] && [ \"\$(ls -A ${REMOTE_APP_DIR}/frontend 2>/dev/null)\" ]; then
            tar -czf ${REMOTE_BACKUP_DIR}/frontend-${backup_name}.tar.gz -C ${REMOTE_APP_DIR}/frontend . 2>/dev/null || true
        fi
        
        # 备份 Nginx 配置
        if [ -f ${NGINX_CONF_DIR}/${NGINX_CONF_NAME} ]; then
            cp ${NGINX_CONF_DIR}/${NGINX_CONF_NAME} ${REMOTE_BACKUP_DIR}/nginx-${backup_name}.conf
        fi
        
        echo '备份完成: ${backup_name}'
    "
    
    log "SUCCESS" "备份创建完成"
}

# 清理临时文件
clean_temp() {
    log "INFO" "清理临时文件..."
    
    rm -rf "${SCRIPT_DIR}/tmp/*"
    remote_exec "rm -rf ${REMOTE_TMP_DIR}/*"
    
    log "SUCCESS" "临时文件清理完成"
}

# 生成部署报告
generate_deploy_report() {
    local deploy_end_time=$(date +%s)
    local deploy_duration=$((deploy_end_time - DEPLOY_START_TIME))
    
    local report_file="${SCRIPT_DIR}/logs/deploy-report-${APP_PORT}-${DEPLOY_VERSION}.txt"
    
    cat > "$report_file" << EOF
========================================
       部署报告
========================================
部署版本: ${DEPLOY_VERSION}
部署时间: $(date '+%Y-%m-%d %H:%M:%S')
部署耗时: ${deploy_duration} 秒

服务器信息:
  IP: ${SERVER_IP}
  端口: ${APP_PORT}
  用户: ${SERVER_USER}

应用信息:
  名称: ${APP_NAME}
  后端端口: ${BACKEND_PORT}
  前端端口: ${FRONTEND_PORT}

目录结构:
  应用目录: ${REMOTE_APP_DIR}
  日志目录: ${REMOTE_LOG_DIR}
  备份目录: ${REMOTE_BACKUP_DIR}

访问地址:
  http://${SERVER_IP}:${APP_PORT}

文件位置:
  部署日志: ${LOG_FILE}
  测试报告: ${SCRIPT_DIR}/logs/test-report-*

========================================
部署状态: 成功
========================================
EOF

    log "INFO" "部署报告已生成: ${report_file}"
}

# 主函数
main() {
    # 初始化日志
    init_logging
    
    # 解析命令
    local command="${1:-full}"
    
    case "$command" in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--version)
            show_version
            exit 0
            ;;
        full)
            deploy_full
            ;;
        backend)
            deploy_backend_only
            ;;
        frontend)
            deploy_frontend_only
            ;;
        nginx)
            "${SCRIPT_DIR}/scripts/nginx-manager.sh" deploy
            ;;
        stop)
            stop_service
            ;;
        restart)
            restart_service
            ;;
        status)
            show_status
            ;;
        logs)
            show_logs "${2:-50}"
            ;;
        test)
            "${SCRIPT_DIR}/scripts/test-deployment.sh" all
            ;;
        rollback)
            "${SCRIPT_DIR}/scripts/rollback.sh" all
            ;;
        backup)
            create_backup
            ;;
        clean)
            clean_temp
            ;;
        *)
            log "ERROR" "未知命令: ${command}"
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"
