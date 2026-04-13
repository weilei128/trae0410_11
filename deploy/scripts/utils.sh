#!/bin/bash
# ============================================================
# 工具函数库
# ============================================================

# 加载配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config/env.sh"

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
    echo "[${timestamp}] [${level}] ${message}" >> "${LOG_FILE}" 2>/dev/null || true
}

# 执行远程命令
remote_exec() {
    local cmd="$1"
    ssh -p "${SERVER_PORT}" -i "${SSH_KEY}" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        "${SERVER_USER}@${SERVER_IP}" "$cmd"
}

# 上传文件
remote_upload() {
    local local_path="$1"
    local remote_path="$2"
    scp -P "${SERVER_PORT}" -i "${SSH_KEY}" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        -r "$local_path" "${SERVER_USER}@${SERVER_IP}:${remote_path}"
}

# 下载文件
remote_download() {
    local remote_path="$1"
    local local_path="$2"
    scp -P "${SERVER_PORT}" -i "${SSH_KEY}" -o StrictHostKeyChecking=no -o ConnectTimeout=10 \
        "${SERVER_USER}@${SERVER_IP}:${remote_path}" "$local_path"
}

# 检查端口占用（仅检查当前项目关联进程）
check_port_usage() {
    log "INFO" "检查端口 ${APP_PORT} 占用情况..."
    
    # 获取占用端口的进程信息
    local pid=$(remote_exec "netstat -tlnp 2>/dev/null | grep ':${APP_PORT}' | awk '{print \$7}' | cut -d'/' -f1 | head -1")
    
    if [ -n "$pid" ] && [ "$pid" != "-" ]; then
        # 获取进程详细信息
        local proc_info=$(remote_exec "ps -p ${pid} -o pid,ppid,cmd --no-headers 2>/dev/null || echo ''")
        
        if [ -n "$proc_info" ]; then
            log "WARN" "端口 ${APP_PORT} 被进程占用:"
            log "WARN" "  PID: ${pid}"
            log "WARN" "  详情: ${proc_info}"
            
            # 检查是否是我们项目的进程（通过检查工作目录或jar包路径）
            local is_our_app=$(remote_exec "ls -l /proc/${pid}/cwd 2>/dev/null | grep -q '${APP_NAME}' && echo 'yes' || echo 'no'")
            
            if [ "$is_our_app" = "yes" ]; then
                log "INFO" "确认是本项目关联进程，准备安全终止..."
                echo "$pid"
                return 0
            else
                log "ERROR" "端口 ${APP_PORT} 被其他服务占用，且不属于本项目！"
                log "ERROR" "进程信息: ${proc_info}"
                return 1
            fi
        fi
    fi
    
    log "INFO" "端口 ${APP_PORT} 未被占用"
    echo ""
    return 0
}

# 安全停止进程
safe_stop_process() {
    local pid="$1"
    local timeout="${2:-30}"
    
    if [ -z "$pid" ]; then
        log "WARN" "没有指定进程ID，跳过停止操作"
        return 0
    fi
    
    log "INFO" "正在优雅停止进程 ${pid}..."
    
    # 发送 SIGTERM 信号
    remote_exec "kill -15 ${pid} 2>/dev/null || true"
    
    # 等待进程结束
    local count=0
    while [ $count -lt $timeout ]; do
        local still_running=$(remote_exec "ps -p ${pid} --no-headers 2>/dev/null | wc -l")
        if [ "$still_running" -eq 0 ]; then
            log "SUCCESS" "进程 ${pid} 已正常停止"
            return 0
        fi
        sleep 1
        count=$((count + 1))
    done
    
    # 超时后强制终止
    log "WARN" "进程未在 ${timeout} 秒内停止，强制终止..."
    remote_exec "kill -9 ${pid} 2>/dev/null || true"
    sleep 1
    
    local still_running=$(remote_exec "ps -p ${pid} --no-headers 2>/dev/null | wc -l")
    if [ "$still_running" -eq 0 ]; then
        log "SUCCESS" "进程 ${pid} 已强制终止"
        return 0
    else
        log "ERROR" "无法终止进程 ${pid}"
        return 1
    fi
}

# 等待服务启动
wait_for_service() {
    local url="$1"
    local timeout="${2:-${HEALTH_CHECK_TIMEOUT}}"
    local interval="${3:-${HEALTH_CHECK_INTERVAL}}"
    
    log "INFO" "等待服务启动，超时时间: ${timeout}秒..."
    
    local count=0
    while [ $count -lt $timeout ]; do
        # 使用远程服务器检查本地服务
        local response=$(remote_exec "curl -s -o /dev/null -w '%{http_code}' ${url} 2>/dev/null || echo '000'")
        
        if [ "$response" = "200" ] || [ "$response" = "401" ] || [ "$response" = "403" ]; then
            log "SUCCESS" "服务已启动，HTTP状态码: ${response}"
            return 0
        fi
        
        sleep $interval
        count=$((count + interval))
        
        if [ $((count % 10)) -eq 0 ]; then
            log "INFO" "已等待 ${count} 秒，继续检查..."
        fi
    done
    
    log "ERROR" "服务启动超时 (${timeout}秒)"
    return 1
}

# 检查服务状态
check_service_status() {
    local url="$1"
    
    local response=$(remote_exec "curl -s -o /dev/null -w '%{http_code}' ${url} 2>/dev/null || echo '000'")
    
    if [ "$response" = "200" ] || [ "$response" = "401" ] || [ "$response" = "403" ]; then
        echo "running"
    else
        echo "stopped"
    fi
}

# 创建远程目录结构
setup_remote_dirs() {
    log "INFO" "创建远程目录结构..."
    
    remote_exec "
        mkdir -p ${REMOTE_APP_DIR} ${REMOTE_LOG_DIR} ${REMOTE_TMP_DIR} ${REMOTE_BACKUP_DIR} ${REMOTE_NGINX_DIR}
        chmod 755 ${REMOTE_BASE_DIR} ${REMOTE_APP_DIR} ${REMOTE_LOG_DIR} ${REMOTE_TMP_DIR} ${REMOTE_BACKUP_DIR} ${REMOTE_NGINX_DIR}
    "
    
    log "SUCCESS" "远程目录结构创建完成"
}

# 清理旧日志
cleanup_old_logs() {
    log "INFO" "清理 ${MAX_LOG_DAYS} 天前的日志..."
    
    remote_exec "
        find ${REMOTE_LOG_DIR} -name '*.log' -mtime +${MAX_LOG_DAYS} -delete 2>/dev/null || true
        find ${REMOTE_BACKUP_DIR} -name '*.tar.gz' -mtime +${MAX_LOG_DAYS} -delete 2>/dev/null || true
    "
    
    log "SUCCESS" "旧日志清理完成"
}

# 保存部署标记
save_deployment_marker() {
    local version="$1"
    local marker_file="${REMOTE_BASE_DIR}/.deployment"
    
    remote_exec "
        echo 'version: ${version}' > ${marker_file}
        echo 'timestamp: $(date +%Y%m%d-%H%M%S)' >> ${marker_file}
        echo 'commit: $(git rev-parse --short HEAD 2>/dev/null || echo unknown)' >> ${marker_file}
        echo 'deployer: $(whoami)' >> ${marker_file}
    "
    
    log "INFO" "部署标记已保存: ${version}"
}

# 获取部署标记
get_deployment_marker() {
    local marker_file="${REMOTE_BASE_DIR}/.deployment"
    remote_exec "cat ${marker_file} 2>/dev/null || echo 'No deployment marker found'"
}
