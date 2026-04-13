# ========================================
# 本地启动测试脚本
# ========================================
$INSTANCE_PORT = "10011"
$PROJECT_ROOT = $PSScriptRoot

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "    博客项目本地启动测试" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`n[1] 检查端口占用..." -ForegroundColor Yellow
$portCheck = Get-NetTCPConnection -LocalPort $INSTANCE_PORT -ErrorAction SilentlyContinue
if ($portCheck) {
    Write-Host "    端口 $INSTANCE_PORT 被占用，尝试终止相关进程..." -ForegroundColor Yellow
    $ownerPid = $portCheck.OwningProcess
    Get-Process -Id $ownerPid -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-Host "    已终止进程 PID: $ownerPid" -ForegroundColor Green
} else {
    Write-Host "    端口 $INSTANCE_PORT 可用" -ForegroundColor Green
}

Write-Host "`n[2] 启动后端服务..." -ForegroundColor Yellow
$backendJar = Join-Path $PROJECT_ROOT "backend\target\user-management-1.0.0.jar"
if (-not (Test-Path $backendJar)) {
    Write-Host "    后端 Jar 文件不存在，先执行打包..." -ForegroundColor Yellow
    Set-Location (Join-Path $PROJECT_ROOT "backend")
    mvn clean package -DskipTests
    Set-Location $PROJECT_ROOT
}

Write-Host "    启动后端服务（后台运行）..." -ForegroundColor Yellow
$javaProcess = Start-Process -FilePath "java" -ArgumentList "-jar", $backendJar `
    -RedirectStandardOutput (Join-Path $PROJECT_ROOT "backend_stdout.log") `
    -RedirectStandardError (Join-Path $PROJECT_ROOT "backend_stderr.log") `
    -PassThru -NoNewWindow

Write-Host "    后端服务 PID: $($javaProcess.Id)" -ForegroundColor Green
Write-Host "    等待服务启动（最多 60 秒）..." -ForegroundColor Yellow

$maxRetries = 30
$started = $false
for ($i = 1; $i -le $maxRetries; $i++) {
    Start-Sleep -Seconds 2
    try {
        $response = Invoke-WebRequest -Uri "http://localhost:$INSTANCE_PORT/api/users" -Method Get -TimeoutSec 5 -UseBasicParsing
        if ($response.StatusCode -eq 200) {
            Write-Host "`n    ✓ 后端服务启动成功！" -ForegroundColor Green
            Write-Host "    ✓ API 测试通过: GET /api/users => HTTP $($response.StatusCode)" -ForegroundColor Green
            Write-Host "    ✓ 响应数据: $($response.Content)" -ForegroundColor Green
            $started = $true
            break
        }
    } catch {
        Write-Host "    等待中... ($i/$maxRetries)" -ForegroundColor Gray
    }
}

if (-not $started) {
    Write-Host "`n    ✗ 服务启动超时，查看日志:" -ForegroundColor Red
    Get-Content (Join-Path $PROJECT_ROOT "backend_stderr.log") -Tail 20
    Stop-Process -Id $javaProcess.Id -Force -ErrorAction SilentlyContinue
    exit 1
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "    本地测试启动成功！" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "`n服务信息:"
Write-Host "  - 后端地址: http://localhost:$INSTANCE_PORT"
Write-Host "  - API 接口: http://localhost:$INSTANCE_PORT/api/users"
Write-Host "  - 进程 PID: $($javaProcess.Id)"
Write-Host "  - 进程名: java.exe"
Write-Host "`n停止命令: Stop-Process -Id $($javaProcess.Id) -Force"
Write-Host "`n按任意键停止服务并退出..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

Write-Host "`n停止后端服务..." -ForegroundColor Yellow
Stop-Process -Id $javaProcess.Id -Force -ErrorAction SilentlyContinue
Write-Host "服务已停止" -ForegroundColor Green
