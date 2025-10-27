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

    public GameOverProcessor(RussiaRoom room, SysParamBo sysParamBo, UserBo userBo) {
        this.room = room;
        this.sysParamBo = sysParamBo;
        this.userBo = userBo;
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
        if (delta >= 1000) {
            adjustment = 100;
        } else if (delta <= -1000) {
            adjustment = 1;
        } else {
            adjustment = 1 + (delta + 1000) * 99 / 2000;
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
        User winer = userBo.findById(winerVo.getId(), true);
        User loser_ = userBo.findById(loserVo.getId(), true);

        // 计算积分调整，优先使用实体分数；若为空（如机器人），退回到VO的显示分数
        final int winerScoreForCalc = (winer != null) ? winer.getGameScore() : winerVo.getGameScore();
        final int loserScoreForCalc = (loser_ != null) ? loser_.getGameScore() : loserVo.getGameScore();
        final int adjustment = calculateWinerScoreAdjustment(winerScoreForCalc, loserScoreForCalc);

        // 获取魔法泡泡奖励/惩罚值
        SysParam sysParam = sysParamBo.findById(SysParam.COW_DUNG_PER_GAME, true);
        int cowDungPerGame = Integer.parseInt(sysParam.getParamValue());

        // 更新赢家VO的显示数据（用于实时展示，实际数据由前端更新后同步）
        if (winer != null) {
            UserGameVo userGameVo = winerVo.getGameByName("russia");
            userGameVo.setWinCount(userGameVo.getWinCount() + 1);
            userGameVo.setScore(userGameVo.getScore() + adjustment);
            winerVo.setGameScore(winerVo.getGameScore() + adjustment);
            winerVo.setCowDung(winerVo.getCowDung() + cowDungPerGame);
        } else {
            // 机器人赢家：仅更新VO显示分数
            UserGameVo userGameVo = winerVo.getGameByName("russia");
            userGameVo.setWinCount(userGameVo.getWinCount() + 1);
            userGameVo.setScore(userGameVo.getScore() + adjustment);
            winerVo.setGameScore(winerVo.getGameScore() + adjustment);
        }

        // 计算输家的积分扣减（避免变成负数）
        int loserScoreDelta;
        if (loser_ != null) {
            UserGameVo loserGameVo = loserVo.getGameByName("russia");
            Integer currentScore = loserGameVo.getScore();
            loserScoreDelta = Math.min(adjustment, currentScore == null ? 0 : currentScore);
            
            // 更新输家VO的显示数据
            loserGameVo.setLoseCount(loserGameVo.getLoseCount() + 1);
            loserGameVo.setScore((currentScore == null ? 0 : currentScore) - loserScoreDelta);
            loserVo.setGameScore(loserVo.getGameScore() - loserScoreDelta);
            loserVo.setCowDung(Math.max(0, loserVo.getCowDung() - cowDungPerGame));
        } else {
            // 机器人输家：仅更新VO显示分数
            int loserVoScore = loserVo.getGameScore();
            loserScoreDelta = Math.min(adjustment, Math.max(0, loserVoScore));
            loserVo.setGameScore(loserVoScore - loserScoreDelta);
            UserGameVo loserGameVo = loserVo.getGameByName("russia");
            if (loserGameVo != null) {
                loserGameVo.setLoseCount(loserGameVo.getLoseCount() + 1);
                loserGameVo.setScore(Math.max(0, loserGameVo.getScore() - loserScoreDelta));
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
