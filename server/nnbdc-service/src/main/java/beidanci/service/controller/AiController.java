package beidanci.service.controller;

import java.util.List;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import com.fasterxml.jackson.databind.ObjectMapper;
import beidanci.api.Result;
import beidanci.service.bo.AiBo;

@RestController
public class AiController {

    @Autowired
    private AiBo aiBo;

    private static final ObjectMapper mapper = new ObjectMapper();

    /**
     * 根据单词列表生成小短文
     * @param wordsJson JSON array of word spells
     * @return 生成的小短文
     */
    @PostMapping("/generateAiShortStory.do")
    public Result<String> generateAiShortStory(@RequestParam("wordsJson") String wordsJson) {
        try {
            List<String> words = mapper.readValue(wordsJson, mapper.getTypeFactory().constructCollectionType(List.class, String.class));
            String story = aiBo.generateShortStory(words);
            return Result.success(story);
        } catch (Exception e) {
            return Result.fail("获取 AI 短文失败: " + e.getMessage());
        }
    }
}
