package beidanci;

import org.junit.jupiter.api.Test;
import com.alibaba.dashscope.audio.tts.SpeechSynthesisParam;
import com.alibaba.dashscope.audio.tts.SpeechSynthesizer;

public class TestOtherVoices {
    @Test
    public void testVoices() throws Exception {
        String apiKey = System.getenv("DASHSCOPE_API_KEY");
        String[] testVoices = {
            "longpaopao_v3", "longshanshan_v3", "longwangwang_v3", 
            "longling_v3", "longke_v3", "longxian_v3",
            "longpaopao", "longshanshan", "longwangwang",
            "longling", "longke", "longxian"
        };
        
        SpeechSynthesizer synthesizer = new SpeechSynthesizer();
        for (String v : testVoices) {
            try {
                SpeechSynthesisParam param = SpeechSynthesisParam.builder()
                        .apiKey(apiKey)
                        .model("cosyvoice-v3-flash")
                        .parameter("voice", v)
                        .parameter("format", "mp3")
                        .text("Hello")
                        .build();
                synthesizer.call(param);
                System.out.println("SUCCESS: " + v);
            } catch (Exception e) {
                // Ignore failure
            }
        }
    }
}
