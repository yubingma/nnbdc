import com.alibaba.dashscope.aigc.generation.Generation;
import com.alibaba.dashscope.aigc.generation.GenerationParam;
import com.alibaba.dashscope.aigc.generation.GenerationResult;
import com.alibaba.dashscope.common.Message;
import com.alibaba.dashscope.common.Role;

import io.reactivex.Flowable;

import java.util.Arrays;

public class TestDashScope {
    public static void main(String[] args) {
        try {
            Generation gen = new Generation();
            Message userMsg = Message.builder()
                    .role(Role.USER.getValue())
                    .content("Hello")
                    .build();
            GenerationParam param = GenerationParam.builder()
                    .apiKey("test")
                    .model("qwen-plus")
                    .messages(Arrays.asList(userMsg))
                    .resultFormat(GenerationParam.ResultFormat.MESSAGE)
                    .build();
            // test if streamCall exists and returns io.reactivex.Flowable
            Flowable<GenerationResult> result = gen.streamCall(param);
            System.out.println("streamCall exists: " + (result != null));
        } catch (Exception e) {
            e.printStackTrace();
        }
    }
}
