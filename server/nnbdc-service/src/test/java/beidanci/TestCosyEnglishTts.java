package beidanci;

import java.nio.ByteBuffer;
import org.junit.jupiter.api.Test;
import com.alibaba.dashscope.audio.ttsv2.SpeechSynthesisAudioFormat;
import com.alibaba.dashscope.audio.ttsv2.SpeechSynthesisParam;
import com.alibaba.dashscope.audio.ttsv2.SpeechSynthesizer;

public class TestCosyEnglishTts {

    @Test
    public void testEnglishVoices() {
        String apiKey = System.getenv("dashscope_api_key");
        if (apiKey == null) {
            apiKey = System.getenv("DASHSCOPE_API_KEY");
        }
        if (apiKey == null) {
            try {
                String yml = new String(java.nio.file.Files.readAllBytes(java.nio.file.Paths.get("src/main/resources/application.yml")));
                for (String line : yml.split("\n")) {
                    if (line.contains("api-key:")) {
                        apiKey = line.split(":")[1].trim();
                        break;
                    }
                }
            } catch (Exception ignored) {}
        }

        String text = "We should book a table in advance because this restaurant is very popular.";
        String[] candidateVoices = {
            "longanyang", "longanhuan", "longyumi_v3", "longanya_v3", "longxiaoxia_v3", "longxiaochun_v3"
        };

        for (String voice : candidateVoices) {
            try {
                SpeechSynthesisParam param = SpeechSynthesisParam.builder()
                        .apiKey(apiKey)
                        .model("cosyvoice-v3-flash")
                        .voice(voice)
                        .format(SpeechSynthesisAudioFormat.MP3_24000HZ_MONO_256KBPS)
                        .build();

                SpeechSynthesizer synthesizer = new SpeechSynthesizer(param, null);
                ByteBuffer buffer = synthesizer.call(text);
                if (buffer != null && buffer.remaining() > 0) {
                    System.out.println("  [OK] " + voice + " -> size=" + buffer.remaining());
                } else {
                    System.out.println("  [EMPTY] " + voice);
                }
            } catch (Exception e) {
                System.out.println("  [FAIL] " + voice + " -> " + e.getMessage());
            }
        }
    }
}
