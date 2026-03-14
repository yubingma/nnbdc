package beidanci.service.socket.system.game.russia.state;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import beidanci.api.model.UserGameVo;
import beidanci.api.model.UserVo;
import beidanci.service.bo.SysParamBo;
import beidanci.service.bo.UserBo;
import beidanci.service.po.SysParam;
import beidanci.service.po.User;
import beidanci.service.socket.UserCmd;
import beidanci.service.socket.system.game.russia.RussiaRoom;
import beidanci.service.socket.system.game.russia.UserGameData;
import beidanci.service.bo.UserGameBo;
import beidanci.service.po.UserGame;
import beidanci.service.po.UserGameId;
import beidanci.service.util.Util;

public class GameOverProcessor {
    private static final Logger log = LoggerFactory.getLogger(GameOverProcessor.class);

    /**
     * 当前游戏的失败者，谁先报告game over谁就是失败者
     */
    private UserVo loser = null;

    private final RussiaRoom room;

    private final SysParamBo sysParamBo;

    UserBo userBo;
    UserGameBo userGameBo;

    public GameOverProcessor(RussiaRoom room, SysParamBo sysParamBo, UserBo userBo, UserGameBo userGameBo) {
        this.room = room;
        this.sysParamBo = sysParamBo;
        this.userBo = userBo;
        this.userGameBo = userGameBo;
    }

    public void processGameOverCmd(UserVo user, UserCmd userCmd) throws IllegalAccessException {
        if (loser == null) {
            // 判断那个玩家失败了
            String loserTag = userCmd.getArgs()[0];
            assert (loserTag.equals("A") || loserTag.equals("B"));
            if (loserTag.equals("A")) {
                loser = user;
            } else {
                loser = room.getAnotherUser(user);
            }

            UserGameData userPlayData = room.getUserPlayData(user);
            if (userPlayData.isExercise()) {
                room.sendEventToUser(user, "loser", loser.getId());
                log.info(String.format("[%s]练习结束, loserTag:[%s]", Util.getNickNameOfUser(loser), loserTag));
            } else {
                room.broadcastEvent("loser", loser.getId());
                log.info(String.format("[%s]触顶，判为失败, loserTag:[%s]", Util.getNickNameOfUser(loser), loserTag));
            }

            // 根据胜负情况对两位玩家的积分进行调整（包含机器人对局，保持一致体验）
            // 检查房间中是否有任何玩家处于练习状态，如果有则不调整积分
            boolean anyUserInExercise = room.getUsers().values().stream()
                    .anyMatch(UserGameData::isExercise);
            if (!anyUserInExercise) {
                UserVo winer = room.getAnotherUser(loser);
                // 直接使用本地逻辑进行积分与魔法泡泡结算（已改为使用新会话，避免currentSession问题）
                adjustUserScore(winer, loser);
            }
        }
        room.broadcastUsersInfo();
    }

    public void reset() {
        loser = null;
    }

    /**
     * 计算赢家的积分调整量
     *
     * @param winerScore
     * @param loserScore
     * @return
     */
    public static int calculateWinerScoreAdjustment(int winerScore, int loserScore) {
        int adjustment;
        int delta = loserScore - winerScore;
        // 调整：将分差影响范围从 ±1000 扩大到 ±1500，缩小奖励波动区间 [10, 60]
        if (delta >= 1500) {
            adjustment = 60;
        } else if (delta <= -1500) {
            adjustment = 10;
        } else {
            // 平滑过渡公式：10 + (delta + 1500) * (60 - 10) / 3000
            adjustment = 10 + (delta + 1500) * 50 / 3000;
        }
        return adjustment;
    }

    /**
     * 根据游戏胜负情况，计算玩家的积分和魔法泡泡调整量并通知前端
     * 注意：本方法不再直接修改数据库，由前端本地更新后通过同步机制同步到后端
     *
     * @param winerVo
     * @param loserVo
     * @throws IllegalAccessException
     */
    public void adjustUserScore(UserVo winerVo, UserVo loserVo) throws IllegalAccessException {
        // 加载/获取持久化对象
        User winer = userBo.findById(winerVo.getId(), true);
        User loser_ = userBo.findById(loserVo.getId(), true);

        // 计算积分基础值
        final int winerScoreForCalc = (winer != null) ? winer.getGameScore() : winerVo.getGameScore();
        final int loserScoreForCalc = (loser_ != null) ? loser_.getGameScore() : loserVo.getGameScore();
        final int adjustment = calculateWinerScoreAdjustment(winerScoreForCalc, loserScoreForCalc);

        // 获取魔法泡泡基础值
        SysParam sysParam = sysParamBo.findById(SysParam.COW_DUNG_PER_GAME, true);
        int cowDungPerGame = Integer.parseInt(sysParam.getParamValue());

        // --- 1. 处理赢家数据 ---
        // 更新 VO 显示（供当前内存使用）
        UserGameVo winerGameVo = winerVo.getGameByName("russia");
        winerGameVo.setWinCount(winerGameVo.getWinCount() + 1);
        winerGameVo.setScore(winerGameVo.getScore() + adjustment);
        winerVo.setGameScore(winerVo.getGameScore() + adjustment);
        winerVo.setCowDung(winerVo.getCowDung() + cowDungPerGame);

        // 持久化更新
        if (winer != null) {
            // 更新 User 汇总积分与魔法泡泡
            winer.setGameScore(winer.getGameScore() + adjustment);
            userBo.updateEntity(winer);
            userBo.adjustCowDung(winer, cowDungPerGame, "RussiaWin");

            // 更新 UserGame 详细记录 (俄罗斯方块项)
            UserGameId ugId = new UserGameId(winer.getId(), "russia");
            UserGame ug = userGameBo.findById(ugId);
            if (ug == null) {
                ug = new UserGame(ugId, winer, 1, 0, adjustment);
                userGameBo.createEntity(ug);
            } else {
                ug.setWinCount(ug.getWinCount() + 1);
                ug.setScore((ug.getScore() == null ? 0 : ug.getScore()) + adjustment);
                userGameBo.updateEntity(ug);
            }

            // 只有真实在线的人类玩家（而非带入真实ID的机器人）需要 log 以便同步
            if (!winerVo.getUserName().startsWith("bot_")) {
                userBo.logUserUpdateForSync(winer);
            }
        }

        // --- 2. 处理输家数据 ---
        int loserScoreDelta = Math.min(adjustment, Math.max(0, loser_ != null ? loser_.getGameScore() : loserVo.getGameScore()));
        
        // 更新 VO 显示
        UserGameVo loserGameVo = loserVo.getGameByName("russia");
        if (loserGameVo != null) {
            loserGameVo.setLoseCount(loserGameVo.getLoseCount() + 1);
            loserGameVo.setScore(Math.max(0, (loserGameVo.getScore() == null ? 0 : loserGameVo.getScore()) - loserScoreDelta));
        }
        loserVo.setGameScore(Math.max(0, loserVo.getGameScore() - loserScoreDelta));
        loserVo.setCowDung(Math.max(0, loserVo.getCowDung() - cowDungPerGame));

        // 持久化更新
        if (loser_ != null) {
            // 更新 User 汇总积分与魔法泡泡
            loser_.setGameScore(Math.max(0, loser_.getGameScore() - loserScoreDelta));
            userBo.updateEntity(loser_);
            userBo.adjustCowDung(loser_, -cowDungPerGame, "RussiaLose");

            // 更新 UserGame 详细记录
            UserGameId ugId = new UserGameId(loser_.getId(), "russia");
            UserGame ug = userGameBo.findById(ugId);
            if (ug == null) {
                ug = new UserGame(ugId, loser_, 0, 1, 0);
                userGameBo.createEntity(ug);
            } else {
                ug.setLoseCount(ug.getLoseCount() + 1);
                ug.setScore(Math.max(0, (ug.getScore() == null ? 0 : ug.getScore()) - loserScoreDelta));
                userGameBo.updateEntity(ug);
            }

            if (!loserVo.getUserName().startsWith("bot_")) {
                userBo.logUserUpdateForSync(loser_);
            }
        }

        // 通知赢家客户端积分和魔法泡泡调整（正值表示增加）
        room.sendEventToUser(winerVo, "scoreAdjust", new Object[]{adjustment, cowDungPerGame});
        // 广播赢家的结算结果，用于在对方客户端显示
        room.broadcastEvent("scoreAdjustPublic", new Object[]{winerVo.getId(), adjustment, cowDungPerGame});

        // 通知输家客户端积分和魔法泡泡调整（负值表示减少）
        room.sendEventToUser(loserVo, "scoreAdjust", new Object[]{-loserScoreDelta, -cowDungPerGame});
        // 广播输家的结算结果
        room.broadcastEvent("scoreAdjustPublic", new Object[]{loserVo.getId(), -loserScoreDelta, -cowDungPerGame});
        
        log.info("游戏结算完成：赢家[{}]积分+{} 魔法泡泡+{}, 输家[{}]积分-{} 魔法泡泡-{}", 
                Util.getNickNameOfUser(winerVo), adjustment, cowDungPerGame,
                Util.getNickNameOfUser(loserVo), loserScoreDelta, cowDungPerGame);
    }

}
