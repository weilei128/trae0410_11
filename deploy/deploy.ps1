# ============================================================
# 主部署脚本 (PowerShell) - 端口 10013 实例
# 前后端分离博客项目自动化部署
# ============================================================

param(
    [Parameter(Position=0)]
    [string]$Command = "full",
    
    [switch]$Help,
    [switch]$Version,
    [switch]$Yes
)

# 错误处理
$ErrorActionPreference = "Stop"

# 脚本目录
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir

# 加载配置
$Config = @{
    # 服务器配置
    ServerIP = "49.235.161.106"
    ServerUser = "root"
    ServerPort = 22
    SSHKey = "$env:USERPROFILE\.ssh\id_rsa"
    
    # 端口配置（固定 10013）
    AppPort = "10013"
    FrontendPort = "10013"
    BackendPort = "10013"
    
    # 项目名称
    ProjectName = "blog"
    
    # 服务器端目录结构
    RemoteBaseDir = "/opt/apps/blog-10013"
    RemoteAppDir = "/opt/apps/blog-10013/app"
    RemoteLogDir = "/opt/apps/blog-10013/logs"
    RemoteTmpDir = "/opt/apps/blog-10013/tmp"
    RemoteBackupDir = "/opt/apps/blog-10013/backup"
    
    # Nginx 配置
    NginxConfDir = "/etc/nginx/conf.d"
    NginxConfName = "blog-10013.conf"
    
    # 应用配置
    JarName = "user-management-1.0.0.jar"
    
    # 健康检查
    HealthCheckUrl = "http://localhost:10013/api/users"
    HealthCheckTimeout = 60
    
    # 应用名称
    AppName = "blog-10013"
}

# 日志函数
function Write-Log {
    param(
        [string]$Level,
        [string]$Message
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $colors = @{
        "INFO" = "Cyan"
        "SUCCESS" = "Green"
        "WARN" = "Yellow"
        "ERROR" = "Red"
    }
    
    $color = $colors[$Level]
    if (-not $color) { $color = "White" }
    
    Write-Host "[$timestamp] [$Level] $Message" -ForegroundColor $color
}

# 执行 SSH 命令
function Invoke-SSHCommand {
    param([string]$Command)
    
    $sshArgs = @(
        "-p", $Config.ServerPort,
        "-i", $Config.SSHKey,
        "-o", "StrictHostKeyChecking=no",
        "-o", "ConnectTimeout=10",
        "$($Config.ServerUser)@$($Config.ServerIP)",
        $Command
    )
    
    & ssh @sshArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "SSH 命令执行失败: $Command"
    }
}

# 上传文件
function Send-SCPFile {
    param(
        [string]$LocalPath,
        [string]$RemotePath
    )
    
    $scpArgs = @(
        "-P", $Config.ServerPort,
        "-i", $Config.SSHKey,
        "-o", "StrictHostKeyChecking=no",
        "-r",
        $LocalPath,
        "$($Config.ServerUser)@$($Config.ServerIP):$RemotePath"
    )
    
    & scp @scpArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "文件上传失败: $LocalPath"
    }
}

# 检查端口占用
function Test-PortUsage {
    Write-Log "INFO" "检查端口 $($Config.AppPort) 占用情况..."
    
    $result = Invoke-SSHCommand "netstat -tlnp 2>/dev/null | grep ':$($Config.AppPort)' | head -5 || echo '未占用'"
    
    if ($result -match "LISTEN") {
        Write-Log "WARN" "端口 $($Config.AppPort) 已被占用"
        Write-Log "INFO" "占用信息: $result"
        return $true
    }
    
    Write-Log "INFO" "端口 $($Config.AppPort) 未被占用"
    return $false
}

# 显示帮助
function Show-Help {
    @"
前后端分离博客项目自动化部署脚本 (PowerShell)

用法: .\deploy.ps1 [命令] [选项]

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

选项:
    -Help         显示帮助信息
    -Version      显示版本信息

示例:
    .\deploy.ps1                    # 执行完整部署
    .\deploy.ps1 backend           # 仅部署后端
    .\deploy.ps1 status            # 查看服务状态
"@
}

# 显示版本
function Show-Version {
    @"
部署脚本版本: 1.0.0
目标端口: $($Config.AppPort)
目标服务器: $($Config.ServerIP)
"@
}

# 显示部署信息
function Show-DeployInfo {
    Write-Log "INFO" "=========================================="
    Write-Log "INFO" "     博客项目自动化部署"
    Write-Log "INFO" "=========================================="
    Write-Log "INFO" "目标端口: $($Config.AppPort)"
    Write-Log "INFO" "目标服务器: $($Config.ServerIP)"
    Write-Log "INFO" "应用名称: $($Config.AppName)"
    Write-Log "INFO" "=========================================="
}

# 构建后端
function Build-Backend {
    Write-Log "INFO" "开始构建后端..."
    
    $backendDir = Join-Path $ProjectRoot "backend"
    Set-Location $backendDir
    
    # 修改 application.properties
    $appProps = @"
server.port=$($Config.BackendPort)
server.servlet.context-path=/

# 日志配置
logging.file.name=$($Config.RemoteLogDir)/app.log
logging.level.root=INFO
logging.level.com.example=DEBUG

# 用户数据文件路径
user.data.file=$($Config.RemoteAppDir)/users.json
"@
    
    Set-Content -Path "src\main\resources\application.properties" -Value $appProps -Encoding UTF8
    Write-Log "INFO" "已更新 application.properties"
    
    # 执行 Maven 构建
    Write-Log "INFO" "执行 Maven 构建..."
    & mvn clean package -DskipTests -q
    
    if ($LASTEXITCODE -ne 0) {
        throw "Maven 构建失败"
    }
    
    $jarPath = Join-Path $backendDir "target\$($Config.JarName)"
    if (-not (Test-Path $jarPath)) {
        throw "JAR 文件不存在: $jarPath"
    }
    
    $jarSize = (Get-Item $jarPath).Length / 1KB
    Write-Log "SUCCESS" "后端构建完成 ($([math]::Round($jarSize, 2)) KB)"
}

# 构建前端
function Build-Frontend {
    Write-Log "INFO" "开始构建前端..."
    
    $frontendDir = Join-Path $ProjectRoot "frontend"
    Set-Location $frontendDir
    
    # 修改 vite.config.js
    $viteConfig = @"
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],
  server: {
    port: $($Config.FrontendPort),
    proxy: {
      '/api': {
        target: 'http://localhost:$($Config.BackendPort)',
        changeOrigin: true
      }
    }
  },
  build: {
    outDir: 'dist',
    assetsDir: 'assets',
    sourcemap: false,
    minify: 'terser'
  }
})
"@
    
    Set-Content -Path "vite.config.js" -Value $viteConfig -Encoding UTF8
    Write-Log "INFO" "已更新 vite.config.js"
    
    # 安装依赖
    Write-Log "INFO" "安装 npm 依赖..."
    & npm ci --silent 2>$null
    if ($LASTEXITCODE -ne 0) {
        & npm install --silent
    }
    
    # 执行构建
    Write-Log "INFO" "执行生产构建..."
    & npm run build
    
    if ($LASTEXITCODE -ne 0) {
        throw "前端构建失败"
    }
    
    $distDir = Join-Path $frontendDir "dist"
    if (-not (Test-Path $distDir)) {
        throw "构建失败，dist 目录不存在"
    }
    
    $fileCount = (Get-ChildItem $distDir -Recurse -File).Count
    Write-Log "SUCCESS" "前端构建完成 ($fileCount 个文件)"
}

# 部署后端
function Deploy-Backend {
    Write-Log "INFO" "开始部署后端..."
    
    # 创建远程目录
    Invoke-SSHCommand "mkdir -p $($Config.RemoteAppDir)/backend $($Config.RemoteLogDir) $($Config.RemoteBackupDir)"
    
    # 停止现有服务
    $pid = Invoke-SSHCommand "netstat -tlnp 2>/dev/null | grep ':$($Config.AppPort)' | awk '{print `$7}' | cut -d'/' -f1 | head -1"
    if ($pid -and $pid -ne "") {
        Write-Log "INFO" "停止现有服务 (PID: $pid)..."
        Invoke-SSHCommand "kill -15 $pid 2>/dev/null || true"
        Start-Sleep -Seconds 2
    }
    
    # 上传 JAR 文件
    $localJar = Join-Path $ProjectRoot "backend\target\$($Config.JarName)"
    Write-Log "INFO" "上传 JAR 文件..."
    Send-SCPFile $localJar "$($Config.RemoteAppDir)/backend/"
    
    # 创建启动脚本
    $startScript = @"
#!/bin/bash
APP_DIR="`$(cd "`$(dirname "`$0")" && pwd)"
nohup java -jar -Xms256m -Xmx512m -XX:+UseG1GC "`$APP_DIR/$($Config.JarName)" > "$($Config.RemoteLogDir)/startup.log" 2>&1 &
echo `$! > "$($Config.RemoteTmpDir)/app.pid"
echo "应用已启动，PID: `$!"
"@
    
    $startScriptPath = Join-Path $ProjectRoot "backend\target\start-$($Config.AppPort).sh"
    Set-Content -Path $startScriptPath -Value $startScript -Encoding UTF8
    Send-SCPFile $startScriptPath "$($Config.RemoteAppDir)/backend/"
    
    # 启动服务
    Write-Log "INFO" "启动后端服务..."
    Invoke-SSHCommand "chmod +x $($Config.RemoteAppDir)/backend/*.sh && cd $($Config.RemoteAppDir)/backend && ./start-$($Config.AppPort).sh"
    
    # 等待启动
    Start-Sleep -Seconds 5
    
    # 健康检查
    Write-Log "INFO" "执行健康检查..."
    $maxAttempts = 20
    $attempt = 1
    $healthy = $false
    
    while ($attempt -le $maxAttempts -and -not $healthy) {
        $response = Invoke-SSHCommand "curl -s -o /dev/null -w '%{http_code}' http://localhost:$($Config.BackendPort)/api/users 2>/dev/null || echo '000'"
        
        if ($response -eq "200") {
            $healthy = $true
            Write-Log "SUCCESS" "后端服务启动成功"
        } else {
            Write-Log "INFO" "健康检查尝试 $attempt/$maxAttempts..."
            Start-Sleep -Seconds 3
            $attempt++
        }
    }
    
    if (-not $healthy) {
        throw "后端服务启动失败"
    }
}

# 部署前端
function Deploy-Frontend {
    Write-Log "INFO" "开始部署前端..."
    
    # 压缩前端文件
    $frontendDir = Join-Path $ProjectRoot "frontend\dist"
    $archivePath = Join-Path $ProjectRoot "frontend-$($Config.AppPort).tar.gz"
    
    Write-Log "INFO" "压缩前端文件..."
    & tar -czf $archivePath -C $frontendDir .
    
    # 上传并解压
    Write-Log "INFO" "上传前端文件..."
    Invoke-SSHCommand "mkdir -p $($Config.RemoteAppDir)/frontend && rm -rf $($Config.RemoteAppDir)/frontend/*"
    Send-SCPFile $archivePath "$($Config.RemoteTmpDir)/"
    Invoke-SSHCommand "tar -xzf $($Config.RemoteTmpDir)/frontend-$($Config.AppPort).tar.gz -C $($Config.RemoteAppDir)/frontend && rm -f $($Config.RemoteTmpDir)/frontend-$($Config.AppPort).tar.gz"
    
    # 清理本地临时文件
    Remove-Item $archivePath -ErrorAction SilentlyContinue
    
    Write-Log "SUCCESS" "前端部署完成"
}

# 配置 Nginx
function Deploy-Nginx {
    Write-Log "INFO" "配置 Nginx..."
    
    $nginxConfig = @"
# Nginx 配置 - $($Config.AppName)
upstream backend_$($Config.AppPort) {
    server 127.0.0.1:$($Config.BackendPort);
    keepalive 32;
}

server {
    listen $($Config.AppPort);
    server_name _;
    
    access_log $($Config.RemoteLogDir)/nginx-access.log;
    error_log $($Config.RemoteLogDir)/nginx-error.log warn;
    
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml;
    
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot|otf)`$ {
        root $($Config.RemoteAppDir)/frontend;
        expires 1y;
        add_header Cache-Control "public, immutable";
        access_log off;
    }
    
    location /api/ {
        proxy_pass http://backend_$($Config.AppPort);
        proxy_http_version 1.1;
        proxy_set_header Connection "";
        proxy_set_header Host ```$host;
        proxy_set_header X-Real-IP ```$remote_addr;
        proxy_set_header X-Forwarded-For ```$proxy_add_x_forwarded_for;
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
    }
    
    location / {
        root $($Config.RemoteAppDir)/frontend;
        index index.html;
        try_files ```$uri ```$uri/ /index.html;
    }
}
"@
    
    # 保存并上传配置
    $configPath = Join-Path $ProjectRoot "nginx-$($Config.AppPort).conf"
    Set-Content -Path $configPath -Value $nginxConfig -Encoding UTF8
    Send-SCPFile $configPath "$($Config.NginxConfDir)/$($Config.NginxConfName)"
    Remove-Item $configPath -ErrorAction SilentlyContinue
    
    # 重载 Nginx
    Invoke-SSHCommand "nginx -t && nginx -s reload"
    
    Write-Log "SUCCESS" "Nginx 配置完成"
}

# 执行测试
function Test-Deployment {
    Write-Log "INFO" "执行部署测试..."
    
    # 测试端口
    $portCheck = Invoke-SSHCommand "netstat -tlnp 2>/dev/null | grep ':$($Config.AppPort)' | wc -l"
    if ($portCheck -gt 0) {
        Write-Log "SUCCESS" "端口 $($Config.AppPort) 监听正常"
    } else {
        Write-Log "ERROR" "端口 $($Config.AppPort) 未监听"
    }
    
    # 测试 API
    $apiResponse = Invoke-SSHCommand "curl -s -o /dev/null -w '%{http_code}' http://localhost:$($Config.BackendPort)/api/users 2>/dev/null || echo '000'"
    if ($apiResponse -eq "200") {
        Write-Log "SUCCESS" "后端 API 测试通过"
    } else {
        Write-Log "ERROR" "后端 API 测试失败 (HTTP $apiResponse)"
    }
    
    # 测试前端
    $frontendResponse = Invoke-SSHCommand "curl -s -o /dev/null -w '%{http_code}' http://localhost:$($Config.AppPort)/ 2>/dev/null || echo '000'"
    if ($frontendResponse -eq "200") {
        Write-Log "SUCCESS" "前端页面测试通过"
    } else {
        Write-Log "ERROR" "前端页面测试失败 (HTTP $frontendResponse)"
    }
    
    Write-Log "INFO" "测试完成"
}

# 主函数
function Main {
    if ($Help) {
        Show-Help
        return
    }
    
    if ($Version) {
        Show-Version
        return
    }
    
    # 切换到项目根目录
    Set-Location $ProjectRoot
    
    switch ($Command) {
        "full" {
            Show-DeployInfo
            Build-Backend
            Build-Frontend
            Deploy-Backend
            Deploy-Frontend
            Deploy-Nginx
            Test-Deployment
            Write-Log "SUCCESS" "=========================================="
            Write-Log "SUCCESS" "     部署成功完成！"
            Write-Log "SUCCESS" "=========================================="
            Write-Log "INFO" "访问地址: http://$($Config.ServerIP):$($Config.AppPort)"
        }
        "backend" {
            Show-DeployInfo
            Build-Backend
            Deploy-Backend
        }
        "frontend" {
            Show-DeployInfo
            Build-Frontend
            Deploy-Frontend
            Deploy-Nginx
        }
        "nginx" {
            Deploy-Nginx
        }
        "test" {
            Test-Deployment
        }
        "status" {
            Invoke-SSHCommand "echo '=== 端口状态 ===' && netstat -tlnp 2>/dev/null | grep ':$($Config.AppPort)' || echo '未监听'"
            Invoke-SSHCommand "echo '=== 进程状态 ===' && ps aux | grep -E '$($Config.AppName)|$($Config.JarName)' | grep -v grep || echo '无相关进程'"
        }
        default {
            Write-Log "ERROR" "未知命令: $Command"
            Show-Help
        }
    }
}

# 执行主函数
Main
