@echo off
chcp 65001 >nul
title 博客项目自动化部署 - 端口 10013

:: ============================================================
:: 前后端分离博客项目自动化部署脚本 (Windows Batch)
:: 端口: 10013
:: 服务器: 49.235.161.106
:: ============================================================

setlocal EnableDelayedExpansion

:: 配置变量
set "SERVER_IP=49.235.161.106"
set "SERVER_USER=root"
set "SERVER_PORT=22"
set "APP_PORT=10013"
set "APP_NAME=blog-10013"
set "REMOTE_BASE_DIR=/opt/apps/%APP_NAME%"
set "NGINX_CONF_NAME=%APP_NAME%.conf"

echo ==========================================
echo      博客项目自动化部署
echo ==========================================
echo 目标端口: %APP_PORT%
echo 目标服务器: %SERVER_IP%
echo 应用名称: %APP_NAME%
echo ==========================================
echo.

:: 检查参数
if "%~1"=="" goto :deploy_full
if "%~1"=="full" goto :deploy_full
if "%~1"=="backend" goto :deploy_backend
if "%~1"=="frontend" goto :deploy_frontend
if "%~1"=="nginx" goto :deploy_nginx
if "%~1"=="test" goto :test_deployment
if "%~1"=="status" goto :show_status
if "%~1"=="help" goto :show_help
goto :show_help

:show_help
echo 用法: deploy.bat [命令]
echo.
echo 命令:
echo   full       执行完整部署（构建+部署+测试）[默认]
echo   backend    仅部署后端
echo   frontend   仅部署前端
echo   nginx      仅更新 Nginx 配置
echo   test       执行测试
echo   status     查看服务状态
echo   help       显示帮助信息
echo.
echo 示例:
echo   deploy.bat           执行完整部署
echo   deploy.bat backend   仅部署后端
echo   deploy.bat status    查看服务状态
echo.
goto :end

:deploy_full
echo [1/6] 开始完整部署流程...
echo.

echo [2/6] 检查环境...
call :check_environment
if errorlevel 1 goto :error

echo [3/6] 构建后端...
call :build_backend
if errorlevel 1 goto :error

echo [4/6] 构建前端...
call :build_frontend
if errorlevel 1 goto :error

echo [5/6] 部署到服务器...
call :deploy_to_server
if errorlevel 1 goto :error

echo [6/6] 执行测试...
call :test_deployment
if errorlevel 1 goto :warning

echo.
echo ==========================================
echo      部署成功完成！
echo ==========================================
echo 访问地址: http://%SERVER_IP%:%APP_PORT%
echo.
goto :end

:deploy_backend
echo 开始后端部署...
call :check_environment
if errorlevel 1 goto :error
call :build_backend
if errorlevel 1 goto :error
call :deploy_backend_to_server
if errorlevel 1 goto :error
echo 后端部署完成！
goto :end

:deploy_frontend
echo 开始前端部署...
call :check_environment
if errorlevel 1 goto :error
call :build_frontend
if errorlevel 1 goto :error
call :deploy_frontend_to_server
if errorlevel 1 goto :error
call :deploy_nginx_config
if errorlevel 1 goto :error
echo 前端部署完成！
goto :end

:deploy_nginx
echo 更新 Nginx 配置...
call :deploy_nginx_config
if errorlevel 1 goto :error
echo Nginx 配置更新完成！
goto :end

:test_deployment
echo 执行部署测试...
call :test_connection
if errorlevel 1 goto :error
echo 测试完成！
goto :end

:show_status
echo 查看服务状态...
ssh -p %SERVER_PORT% %SERVER_USER%@%SERVER_IP% "echo '=== 端口状态 ===' && netstat -tlnp 2>/dev/null | grep ':%APP_PORT%' || echo '未监听'"
ssh -p %SERVER_PORT% %SERVER_USER%@%SERVER_IP% "echo '=== 进程状态 ===' && ps aux | grep -E '%APP_NAME%|user-management' | grep -v grep || echo '无相关进程'"
goto :end

:: ============================================================
:: 子程序
:: ============================================================

:check_environment
echo 检查环境...

:: 检查 SSH
ssh -V >nul 2>&1
if errorlevel 1 (
    echo [错误] 未找到 SSH 客户端，请安装 OpenSSH
    exit /b 1
)

:: 检查 Java
java -version >nul 2>&1
if errorlevel 1 (
    echo [错误] 未找到 Java，请安装 Java 8+
    exit /b 1
)

:: 检查 Maven
call mvn -version >nul 2>&1
if errorlevel 1 (
    echo [错误] 未找到 Maven，请安装 Maven 3.6+
    exit /b 1
)

:: 检查 Node.js
call node -v >nul 2>&1
if errorlevel 1 (
    echo [错误] 未找到 Node.js，请安装 Node.js 16+
    exit /b 1
)

:: 检查 SSH 连接
echo 检查 SSH 连接...
ssh -p %SERVER_PORT% -o ConnectTimeout=5 -o StrictHostKeyChecking=no %SERVER_USER%@%SERVER_IP% "echo 'SSH OK'" >nul 2>&1
if errorlevel 1 (
    echo [错误] 无法连接到服务器 %SERVER_IP%:%SERVER_PORT%
    echo 请检查 SSH 密钥和网络连接
    exit /b 1
)

echo [OK] 环境检查通过
exit /b 0

:build_backend
echo 构建后端应用...

cd ..\backend

:: 修改 application.properties
echo server.port=%APP_PORT%> src\main\resources\application.properties
echo server.servlet.context-path=/>> src\main\resources\application.properties
echo.>> src\main\resources\application.properties
echo # 日志配置>> src\main\resources\application.properties
echo logging.file.name=%REMOTE_BASE_DIR%/logs/app.log>> src\main\resources\application.properties
echo logging.level.root=INFO>> src\main\resources\application.properties
echo.>> src\main\resources\application.properties
echo # 用户数据文件路径>> src\main\resources\application.properties
echo user.data.file=%REMOTE_BASE_DIR%/app/users.json>> src\main\resources\application.properties

:: 执行 Maven 构建
call mvn clean package -DskipTests -q
if errorlevel 1 (
    echo [错误] Maven 构建失败
    exit /b 1
)

if not exist "target\user-management-1.0.0.jar" (
    echo [错误] JAR 文件不存在
    exit /b 1
)

echo [OK] 后端构建完成
exit /b 0

:build_frontend
echo 构建前端应用...

cd ..\frontend

:: 修改 vite.config.js
echo import { defineConfig } from 'vite'> vite.config.js
echo import vue from '@vitejs/plugin-vue'>> vite.config.js
echo.>> vite.config.js
echo export default defineConfig({>> vite.config.js
echo   plugins: [vue()],>> vite.config.js
echo   server: {>> vite.config.js
echo     port: %APP_PORT%,>> vite.config.js
echo     proxy: {>> vite.config.js
echo       '/api': {>> vite.config.js
echo         target: 'http://localhost:%APP_PORT%',>> vite.config.js
echo         changeOrigin: true>> vite.config.js
echo       }>> vite.config.js
echo     }>> vite.config.js
echo   },>> vite.config.js
echo   build: {>> vite.config.js
echo     outDir: 'dist',>> vite.config.js
echo     assetsDir: 'assets',>> vite.config.js
echo     sourcemap: false>> vite.config.js
echo   }>> vite.config.js
echo })>> vite.config.js

:: 安装依赖并构建
call npm ci --silent 2>nul
if errorlevel 1 call npm install --silent

call npm run build
if errorlevel 1 (
    echo [错误] 前端构建失败
    exit /b 1
)

if not exist "dist\index.html" (
    echo [错误] 构建产物不存在
    exit /b 1
)

echo [OK] 前端构建完成
exit /b 0

:deploy_to_server
echo 部署到服务器...

:: 创建远程目录
ssh -p %SERVER_PORT% %SERVER_USER%@%SERVER_IP% "mkdir -p %REMOTE_BASE_DIR%/{app/backend,app/frontend,logs,tmp,backup}"

:: 检查并停止现有服务
for /f "tokens=*" %%a in ('ssh -p %SERVER_PORT% %SERVER_USER%@%SERVER_IP% "netstat -tlnp 2>/dev/null ^| grep ':%APP_PORT%' ^| awk '{print \$7}' ^| cut -d'/' -f1 ^| head -1"') do (
    if not "%%a"=="" (
        echo 停止现有服务 ^(PID: %%a^)...
        ssh -p %SERVER_PORT% %SERVER_USER%@%SERVER_IP% "kill -15 %%a 2>/dev/null || true"
        timeout /t 2 /nobreak >nul
    )
)

:: 部署后端
call :deploy_backend_to_server
if errorlevel 1 exit /b 1

:: 部署前端
call :deploy_frontend_to_server
if errorlevel 1 exit /b 1

:: 配置 Nginx
call :deploy_nginx_config
if errorlevel 1 exit /b 1

echo [OK] 部署完成
exit /b 0

:deploy_backend_to_server
echo 部署后端...

:: 上传 JAR 文件
scp -P %SERVER_PORT% ..\backend\target\user-management-1.0.0.jar %SERVER_USER%@%SERVER_IP%:%REMOTE_BASE_DIR%/app/backend/

:: 创建启动脚本
echo #!/bin/bash> ..\backend\target\start-%APP_PORT%.sh
echo APP_DIR="$(cd "$(dirname "$0")" ^&^& pwd)">> ..\backend\target\start-%APP_PORT%.sh
echo nohup java -jar -Xms256m -Xmx512m -XX:+UseG1GC "$APP_DIR/user-management-1.0.0.jar" ^> "%REMOTE_BASE_DIR%/logs/startup.log" 2^>^&1 ^&>> ..\backend\target\start-%APP_PORT%.sh
echo echo $! ^> "%REMOTE_BASE_DIR%/tmp/app.pid">> ..\backend\target\start-%APP_PORT%.sh
echo echo "应用已启动，PID: $!">> ..\backend\target\start-%APP_PORT%.sh

scp -P %SERVER_PORT% ..\backend\target\start-%APP_PORT%.sh %SERVER_USER%@%SERVER_IP%:%REMOTE_BASE_DIR%/app/backend/

:: 启动服务
ssh -p %SERVER_PORT% %SERVER_USER%@%SERVER_IP% "chmod +x %REMOTE_BASE_DIR%/app/backend/*.sh && cd %REMOTE_BASE_DIR%/app/backend && ./start-%APP_PORT%.sh"

:: 等待启动
timeout /t 5 /nobreak >nul

echo [OK] 后端部署完成
exit /b 0

:deploy_frontend_to_server
echo 部署前端...

:: 压缩前端文件
cd ..\frontend
tar -czf ..\deploy\frontend-%APP_PORT%.tar.gz -C dist .
cd ..\deploy

:: 上传并解压
scp -P %SERVER_PORT% frontend-%APP_PORT%.tar.gz %SERVER_USER%@%SERVER_IP%:%REMOTE_BASE_DIR%/tmp/
ssh -p %SERVER_PORT% %SERVER_USER%@%SERVER_IP% "rm -rf %REMOTE_BASE_DIR%/app/frontend/* && tar -xzf %REMOTE_BASE_DIR%/tmp/frontend-%APP_PORT%.tar.gz -C %REMOTE_BASE_DIR%/app/frontend && rm -f %REMOTE_BASE_DIR%/tmp/frontend-%APP_PORT%.tar.gz"

:: 清理本地文件
del /f frontend-%APP_PORT%.tar.gz 2>nul

echo [OK] 前端部署完成
exit /b 0

:deploy_nginx_config
echo 配置 Nginx...

:: 生成 Nginx 配置
echo # Nginx 配置 - %APP_NAME%> nginx-%APP_PORT%.conf
echo upstream backend_%APP_PORT% {>> nginx-%APP_PORT%.conf
echo     server 127.0.0.1:%APP_PORT%;>> nginx-%APP_PORT%.conf
echo     keepalive 32;>> nginx-%APP_PORT%.conf
echo }>> nginx-%APP_PORT%.conf
echo.>> nginx-%APP_PORT%.conf
echo server {>> nginx-%APP_PORT%.conf
echo     listen %APP_PORT%;>> nginx-%APP_PORT%.conf
echo     server_name _;>> nginx-%APP_PORT%.conf
echo.>> nginx-%APP_PORT%.conf
echo     access_log %REMOTE_BASE_DIR%/logs/nginx-access.log;>> nginx-%APP_PORT%.conf
echo     error_log %REMOTE_BASE_DIR%/logs/nginx-error.log warn;>> nginx-%APP_PORT%.conf
echo.>> nginx-%APP_PORT%.conf
echo     gzip on;>> nginx-%APP_PORT%.conf
echo     gzip_vary on;>> nginx-%APP_PORT%.conf
echo     gzip_min_length 1024;>> nginx-%APP_PORT%.conf
echo     gzip_types text/plain text/css application/json application/javascript;>> nginx-%APP_PORT%.conf
echo.>> nginx-%APP_PORT%.conf
echo     location /api/ {>> nginx-%APP_PORT%.conf
echo         proxy_pass http://backend_%APP_PORT%;>> nginx-%APP_PORT%.conf
echo         proxy_http_version 1.1;>> nginx-%APP_PORT%.conf
echo         proxy_set_header Host $host;>> nginx-%APP_PORT%.conf
echo         proxy_set_header X-Real-IP $remote_addr;>> nginx-%APP_PORT%.conf
echo         proxy_connect_timeout 30s;>> nginx-%APP_PORT%.conf
echo     }>> nginx-%APP_PORT%.conf
echo.>> nginx-%APP_PORT%.conf
echo     location / {>> nginx-%APP_PORT%.conf
echo         root %REMOTE_BASE_DIR%/app/frontend;>> nginx-%APP_PORT%.conf
echo         index index.html;>> nginx-%APP_PORT%.conf
echo         try_files $uri $uri/ /index.html;>> nginx-%APP_PORT%.conf
echo     }>> nginx-%APP_PORT%.conf
echo }>> nginx-%APP_PORT%.conf

:: 上传配置
scp -P %SERVER_PORT% nginx-%APP_PORT%.conf %SERVER_USER%@%SERVER_IP%:/etc/nginx/conf.d/%NGINX_CONF_NAME%

:: 重载 Nginx
ssh -p %SERVER_PORT% %SERVER_USER%@%SERVER_IP% "nginx -t && nginx -s reload"

:: 清理
del /f nginx-%APP_PORT%.conf 2>nul

echo [OK] Nginx 配置完成
exit /b 0

:test_connection
echo 测试连接...

:: 测试端口
for /f "tokens=*" %%a in ('ssh -p %SERVER_PORT% %SERVER_USER%@%SERVER_IP% "netstat -tlnp 2>/dev/null ^| grep ':%APP_PORT%' ^| wc -l"') do (
    if "%%a"=="0" (
        echo [警告] 端口 %APP_PORT% 未监听
    ) else (
        echo [OK] 端口 %APP_PORT% 监听正常
    )
)

:: 测试 API
for /f "tokens=*" %%a in ('ssh -p %SERVER_PORT% %SERVER_USER%@%SERVER_IP% "curl -s -o /dev/null -w '%%{http_code}' http://localhost:%APP_PORT%/api/users 2>/dev/null || echo '000'"') do (
    if "%%a"=="200" (
        echo [OK] API 测试通过
    ) else (
        echo [警告] API 测试失败 ^(HTTP %%a^)
    )
)

exit /b 0

:warning
echo.
echo [警告] 部署完成，但测试未完全通过
echo 请检查日志排查问题
goto :end

:error
echo.
echo [错误] 部署失败！
echo 请检查错误信息并修复后重试
goto :end

:end
echo.
pause
