package beidanci.service.socket.system.game.russia.state;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedList;
import java.util.List;
import java.util.Map;
import java.util.Set;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import beidanci.api.model.*;
import beidanci.service.socket.UserCmd;
import beidanci.service.socket.system.game.russia.HallWordPool;
import beidanci.service.socket.system.game.russia.RussiaRoom;
import beidanci.service.socket.system.game.russia.UserGameData;
import beidanci.service.util.Util;
import beidanci.util.Utils;

public final class GetNextWordProcessor {
    private static final Logger log = LoggerFactory.getLogger(GetNextWordProcessor.class);

    /**
     * 一次下发给客户端的单词包大小。客户端拿到包后在本地依次出题，
     * 不必每答一题就往返一次，短暂断链也不会中断出题。
     */
    public static final int PACK_SIZE = 50;

    /**
     * 挑词时最多重试几次去避开已用过的拼写。池子比一包还小时（例如大厅只有 30 个词）
     * 本来就避不开，试有限次就接受重复，不在这里死循环。
     */
    private static final int MAX_PICK_RETRY = 20;

    private final RussiaRoom room;
    public GetNextWordProcessor(RussiaRoom room) {
        this.room = room;
        reset();
    }

    /**
     * 保存当前游戏的单词，以使两个玩家得到一样的单词，保证公平<br/>
     * Object[0]: word<br/>
     * Object[1]: meanings of three other words<br/>
     * Object[2]: sound url<br/>
     * Object[3]: spells of three other words
     */
    private final List<Object[]> words = new LinkedList<>();

    /**
     * 对外提供按索引获取当前局内单词拼写的能力（用于日志等场景）。
     * @param index words 列表中的索引
     * @return 该索引对应的单词拼写；若索引无效则返回空串
     */
    public String getSpellByIndex(int index) {
        synchronized (words) {
            if (index >= 0 && index < words.size()) {
                WordVo w = (WordVo) words.get(index)[0];
                return w.getSpell();
            }
        }
        return "";
    }

    /**
     * 老协议：客户端每答一题就向服务端要下一个单词，服务端回 wordA（新客户端已不再使用，仅为兼容旧安装包保留）。
     */
    public void processGetNextWordCmd(UserVo user, UserCmd userCmd) {
        try {
            Object[] wordObj = reportAnswer(user, userCmd);
            room.sendEventToUser(user, "wordA", wordObj);
            notifyOpponentWordB(user, userCmd.getArgs()[1], wordObj);
        } catch (NumberFormatException e) {
            log.error("解析用户命令参数失败: userCmd={}", userCmd, e);
        } catch (Exception e) {
            log.error("处理获取下一个单词命令失败: user={}, userCmd={}", user, userCmd, e);
        }
    }

    /**
     * 新协议：客户端本地出题，答题结果只做单向上报，服务端不再回 wordA。
     */
    public void processAnswerCmd(UserVo user, UserCmd userCmd) {
        try {
            Object[] wordObj = reportAnswer(user, userCmd);
            if (wordObj != null) {
                notifyOpponentWordB(user, userCmd.getArgs()[1], wordObj);
            }
        } catch (NumberFormatException e) {
            log.error("解析用户命令参数失败: userCmd={}", userCmd, e);
        } catch (Exception e) {
            log.error("处理答题上报命令失败: user={}, userCmd={}", user, userCmd, e);
        }
    }

    /**
     * 新协议：一次性把 [fromIndex, fromIndex + PACK_SIZE) 这段单词下发给客户端。
     * 单词取自房间共用的 words 列表，两个玩家拿到的词序完全一致。
     */
    public void processGetWordPackCmd(UserVo user, UserCmd userCmd) {
        try {
            int fromIndex = Math.max(0, Integer.parseInt(userCmd.getArgs()[0]));
            List<Object[]> pack;
            synchronized (words) {
                // 这一包里已经用过的拼写（这段可能之前已经生成过一部分）
                Set<String> usedInPack = new HashSet<>();
                for (int i = fromIndex; i < words.size(); i++) {
                    usedInPack.add(((WordVo) words.get(i)[0]).getSpell());
                }
                while (words.size() < fromIndex + PACK_SIZE) {
                    words.add(buildWordObj(usedInPack));
                }
                pack = new ArrayList<>(words.subList(fromIndex, fromIndex + PACK_SIZE));
            }
            List<Object[]> wirePack = new ArrayList<>(pack.size());
            for (Object[] wordObj : pack) {
                wirePack.add(toWireWord(wordObj));
            }
            room.sendEventToUser(user, "wordPack", new Object[]{fromIndex, wirePack});
        } catch (NumberFormatException e) {
            log.error("解析用户命令参数失败: userCmd={}", userCmd, e);
        } catch (Exception e) {
            log.error("处理获取单词包命令失败: user={}, userCmd={}", user, userCmd, e);
        }
    }

    /**
     * 单词包里每个词条的线上形态：结构与 wordA 一致（客户端复用同一段解析），
     * 但只带本地出题真正要用的字段（拼写、中文释义、3 个干扰词拼写），
     * 否则整包会带上词向量、相似词等大字段，一包几十个词会撑爆单帧。
     */
    private static Object[] toWireWord(Object[] wordObj) {
        WordVo word = (WordVo) wordObj[0];
        Map<String, Object> leanWord = new HashMap<>();
        leanWord.put("spell", word.getSpell());
        leanWord.put("meaningStr", word.getMeaningStr());
        return new Object[]{leanWord, null, null, wordObj[3]};
    }

    /**
     * 答题记账（连对计数、连对奖励道具、答错日志），并返回本题对应的单词对象。
     *
     * @return 本题索引对应的单词对象；老协议下若索引超出已有词库则即时生成一个并追加
     */
    private Object[] reportAnswer(UserVo user, UserCmd userCmd) {
        int wordIndex = Integer.parseInt(userCmd.getArgs()[0]);
        String currWord = userCmd.getArgs()[2];
        UserGameData userPlayData = room.getUserPlayData(user);

        // 更新连对次数
        String answerResult = userCmd.getArgs()[1];
        if (answerResult.equals("true")) {// 答对了
            userPlayData.setCorrectCount(userPlayData.getCorrectCount() + 1);
        } else {// 答错了
            userPlayData.setCorrectCount(0);

            // 由前端本地加入并通过同步机制落库到服务端（此处不再通知）
            if (wordIndex >= 0) {
                log.info(String.format("前端将处理答错单词[%s]加入生词本(本地+同步)", currWord));
            }
        }

        // 如果连对3次，奖励道具（加一行/水雷 vs 减一行/海星 50/50），与前端每连对 3 次奖励道具一致
        if (userPlayData.getCorrectCount() >= 3 && userPlayData.getCorrectCount() % 3 == 0) {
            int props = java.util.concurrent.ThreadLocalRandom.current().nextInt(2); // 0 或 1
            userPlayData.getPropsCounts()[props]++;
            room.sendEventToUser(user, "giveProps",
                    new int[]{props, userPlayData.getPropsCounts()[props]});
            // 机器人获得道具时打印日志
            if (user.getUserName() != null && user.getUserName().startsWith("bot_")) {
                int c0 = userPlayData.getPropsCounts()[0];
                int c1 = userPlayData.getPropsCounts()[1];
                log.info(String.format("机器人[%s] 连击获得道具[%s]，道具库存：水雷(0)=%d，海星(1)=%d",
                        Util.getNickNameOfUser(user),
                        (props == 0 ? "水雷(0)" : "海星(1)"), c0, c1));
            }
        }

        synchronized (words) {
            if (wordIndex < words.size()) {
                return words.get(wordIndex);
            }
            Object[] wordObj = buildWordObj(new HashSet<>());
            words.add(wordObj);
            return wordObj;
        }
    }

    /**
     * 组一个词条：目标词 + 3 个互不相同的干扰词，词都取自本房间锁定的当日词池。
     * 用到的拼写会加进 usedSpells，这样同一个词包里不会重复出同一个词。
     */
    private Object[] buildWordObj(Set<String> usedSpells) {
        WordVo word = pickWordAvoiding(usedSpells);
        usedSpells.add(word.getSpell());
        WordVo word2 = pickWordAvoiding(usedSpells);
        usedSpells.add(word2.getSpell());
        WordVo word3 = pickWordAvoiding(usedSpells);
        usedSpells.add(word3.getSpell());
        WordVo word4 = pickWordAvoiding(usedSpells);
        usedSpells.add(word4.getSpell());

        String[] meanings = new String[]{word2.getMeaningStr(), word3.getMeaningStr(), word4.getMeaningStr()};
        String[] distractorSpells = new String[]{word2.getSpell(), word3.getSpell(), word4.getSpell()};
        String soundUrl = Utils.getFileNameOfWordSound(word.getSpell());
        return new Object[]{word, meanings, soundUrl, distractorSpells};
    }

    /**
     * 从当日词池里随机取一个不在 usedSpells 里的词；试有限次仍避不开就接受重复。
     */
    private WordVo pickWordAvoiding(Set<String> usedSpells) {
        HallWordPool pool = room.getWordPool();
        for (int i = 0; i < MAX_PICK_RETRY; i++) {
            WordVo word = pool.getWordRandomly(null);
            if (!usedSpells.contains(word.getSpell())) {
                return word;
            }
        }
        return pool.getWordRandomly(null);
    }

    /**
     * 把我的答题进度同步给对手（对手据此看到我的进度）。
     */
    private void notifyOpponentWordB(UserVo user, String answerResult, Object[] wordObj) {
        UserVo anotherUser = room.getAnotherUser(user);
        if (anotherUser == null) {// 对方有可能突然不在线了(或者是单人练习模式)，所以要判断一下
            return;
        }
        String spell = ((WordVo) wordObj[0]).getSpell();
        room.sendEventToUser(anotherUser, "wordB", new Object[]{answerResult, spell});
    }

    public void reset() {
        synchronized (words) {
            words.clear();
        }
    }
}
