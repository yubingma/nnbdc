package beidanci.service.bo;

import org.junit.jupiter.api.Test;

import beidanci.api.model.SystemHealthIssue;

import static org.junit.jupiter.api.Assertions.*;

/**
 * 「学习进度与学习记录一致性」审计的判定口径测试。
 *
 * <p>审计窗口是 SQL 侧的事（服务端无法把评分流水的 UTC 写入时刻换算成各用户的当地业务日），
 * 这里只固定不变式的判定与说明文案：
 * <ol>
 * <li>今日评分流水条数不得多于今日环节进度；</li>
 * <li>今日环节进度不得多于当前配置下的轨道长度上限。</li>
 * </ol>
 */
public class SystemHealthCheckBoTest {

    private static final String TYPE = "learning_progress_inconsistent";

    @Test
    public void 流水与进度相等且未超轨道长度时说明中不含异常描述() {
        SystemHealthIssue issue = SystemHealthCheckBo.buildLearningProgressIssue(
                "user_1", "纪白", "15407", "electronic", 3, 3, 3);

        assertEquals(TYPE, issue.getType());
        assertEquals(TYPE, issue.getCategory());
        String desc = issue.getDescription();
        assertTrue(desc.contains("electronic"), "应带上单词拼写: " + desc);
        assertTrue(desc.contains("15407"), "应带上单词 ID: " + desc);
        assertTrue(desc.contains("纪白"), "应带上用户昵称: " + desc);
        assertFalse(desc.contains("同一次作答被重复计分"), "自洽数据不得出现重复计分提示: " + desc);
        assertFalse(desc.contains("进度超过轨道长度"), "自洽数据不得出现越界提示: " + desc);
    }

    @Test
    public void 流水多于进度时提示同一次作答被重复计分() {
        // 线上真实形态：同一次作答被写了两条学习记录（进度只加了 1，流水却多出一条）
        SystemHealthIssue issue = SystemHealthCheckBo.buildLearningProgressIssue(
                "user_1", "纪白", "15407", "electronic", 5, 3, 5);

        assertTrue(issue.getDescription().contains("同一次作答被重复计分"),
                "应提示重复计分: " + issue.getDescription());
    }

    @Test
    public void 进度超过轨道长度时提示环节被多推进() {
        // 线上真实形态：轨道 3 个环节，进度被推到 4，客户端会把越界环节夹回最后一个环节反复出题
        SystemHealthIssue issue = SystemHealthCheckBo.buildLearningProgressIssue(
                "user_1", "纪白", "15407", "electronic", 3, 4, 3);

        assertTrue(issue.getDescription().contains("进度超过轨道长度"),
                "应提示环节被多推进: " + issue.getDescription());
        assertTrue(issue.getDescription().contains("反复出题"),
                "应说明该词会被反复出题: " + issue.getDescription());

        SystemHealthIssue bigger = SystemHealthCheckBo.buildLearningProgressIssue(
                "user_1", "纪白", "15407", "electronic", 3, 5, 3);
        assertTrue(bigger.getDescription().contains("进度超过轨道长度"),
                "进度超过轨道长度更多时同样要提示: " + bigger.getDescription());
    }

    @Test
    public void 两条不变式同时被破坏时两种说明都要给出() {
        SystemHealthIssue issue = SystemHealthCheckBo.buildLearningProgressIssue(
                "user_1", "纪白", "15407", "electronic", 5, 4, 3);

        assertTrue(issue.getDescription().contains("同一次作答被重复计分"),
                "应提示重复计分: " + issue.getDescription());
        assertTrue(issue.getDescription().contains("进度超过轨道长度"),
                "应提示环节被多推进: " + issue.getDescription());
    }

    @Test
    public void 缺少昵称与拼写时分别退回用户ID与单词ID() {
        SystemHealthIssue noNickName = SystemHealthCheckBo.buildLearningProgressIssue(
                "user_1", null, "15407", "electronic", 3, 5, 3);
        assertTrue(noNickName.getDescription().contains("user_1"),
                "无昵称时应退回用户 ID: " + noNickName.getDescription());

        SystemHealthIssue emptyNickName = SystemHealthCheckBo.buildLearningProgressIssue(
                "user_1", "", "15407", "electronic", 3, 5, 3);
        assertTrue(emptyNickName.getDescription().contains("「user_1」"),
                "空昵称时应退回用户 ID: " + emptyNickName.getDescription());

        SystemHealthIssue noSpell = SystemHealthCheckBo.buildLearningProgressIssue(
                "user_1", "纪白", "15407", null, 3, 5, 3);
        assertTrue(noSpell.getDescription().contains("15407 ("),
                "拼写缺失时应退回单词 ID: " + noSpell.getDescription());
    }
}
