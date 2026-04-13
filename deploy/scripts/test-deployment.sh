#!/bin/bash
# ============================================================
# 部署测试脚本
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config/env.sh"
source "${SCRIPT_DIR}/utils.sh"

# 测试报告
REPORT_FILE="${SCRIPT_DIR}/../logs/test-report-${APP_PORT}-$(date +%Y%m%d-%H%M%S).txt"

# 记录测试结果
record_result() {
    local test_name="$1"
    local result="$2"
    local details="${3:-}"
    
    echo "[$(date '+%H:%M:%S')] ${test_name}: ${result}" >> "$REPORT_FILE"
    if [ -n "$details" ]; then
        echo "  详情: ${details}" >> "$REPORT_FILE"
    fi
    echo "" >> "$REPORT_FILE"
}

# 测试后端 API
test_backend_api() {
    log "INFO" "测试后端 API..."
    
    local test_url="http://${SERVER_IP}:${APP_PORT}/api/users"
    local response=$(remote_exec "curl -s -w '\\nHTTP_CODE:%{http_code}' ${test_url} 2>/dev/null || echo 'HTTP_CODE:000'")
    
    local http_code=$(echo "$response" | grep "HTTP_CODE:" | cut -d':' -f2)
    local body=$(echo "$response" | grep -v "HTTP_CODE:")
    
    if [ "$http_code" = "200" ]; then
        log "SUCCESS" "后端 API 测试通过 (HTTP ${http_code})"
        record_result "后端 API 测试" "通过" "URL: ${test_url}, 响应: ${body:0:100}"
        return 0
    else
        log "ERROR" "后端 API 测试失败 (HTTP ${http_code})"
        record_result "后端 API 测试" "失败" "URL: ${test_url}, HTTP 状态码: ${http_code}"
        return 1
    fi
}

# 测试前端页面
test_frontend_page() {
    log "INFO" "测试前端页面..."
    
    local test_url="http://${SERVER_IP}:${APP_PORT}/"
    local response=$(curl -s -w '\nHTTP_CODE:%{http_code}' --max-time 10 "${test_url}" 2>/dev/null || echo 'HTTP_CODE:000')
    
    local http_code=$(echo "$response" | grep "HTTP_CODE:" | cut -d':' -f2)
    local body=$(echo "$response" | grep -v "HTTP_CODE:")
    
    if [ "$http_code" = "200" ] && echo "$body" | grep -q "html"; then
        log "SUCCESS" "前端页面测试通过 (HTTP ${http_code})"
        record_result "前端页面测试" "通过" "URL: ${test_url}"
        return 0
    else
        log "ERROR" "前端页面测试失败 (HTTP ${http_code})"
        record_result "前端页面测试" "失败" "URL: ${test_url}, HTTP 状态码: ${http_code}"
        return 1
    fi
}

# 测试 Nginx 配置
test_nginx_config() {
    log "INFO" "测试 Nginx 配置..."
    
    local test_result=$(remote_exec "nginx -t 2>&1")
    
    if echo "$test_result" | grep -q "successful"; then
        log "SUCCESS" "Nginx 配置测试通过"
        record_result "Nginx 配置测试" "通过"
        return 0
    else
        log "ERROR" "Nginx 配置测试失败"
        record_result "Nginx 配置测试" "失败" "${test_result}"
        return 1
    fi
}

# 测试端口监听
test_port_listening() {
    log "INFO" "测试端口监听..."
    
    local port_check=$(remote_exec "netstat -tlnp 2>/dev/null | grep ':${APP_PORT}' | wc -l")
    
    if [ "$port_check" -gt 0 ]; then
        log "SUCCESS" "端口 ${APP_PORT} 监听正常"
        local listeners=$(remote_exec "netstat -tlnp 2>/dev/null | grep ':${APP_PORT}' | awk '{print \$7}'")
        record_result "端口监听测试" "通过" "端口: ${APP_PORT}, 监听进程: ${listeners}"
        return 0
    else
        log "ERROR" "端口 ${APP_PORT} 未监听"
        record_result "端口监听测试" "失败" "端口: ${APP_PORT}"
        return 1
    fi
}

# 测试服务健康状态
test_health_check() {
    log "INFO" "测试服务健康状态..."
    
    local health_url="http://${SERVER_IP}:${APP_PORT}/api/users"
    local max_attempts=5
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local response=$(remote_exec "curl -s -o /dev/null -w '%{http_code}' ${health_url} 2>/dev/null || echo '000'")
        
        if [ "$response" = "200" ]; then
            log "SUCCESS" "服务健康检查通过"
            record_result "服务健康检查" "通过" "尝试次数: ${attempt}"
            return 0
        fi
        
        log "INFO" "健康检查尝试 ${attempt}/${max_attempts} 失败 (HTTP ${response})，等待重试..."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    log "ERROR" "服务健康检查失败"
    record_result "服务健康检查" "失败" "最大尝试次数: ${max_attempts}"
    return 1
}

# 测试静态资源
test_static_resources() {
    log "INFO" "测试静态资源访问..."
    
    local static_urls=(
        "http://${SERVER_IP}:${APP_PORT}/index.html"
    )
    
    local all_passed=true
    for url in "${static_urls[@]}"; do
        local response=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$url" 2>/dev/null || echo '000')
        
        if [ "$response" = "200" ]; then
            log "INFO" "  ✓ ${url} (HTTP ${response})"
        else
            log "WARN" "  ✗ ${url} (HTTP ${response})"
            all_passed=false
        fi
    done
    
    if [ "$all_passed" = true ]; then
        record_result "静态资源测试" "通过"
        return 0
    else
        record_result "静态资源测试" "部分失败"
        return 1
    fi
}

# 生成测试报告
generate_report() {
    log "INFO" "生成测试报告..."
    
    local total_tests=0
    local passed_tests=0
    local failed_tests=0
    
    # 统计结果
    while IFS= read -r line; do
        if [[ "$line" == *": 通过"* ]]; then
            passed_tests=$((passed_tests + 1))
            total_tests=$((total_tests + 1))
        elif [[ "$line" == *": 失败"* ]]; then
            failed_tests=$((failed_tests + 1))
            total_tests=$((total_tests + 1))
        fi
    done < "$REPORT_FILE"
    
    # 添加报告头部
    local temp_file="${REPORT_FILE}.tmp"
    {
        echo "=========================================="
        echo "    部署测试报告"
        echo "=========================================="
        echo "测试时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "目标服务器: ${SERVER_IP}:${APP_PORT}"
        echo "应用名称: ${APP_NAME}"
        echo "=========================================="
        echo ""
        echo "测试统计:"
        echo "  总测试数: ${total_tests}"
        echo "  通过: ${passed_tests}"
        echo "  失败: ${failed_tests}"
        echo "  通过率: $(( passed_tests * 100 / total_tests ))%"
        echo ""
        echo "详细结果:"
        echo "------------------------------------------"
        echo ""
        cat "$REPORT_FILE"
        echo ""
        echo "=========================================="
        if [ $failed_tests -eq 0 ]; then
            echo "结论: 所有测试通过 ✓"
        else
            echo "结论: 存在失败的测试 ✗"
        fi
        echo "=========================================="
    } > "$temp_file"
    
    mv "$temp_file" "$REPORT_FILE"
    
    # 显示报告
    cat "$REPORT_FILE"
    
    log "INFO" "测试报告已保存: ${REPORT_FILE}"
    
    # 返回测试结果
    if [ $failed_tests -eq 0 ]; then
        return 0
    else
        return 1
    fi
}

# 执行所有测试
run_all_tests() {
    log "INFO" "=========================================="
    log "INFO" "开始部署测试 - 端口 ${APP_PORT}"
    log "INFO" "=========================================="
    
    mkdir -p "$(dirname "$REPORT_FILE")"
    
    local failed=0
    
    # 执行各项测试
    test_port_listening || failed=$((failed + 1))
    test_nginx_config || failed=$((failed + 1))
    test_health_check || failed=$((failed + 1))
    test_backend_api || failed=$((failed + 1))
    test_frontend_page || failed=$((failed + 1))
    test_static_resources || failed=$((failed + 1))
    
    # 生成报告
    generate_report
    local report_result=$?
    
    log "INFO" "=========================================="
    if [ $report_result -eq 0 ]; then
        log "SUCCESS" "所有测试通过！"
    else
        log "ERROR" "部分测试失败，请查看报告"
    fi
    log "INFO" "=========================================="
    
    return $report_result
}

# 主函数
case "${1:-}" in
    api)
        test_backend_api
        ;;
    frontend)
        test_frontend_page
        ;;
    nginx)
        test_nginx_config
        ;;
    port)
        test_port_listening
        ;;
    health)
        test_health_check
        ;;
    static)
        test_static_resources
        ;;
    all|"")
        run_all_tests
        ;;
    *)
        echo "用法: $0 {api|frontend|nginx|port|health|static|all}"
        exit 1
        ;;
esac
