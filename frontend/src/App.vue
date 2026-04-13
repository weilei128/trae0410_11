<template>
  <div id="app">
    <div class="container">
      <h1>用户信息管理</h1>
      
      <div class="toolbar">
        <button @click="showAddModal" class="btn btn-primary">添加用户</button>
      </div>
      
      <table class="user-table">
        <thead>
          <tr>
            <th>ID</th>
            <th>姓名</th>
            <th>年龄</th>
            <th>邮箱</th>
            <th>操作</th>
          </tr>
        </thead>
        <tbody>
          <tr v-for="user in users" :key="user.id">
            <td>{{ user.id }}</td>
            <td>{{ user.name }}</td>
            <td>{{ user.age }}</td>
            <td>{{ user.email }}</td>
            <td>
              <button @click="showEditModal(user)" class="btn btn-edit">编辑</button>
              <button @click="deleteUser(user.id)" class="btn btn-danger">删除</button>
            </td>
          </tr>
          <tr v-if="users.length === 0">
            <td colspan="5" class="empty-message">暂无用户数据</td>
          </tr>
        </tbody>
      </table>
      
      <div v-if="showModal" class="modal-overlay" @click.self="closeModal">
        <div class="modal">
          <h2>{{ isEdit ? '编辑用户' : '添加用户' }}</h2>
          <form @submit.prevent="submitForm">
            <div class="form-group">
              <label>姓名:</label>
              <input v-model="formData.name" type="text" required />
            </div>
            <div class="form-group">
              <label>年龄:</label>
              <input v-model.number="formData.age" type="number" required />
            </div>
            <div class="form-group">
              <label>邮箱:</label>
              <input v-model="formData.email" type="email" required />
            </div>
            <div class="modal-actions">
              <button type="submit" class="btn btn-primary">{{ isEdit ? '保存' : '添加' }}</button>
              <button type="button" @click="closeModal" class="btn btn-secondary">取消</button>
            </div>
          </form>
        </div>
      </div>
    </div>
  </div>
</template>

<script>
import userApi from './api/userApi'

export default {
  name: 'App',
  data() {
    return {
      users: [],
      showModal: false,
      isEdit: false,
      formData: {
        id: null,
        name: '',
        age: null,
        email: ''
      }
    }
  },
  mounted() {
    this.loadUsers()
  },
  methods: {
    async loadUsers() {
      try {
        const response = await userApi.getAllUsers()
        this.users = response.data
      } catch (error) {
        console.error('加载用户列表失败:', error)
      }
    },
    
    showAddModal() {
      this.isEdit = false
      this.formData = { id: null, name: '', age: null, email: '' }
      this.showModal = true
    },
    
    showEditModal(user) {
      this.isEdit = true
      this.formData = { ...user }
      this.showModal = true
    },
    
    closeModal() {
      this.showModal = false
    },
    
    async submitForm() {
      try {
        if (this.isEdit) {
          await userApi.updateUser(this.formData.id, this.formData)
        } else {
          await userApi.createUser(this.formData)
        }
        this.closeModal()
        this.loadUsers()
      } catch (error) {
        console.error('保存用户失败:', error)
      }
    },
    
    async deleteUser(id) {
      if (confirm('确定要删除该用户吗？')) {
        try {
          await userApi.deleteUser(id)
          this.loadUsers()
        } catch (error) {
          console.error('删除用户失败:', error)
        }
      }
    }
  }
}
</script>

<style>
* {
  margin: 0;
  padding: 0;
  box-sizing: border-box;
}

body {
  font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
  background-color: #f5f5f5;
}

.container {
  max-width: 1000px;
  margin: 0 auto;
  padding: 20px;
}

h1 {
  text-align: center;
  margin-bottom: 30px;
  color: #333;
}

.toolbar {
  margin-bottom: 20px;
}

.btn {
  padding: 8px 16px;
  border: none;
  border-radius: 4px;
  cursor: pointer;
  font-size: 14px;
  margin-right: 8px;
}

.btn-primary {
  background-color: #409eff;
  color: white;
}

.btn-primary:hover {
  background-color: #66b1ff;
}

.btn-edit {
  background-color: #67c23a;
  color: white;
}

.btn-edit:hover {
  background-color: #85ce61;
}

.btn-danger {
  background-color: #f56c6c;
  color: white;
}

.btn-danger:hover {
  background-color: #f78989;
}

.btn-secondary {
  background-color: #909399;
  color: white;
}

.btn-secondary:hover {
  background-color: #a6a9ad;
}

.user-table {
  width: 100%;
  border-collapse: collapse;
  background: white;
  box-shadow: 0 2px 12px rgba(0, 0, 0, 0.1);
  border-radius: 4px;
  overflow: hidden;
}

.user-table th,
.user-table td {
  padding: 12px;
  text-align: left;
  border-bottom: 1px solid #ebeef5;
}

.user-table th {
  background-color: #f5f7fa;
  color: #606266;
  font-weight: 600;
}

.user-table tr:hover {
  background-color: #f5f7fa;
}

.empty-message {
  text-align: center;
  color: #909399;
  padding: 40px;
}

.modal-overlay {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background-color: rgba(0, 0, 0, 0.5);
  display: flex;
  justify-content: center;
  align-items: center;
  z-index: 1000;
}

.modal {
  background: white;
  padding: 24px;
  border-radius: 8px;
  width: 400px;
  max-width: 90%;
}

.modal h2 {
  margin-bottom: 20px;
  color: #333;
}

.form-group {
  margin-bottom: 16px;
}

.form-group label {
  display: block;
  margin-bottom: 8px;
  color: #606266;
  font-weight: 500;
}

.form-group input {
  width: 100%;
  padding: 10px;
  border: 1px solid #dcdfe6;
  border-radius: 4px;
  font-size: 14px;
}

.form-group input:focus {
  outline: none;
  border-color: #409eff;
}

.modal-actions {
  margin-top: 24px;
  text-align: right;
}

.modal-actions .btn {
  margin-left: 8px;
  margin-right: 0;
}
</style>
