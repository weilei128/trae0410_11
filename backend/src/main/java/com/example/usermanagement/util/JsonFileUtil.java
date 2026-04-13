package com.example.usermanagement.util;

import com.example.usermanagement.model.User;
import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.core.io.ClassPathResource;
import org.springframework.stereotype.Component;

import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;
import java.util.ArrayList;
import java.util.List;

@Component
public class JsonFileUtil {
    
    private final ObjectMapper objectMapper = new ObjectMapper();
    private File jsonFile;

    private File getJsonFile() throws IOException {
        if (jsonFile == null || !jsonFile.exists()) {
            ClassPathResource resource = new ClassPathResource("users.json");
            InputStream inputStream = resource.getInputStream();
            
            File tempFile = File.createTempFile("users", ".json");
            Files.copy(inputStream, tempFile.toPath(), StandardCopyOption.REPLACE_EXISTING);
            inputStream.close();
            
            this.jsonFile = tempFile;
        }
        return jsonFile;
    }

    public List<User> readUsers() {
        try {
            File file = getJsonFile();
            if (file.length() == 0) {
                return new ArrayList<>();
            }
            return objectMapper.readValue(file, new TypeReference<List<User>>() {});
        } catch (IOException e) {
            e.printStackTrace();
            return new ArrayList<>();
        }
    }

    public void writeUsers(List<User> users) {
        try {
            File file = getJsonFile();
            objectMapper.writerWithDefaultPrettyPrinter().writeValue(file, users);
        } catch (IOException e) {
            e.printStackTrace();
        }
    }
}
