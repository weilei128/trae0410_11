#!/bin/bash
# ========================================
# 后端服务控制脚本 - Linux 服务器端
# ========================================

INSTANCE_PORT="10011"
IDENTIFIER="10013"
BASE_DIR="/opt/blog_${IDENTIFIER}"
JAR_FILE="${BASE_DIR}/backend/blog_${IDENTIFIER}.jar"
PID_FILE="${BASE_DIR}/backend/pid_${IDENTIFIER}"
LOG_FILE="${BASE_DIR}/logs/backend_${IDENTIFIER}.log"

check_status() {
    if [ -f "${PID_FILE}" ]; then
        PID=$(cat "${PID_FILE}")
        if ps -p "${PID}" > /dev/null 2>&1; then
            echo "RUNNING (PID: ${PID})"
            return 0
        else
            echo "STOPPED (PID file exists but process not found)"
            rm -f "${PID_FILE}"
            return 1
        fi
    else
        PORT_CHECK=$(netstat -tlnp 2>/dev/null | grep ":${INSTANCE_PORT}" | grep java)
        if [ -n "${PORT_CHECK}" ]; then
            echo "RUNNING (no PID file, but port occupied)"
            return 0
        else
            echo "STOPPED"
            return 1
        fi
    fi
}

start() {
    echo "Starting backend service..."
    mkdir -p "${BASE_DIR}/logs"
    
    if check_status | grep -q "RUNNING"; then
        echo "Service is already running!"
        return 1
    fi
    
    cd "${BASE_DIR}/backend"
    nohup java -jar \
        -Dserver.port="${INSTANCE_PORT}" \
        -Dlogging.file.name="${LOG_FILE}" \
        "${JAR_FILE}" > "${BASE_DIR}/logs/nohup_${IDENTIFIER}.out" 2>&1 &
    
    echo $! > "${PID_FILE}"
    echo "Service started (PID: $!)"
    echo "Log file: ${LOG_FILE}"
    
    for i in {1..30}; do
        sleep 2
        if curl -s http://127.0.0.1:${INSTANCE_PORT}/api/users > /dev/null 2>&1; then
            echo "Service is healthy!"
            return 0
        fi
        echo -n "."
    done
    echo "Warning: Service may not be fully started"
}

stop() {
    echo "Stopping backend service..."
    if [ -f "${PID_FILE}" ]; then
        PID=$(cat "${PID_FILE}")
        echo "Sending TERM signal to PID: ${PID}"
        kill -TERM "${PID}" 2>/dev/null
        
        for i in {1..15}; do
            if ! ps -p "${PID}" > /dev/null 2>&1; then
                echo "Service stopped gracefully"
                rm -f "${PID_FILE}"
                return 0
            fi
            sleep 1
            echo -n "."
        done
        
        echo "Force killing process..."
        kill -9 "${PID}" 2>/dev/null
        rm -f "${PID_FILE}"
    else
        echo "No PID file found, trying port-based stop..."
        fuser -k -TERM "${INSTANCE_PORT}/tcp" 2>/dev/null
    fi
    sleep 2
    echo "Service stopped"
}

restart() {
    stop
    sleep 3
    start
}

status() {
    echo -n "Service status: "
    check_status
}

logs() {
    LINES=${1:-50}
    echo "Showing last ${LINES} lines of ${LOG_FILE}:"
    tail -n "${LINES}" -f "${LOG_FILE}"
}

healthcheck() {
    echo "Performing health check..."
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:${INSTANCE_PORT}/api/users 2>/dev/null || echo "000")
    if [ "${HTTP_STATUS}" = "200" ]; then
        echo "HEALTHY (HTTP ${HTTP_STATUS})"
        return 0
    else
        echo "UNHEALTHY (HTTP ${HTTP_STATUS})"
        return 1
    fi
}

case "$1" in
    start)
        start
        ;;
    stop)
        stop
        ;;
    restart)
        restart
        ;;
    status)
        status
        ;;
    logs)
        logs $2
        ;;
    healthcheck)
        healthcheck
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|logs|healthcheck}"
        echo "  logs [lines]   - Show live logs (default 50 lines)"
        exit 1
        ;;
esac
