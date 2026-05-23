package beidanci.service.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

/**
 * 阿里云 AI (DashScope/CosyVoice) 配置属性
 */
@Component
@ConfigurationProperties(prefix = "aliyun.ai")
public class AliyunAiProperties {

    /**
     * DashScope API Key
     */
    private String apiKey;

    /**
     * 文本生成使用的模型 (如 qwen-max, qwen-plus, qwen3.5-flash)
     */
    private String textModel = "qwen3.5-flash";

    /**
     * 语音合成使用的模型 (如 cosyvoice-v1)
     */
    private String ttsModel = "cosyvoice-v1";

    /**
     * 语音合成发音角色 (如 longxiaochun)
     */
    private String voice = "longxiaochun";

    public String getApiKey() {
        return apiKey;
    }

    public void setApiKey(String apiKey) {
        this.apiKey = apiKey;
    }

    public String getTextModel() {
        return textModel;
    }

    public void setTextModel(String textModel) {
        this.textModel = textModel;
    }

    public String getTtsModel() {
        return ttsModel;
    }

    public void setTtsModel(String ttsModel) {
        this.ttsModel = ttsModel;
    }

    public String getVoice() {
        return voice;
    }

    public void setVoice(String voice) {
        this.voice = voice;
    }
}
