#!/bin/bash
# 启动服务脚本

APP_PORT="10013"
APP_DIR="/opt/apps/blog-10013"

# 检查并停止现有服务
PID=$(netstat -tlnp 2>/dev/null | grep ":${APP_PORT}" | awk '{print $7}' | cut -d'/' -f1 | head -1)
if [ -n "$PID" ]; then
    echo "停止现有服务 (PID: ${PID})..."
    kill -15 ${PID} 2>/dev/null || true
    sleep 2
fi

# 创建启动脚本
cat > ${APP_DIR}/app/backend/start-10013.sh << 'EOF'
#!/bin/bash
APP_DIR="/opt/apps/blog-10013/app/backend"
nohup java -jar -Xms256m -Xmx512m -XX:+UseG1GC "${APP_DIR}/user-management-1.0.0.jar" > /opt/apps/blog-10013/logs/startup.log 2>&1 &
echo $! > /opt/apps/blog-10013/tmp/app.pid
echo "应用已启动，PID: $!"
EOF
chmod +x ${APP_DIR}/app/backend/start-10013.sh

# 启动服务
cd ${APP_DIR}/app/backend && ./start-10013.sh

echo "等待服务启动..."
sleep 5

# 检查状态
if netstat -tlnp 2>/dev/null | grep -q ":${APP_PORT}"; then
    echo "服务启动成功，端口 ${APP_PORT} 正在监听"
    # 测试 API
    HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:${APP_PORT}/api/users 2>/dev/null || echo "000")
    echo "API 测试: HTTP ${HTTP_CODE}"
else
    echo "服务启动失败，请检查日志:"
    tail -n 20 ${APP_DIR}/logs/startup.log
fi
