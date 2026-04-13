#!/bin/bash
# ============================================================
# 前端构建脚本
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../config/env.sh"
source "${SCRIPT_DIR}/utils.sh"

log "INFO" "=========================================="
log "INFO" "开始前端构建 - 端口 ${APP_PORT}"
log "INFO" "=========================================="

# 进入前端目录
cd "${SCRIPT_DIR}/../../frontend" || {
    log "ERROR" "无法进入前端目录"
    exit 1
}

# 检查 Node.js 环境
log "INFO" "检查 Node.js 环境..."
if ! command -v node &> /dev/null; then
    log "ERROR" "Node.js 未安装"
    exit 1
fi

NODE_VERSION=$(node -v)
NPM_VERSION=$(npm -v)
log "INFO" "Node.js: ${NODE_VERSION}, npm: ${NPM_VERSION}"

# 安装依赖
log "INFO" "安装 npm 依赖..."
npm ci --silent || npm install --silent

# 修改 vite.config.js 使用正确的后端端口
log "INFO" "配置 API 代理..."
cat > vite.config.js << EOF
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],
  server: {
    port: ${FRONTEND_PORT},
    proxy: {
      '/api': {
        target: 'http://localhost:${BACKEND_PORT}',
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
EOF

# 执行构建
log "INFO" "执行生产构建..."
npm run build

# 检查构建结果
if [ ! -d "dist" ]; then
    log "ERROR" "构建失败，dist 目录不存在"
    exit 1
fi

if [ ! -f "dist/index.html" ]; then
    log "ERROR" "构建失败，index.html 不存在"
    exit 1
fi

# 压缩构建产物
log "INFO" "压缩构建产物..."
BUILD_ARCHIVE="${SCRIPT_DIR}/../tmp/frontend-${APP_PORT}-$(date +%Y%m%d-%H%M%S).tar.gz"
mkdir -p "$(dirname "$BUILD_ARCHIVE")"
tar -czf "$BUILD_ARCHIVE" -C dist .

FILE_SIZE=$(du -h "$BUILD_ARCHIVE" | cut -f1)
log "SUCCESS" "前端构建完成: ${FILE_SIZE}"
log "INFO" "构建产物: ${BUILD_ARCHIVE}"

# 输出构建信息
FILE_COUNT=$(find dist -type f | wc -l)
log "INFO" "文件数量: ${FILE_COUNT}"

echo "$BUILD_ARCHIVE"
