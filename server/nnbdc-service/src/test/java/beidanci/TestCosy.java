package beidanci;

import org.junit.jupiter.api.Test;
import com.alibaba.dashscope.audio.tts.SpeechSynthesisParam;
import com.alibaba.dashscope.audio.tts.SpeechSynthesizer;

public class TestCosy {
    @Test
    public void testVoices() {
        String apiKey = System.getenv("DASHSCOPE_API_KEY");
        if (apiKey == null) {
            // Read application.yml manually
            try {
                String yml = new String(java.nio.file.Files.readAllBytes(java.nio.file.Paths.get("src/main/resources/application.yml")));
                for (String line : yml.split("\n")) {
                    if (line.contains("api-key:")) {
                        apiKey = line.split(":")[1].trim();
                        break;
                    }
                }
            } catch (Exception e) {}
        }
        System.out.println("API Key: " + (apiKey != null ? "Found" : "Missing"));

        String[] testVoices = {
            "longniuniu", "longniuniu_v3",
            "longhuhu", "longhuhu_v3",
            "longxiaobai", "longxiaobai_v3",
            "longxiaocheng", "longxiaocheng_v3",
            "longxiaomeng", "longxiaomeng_v3",
            "longxiaotong", "longxiaotong_v3",
            "longjielidou", "longjielidou_v3"
        };
        
        SpeechSynthesizer synthesizer = new SpeechSynthesizer();
        for (String v : testVoices) {
            System.out.print("Testing " + v + "... ");
            try {
                SpeechSynthesisParam param = SpeechSynthesisParam.builder()
                        .apiKey(apiKey)
                        .model("cosyvoice-v3-flash")
                        .parameter("voice", v)
                        .parameter("format", "mp3")
                        .text("Hello world")
                        .build();
                synthesizer.call(param);
                System.out.println("SUCCESS!");
            } catch (Exception e) {
                System.out.println("FAILED: " + e.getMessage());
            }
        }
    }
}
