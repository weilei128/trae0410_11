#!/bin/bash
# ============================================================
# 后端部署脚本
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config/env.sh"
source "${SCRIPT_DIR}/utils.sh"

log "INFO" "=========================================="
log "INFO" "开始后端部署 - 端口 ${APP_PORT}"
log "INFO" "=========================================="

# 步骤1: 检查端口占用并安全停止现有服务
log "INFO" "步骤1: 检查端口占用情况..."
EXISTING_PID=$(check_port_usage)

if [ $? -ne 0 ]; then
    log "ERROR" "端口检查失败，终止部署"
    exit 1
fi

if [ -n "$EXISTING_PID" ]; then
    log "INFO" "发现现有进程，准备安全停止..."
    safe_stop_process "$EXISTING_PID" 30
    if [ $? -ne 0 ]; then
        log "ERROR" "无法停止现有进程"
        exit 1
    fi
fi

# 步骤2: 创建远程目录
log "INFO" "步骤2: 创建远程目录结构..."
setup_remote_dirs

# 步骤3: 备份现有版本
log "INFO" "步骤3: 备份现有版本..."
remote_exec "
    if [ -f ${REMOTE_APP_DIR}/backend/${JAR_NAME} ]; then
        BACKUP_NAME=\"backend-\$(date +%Y%m%d-%H%M%S).tar.gz\"
        tar -czf ${REMOTE_BACKUP_DIR}/\${BACKUP_NAME} -C ${REMOTE_APP_DIR}/backend . 2>/dev/null || true
        echo \"备份完成: \${BACKUP_NAME}\"
    fi
"

# 步骤4: 上传 JAR 包和脚本
log "INFO" "步骤4: 上传应用文件..."
remote_exec "mkdir -p ${REMOTE_APP_DIR}/backend"

remote_upload "${JAR_PATH}" "${REMOTE_APP_DIR}/backend/"
remote_upload "${LOCAL_BACKEND_TARGET}/start-${APP_PORT}.sh" "${REMOTE_APP_DIR}/backend/"
remote_upload "${LOCAL_BACKEND_TARGET}/stop-${APP_PORT}.sh" "${REMOTE_APP_DIR}/backend/"
remote_upload "${LOCAL_BACKEND_TARGET}/status-${APP_PORT}.sh" "${REMOTE_APP_DIR}/backend/"

# 步骤5: 设置权限
log "INFO" "步骤5: 设置文件权限..."
remote_exec "
    chmod +x ${REMOTE_APP_DIR}/backend/*.sh
    chown -R www-data:www-data ${REMOTE_APP_DIR}/backend 2>/dev/null || chown -R root:root ${REMOTE_APP_DIR}/backend
    chmod -R 755 ${REMOTE_APP_DIR}/backend
"

# 步骤6: 复制用户数据文件（如果不存在则复制默认数据）
log "INFO" "步骤6: 检查用户数据文件..."
remote_exec "
    if [ ! -f ${REMOTE_APP_DIR}/users.json ]; then
        if [ -f ${REMOTE_APP_DIR}/backend/users.json ]; then
            cp ${REMOTE_APP_DIR}/backend/users.json ${REMOTE_APP_DIR}/users.json
        else
            echo '[]' > ${REMOTE_APP_DIR}/users.json
        fi
        chmod 644 ${REMOTE_APP_DIR}/users.json
    fi
"

# 步骤7: 启动应用
log "INFO" "步骤7: 启动后端服务..."
remote_exec "cd ${REMOTE_APP_DIR}/backend && ./start-${APP_PORT}.sh"

# 等待应用启动
sleep 3

# 步骤8: 健康检查
log "INFO" "步骤8: 执行健康检查..."
if wait_for_service "${HEALTH_CHECK_URL}" "${HEALTH_CHECK_TIMEOUT}" "${HEALTH_CHECK_INTERVAL}"; then
    log "SUCCESS" "后端服务启动成功"
else
    log "ERROR" "后端服务启动失败"
    # 输出日志帮助排查
    remote_exec "tail -n 50 ${REMOTE_LOG_DIR}/startup.log" || true
    remote_exec "tail -n 50 ${REMOTE_LOG_DIR}/app.log" || true
    exit 1
fi

# 步骤9: 保存部署标记
save_deployment_marker "$(date +%Y%m%d-%H%M%S)"

log "SUCCESS" "=========================================="
log "SUCCESS" "后端部署完成 - 端口 ${APP_PORT}"
log "SUCCESS" "=========================================="
log "INFO" "应用路径: ${REMOTE_APP_DIR}/backend"
log "INFO" "日志路径: ${REMOTE_LOG_DIR}"
log "INFO" "健康检查: ${HEALTH_CHECK_URL}"
