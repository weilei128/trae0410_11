import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],
  server: {
    port: 10022,
    proxy: {
      '/api': {
        target: 'http://localhost:10021',
        changeOrigin: true
      }
    }
  }
})
