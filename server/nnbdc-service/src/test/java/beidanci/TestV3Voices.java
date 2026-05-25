package beidanci;

import org.junit.jupiter.api.Test;
import com.alibaba.dashscope.audio.tts.SpeechSynthesisParam;
import com.alibaba.dashscope.audio.tts.SpeechSynthesizer;

/**
 * 测试 cosyvoice-v3-flash 所有标准发音人的可用性
 */
public class TestV3Voices {

    @Test
    public void testAllV3Voices() {
        String apiKey = System.getenv("dashscope_api_key");
        if (apiKey == null) {
            apiKey = System.getenv("DASHSCOPE_API_KEY");
        }
        System.out.println("API Key: " + (apiKey != null ? "Found (prefix: " + apiKey.substring(0, 6) + "...)" : "Missing"));

        // cosyvoice-v3-flash 全部标准发音人
        String[] testVoices = {
            // 基准音色（社交陪伴，支持 Instruct）
            "longanyang",       // 龙安洋 - 阳光青年男声
            "longanhuan",       // 龙安欢 - 活力开朗女声

            // 童声
            "longhuhu_v3",      // 龙虎虎
            "longpaopao_v3",    // 龙泡泡
            "longjielidou_v3",  // 龙杰里豆
            "longxian_v3",      // 龙娴
            "longling_v3",      // 龙灵
            "longshanshan_v3",  // 龙珊珊
            "longniuniu_v3",    // 龙牛牛

            // 有声书
            "longmiao_v3",      // 龙淼
            "longsanshu_v3",    // 龙三叔
            "longyuan_v3",      // 龙媛
            "longyue_v3",       // 龙悦
            "longxiu_v3",       // 龙修
            "longnan_v3",       // 龙楠
            "longwanjun_v3",    // 龙婉君
            "longyichen_v3",    // 龙逸晨
            "longlaobo_v3",     // 龙老伯
            "longlaoyi_v3",     // 龙老姨

            // 语音助手
            "longxiaochun_v3",  // 龙小纯
            "longxiaoxia_v3",   // 龙小夏
            "longyumi_v3",      // YUMI
            "longanyun_v3",     // 龙安云
            "longanwen_v3",     // 龙安文
            "longanli_v3",      // 龙安莉
            "longanlang_v3",    // 龙安朗
            "longyingmu_v3",    // 龙瑛沐

            // 社交陪伴
            "longcheng_v3",     // 龙城
            "longze_v3",        // 龙泽
            "longzhe_v3",       // 龙哲
            "longyan_v3",       // 龙妍
            "longxing_v3",      // 龙星
            "longtian_v3",      // 龙天
            "longwan_v3",       // 龙婉
            "longhao_v3",       // 龙浩
            "longhan_v3",       // 龙涵
            "longfeifei_v3",    // 龙菲菲
            "longhua_v3",       // 龙华
            "longanzhi_v3",     // 龙安志
            "longanling_v3",    // 龙安灵
            "longanya_v3",      // 龙安雅
            "longanqin_v3",     // 龙安琴
            "longanrou_v3",     // 龙安柔
            "longqiang_v3",     // 龙蔷
            "longantai_v3",     // 龙安泰
            "longke_v3",        // 龙可
            "longwangwang_v3",  // 龙旺旺
            "longling_v3",      // 龙玲 (renamed)
            "longfei_v3",       // 龙飞 - 诗歌朗诵
            "longshuo_v3",      // 龙烁 - 新闻播报
            "longshu_v3",       // 龙述 - 新闻播报
            "loongbella_v3",    // Bella 3.0 - 新闻播报

            // 方言
            "longjiaxin_v3",    // 粤语女声
            "longjiayi_v3",     // 粤语女声
            "longanyue_v3",     // 粤语男声
            "longlaotie_v3",    // 东北话
            "longshange_v3",    // 陕西话
            "longanmin_v3",     // 闽南语

            // 外语
            "loongkyong_v3",    // 韩语
            "loongriko_v3",     // 日语
            "loongtomoka_v3",   // 日语
        };

        int successCount = 0;
        int failCount = 0;
        java.util.List<String> successVoices = new java.util.ArrayList<>();
        java.util.List<String> failVoices = new java.util.ArrayList<>();

        for (String v : testVoices) {
            try {
                SpeechSynthesizer synthesizer = new SpeechSynthesizer();
                SpeechSynthesisParam param = SpeechSynthesisParam.builder()
                        .apiKey(apiKey)
                        .model("cosyvoice-v3-flash")
                        .parameter("voice", v)
                        .parameter("format", "mp3")
                        .text("Hello world, this is a test.")
                        .build();
                synthesizer.call(param);
                System.out.println("  [OK] " + v);
                successVoices.add(v);
                successCount++;
            } catch (Exception e) {
                String msg = e.getMessage();
                String shortMsg = msg != null && msg.length() > 80 ? msg.substring(0, 80) + "..." : msg;
                System.out.println("  [FAIL] " + v + " -> " + shortMsg);
                failVoices.add(v);
                failCount++;
            }
        }

        System.out.println("\n=== 测试结果汇总 ===");
        System.out.println("成功: " + successCount + " / " + (successCount + failCount));
        System.out.println("失败: " + failCount);
        System.out.println("\n可用发音人 (" + successVoices.size() + "):");
        for (String v : successVoices) {
            System.out.println("  " + v);
        }
        if (!failVoices.isEmpty()) {
            System.out.println("\n不可用发音人 (" + failVoices.size() + "):");
            for (String v : failVoices) {
                System.out.println("  " + v);
            }
        }
    }
}
