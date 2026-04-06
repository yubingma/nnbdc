package beidanci.service.socket.system.game.russia.state;

import java.util.LinkedList;
import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import beidanci.api.model.*;
import beidanci.service.socket.UserCmd;
import beidanci.service.socket.system.game.russia.RussiaRoom;
import beidanci.service.socket.system.game.russia.UserGameData;
import beidanci.service.util.Util;
import beidanci.util.Utils;

public final class GetNextWordProcessor {
    private static final Logger log = LoggerFactory.getLogger(GetNextWordProcessor.class);
    private final RussiaRoom room;
    public GetNextWordProcessor(RussiaRoom room) {
        this.room = room;
        reset();
    }

    /**
     * 保存当前游戏的单词，以使两个玩家得到一样的单词，保证公平<br/>
     * Object[0]: word<br/>
     * Object[1]: meanings of two other words
     */
    private final List<Object[]> words = new LinkedList<>();

    /**
     * 对外提供按索引获取当前局内单词拼写的能力（用于日志等场景）。
     * @param index words 列表中的索引
     * @return 该索引对应的单词拼写；若索引无效则返回空串
     */
    public String getSpellByIndex(int index) {
        try {
            if (index >= 0 && index < words.size()) {
                WordVo w = (WordVo) words.get(index)[0];
                return w.getSpell();
            }
        } catch (Exception e) {
            log.error("获取单词拼写失败: index={}, words.size()={}", index, words.size(), e);
        }
        return "";
    }

    public void processGetNextWordCmd(UserVo user, UserCmd userCmd) {
        try {
            Object[] wordObj;
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

            // 如果连对5次，奖励道具（加一行/减一行 50/50）
            if (userPlayData.getCorrectCount() == 5) {
                userPlayData.setCorrectCount(0);
                int props = java.util.concurrent.ThreadLocalRandom.current().nextInt(2); // 0 或 1
                userPlayData.getPropsCounts()[props]++;
                room.sendEventToUser(user, "giveProps",
                        new int[]{props, userPlayData.getPropsCounts()[props]});
                // 机器人获得道具时打印日志
                if (user.getUserName() != null && user.getUserName().startsWith("bot_")) {
                    int c0 = userPlayData.getPropsCounts()[0];
                    int c1 = userPlayData.getPropsCounts()[1];
                    log.info(String.format("机器人[%s] 获得道具[%s]，道具库存：加一行=%d，减一行=%d",
                            Util.getNickNameOfUser(user),
                            (props == 0 ? "加一行" : "减一行"), c0, c1));
                }
            }

            if (wordIndex < words.size()) {
                wordObj = words.get(wordIndex);
            } else {
                // 随机选择一个单词
                WordVo word = room.getHall().getWordRandomly(null);

                // 随机选择其他两个单词的意思，用以迷惑用户
                WordVo word2 = room.getHall().getWordRandomly(word);
                WordVo word3 = room.getHall().getWordRandomly(word);
                String[] meanings = new String[]{word2.getMeaningStr(), word3.getMeaningStr()};

                // 单词的发音
                String soundUrl = Utils.getFileNameOfWordSound(word.getSpell());

                wordObj = new Object[]{word, meanings, soundUrl};
                words.add(wordObj);

            }

            room.sendEventToUser(user, "wordA", wordObj);

            // 给对手也发一份，让对手看到我的进度
            UserVo anotherUser = room.getAnotherUser(user);
            if (anotherUser != null) {// 对方有可能突然不在线了(或者是单人练习模式)，所以要判断一下
                String spell = ((WordVo) wordObj[0]).getSpell();
                room.sendEventToUser(anotherUser, "wordB", new Object[]{answerResult, spell});
            }
        } catch (NumberFormatException e) {
            log.error("解析用户命令参数失败: userCmd={}", userCmd, e);
            // 参数解析失败，无法继续处理，记录错误后返回
            return;
        } catch (Exception e) {
            log.error("处理获取下一个单词命令失败: user={}, userCmd={}", user, userCmd, e);
            // 其他异常也需要记录，不能静默失败
            return;
        }
    }

    public void reset() {
        words.clear();
    }
}
