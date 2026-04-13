#!/bin/bash
# ============================================================
# 后端构建脚本
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config/env.sh"
source "${SCRIPT_DIR}/utils.sh"

log "INFO" "=========================================="
log "INFO" "开始后端构建 - 端口 ${APP_PORT}"
log "INFO" "=========================================="

# 进入后端目录
cd "${SCRIPT_DIR}/../../backend" || {
    log "ERROR" "无法进入后端目录"
    exit 1
}

# 检查 Java 环境
log "INFO" "检查 Java 环境..."
if ! command -v java &> /dev/null; then
    log "ERROR" "Java 未安装"
    exit 1
fi

JAVA_VERSION=$(java -version 2>&1 | head -1 | cut -d'"' -f2)
log "INFO" "Java 版本: ${JAVA_VERSION}"

# 检查 Maven
log "INFO" "检查 Maven 环境..."
if ! command -v mvn &> /dev/null; then
    log "ERROR" "Maven 未安装"
    exit 1
fi

MVN_VERSION=$(mvn -v | head -1)
log "INFO" "Maven: ${MVN_VERSION}"

# 修改 application.properties 使用正确的端口
log "INFO" "配置应用端口..."
cat > src/main/resources/application.properties << EOF
server.port=${BACKEND_PORT}
server.servlet.context-path=/

# 日志配置
logging.file.name=${REMOTE_LOG_DIR}/app.log
logging.level.root=INFO
logging.level.com.example=DEBUG

# 用户数据文件路径
user.data.file=${REMOTE_APP_DIR}/users.json
EOF

# 清理之前的构建
log "INFO" "清理之前的构建..."
rm -rf target/

# 执行 Maven 构建
log "INFO" "执行 Maven 构建..."
mvn clean package -DskipTests -q

# 检查构建结果
if [ ! -f "target/${JAR_NAME}" ]; then
    log "ERROR" "构建失败，JAR 文件不存在"
    exit 1
fi

# 获取构建信息
JAR_SIZE=$(du -h "target/${JAR_NAME}" | cut -f1)
JAR_VERSION=$(unzip -p "target/${JAR_NAME}" META-INF/MANIFEST.MF | grep Implementation-Version | cut -d' ' -f2 || echo "unknown")

log "SUCCESS" "后端构建完成"
log "INFO" "JAR 文件: ${JAR_NAME}"
log "INFO" "文件大小: ${JAR_SIZE}"
log "INFO" "版本: ${JAR_VERSION}"

# 创建启动脚本
cat > "target/start-${APP_PORT}.sh" << 'START_SCRIPT'
#!/bin/bash
APP_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="${JAR_NAME}"
APP_PORT="${APP_PORT}"
LOG_DIR="${REMOTE_LOG_DIR}"
PID_FILE="${REMOTE_TMP_DIR}/app.pid"

# 启动应用
nohup java -jar \
    -Xms256m -Xmx512m \
    -XX:+UseG1GC \
    -XX:+HeapDumpOnOutOfMemoryError \
    -XX:HeapDumpPath="${LOG_DIR}/heapdump.hprof" \
    -Djava.awt.headless=true \
    -Dfile.encoding=UTF-8 \
    "${APP_DIR}/${APP_NAME}" \
    > "${LOG_DIR}/startup.log" 2>&1 &

# 保存 PID
echo $! > "${PID_FILE}"
echo "应用已启动，PID: $!"
START_SCRIPT

# 创建停止脚本
cat > "target/stop-${APP_PORT}.sh" << 'STOP_SCRIPT'
#!/bin/bash
PID_FILE="${REMOTE_TMP_DIR}/app.pid"

if [ -f "${PID_FILE}" ]; then
    PID=$(cat "${PID_FILE}")
    if ps -p "${PID}" > /dev/null 2>&1; then
        echo "正在停止应用 (PID: ${PID})..."
        kill -15 "${PID}"
        
        # 等待进程结束
        for i in {1..30}; do
            if ! ps -p "${PID}" > /dev/null 2>&1; then
                echo "应用已停止"
                rm -f "${PID_FILE}"
                exit 0
            fi
            sleep 1
        done
        
        # 强制终止
        echo "强制终止应用..."
        kill -9 "${PID}" 2>/dev/null || true
    else
        echo "应用未运行"
    fi
    rm -f "${PID_FILE}"
else
    echo "PID 文件不存在"
fi
STOP_SCRIPT

# 创建状态检查脚本
cat > "target/status-${APP_PORT}.sh" << 'STATUS_SCRIPT'
#!/bin/bash
PID_FILE="${REMOTE_TMP_DIR}/app.pid"
APP_PORT="${APP_PORT}"

if [ -f "${PID_FILE}" ]; then
    PID=$(cat "${PID_FILE}")
    if ps -p "${PID}" > /dev/null 2>&1; then
        echo "应用运行中 (PID: ${PID})"
        # 检查端口
        if netstat -tlnp 2>/dev/null | grep -q ":${APP_PORT}"; then
            echo "端口 ${APP_PORT} 监听正常"
        else
            echo "警告: 端口 ${APP_PORT} 未监听"
        fi
        exit 0
    else
        echo "应用未运行 (PID 文件存在但进程不存在)"
        exit 1
    fi
else
    echo "应用未运行"
    exit 1
fi
STATUS_SCRIPT

chmod +x target/*.sh

log "INFO" "启动脚本已生成"
