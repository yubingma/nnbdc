package beidanci.service.socket.system.game.russia;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Objects;
import java.util.Random;

/**
 * 游戏大厅的用词抽样规则：一个大厅每天最多用 {@link #MAX_POOL_SIZE} 个词。
 *
 * 大厅的词来自一组词书，量可以很大（生产上「所有单词」大厅有约 7 万个词、850 本词书）。
 * 把全量词表装进内存既慢又占地方，而玩家天天遇到的还是同一批词，所以改成"每天一批"：
 * <ul>
 *   <li>厅里词数超过 {@link #MAX_POOL_SIZE} 就每天抽这么多个；不足就全都要（没有第二条规则）；</li>
 *   <li>结果由"日期 + 大厅 id"决定：同一天、同一个大厅在任何实例上算出来都一样，
 *       换一天就换一批——所以不能用 random()，只能用固定种子的确定性洗牌；</li>
 *   <li>因此每日轮转只对词数超过 {@link #MAX_POOL_SIZE} 的大厅有实际影响，
 *       词少的厅本来所有词每天都在一起。</li>
 * </ul>
 */
public final class HallWordSampler {
    /**
     * 一个大厅每天最多用这么多个词；厅里词数不足就全都要
     */
    static final int MAX_POOL_SIZE = 2000;

    private HallWordSampler() {
    }

    /**
     * 从大厅的全部词里挑出"今天用"的那一批。
     *
     * @param allWordIds 大厅全部词的 id
     * @param day        业务日期（自然日）
     * @param hallId     大厅 id
     * @return 今天要用的词 id
     */
    public static List<String> pickWordIds(List<String> allWordIds, LocalDate day, String hallId) {
        List<String> shuffled = new ArrayList<>(allWordIds);
        Collections.shuffle(shuffled, new Random(Objects.hash(day, hallId)));
        return new ArrayList<>(shuffled.subList(0, Math.min(MAX_POOL_SIZE, shuffled.size())));
    }
}
