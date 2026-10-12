package beidanci.service.socket.system.game.russia;

import java.time.LocalDate;
import java.util.List;

import beidanci.api.model.WordVo;

/**
 * 一个游戏大厅"某一天"的用词池：同一天内不变，跨天换一批（由 {@link HallWordSampler} 决定抽哪些词）。
 *
 * 房间在创建时拿到当时的池对象并一直用到底，所以跨零点的对局不会中途换题源——
 * 换池只影响零点之后新开的房间，旧池由还在用它的房间持有，最后一个房间打完自然回收。
 */
public final class HallWordPool {
    private final LocalDate day;
    private final List<WordVo> words;

    public HallWordPool(LocalDate day, List<WordVo> words) {
        this.day = day;
        this.words = words;
    }

    public LocalDate getDay() {
        return day;
    }

    public int size() {
        return words.size();
    }

    /**
     * 随机取一个词；指定了 otherThan 就避开与它拼写相同的词。
     */
    public WordVo getWordRandomly(WordVo otherThan) {
        int randomIndex = (int) (words.size() * Math.random());
        randomIndex = randomIndex == words.size() ? 0 : randomIndex;
        WordVo word = words.get(randomIndex);

        if (otherThan != null && otherThan.getSpell() != null
                && otherThan.getSpell().equalsIgnoreCase(word.getSpell())) {
            randomIndex++;
            randomIndex = randomIndex == words.size() ? 0 : randomIndex;
            word = words.get(randomIndex);
        }
        return word;
    }
}
