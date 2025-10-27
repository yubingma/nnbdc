package beidanci.service.socket.system.game.russia.state;

import java.util.Timer;
import java.util.TimerTask;

import org.apache.commons.lang3.NotImplementedException;

import beidanci.api.model.UserVo;
import beidanci.service.bo.DictBo;
import beidanci.service.bo.DictWordBo;
import beidanci.service.bo.SysParamBo;
import beidanci.service.bo.UserBo;
import beidanci.service.bo.UserGameBo;
import beidanci.service.bo.WordBo;
import beidanci.service.po.SysParam;
import beidanci.service.socket.UserCmd;
import beidanci.service.socket.system.game.russia.RussiaRoom;
import beidanci.service.socket.system.game.russia.UserGameData;
import beidanci.service.store.WordCache;
import beidanci.service.util.UserSorter;
import beidanci.service.util.Util;

/**
 * 当游戏室有两人时，即进入Ready State.
 *
 * @author Administrator
 */
public class ReadyState extends RoomState {

    private final GetNextWordProcessor getNextWordProcessor;
    private final GameOverProcessor gameOverProcessor;
    private final StartExerciseProcessor startExerciseProcessor;
    private final SysParamBo sysParamBo;
    private final UserBo userBo;

    /**
     * 游戏是否正在进行中
     */
    boolean isPlaying;

    /**
     * 检查游戏是否正在进行中
     */
    public boolean isGamePlaying() {
        return isPlaying;
    }

    // 前端上报下落触底 ETA 的调度器与任务表（按用户）
    private final java.util.Timer fallTimer = new java.util.Timer(true);
    private final java.util.Map<String, java.util.TimerTask> fallTasks = new java.util.concurrent.ConcurrentHashMap<>();
    // 同一单词最多只+1的防抖标记：userId -> 是否已对当前下落单词做过+1
    private final java.util.Map<String, java.lang.Boolean> stackAddedOnce = new java.util.concurrent.ConcurrentHashMap<>();
    // 机器人自动开始游戏的定时任务
    private java.util.TimerTask botAutoStartTask = null;
    // 记录机器人上次的堆叠行数，用于检测是否被攻击
    private int botLastStackRows = 0;
    // 机器人使用道具的延迟任务（避免立即反击, 显得更真实）
    private java.util.TimerTask botPropsDelayTask = null;

    /**
     * 递归调度机器人动作（用道具 + 答题），避免局部 lambda 的捕获初始化问题。
     */
    private void scheduleBotNext(java.util.Timer botTimer, long delayMs, UserVo botUser, UserVo humanUser, int[] idx) {
        botTimer.schedule(new java.util.TimerTask() {
            @Override
            public void run() {
                try {
                    if (!isPlaying) {
                        cancel();
                        return;
                    }

                    // 机器人所依附的“真实玩家”历史胜率（机器人昵称与胜率均来自该玩家）
                    double botWinRatio = 0.5;
                    try {
                        beidanci.api.model.UserGameVo gameVo = botUser.getGameByName("russia");
                        Integer winCountObj = gameVo.getWinCount();
                        Integer loseCountObj = gameVo.getLoseCount();
                        int w = winCountObj != null ? winCountObj : 0;
                        int l = loseCountObj != null ? loseCountObj : 0;
                        int total = Math.max(1, w + l);
                        botWinRatio = w * 1.0 / total;
                    } catch (Exception ignored2) {
                    }

                    // 正确率：人类越强，机器人越强 [0.45, 0.95] - 保持原有正确率
                    double correctRate = Math.min(0.95, Math.max(0.45, 0.45 + botWinRatio * 0.5));
                    // 思考时间：正确率越低，思考时间越长，上界接近“单词落到底部”的时间
                    long now = System.currentTimeMillis();
                    long sinceLastOp = now - room.getUserPlayData(humanUser).getLastOperationTime();
                    final long minDelay = 2000; // 提高机器人答题速度20%：从2500减少到2000
                    final long maxDelay = 4800; // 提高机器人答题速度20%：从6000减少到4800
                    long baseDelay = (long) (maxDelay - (correctRate - 0.45) / (0.95 - 0.45) * (maxDelay - minDelay));
                    long thinkDelay = Math.max(minDelay, Math.min(maxDelay, Math.max(baseDelay, sinceLastOp)));
                    long jitter = (long) ((Math.random() - 0.5) * 600); // 增加随机性
                    thinkDelay = Math.max(minDelay, Math.min(maxDelay, thinkDelay + jitter));

                    // --- 自动使用道具（添加延迟，模拟人类反应时间） ---
                    UserGameData botData = room.getUserPlayData(botUser);
                    int currentStackRows = botData.getStackRows();

                    // 检测堆叠行数是否增加（说明被对手攻击了）
                    if (currentStackRows > botLastStackRows && botData.getPropsCounts()[1] > 0
                            && botPropsDelayTask == null) {
                        // 堆叠行数增加了，延迟300ms-2秒后使用"减一行"道具，模拟人类反应时间
                        long delayMs = 300L + (long) (Math.random() * 1700L);
                        botPropsDelayTask = new java.util.TimerTask() {
                            @Override
                            public void run() {
                                try {
                                    if (!isPlaying) {
                                        cancel();
                                        return;
                                    }
                                    UserGameData currentBotData = room.getUserPlayData(botUser);
                                    if (currentBotData.getPropsCounts()[1] > 0 && currentBotData.getStackRows() > 0) {
                                        UserCmd propsCmd = new UserCmd(userBo);
                                        propsCmd.setUserBo(userBo);
                                        java.lang.reflect.Field fUserId2 = UserCmd.class.getDeclaredField("userId");
                                        fUserId2.setAccessible(true);
                                        fUserId2.set(propsCmd, botUser.getId());
                                        java.lang.reflect.Field fSystem2 = UserCmd.class.getDeclaredField("system");
                                        fSystem2.setAccessible(true);
                                        fSystem2.set(propsCmd, "russia");
                                        java.lang.reflect.Field fCmd2 = UserCmd.class.getDeclaredField("cmd");
                                        fCmd2.setAccessible(true);
                                        fCmd2.set(propsCmd, "USE_PROPS");
                                        java.lang.reflect.Field fArgs2 = UserCmd.class.getDeclaredField("args");
                                        fArgs2.setAccessible(true);
                                        fArgs2.set(propsCmd, new String[] { "1" });
                                        room.processUserCmd(botUser, propsCmd);
                                        // 打印机器人使用"减一行"日志
                                        org.slf4j.LoggerFactory.getLogger(ReadyState.class)
                                                .info(String.format("🤖 机器人[%s] 延迟%.1f秒后使用了道具[减一行]，库存：加一行=%d，减一行=%d",
                                                        beidanci.service.util.Util.getNickNameOfUser(botUser),
                                                        delayMs / 1000.0,
                                                        currentBotData.getPropsCounts()[0],
                                                        currentBotData.getPropsCounts()[1]));
                                    }
                                    botPropsDelayTask = null;
                                } catch (Exception ignored) {
                                }
                            }
                        };
                        fallTimer.schedule(botPropsDelayTask, delayMs);
                    }

                    // 更新记录的堆叠行数
                    botLastStackRows = currentStackRows;
                    if (botData.getPropsCounts()[0] > 0) {
                        UserCmd propsCmd2 = new UserCmd(userBo);
                        propsCmd2.setUserBo(userBo);
                        java.lang.reflect.Field fUserId3 = UserCmd.class.getDeclaredField("userId");
                        fUserId3.setAccessible(true);
                        fUserId3.set(propsCmd2, botUser.getId());
                        java.lang.reflect.Field fSystem3 = UserCmd.class.getDeclaredField("system");
                        fSystem3.setAccessible(true);
                        fSystem3.set(propsCmd2, "russia");
                        java.lang.reflect.Field fCmd3 = UserCmd.class.getDeclaredField("cmd");
                        fCmd3.setAccessible(true);
                        fCmd3.set(propsCmd2, "USE_PROPS");
                        java.lang.reflect.Field fArgs3 = UserCmd.class.getDeclaredField("args");
                        fArgs3.setAccessible(true);
                        fArgs3.set(propsCmd2, new String[] { "0" });
                        room.processUserCmd(botUser, propsCmd2);
                    }

                    // 答题：保持原有正确率，主要调整速度
                    double jitterRate = (Math.random() - 0.5) * 0.1;
                    boolean correct = Math.random() < Math.min(0.98, Math.max(0.02, correctRate + jitterRate));

                    UserCmd cmd = new UserCmd(userBo);
                    cmd.setUserBo(userBo);
                    java.lang.reflect.Field fUserId = UserCmd.class.getDeclaredField("userId");
                    fUserId.setAccessible(true);
                    fUserId.set(cmd, botUser.getId());
                    java.lang.reflect.Field fSystem = UserCmd.class.getDeclaredField("system");
                    fSystem.setAccessible(true);
                    fSystem.set(cmd, "russia");
                    java.lang.reflect.Field fCmd = UserCmd.class.getDeclaredField("cmd");
                    fCmd.setAccessible(true);
                    fCmd.set(cmd, "GET_NEXT_WORD");
                    java.lang.reflect.Field fArgs = UserCmd.class.getDeclaredField("args");
                    fArgs.setAccessible(true);
                    fArgs.set(cmd, new String[] { String.valueOf(idx[0]++), correct ? "true" : "false", "" });
                    room.processUserCmd(botUser, cmd);

                    // 下一次
                    scheduleBotNext(botTimer, thinkDelay, botUser, humanUser, idx);
                } catch (IllegalAccessException | IllegalArgumentException | NoSuchFieldException
                        | SecurityException ignored) {
                    cancel();
                }
            }
        }, delayMs);
    }

    private void scheduleFallTask(UserVo user, long etaMs) {
        // 取消旧任务
        cancelFallTask(user);
        if (etaMs <= 0)
            return;
        // 新词开始下落，重置“一次性+1”标记
        stackAddedOnce.put(user.getId(), Boolean.FALSE);
        java.util.TimerTask task = new java.util.TimerTask() {
            @Override
            public void run() {
                try {
                    if (!isPlaying) {
                        cancel();
                        return;
                    }
                    // 若在ETA到达时该用户没有提交答题（近似判断：lastUserCmd不是GET_NEXT_WORD或时间未更新），则判定触底堆叠+1
                    tryAddStackOnce(user, "触底");
                } catch (Exception ignored) {
                    cancel();
                }
            }
        };
        fallTasks.put(user.getId(), task);
        fallTimer.schedule(task, Math.max(1, etaMs));
    }

    private void cancelFallTask(UserVo user) {
        java.util.TimerTask old = fallTasks.remove(user.getId());
        if (old != null)
            old.cancel();
    }

    private void tryAddStackOnce(UserVo user, String reason) {
        Boolean added = stackAddedOnce.get(user.getId());
        if (Boolean.TRUE.equals(added))
            return; // 已加过，忽略
        // 未加过：执行+1并置已加
        UserGameData pd = room.getUserPlayData(user);
        pd.setStackRows(pd.getStackRows() + 1);
        stackAddedOnce.put(user.getId(), Boolean.TRUE);
        org.slf4j.LoggerFactory.getLogger(ReadyState.class)
                .info(String.format("🧱 玩家[%s] %s，堆叠+1 => %d",
                        Util.getNickNameOfUser(user), reason, pd.getStackRows()));
    }

    public ReadyState(RussiaRoom room, WordCache wordCache, WordBo wordBo, UserGameBo userGameBo, DictWordBo rawWordBo,
            UserSorter userSorter, SysParamBo sysParamBo, UserBo userBo, DictBo dictBo) {
        super(room);
        getNextWordProcessor = new GetNextWordProcessor(room);
        gameOverProcessor = new GameOverProcessor(room, sysParamBo, userBo);
        startExerciseProcessor = new StartExerciseProcessor(room);
        this.sysParamBo = sysParamBo;
        this.userBo = userBo;
    }

    /**
     * 调度机器人自动点击开始按钮
     */
    private void scheduleBotAutoStart() {
        // 取消之前的任务
        if (botAutoStartTask != null) {
            botAutoStartTask.cancel();
            botAutoStartTask = null;
        }

        // 检查房间内是否有机器人，如果有，让机器人在3-10秒后自动点击开始
        for (UserVo user : room.getUsers().keySet()) {
            if (user.getUserName() != null && user.getUserName().startsWith("bot_")) {
                // 随机延迟3-10秒
                long delayMs = 3000L + (long) (Math.random() * 7000L);
                final UserVo botUser = user;

                botAutoStartTask = new java.util.TimerTask() {
                    @Override
                    public void run() {
                        try {
                            // 检查机器人是否还在房间内且还未开始
                            if (room.getUsers().containsKey(botUser)) {
                                UserGameData botData = room.getUserPlayData(botUser);
                                if (botData != null && !botData.isMatchStarted() && !isPlaying) {
                                    // 模拟机器人点击开始按钮
                                    UserCmd startCmd = new UserCmd(userBo);
                                    startCmd.setUserBo(userBo);
                                    java.lang.reflect.Field fUserId = UserCmd.class.getDeclaredField("userId");
                                    fUserId.setAccessible(true);
                                    fUserId.set(startCmd, botUser.getId());
                                    java.lang.reflect.Field fSystem = UserCmd.class.getDeclaredField("system");
                                    fSystem.setAccessible(true);
                                    fSystem.set(startCmd, "russia");
                                    java.lang.reflect.Field fCmd = UserCmd.class.getDeclaredField("cmd");
                                    fCmd.setAccessible(true);
                                    fCmd.set(startCmd, "START_GAME");
                                    java.lang.reflect.Field fArgs = UserCmd.class.getDeclaredField("args");
                                    fArgs.setAccessible(true);
                                    fArgs.set(startCmd, new String[] {});

                                    room.processUserCmd(botUser, startCmd);

                                    org.slf4j.LoggerFactory.getLogger(ReadyState.class)
                                            .info(String.format("🤖 机器人[%s]自动点击开始按钮完成，已调用processUserCmd",
                                                    Util.getNickNameOfUser(botUser)));
                                }
                            }
                        } catch (Exception e) {
                            org.slf4j.LoggerFactory.getLogger(ReadyState.class)
                                    .error("机器人自动开始失败", e);
                        }
                    }
                };

                fallTimer.schedule(botAutoStartTask, delayMs);

                org.slf4j.LoggerFactory.getLogger(ReadyState.class)
                        .info(String.format("🤖 已调度机器人[%s]在%.1f秒后自动开始",
                                Util.getNickNameOfUser(botUser), delayMs / 1000.0));
                break; // 只处理一个机器人
            }
        }
    }

    @Override
    public void enter() {
        room.broadcastEvent("enterReady", null);
        // 调度机器人自动开始
        scheduleBotAutoStart();
    }

    @Override
    public void processUserCmd(UserVo user, UserCmd userCmd) throws IllegalAccessException {
        switch (userCmd.getCmd()) {
            case "GET_NEXT_WORD" -> {
                // 收到答题，取消该用户的触底计时；若答错，则堆叠+1（同一单词最多+1）
                cancelFallTask(user);
                String[] args = userCmd.getArgs();
                if (args != null && args.length >= 2 && "false".equals(args[1])) {
                    String word = (args.length >= 3 && args[2] != null) ? args[2] : "";
                    if (word.isEmpty()) {
                        try {
                            int wIdx = Integer.parseInt(args[0]);
                            // 取上一题的单词（当前 GET_NEXT_WORD 针对的是下一题）
                            word = getNextWordProcessor.getSpellByIndex(wIdx - 1);
                        } catch (NumberFormatException ignored) {
                            /* 安静忽略 */ }
                    }
                    String reason = word.isEmpty() ? "答错[]" : ("答错[" + word + "]");
                    tryAddStackOnce(user, reason);
                }
                getNextWordProcessor.processGetNextWordCmd(user, userCmd);
            }
            case "START_EXERCISE" -> {
                // 单人练习命令
                getNextWordProcessor.reset();
                gameOverProcessor.reset();
                // 清空堆叠标记
                stackAddedOnce.clear();
                startExerciseProcessor.process(user, userCmd);
            }
            case "GAME_OVER" -> {
                isPlaying = false;
                // 清空堆叠标记
                stackAddedOnce.clear();
                gameOverProcessor.processGameOverCmd(user, userCmd);
                // 游戏结束后，重新调度机器人自动开始（为下一局做准备）
                scheduleBotAutoStart();
            }
            case "START_GAME" -> processStartGameCmd(user);
            case "REPORT_FALL_B" -> {
                // 仅当对手是机器人时，接受 B 侧（机器人）的 ETA 并调度触底判定
                try {
                    UserVo bot = room.getAnotherUser(user);
                    if (bot != null && bot.getUserName() != null && bot.getUserName().startsWith("bot_")) {
                        String[] args = userCmd.getArgs();
                        if (args != null && args.length >= 1) {
                            long etaMs = Long.parseLong(args[0]);
                            scheduleFallTask(bot, etaMs); // 新词：重置一次性标记在scheduleFallTask中
                        }
                    }
                } catch (NumberFormatException ignored) {
                }
            }
            case "REPORT_STACK_ROWS" -> processReportStackRows(user, userCmd);
            case "USE_PROPS" -> processUsePropsCmd(user, Integer.parseInt(userCmd.getArgs()[0]));
            default -> throw new NotImplementedException(String.format("Don't support cmd[%s]", userCmd.getCmd()));
        }

    }

    private void processUsePropsCmd(UserVo user, int props) {
        UserGameData playData = room.getUserPlayData(user);
        if (playData.getPropsCounts()[props] > 0) {
            playData.getPropsCounts()[props]--;
            room.broadcastEvent("propsUsed", new Object[] { user.getId(), props, playData.getPropsCounts()[props],
                    Util.getNickNameOfUser(user) });

            // 精准维护 stackRows：
            // 加一行(0) → 对手堆叠 +1；减一行(1) → 自己堆叠 -1
            try {
                if (props == 0) {
                    UserVo another = room.getAnotherUser(user);
                    if (another != null) {
                        UserGameData opp = room.getUserPlayData(another);
                        opp.setStackRows(opp.getStackRows() + 1);
                    }
                } else if (props == 1) {
                    playData.setStackRows(Math.max(0, playData.getStackRows() - 1));
                }
            } catch (Exception ignored) {
            }
        }
    }

    /**
     * 精准同步堆叠行数：
     * args[0] = 自己的 rows；可选 args[1] = 对手的 rows（若前端已一并上报）
     */
    private void processReportStackRows(UserVo user, UserCmd userCmd) throws IllegalAccessException {
        try {
            String[] args = userCmd.getArgs();
            if (args.length >= 1) {
                int selfRows = Integer.parseInt(args[0]);
                room.getUserPlayData(user).setStackRows(selfRows);
            }
            // 不再接收/处理对手行数，仅接收 A 玩家自身行数
        } catch (NumberFormatException ignored) {
            // 忽略异常输入，避免中断对局
        }
    }

    private void processStartGameCmd(UserVo user) throws IllegalAccessException {
        // 取消机器人自动开始的任务（因为用户已经点击开始）
        if (botAutoStartTask != null) {
            botAutoStartTask.cancel();
            botAutoStartTask = null;
        }

        // 获取系统配置（每局游戏需要支付的魔法泡泡数）
        // 在socket线程中无事务环境，使用newSession方式避免获取currentSession失败
        SysParam sysParam = sysParamBo.findById(SysParam.COW_DUNG_PER_GAME, true);
        final int cowDungPerGame = Integer.parseInt(sysParam.getParamValue());

        // 检查用户是否有足够的魔法泡泡（机器人不需要检查）
        boolean isBot = user.getUserName() != null && user.getUserName().startsWith("bot_");
        if (!isBot && user.getCowDung() < cowDungPerGame) {
            org.slf4j.LoggerFactory.getLogger(ReadyState.class)
                    .warn(String.format("❌ 用户[%s]魔法泡泡不足：需要%d，现有%d",
                            Util.getNickNameOfUser(user), cowDungPerGame, user.getCowDung()));
            room.sendEventToUser(user, "noEnoughCowDung", cowDungPerGame);
            return;
        }


        // 设置用户的游戏状态为"开始"
        UserGameData userPlayData1 = room.getUserPlayData(user);
        userPlayData1.setMatchStarted(true);
        room.broadcastEvent("userStarted", user.getId());


        // 获取另一位玩家的游戏状态信息
        UserVo anotherUser = room.getAnotherUser(user);
        UserGameData userPlayData2 = room.getUserPlayData(anotherUser);
        
        // 如果对手是机器人且机器人还未点击开始，延迟2-5秒后才设置机器人为已开始，让机器人显得更真实
        if (anotherUser != null && anotherUser.getUserName() != null && anotherUser.getUserName().startsWith("bot_") 
                && !userPlayData2.isMatchStarted()) {
            // 随机延迟2-5秒（比之前更长，更像真人反应时间）
            long delayMs = 2000L + (long) (Math.random() * 3000L);
            final UserVo bot = anotherUser;
            final UserVo humanUser = user;
            new Timer(true).schedule(new TimerTask() {
                @Override
                public void run() {
                    try {
                        // 机器人有10%的概率选择离开而不是开始游戏，更真实
                        // （因为人类已经点击开始，所以离开概率略低于主动开始时的概率）
                        double leaveChance = 0.10;
                        if (Math.random() < leaveChance) {
                            org.slf4j.LoggerFactory.getLogger(ReadyState.class)
                                    .info(String.format("🤖 机器人[%s]在人类玩家开始后选择离开游戏（延迟%.1f秒后的决定）",
                                            Util.getNickNameOfUser(bot), delayMs / 1000.0));
                            // 让机器人离开房间
                            room.userLeave(bot);
                            return;
                        }

                        // 90%概率：先广播机器人点击了开始
                        room.broadcastEvent("userStarted", bot.getId());
                        org.slf4j.LoggerFactory.getLogger(ReadyState.class)
                                .info(String.format("✅ 已广播机器人[%s]的userStarted事件",
                                        Util.getNickNameOfUser(bot)));

                        // 设置机器人为已开始状态
                        UserGameData botPlayData = room.getUserPlayData(bot);
                        UserGameData humanPlayData = room.getUserPlayData(humanUser);
                        botPlayData.setMatchStarted(true);

                        // 检查双方是否都已开始，如果是则开始游戏
                        if (botPlayData.isMatchStarted() && humanPlayData.isMatchStarted()) {
                            startGame(humanUser, bot, humanPlayData, botPlayData);
                        }
                    } catch (Exception e) {
                        org.slf4j.LoggerFactory.getLogger(ReadyState.class)
                                .error("机器人延迟开始失败", e);
                    }
                }
            }, delayMs);
            return; // 机器人需要延迟，直接返回，不继续执行后面的开始游戏逻辑
        }

        // 如果两个用户都点击了【开始】按钮，则开始新游戏
        if (userPlayData1.isMatchStarted() && userPlayData2.isMatchStarted()) {
            startGame(user, anotherUser, userPlayData1, userPlayData2);
        }
    }

    /**
     * 开始游戏的核心逻辑（提取为独立方法，便于在延迟回调中复用）
     */
    private void startGame(UserVo user1, UserVo user2, UserGameData playData1, UserGameData playData2) {
        // 复位用户的游戏状态信息
        playData1.setMatchStarted(false);
        playData1.setCorrectCount(0);
        playData1.getPropsCounts()[0] = 0;
        playData1.getPropsCounts()[1] = 0;
        playData1.setStackRows(0);
        playData2.setMatchStarted(false);
        playData2.setCorrectCount(0);
        playData2.getPropsCounts()[0] = 0;
        playData2.getPropsCounts()[1] = 0;
        playData2.setStackRows(0);

        // 复位游戏状态
        gameOverProcessor.reset();
        getNextWordProcessor.reset();

        room.broadcastEvent("sysCmd", "BEGIN");
        isPlaying = true;
        // 清空历史触底计时
        fallTasks.values().forEach(java.util.TimerTask::cancel);
        fallTasks.clear();
        // 清空堆叠标记，避免上一局游戏状态影响新游戏
        stackAddedOnce.clear();
        // 重置机器人道具相关状态
        botLastStackRows = 0;
        if (botPropsDelayTask != null) {
            botPropsDelayTask.cancel();
            botPropsDelayTask = null;
        }

        // 确定哪个是机器人，哪个是真人
        UserVo botUser = null;
        UserVo humanUser = null;
        if (user1 != null && user1.getUserName() != null && user1.getUserName().startsWith("bot_")) {
            botUser = user1;
            humanUser = user2;
        } else if (user2 != null && user2.getUserName() != null && user2.getUserName().startsWith("bot_")) {
            botUser = user2;
            humanUser = user1;
        }

        // 若存在机器人：
        // 1) 根据对手历史胜率动态模拟答题：胜率越低，思考时间越长，并加入随机性
        // 2) 同时根据局势自动使用道具（自救优先，其次进攻），使用与答题共享的调度器
        if (botUser != null) {
            final java.util.Timer botTimer = new java.util.Timer(true);
            final int[] idx = new int[] { 0 };
            // 首次调度：设置合理的初始延迟，让机器人与人类基本同步开始
            scheduleBotNext(botTimer, 800L, botUser, humanUser, idx);
        }

        // 两位玩家各扣除若干魔法泡泡（按照系统配置）
        /*
         * for (UserVo userVo : room.getUsers().keySet()) {
         * User user2 = Global.getUserBo().findById(userVo.getId());
         * Global.getUserBo().adjustCowDung(user2, cowDungPerGame * (-1),
         * "游戏开始时扣除的魔法泡泡");
         * }
         */

        room.broadcastUsersInfo();
    }

    @Override
    public void exit(UserVo user) throws IllegalAccessException {
        // 取消机器人自动开始的任务
        if (botAutoStartTask != null) {
            botAutoStartTask.cancel();
            botAutoStartTask = null;
        }
        // 取消机器人道具延迟任务
        if (botPropsDelayTask != null) {
            botPropsDelayTask.cancel();
            botPropsDelayTask = null;
        }

        // 游戏正在进行中，用户退出，判为输家，另一方判为赢家
        if (isPlaying) {
            assert (room.getUsers().size() == 1);
            UserVo winer = room.getUsers().keySet().iterator().next();
            UserVo loser = user;
            room.broadcastEvent("loser", loser.getId());
            gameOverProcessor.adjustUserScore(winer, loser);
            isPlaying = false;
            fallTasks.values().forEach(java.util.TimerTask::cancel);
            fallTasks.clear();
            // 清空堆叠标记
            stackAddedOnce.clear();
            room.broadcastUsersInfo();
        }
    }

}
