package beidanci.service.bo;

import org.junit.jupiter.api.Test;

import beidanci.api.model.LearningProgressRepairItem;
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
        assertFalse(desc.contains("重复"), "自洽数据不得出现重复计分提示: " + desc);
        assertFalse(desc.contains("进度超过轨道长度"), "自洽数据不得出现越界提示: " + desc);
    }

    @Test
    public void 评分流水多于今日进度时提示重复写记录() {
        // 线上真实形态：同一次作答被写了两条学习记录（进度只加了 1，流水却多出一条）
        SystemHealthIssue issue = SystemHealthCheckBo.buildLearningProgressIssue(
                "user_1", "纪白", "15407", "electronic", 5, 3, 5);

        assertTrue(issue.getDescription().contains("重复写了学习记录"),
                "应提示流水重复写入: " + issue.getDescription());
    }

    @Test
    public void 今日进度多于评分流水时提示环节被重复推进() {
        // 线上真实形态：3 条流水、进度被推到 4，客户端把越界环节夹回最后一个环节反复出题
        SystemHealthIssue issue = SystemHealthCheckBo.buildLearningProgressIssue(
                "user_1", "纪白", "15407", "electronic", 3, 4, 4);

        assertTrue(issue.getDescription().contains("重复推进了环节"),
                "应提示环节被多推进: " + issue.getDescription());
        assertTrue(issue.getDescription().contains("反复出题"),
                "应说明该词会被反复出题: " + issue.getDescription());
    }

    @Test
    public void 进度超过轨道长度时单独提示越界() {
        SystemHealthIssue issue = SystemHealthCheckBo.buildLearningProgressIssue(
                "user_1", "纪白", "15407", "electronic", 3, 4, 3);

        assertTrue(issue.getDescription().contains("进度超过轨道长度"),
                "应提示环节越界: " + issue.getDescription());

        SystemHealthIssue bigger = SystemHealthCheckBo.buildLearningProgressIssue(
                "user_1", "纪白", "15407", "electronic", 3, 5, 3);
        assertTrue(bigger.getDescription().contains("进度超过轨道长度"),
                "进度超过轨道长度更多时同样要提示: " + bigger.getDescription());
    }

    @Test
    public void 两种异常同时存在时两条说明都要给出() {
        SystemHealthIssue issue = SystemHealthCheckBo.buildLearningProgressIssue(
                "user_1", "纪白", "15407", "electronic", 5, 4, 3);

        assertTrue(issue.getDescription().contains("重复写了学习记录"),
                "应提示流水重复写入: " + issue.getDescription());
        assertTrue(issue.getDescription().contains("进度超过轨道长度"),
                "应提示环节越界: " + issue.getDescription());
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

    // ---------- 管理端单点修复的可修性判定（四条护栏） ----------

    /** 一个"已经凉下来"的进度行：7 小时前更新过，用户显然没在学这个词 */
    private static java.util.Date staleProgressUpdate() {
        return new java.util.Date(System.currentTimeMillis() - 7 * 3600_000L);
    }

    private static java.util.Date freshProgressUpdate() {
        return new java.util.Date(System.currentTimeMillis() - 60_000L);
    }

    @Test
    public void 可修性判定_进度超轨道且流水足够且已凉下来时才允许修复() {
        LearningProgressRepairItem item = SystemHealthCheckBo.buildLearningProgressRepairItem(
                "user_1", "纪白", "15407", "electronic", 4, 3, 3, staleProgressUpdate(), "26021901");

        assertTrue(item.getCanRepair(), "四条护栏都满足时应允许修复");
        assertNull(item.getRepairBlockReason());
        assertEquals(4, item.getProgress());
        assertEquals(3, item.getTodayLogCount(), "修复目标值应为今天的流水条数");
        assertEquals("electronic", item.getSpell());
    }

    @Test
    public void 可修性判定_进度未超轨道长度时不修() {
        // 只是"比流水多一条"，可能是同步滞后；没超轨道长度说明该词还没走完整条轨道
        LearningProgressRepairItem item = SystemHealthCheckBo.buildLearningProgressRepairItem(
                "user_1", "纪白", "15407", "electronic", 2, 1, 3, staleProgressUpdate(), "26021901");

        assertFalse(item.getCanRepair(), "进度未超过轨道长度时不得在服务端改动");
        assertEquals(LearningProgressRepairItem.BLOCK_NOT_OVER_TRACK, item.getRepairBlockReason());
    }

    @Test
    public void 可修性判定_今天没有流水时不修() {
        LearningProgressRepairItem item = SystemHealthCheckBo.buildLearningProgressRepairItem(
                "user_1", "纪白", "15407", "electronic", 4, 0, 3, staleProgressUpdate(), "26021901");

        assertFalse(item.getCanRepair(), "没有流水就没有可靠依据判断该整成几");
        assertEquals(LearningProgressRepairItem.BLOCK_NO_LOG_TODAY, item.getRepairBlockReason());
    }

    @Test
    public void 可修性判定_进度行最近还在更新时不修() {
        // 用户可能正在学这个词：此刻改它会把他刚走完的进度倒退回去
        LearningProgressRepairItem item = SystemHealthCheckBo.buildLearningProgressRepairItem(
                "user_1", "纪白", "15407", "electronic", 4, 3, 3, freshProgressUpdate(), "26021901");

        assertFalse(item.getCanRepair(), "进度行还在更新时不得改动，避免倒退用户正在学的进度");
        assertEquals(LearningProgressRepairItem.BLOCK_UPDATED_TODAY, item.getRepairBlockReason());
    }

    @Test
    public void 可修性判定_目标值不得大于等于当前值() {
        // 只降不升：进度已经等于流水条数时没有可下调的空间
        LearningProgressRepairItem item = SystemHealthCheckBo.buildLearningProgressRepairItem(
                "user_1", "纪白", "15407", "electronic", 3, 3, 3, staleProgressUpdate(), "26021901");

        assertFalse(item.getCanRepair());
        assertEquals(LearningProgressRepairItem.BLOCK_NOT_OVER_TRACK, item.getRepairBlockReason());
    }

    // ---------- 界面按用户分组展示所需的两项信息 ----------

    @Test
    public void 逐词明细带着与体检说明一字不差的诊断文案和用户上报的客户端版本() {
        // 同一份现场：3 条流水、进度被推到 4、轨道长度 2（进度既多于流水、又超过轨道长度）
        SystemHealthIssue issue = SystemHealthCheckBo.buildLearningProgressIssue(
                "user_1", "纪白", "15407", "electronic", 3, 4, 2);
        LearningProgressRepairItem item = SystemHealthCheckBo.buildLearningProgressRepairItem(
                "user_1", "纪白", "15407", "electronic", 4, 3, 2, staleProgressUpdate(), "26021901");

        assertTrue(item.getDiagnosis().contains("重复推进了环节"), item.getDiagnosis());
        assertTrue(item.getDiagnosis().contains("进度超过轨道长度"), item.getDiagnosis());
        assertTrue(issue.getDescription().endsWith(item.getDiagnosis()),
                "体检说明里那句诊断应与逐词明细一致，不能两处各写一套: " + issue.getDescription());
        assertEquals("26021901", item.getClientVersion());
    }
}
