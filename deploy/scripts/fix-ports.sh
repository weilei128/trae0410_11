#!/bin/bash
# 修复端口冲突脚本

APP_DIR="/opt/apps/blog-10013"

# 停止所有使用 10013 的服务
echo "停止现有服务..."
PID=$(cat ${APP_DIR}/tmp/app.pid 2>/dev/null)
if [ -n "$PID" ]; then
    kill -15 $PID 2>/dev/null || true
    sleep 2
fi

# 重新构建 JAR 文件，使用端口 10014
echo "重新配置后端端口为 10014..."
cd /tmp
rm -rf jar_extract
mkdir jar_extract
cd jar_extract
jar xf ${APP_DIR}/app/backend/user-management-1.0.0.jar

# 修改配置文件
sed -i 's/10013/10014/g' BOOT-INF/classes/application.properties

# 重新打包
jar cfm ${APP_DIR}/app/backend/user-management-1.0.0.jar META-INF/MANIFEST.MF .
cd /
rm -rf /tmp/jar_extract

# 修改 Nginx 配置
echo "更新 Nginx 配置..."
cat > /etc/nginx/conf.d/blog-10013.conf << 'EOF'
upstream backend_10013 {
    server 127.0.0.1:10014;
    keepalive 32;
}

server {
    listen 10013;
    server_name _;

    access_log /opt/apps/blog-10013/logs/nginx-access.log;
    error_log /opt/apps/blog-10013/logs/nginx-error.log warn;

    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css application/json application/javascript text/xml;

    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|otf)$ {
        root /opt/apps/blog-10013/app/frontend/dist;
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }

    location /api/ {
        proxy_pass http://backend_10013;
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
    }

    location / {
        root /opt/apps/blog-10013/app/frontend/dist;
        index index.html;
        try_files $uri $uri/ /index.html;
    }
}
EOF

# 启动后端
echo "启动后端服务 (端口 10014)..."
cd ${APP_DIR}/app/backend
nohup java -jar -Xms256m -Xmx512m -XX:+UseG1GC user-management-1.0.0.jar > ${APP_DIR}/logs/startup.log 2>&1 &
echo $! > ${APP_DIR}/tmp/app.pid
echo "后端 PID: $!"

sleep 5

# 启动 Nginx
echo "启动 Nginx (端口 10013)..."
nginx

echo "等待服务启动..."
sleep 3

# 检查状态
echo "=== 端口状态 ==="
netstat -tlnp | grep -E '10013|10014' || echo "无监听"

echo "=== 服务状态 ==="
curl -s http://localhost:10013/api/users && echo "API 正常" || echo "API 异常"
