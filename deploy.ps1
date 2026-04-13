# ========================================
# 标准化自动化部署脚本 - 博客项目 10011 实例
# ========================================
param(
    [string]$Action = "deploy",
    [switch]$Rollback
)

$INSTANCE_PORT = "10011"
$IDENTIFIER = "10013"
$SERVER_HOST = "49.235.161.106"
$SERVER_USER = "root"
$SSH_PORT = "22"

$PROJECT_ROOT = $PSScriptRoot
$BACKEND_DIR = Join-Path $PROJECT_ROOT "backend"
$FRONTEND_DIR = Join-Path $PROJECT_ROOT "frontend"
$DEPLOY_TEMP = Join-Path $PROJECT_ROOT ".deploy_$IDENTIFIER"
$DEPLOY_LOG = Join-Path $DEPLOY_TEMP "deploy_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

$REMOTE_BASE = "/opt/blog_$IDENTIFIER"
$REMOTE_BACKEND = "$REMOTE_BASE/backend"
$REMOTE_FRONTEND = "$REMOTE_BASE/frontend"
$REMOTE_LOGS = "$REMOTE_BASE/logs"
$REMOTE_TEMP = "$REMOTE_BASE/temp"
$REMOTE_NGINX = "/etc/nginx/conf.d/blog_$IDENTIFIER.conf"

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMsg = "[$timestamp] [$Level] $Message"
    Write-Host $logMsg
    Add-Content -Path $DEPLOY_LOG -Value $logMsg
}

function Invoke-RemoteCommand {
    param([string]$Command)
    $fullCmd = "ssh -p $SSH_PORT $SERVER_USER@$SERVER_HOST `"$Command`""
    Write-Log "执行远程命令: $Command"
    $output = cmd /c $fullCmd 2>&1
    return $output
}

function Test-PortAvailability {
    Write-Log "=== 端口安全检测 ==="
    $result = Invoke-RemoteCommand "netstat -tlnp 2>/dev/null | grep :$INSTANCE_PORT || echo 'not_in_use'"
    if ($result -match 'java') {
        Write-Log "检测到端口 $INSTANCE_PORT 被项目进程占用，准备安全停止"
        Stop-BackendService
    } elseif ($result -notmatch 'not_in_use') {
        Write-Log "警告: 端口 $INSTANCE_PORT 被其他进程占用，但不影响本项目启动" "WARNING"
    } else {
        Write-Log "端口 $INSTANCE_PORT 未被占用，安全"
    }
}

function Build-Frontend {
    Write-Log "=== 前端本地构建打包 ==="
    Set-Location $FRONTEND_DIR
    Write-Log "安装前端依赖..."
    npm install
    if ($LASTEXITCODE -ne 0) {
        Write-Log "前端依赖安装失败" "ERROR"
        exit 1
    }
    Write-Log "执行前端构建..."
    npm run build
    if ($LASTEXITCODE -ne 0) {
        Write-Log "前端构建失败" "ERROR"
        exit 1
    }
    $distPath = Join-Path $FRONTEND_DIR "dist"
    if (Test-Path $distPath) {
        Write-Log "前端构建成功，输出目录: $distPath"
    } else {
        Write-Log "前端构建输出目录不存在" "ERROR"
        exit 1
    }
    Set-Location $PROJECT_ROOT
}

function Build-Backend {
    Write-Log "=== 后端本地构建打包 ==="
    Set-Location $BACKEND_DIR
    Write-Log "执行 Maven 打包..."
    mvn clean package -DskipTests
    if ($LASTEXITCODE -ne 0) {
        Write-Log "后端打包失败" "ERROR"
        exit 1
    }
    $jarPath = Join-Path $BACKEND_DIR "target\user-management-1.0.0.jar"
    if (Test-Path $jarPath) {
        Write-Log "后端打包成功: $jarPath"
    } else {
        Write-Log "后端 Jar 文件不存在" "ERROR"
        exit 1
    }
    Set-Location $PROJECT_ROOT
}

function Upload-Files {
    Write-Log "=== 文件上传 ==="
    Invoke-RemoteCommand "mkdir -p $REMOTE_BACKEND $REMOTE_FRONTEND $REMOTE_LOGS $REMOTE_TEMP"
    
    Write-Log "上传后端 Jar 文件..."
    $jarFile = Join-Path $BACKEND_DIR "target\user-management-1.0.0.jar"
    scp -P $SSH_PORT $jarFile "$SERVER_USER@$SERVER_HOST`:$REMOTE_BACKEND/blog_$IDENTIFIER.jar"
    
    Write-Log "上传前端资源..."
    $distDir = Join-Path $FRONTEND_DIR "dist"
    scp -P $SSH_PORT -r "$distDir\*" "$SERVER_USER@$SERVER_HOST`:$REMOTE_FRONTEND/"
    
    Write-Log "上传服务控制脚本..."
    scp -P $SSH_PORT (Join-Path $PROJECT_ROOT "server_control.sh") "$SERVER_USER@$SERVER_HOST`:$REMOTE_BACKEND/"
    Invoke-RemoteCommand "chmod +x $REMOTE_BACKEND/server_control.sh"
    
    Write-Log "文件上传完成"
}

function Configure-Nginx {
    Write-Log "=== Nginx 配置自动写入 ==="
    $nginxConfig = @"
server {
    listen 80;
    server_name _;
    access_log $REMOTE_LOGS/nginx_access_$IDENTIFIER.log;
    error_log $REMOTE_LOGS/nginx_error_$IDENTIFIER.log;

    location /api/ {
        proxy_pass http://127.0.0.1:$INSTANCE_PORT/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_connect_timeout 60s;
        proxy_read_timeout 60s;
    }

    location / {
        root $REMOTE_FRONTEND;
        index index.html;
        try_files \$uri \$uri/ /index.html;
    }
}
"@
    $tempNginx = Join-Path $DEPLOY_TEMP "nginx_$IDENTIFIER.conf"
    $nginxConfig | Out-File -FilePath $tempNginx -Encoding utf8
    scp -P $SSH_PORT $tempNginx "$SERVER_USER@$SERVER_HOST`:$REMOTE_TEMP/nginx.conf"
    Invoke-RemoteCommand "cp $REMOTE_TEMP/nginx.conf $REMOTE_NGINX"
    
    Write-Log "验证 Nginx 配置..."
    $nginxTest = Invoke-RemoteCommand "nginx -t 2>&1"
    if ($nginxTest -match "test is successful") {
        Write-Log "Nginx 配置验证通过"
        Invoke-RemoteCommand "nginx -s reload"
        Write-Log "Nginx 重载完成"
    } else {
        Write-Log "Nginx 配置验证失败: $nginxTest" "ERROR"
        exit 1
    }
}

function Start-BackendService {
    Write-Log "=== 后端优雅启动 ==="
    $startCmd = @"
cd $REMOTE_BACKEND
nohup java -jar -Dserver.port=$INSTANCE_PORT \
    -Dlogging.file.name=$REMOTE_LOGS/backend_$IDENTIFIER.log \
    blog_$IDENTIFIER.jar > $REMOTE_LOGS/nohup_$IDENTIFIER.out 2>&1 &
echo \$! > $REMOTE_BACKEND/pid_$IDENTIFIER
"@
    Invoke-RemoteCommand $startCmd
    Write-Log "后端启动命令已执行，等待服务就绪..."
    
    $maxRetries = 30
    for ($i = 1; $i -le $maxRetries; $i++) {
        Start-Sleep -Seconds 2
        $healthCheck = Invoke-RemoteCommand "curl -s http://127.0.0.1:$INSTANCE_PORT/api/users 2>/dev/null || echo 'FAIL'"
        if ($healthCheck -notmatch 'FAIL') {
            Write-Log "后端服务启动成功，耗时 $($i*2) 秒"
            return $true
        }
        Write-Log "健康检查中... ($i/$maxRetries)"
    }
    Write-Log "后端服务启动超时" "ERROR"
    return $false
}

function Stop-BackendService {
    Write-Log "=== 后端安全停止 ==="
    $pidFile = "$REMOTE_BACKEND/pid_$IDENTIFIER"
    $pidCheck = Invoke-RemoteCommand "cat $pidFile 2>/dev/null || echo ''"
    
    if ($pidCheck -match '^\d+$') {
        Write-Log "找到进程 PID: $pidCheck，发送优雅停止信号"
        Invoke-RemoteCommand "kill -TERM $pidCheck 2>/dev/null || true"
        
        for ($i = 1; $i -le 15; $i++) {
            Start-Sleep -Seconds 1
            $running = Invoke-RemoteCommand "ps -p $pidCheck -o pid= 2>/dev/null || echo ''"
            if (-not $running) {
                Write-Log "进程已优雅停止"
                Invoke-RemoteCommand "rm -f $pidFile"
                return $true
            }
        }
        Write-Log "优雅停止超时，强制终止" "WARNING"
        Invoke-RemoteCommand "kill -9 $pidCheck 2>/dev/null || true"
    } else {
        Write-Log "未找到 PID 文件，尝试端口方式停止"
        Invoke-RemoteCommand "fuser -k -TERM $INSTANCE_PORT/tcp 2>/dev/null || true"
    }
    Start-Sleep -Seconds 2
    return $true
}

function Show-BackendLogs {
    Write-Log "=== 后端日志实时查看（最后 50 行） ==="
    $logContent = Invoke-RemoteCommand "tail -50 $REMOTE_LOGS/backend_$IDENTIFIER.log 2>/dev/null || echo '日志文件暂未生成'"
    Write-Host $logContent
}

function Test-Connectivity {
    Write-Log "=== 连通性测试 ==="
    $testResults = @{}
    
    Write-Log "测试后端接口连通性..."
    $apiTest = Invoke-RemoteCommand "curl -s -w '%{http_code}' http://127.0.0.1:$INSTANCE_PORT/api/users -o /dev/null 2>/dev/null || echo '000'"
    $testResults["Backend_API"] = if ($apiTest -eq '200') { "PASS (HTTP 200)" } else { "FAIL (HTTP $apiTest)" }
    
    Write-Log "测试 Nginx 代理连通性..."
    $nginxTest = Invoke-RemoteCommand "curl -s -w '%{http_code}' http://127.0.0.1/api/users -o /dev/null 2>/dev/null || echo '000'"
    $testResults["Nginx_Proxy"] = if ($nginxTest -eq '200') { "PASS (HTTP 200)" } else { "FAIL (HTTP $nginxTest)" }
    
    Write-Log "测试前端页面访问..."
    $frontTest = Invoke-RemoteCommand "curl -s -w '%{http_code}' http://127.0.0.1/ -o /dev/null 2>/dev/null || echo '000'"
    $testResults["Frontend_Page"] = if ($frontTest -eq '200') { "PASS (HTTP 200)" } else { "FAIL (HTTP $frontTest)" }
    
    return $testResults
}

function Generate-Report {
    param($Results)
    Write-Log "`n========================================"
    Write-Log "          部 署 报 告"
    Write-Log "========================================"
    Write-Log "实例标识: $IDENTIFIER"
    Write-Log "后端端口: $INSTANCE_PORT"
    Write-Log "部署时间: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Log "部署服务器: $SERVER_HOST"
    Write-Log "----------------------------------------"
    Write-Log "测试结果:"
    foreach ($key in $Results.Keys) {
        $status = if ($Results[$key] -match 'PASS') { "✓" } else { "✗" }
        Write-Log "  $status $key : $($Results[$key])"
    }
    Write-Log "----------------------------------------"
    Write-Log "相关路径:"
    Write-Log "  应用根目录: $REMOTE_BASE"
    Write-Log "  日志目录: $REMOTE_LOGS"
    Write-Log "  Nginx 配置: $REMOTE_NGINX"
    Write-Log "----------------------------------------"
    $allPass = ($Results.Values | Where-Object { $_ -match 'PASS' } | Measure-Object).Count -eq $Results.Count
    if ($allPass) {
        Write-Log "部署结果: ✓ 全部测试通过，部署成功！" "SUCCESS"
        Write-Log "回滚标记: deploy_$(Get-Date -Format 'yyyyMMdd_HHmmss') - 可用于回滚"
    } else {
        Write-Log "部署结果: ✗ 部分测试失败，请检查日志" "ERROR"
        Write-Log "回滚命令: .\deploy.ps1 -Rollback -RollbackTag 'PREVIOUS'"
    }
    Write-Log "========================================`n"
}

function Invoke-Rollback {
    Write-Log "=== 执行回滚 ==="
    Write-Log "停止当前服务..."
    Stop-BackendService
    Write-Log "回滚操作完成（需配合备份机制实现完整回滚）" "WARNING"
}

# 主流程
New-Item -ItemType Directory -Path $DEPLOY_TEMP -Force | Out-Null
Write-Log "========================================"
Write-Log "博客项目自动化部署脚本启动"
Write-Log "========================================"

if ($Rollback) {
    Invoke-Rollback
    exit 0
}

switch ($Action) {
    "deploy" {
        Test-PortAvailability
        Build-Frontend
        Build-Backend
        Upload-Files
        Configure-Nginx
        $startSuccess = Start-BackendService
        Show-BackendLogs
        $results = Test-Connectivity
        Generate-Report $results
    }
    "start" {
        Start-BackendService
        Show-BackendLogs
    }
    "stop" {
        Stop-BackendService
    }
    "logs" {
        Show-BackendLogs
    }
    "test" {
        $results = Test-Connectivity
        Generate-Report $results
    }
    default {
        Write-Log "未知操作: $Action" "ERROR"
        Write-Log "可用操作: deploy, start, stop, logs, test"
        exit 1
    }
}
