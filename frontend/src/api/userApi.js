import axios from 'axios'

const API_BASE_URL = '/api/users'

export default {
  getAllUsers() {
    return axios.get(API_BASE_URL)
  },
  
  getUserById(id) {
    return axios.get(`${API_BASE_URL}/${id}`)
  },
  
  createUser(user) {
    return axios.post(API_BASE_URL, user)
  },
  
  updateUser(id, user) {
    return axios.put(`${API_BASE_URL}/${id}`, user)
  },
  
  deleteUser(id) {
    return axios.delete(`${API_BASE_URL}/${id}`)
  }
}
