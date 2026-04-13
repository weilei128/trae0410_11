package com.example.usermanagement.controller;

import com.example.usermanagement.model.User;
import com.example.usermanagement.util.JsonFileUtil;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.*;

import java.util.Comparator;
import java.util.List;
import java.util.Optional;

@RestController
@RequestMapping("/api/users")
@CrossOrigin(origins = "*")
public class UserController {

    @Autowired
    private JsonFileUtil jsonFileUtil;

    @GetMapping
    public List<User> getAllUsers() {
        return jsonFileUtil.readUsers();
    }

    @GetMapping("/{id}")
    public User getUserById(@PathVariable Long id) {
        List<User> users = jsonFileUtil.readUsers();
        return users.stream()
                .filter(u -> u.getId().equals(id))
                .findFirst()
                .orElse(null);
    }

    @PostMapping
    public User createUser(@RequestBody User user) {
        List<User> users = jsonFileUtil.readUsers();
        Long maxId = users.stream()
                .mapToLong(User::getId)
                .max()
                .orElse(0L);
        user.setId(maxId + 1);
        users.add(user);
        jsonFileUtil.writeUsers(users);
        return user;
    }

    @PutMapping("/{id}")
    public User updateUser(@PathVariable Long id, @RequestBody User userDetails) {
        List<User> users = jsonFileUtil.readUsers();
        Optional<User> userOptional = users.stream()
                .filter(u -> u.getId().equals(id))
                .findFirst();
        
        if (userOptional.isPresent()) {
            User user = userOptional.get();
            user.setName(userDetails.getName());
            user.setAge(userDetails.getAge());
            user.setEmail(userDetails.getEmail());
            jsonFileUtil.writeUsers(users);
            return user;
        }
        return null;
    }

    @DeleteMapping("/{id}")
    public void deleteUser(@PathVariable Long id) {
        List<User> users = jsonFileUtil.readUsers();
        users.removeIf(u -> u.getId().equals(id));
        jsonFileUtil.writeUsers(users);
    }
}
