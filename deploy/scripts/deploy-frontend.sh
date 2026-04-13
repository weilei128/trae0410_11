#!/bin/bash
# ============================================================
# 前端部署脚本
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config/env.sh"
source "${SCRIPT_DIR}/utils.sh"

# 构建产物路径（可以通过参数传入，否则自动构建）
BUILD_ARCHIVE="${1:-}"

log "INFO" "=========================================="
log "INFO" "开始前端部署 - 端口 ${APP_PORT}"
log "INFO" "=========================================="

# 如果没有提供构建产物，先执行构建
if [ -z "$BUILD_ARCHIVE" ]; then
    log "INFO" "未提供构建产物，执行自动构建..."
    BUILD_ARCHIVE=$("${SCRIPT_DIR}/build-frontend.sh")
    
    if [ ! -f "$BUILD_ARCHIVE" ]; then
        log "ERROR" "构建失败，无法找到构建产物"
        exit 1
    fi
fi

# 检查构建产物
if [ ! -f "$BUILD_ARCHIVE" ]; then
    log "ERROR" "构建产物不存在: ${BUILD_ARCHIVE}"
    exit 1
fi

# 创建远程目录
log "INFO" "创建远程前端目录..."
remote_exec "mkdir -p ${REMOTE_APP_DIR}/frontend"

# 备份现有版本（如果存在）
log "INFO" "备份现有前端版本..."
remote_exec "
    if [ -d ${REMOTE_APP_DIR}/frontend ] && [ \"\$(ls -A ${REMOTE_APP_DIR}/frontend 2>/dev/null)\" ]; then
        BACKUP_NAME=\"frontend-\$(date +%Y%m%d-%H%M%S).tar.gz\"
        tar -czf ${REMOTE_BACKUP_DIR}/\${BACKUP_NAME} -C ${REMOTE_APP_DIR}/frontend . 2>/dev/null || true
        echo \"备份完成: \${BACKUP_NAME}\"
    fi
"

# 清理旧文件
log "INFO" "清理旧文件..."
remote_exec "rm -rf ${REMOTE_APP_DIR}/frontend/*"

# 上传构建产物
log "INFO" "上传构建产物到服务器..."
UPLOAD_TEMP="${REMOTE_TMP_DIR}/frontend-upload-$(date +%s).tar.gz"
remote_upload "$BUILD_ARCHIVE" "$UPLOAD_TEMP"

# 解压构建产物
log "INFO" "解压构建产物..."
remote_exec "
    tar -xzf ${UPLOAD_TEMP} -C ${REMOTE_APP_DIR}/frontend
    rm -f ${UPLOAD_TEMP}
    chown -R www-data:www-data ${REMOTE_APP_DIR}/frontend 2>/dev/null || chown -R root:root ${REMOTE_APP_DIR}/frontend
    chmod -R 755 ${REMOTE_APP_DIR}/frontend
"

# 验证部署
log "INFO" "验证前端部署..."
INDEX_FILE="${REMOTE_APP_DIR}/frontend/index.html"
remote_exec "
    if [ ! -f ${INDEX_FILE} ]; then
        echo 'ERROR: index.html not found'
        exit 1
    fi
    echo '验证通过: index.html 存在'
    echo \"文件大小: \$(du -h ${INDEX_FILE} | cut -f1)\"
"

log "SUCCESS" "前端部署完成"
log "INFO" "前端路径: ${REMOTE_APP_DIR}/frontend"

# 清理本地临时文件
rm -f "$BUILD_ARCHIVE" 2>/dev/null || true
