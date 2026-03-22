package beidanci.service.controller;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;


public class AdminImageReviewTask {
    public boolean isRunning = false;
    public int totalImages = 0;
    public int currentIndex = 0;
    public boolean autoDelete = false;
    public String dictId = "";
    
    public List<Map<String, Object>> deletedImages = new ArrayList<>();
    public List<Map<String, Object>> markedImages = new ArrayList<>();
    
    public String statusMsg = "任务未启动";

    public synchronized void reset() {
        isRunning = true;
        totalImages = 0;
        currentIndex = 0;
        deletedImages.clear();
        markedImages.clear();
        statusMsg = "初始化中...";
    }
}
