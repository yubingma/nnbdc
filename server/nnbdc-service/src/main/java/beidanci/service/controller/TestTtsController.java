package beidanci.service.controller;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import beidanci.service.bo.AiBo;

@RestController
public class TestTtsController {
    @Autowired
    private AiBo aiBo;

    @GetMapping("/testTts")
    public String testTts(@RequestParam String voice) {
        try {
            aiBo.generateSpeech("Hello world", voice);
            return "SUCCESS: " + voice;
        } catch (Exception e) {
            return "FAILED: " + e.getMessage();
        }
    }
}
