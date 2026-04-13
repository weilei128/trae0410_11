#!/bin/bash
# 部署测试报告脚本

echo '========================================'
echo '       部署测试报告'
echo '========================================'
echo ''
echo '1. 端口监听测试:'
netstat -tlnp | grep -E '10013|10014'
echo ''
echo '2. API 连通性测试:'
curl -s http://localhost:10013/api/users
echo ''
echo ''
echo '3. 前端页面测试:'
HTTP_CODE=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:10013/)
echo "HTTP 状态码: ${HTTP_CODE}"
if [ "${HTTP_CODE}" = "200" ]; then
    echo '✓ 前端访问正常'
else
    echo '✗ 前端访问异常'
fi
echo ''
echo '4. Nginx 配置测试:'
nginx -t 2>&1 | head -2
echo ''
echo '5. 进程状态:'
ps aux | grep -E 'nginx|user-management' | grep -v grep
echo ''
echo '========================================'
echo '访问地址: http://49.235.161.106:10013'
echo '========================================'
