package beidanci.service.socket.system.game.russia.state;

import java.util.Map;
import java.util.Timer;
import java.util.TimerTask;
import java.util.concurrent.ConcurrentHashMap;

import org.apache.commons.lang3.NotImplementedException;

import org.slf4j.LoggerFactory;
import beidanci.api.model.*;
import beidanci.service.bo.DictBo;
import beidanci.service.bo.DictWordBo;
import beidanci.service.bo.SysParamBo;
import beidanci.service.bo.UserBo;
import beidanci.service.bo.UserGameBo;
import beidanci.service.bo.WordBo;
import beidanci.service.po.SysParam;
import beidanci.service.socket.SocketService;
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
    private static final org.slf4j.Logger log = org.slf4j.LoggerFactory.getLogger(ReadyState.class);

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
        if (isPlaying) {
            return true;
        }
        return room.getUsers().values().stream().anyMatch(u -> u != null && u.isExercise());
    }

    /**
     * 一道题允许的最长答题间隔。客户端的气泡到顶会自动上报一次漏答，
     * 所以在正常出题的情况下，两次答题上报的间隔一定会小于气泡升到顶的时间。
     * 明显超过这个间隔，说明客户端根本没在出题（例如退到后台被系统挂起）——
     * 这跟"漏答"是同一个物理事实，按漏答补扣。
     */
    private static final long MAX_ANSWER_GAP_MS = 60 * 1000;

    /**
     * 单次断线的宽限时长。传输层断开不等于用户走了，先给这段时间等他回来接管对局。
     */
    private static final long DISCONNECT_GRACE_MS = 60 * 1000;

    /**
     * 一局里累计可以断线的总时长。允许重连，但不允许"断 59 秒、回 1 秒"反复刷新宽限来拖住对手。
     */
    private static final long MAX_TOTAL_DISCONNECT_MS = 90 * 1000;

    // 前端上报下落触底 ETA 的调度器与任务表（按用户）
    private final Timer fallTimer = new Timer(true);
    private final Map<String, TimerTask> fallTasks = new ConcurrentHashMap<>();
    // 同一单词最多只+1的防抖标记：userId -> 是否已对当前下落单词做过+1
    private final Map<String, Boolean> stackAddedOnce = new ConcurrentHashMap<>();
    // 机器人自动开始游戏的定时任务
    private TimerTask botAutoStartTask = null;
    // 机器人延迟开始游戏的定时任务
    private TimerTask botDelayStartTask = null;
    // 机器人使用道具的延迟任务（避免立即反击, 显得更真实）
    private TimerTask botPropsDelayTask = null;

    // 机器人主循环任务
    private TimerTask botActionTask = null;
    // 机器人当前单词索引
    private int botWordIdx = 0;
    // 机器人定时器
    private Timer botTimer = null;
    // 缓存机器人用户对象
    private UserVo botUserObj = null;
    // 缓存人类用户对象
    private UserVo humanUserObj = null;

    /**
     * 触发机器人进行一次答题动作。
     * 
     * @param correct 是否回答正确。若为 null，则根据胜率随机决定。
     */
    private void triggerBotAnswer(Boolean correct) {
        if (!isPlaying || botUserObj == null) {
            return;
        }

        try {
            // 如果有待执行的常规思考任务，取消它
            if (botActionTask != null) {
                botActionTask.cancel();
                botActionTask = null;
            }

            // 机器人所依附的“真实玩家”历史胜率（机器人昵称与胜率均来自该玩家）
            double botWinRatio = 0.7;
            try {
                UserGameVo gameVo = botUserObj.getGameByName("russia");
                int w = gameVo != null && gameVo.getWinCount() != null ? gameVo.getWinCount() : 0;
                int l = gameVo != null && gameVo.getLoseCount() != null ? gameVo.getLoseCount() : 0;
                int total = w + l;
                // 胜率条件放开：如果总局数不足 3 局，则默认胜率为 70%，避免极少数局数导致的性能偏差
                if (total >= 3) {
                    botWinRatio = (double) w / total;
                } else {
                    botWinRatio = 0.7;
                }
            } catch (Exception ignored2) {
            }

            // 正确率：人类越强，机器人越强 [0.45, 0.95]
            double correctRate = Math.min(0.95, Math.max(0.45, 0.45 + botWinRatio * 0.5));
            UserGameData botData = room.getUserPlayData(botUserObj);

            // --- 自动使用道具（添加延迟，模拟人类反应时间） ---
            final UserGameData currentBotData = botData;

            // 1. 进攻逻辑（水雷/加一行 - 索引0）：有就发射轰击人类，带点随机延迟
            if (currentBotData.getPropsCounts()[0] > 0) {
                long attackDelay = 400L + (long) (Math.random() * 1000L);
                fallTimer.schedule(new TimerTask() {
                    @Override
                    public void run() {
                        try {
                            if (!isPlaying) return;
                            if (currentBotData.getPropsCounts()[0] > 0) {
                                UserCmd propsCmd = new UserCmd(userBo);
                                propsCmd.setUserId(botUserObj.getId());
                                propsCmd.setSystem("russia");
                                propsCmd.setCmd("USE_PROPS");
                                propsCmd.setArgs(new String[] { "0" });
                                room.processUserCmd(botUserObj, propsCmd);
                                LoggerFactory.getLogger(ReadyState.class).info("🤖 机器人使用了水雷道具(轰击人类玩家)");
                            }
                        } catch (Exception ignored) {}
                    }
                }, attackDelay);
            }

            // 2. 自救逻辑（飞针/减一行 - 索引1）：有就自救治愈，带点随机延迟
            if (currentBotData.getPropsCounts()[1] > 0 && botPropsDelayTask == null) {
                long delayMs = 500L + (long) (Math.random() * 1300L);
                botPropsDelayTask = new TimerTask() {
                    @Override
                    public void run() {
                        try {
                            if (!isPlaying) {
                                cancel();
                                return;
                            }
                            if (currentBotData.getPropsCounts()[1] > 0) {
                                UserCmd propsCmd = new UserCmd(userBo);
                                propsCmd.setUserId(botUserObj.getId());
                                propsCmd.setSystem("russia");
                                propsCmd.setCmd("USE_PROPS");
                                propsCmd.setArgs(new String[] { "1" });
                                room.processUserCmd(botUserObj, propsCmd);
                                LoggerFactory.getLogger(ReadyState.class).info("🤖 机器人使用了飞针道具(自救治愈)");
                            }
                            botPropsDelayTask = null;
                        } catch (Exception ignored) {
                        }
                    }
                };
                fallTimer.schedule(botPropsDelayTask, delayMs);
            }

            // 答题逻辑
            boolean isCorrect = (correct != null) ? correct
                    : (Math.random() < (correctRate + (Math.random() - 0.5) * 0.1));
            UserCmd cmd = new UserCmd(userBo);
            cmd.setUserId(botUserObj.getId());
            cmd.setSystem("russia");
            cmd.setCmd("GET_NEXT_WORD");
            cmd.setArgs(new String[] { String.valueOf(botWordIdx++), isCorrect ? "true" : "false", "" });
            room.processUserCmd(botUserObj, cmd);

            // 调度下一次动作
            long now = System.currentTimeMillis();
            long sinceLastOp = now - room.getUserPlayData(humanUserObj).getLastOperationTime();
            final long minDelay = 2000;
            final long maxDelay = 4800;
            long baseDelay = (long) (maxDelay - (correctRate - 0.45) / (0.95 - 0.45) * (maxDelay - minDelay));
            long thinkDelay = Math.max(minDelay, Math.min(maxDelay, Math.max(baseDelay, sinceLastOp)));
            long jitter = (long) ((Math.random() - 0.5) * 600);
            long delay = Math.max(minDelay, Math.min(maxDelay, thinkDelay + jitter));

            scheduleBotNext(delay);
        } catch (Exception e) {
            LoggerFactory.getLogger(ReadyState.class).error("机器人执行动作失败", e);
        }
    }

    private void scheduleBotNext(long delayMs) {
        if (!isPlaying || botUserObj == null)
            return;
        botActionTask = new TimerTask() {
            @Override
            public void run() {
                triggerBotAnswer(null);
            }
        };
        botTimer.schedule(botActionTask, delayMs);
    }

    /**
     * 答题上报的公共处理：取消该用户的触底计时；若答错，则堆叠+1（同一单词最多+1）。
     * 老协议 GET_NEXT_WORD 与新协议 ANSWER 共用这段逻辑。
     */
    private void processAnswerReport(UserVo user, UserCmd userCmd) {
        cancelFallTask(user);
        String[] args = userCmd.getArgs();
        if (args == null || args.length < 2 || !"false".equals(args[1])) {
            return;
        }
        String word = (args.length >= 3 && args[2] != null) ? args[2] : "";
        if (word.isEmpty()) {
            try {
                int wIdx = Integer.parseInt(args[0]);
                // 老协议里当前命令针对的是下一题，词拼写取自上一题
                word = getNextWordProcessor.getSpellByIndex(wIdx - 1);
            } catch (NumberFormatException ignored) {
                /* 安静忽略 */ }
        }
        tryAddStackOnce(user, word.isEmpty() ? "答错[]" : ("答错[" + word + "]"));
    }

    /**
     * 防挂起推演：客户端还连着，却长时间没有上报任何答题，说明它根本没在出题
     * （最常见的是被切到后台，渲染与定时器被系统挂起，气泡停在原地不动）。
     * 这跟"气泡到顶漏答"是同一个物理事实，所以按漏答补扣，不是新增惩罚。
     * 断线期间不推演——那是网络问题，走断线宽限，不能误伤真正网络不稳的用户。
     */
    private void applyAnswerGapPenalty(UserVo user) {
        UserGameData playData = room.getUserPlayData(user);
        if (playData == null || playData.getDisconnectedSinceMs() >= 0) {
            return;
        }
        long now = System.currentTimeMillis();
        long gap = now - playData.getLastAnswerAtMs();
        playData.setLastAnswerAtMs(now);
        if (gap <= MAX_ANSWER_GAP_MS) {
            return;
        }
        int missed = (int) Math.min(gap / MAX_ANSWER_GAP_MS, 10);
        addStackRows(user, missed, String.format("客户端%.0f秒未出题", gap / 1000.0));
    }

    /**
     * 连接断了：先进入宽限，保留对局等他重连接管，并把"对手暂时掉线"告诉还在线的一方。
     */
    public void markUserDisconnected(UserVo user) {
        UserGameData playData = room.getUserPlayData(user);
        if (playData == null || playData.getDisconnectedSinceMs() >= 0) {
            return;
        }
        playData.setDisconnectedSinceMs(System.currentTimeMillis());
        cancelFallTask(user);
        log.info(String.format("玩家[%s]连接中断，保留对局等待重连（单次宽限%.0f秒、单局累计上限%.0f秒）",
                Util.getNickNameOfUser(user), DISCONNECT_GRACE_MS / 1000.0, MAX_TOTAL_DISCONNECT_MS / 1000.0));
        UserVo opponent = room.getAnotherUser(user);
        if (opponent != null) {
            room.sendEventToUser(opponent, "opponentOffline", (int) (DISCONNECT_GRACE_MS / 1000));
        }
    }

    /**
     * 用户重连接管对局。
     *
     * @return true 表示接管成功、对局继续；false 表示本局累计断线已超上限、不能再接管
     */
    public boolean markUserReconnected(UserVo user) {
        UserGameData playData = room.getUserPlayData(user);
        if (playData == null || playData.getDisconnectedSinceMs() < 0) {
            return true;
        }
        long disconnectedMs = System.currentTimeMillis() - playData.getDisconnectedSinceMs();
        playData.setDisconnectedSinceMs(-1);
        playData.setTotalDisconnectedMs(playData.getTotalDisconnectedMs() + disconnectedMs);
        // 断线这段时间不算"客户端挂起"，否则重连后会被答题间隔再扣一次
        playData.setLastAnswerAtMs(System.currentTimeMillis());

        if (playData.getTotalDisconnectedMs() > MAX_TOTAL_DISCONNECT_MS) {
            log.info(String.format("玩家[%s]本局累计断线%.0f秒，超过上限%.0f秒，不再接管",
                    Util.getNickNameOfUser(user), playData.getTotalDisconnectedMs() / 1000.0,
                    MAX_TOTAL_DISCONNECT_MS / 1000.0));
            return false;
        }
        log.info(String.format("玩家[%s]重连成功，本局累计断线%.0f秒，对局继续",
                Util.getNickNameOfUser(user), playData.getTotalDisconnectedMs() / 1000.0));
        UserVo opponent = room.getAnotherUser(user);
        if (opponent != null) {
            room.sendEventToUser(opponent, "opponentOnline", null);
        }
        return true;
    }

    /**
     * 该用户是否已经不在这场对局里了：连接断了，或者长时间没有任何命令。
     * 用于判断"另一方是不是也早就掉线了"。
     */
    public boolean isUserGone(UserVo user) {
        UserGameData playData = room.getUserPlayData(user);
        if (playData == null) {
            return true;
        }
        return playData.getDisconnectedSinceMs() >= 0
                || System.currentTimeMillis() - playData.getLastOperationTime() > MAX_ANSWER_GAP_MS;
    }

    /**
     * 本局作废（双方都掉线）：不判负、不计分，只把对局关掉。
     */
    @Override
    public void voidGame() {
        isPlaying = false;
        for (UserVo u : room.getUsers().keySet()) {
            cancelFallTask(u);
        }
        stackAddedOnce.clear();
    }

    /**
     * 按漏答给用户补扣堆叠行数，并把服务端的权威行数同步给客户端校正血条。
     */
    private void addStackRows(UserVo user, int rows, String reason) {
        if (rows <= 0) {
            return;
        }
        UserGameData playData = room.getUserPlayData(user);
        playData.setStackRows(playData.getStackRows() + rows);
        log.info(String.format("🧱 玩家[%s] %s，堆叠+%d => %d",
                Util.getNickNameOfUser(user), reason, rows, playData.getStackRows()));
        room.sendEventToUser(user, "stackSync", new Object[]{playData.getStackRows(), reason});
        if (playData.getStackRows() >= 10) {
            try {
                gameOverProcessor.handleLoser(user);
            } catch (IllegalAccessException e) {
                log.error("处理游戏淘汰失败", e);
            }
        }
    }

    private void scheduleFallTask(UserVo user, long etaMs) {
        // 取消旧任务
        cancelFallTask(user);

        // 新词开始下落，重置“一次性+1”标记
        stackAddedOnce.put(user.getId(), Boolean.FALSE);

        if (etaMs <= 0) {
            // 立即处理触底
            tryAddStackOnce(user, "立即触底上报");
            return;
        }

        TimerTask task = new TimerTask() {
            @Override
            public void run() {
                try {
                    if (!isPlaying) {
                        cancel();
                        return;
                    }
                    // 若在ETA到达时该用户没有提交答题（近似判断：lastUserCmd不是GET_NEXT_WORD或时间未更新），则判定触底堆叠+1
                    tryAddStackOnce(user, "触底周期完成");
                } catch (Exception ignored) {
                    cancel();
                }
            }
        };
        fallTasks.put(user.getId(), task);
        fallTimer.schedule(task, etaMs);
    }

    private void cancelFallTask(UserVo user) {
        TimerTask old = fallTasks.remove(user.getId());
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
        LoggerFactory.getLogger(ReadyState.class)
                .info(String.format("🧱 玩家[%s] %s，堆叠+1 => %d",
                        Util.getNickNameOfUser(user), reason, pd.getStackRows()));

        // 如果堆叠达到 10 行（生命值耗尽淘汰），立即判定该玩家为失败者
        if (pd.getStackRows() >= 10) {
            try {
                gameOverProcessor.handleLoser(user);
            } catch (IllegalAccessException e) {
                LoggerFactory.getLogger(ReadyState.class).error("处理游戏淘汰失败", e);
            }
            return;
        }

        // 如果是机器人触底，强制立即进行下一次答题动作（Force False），解决高叠时的同步延迟
        if (botUserObj != null && user.getId().equals(botUserObj.getId())) {
            triggerBotAnswer(false);
        }
    }

    public ReadyState(RussiaRoom room, WordCache wordCache, WordBo wordBo, UserGameBo userGameBo, DictWordBo rawWordBo,
            UserSorter userSorter, SysParamBo sysParamBo, UserBo userBo, DictBo dictBo) {
        super(room);
        getNextWordProcessor = new GetNextWordProcessor(room);
        gameOverProcessor = new GameOverProcessor(room, sysParamBo, userBo, userGameBo);
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

                botAutoStartTask = new TimerTask() {
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

                                    LoggerFactory.getLogger(ReadyState.class)
                                            .info(String.format("机器人[%s]自动点击开始按钮完成，已调用processUserCmd",
                                                    Util.getNickNameOfUser(botUser)));
                                }
                            }
                        } catch (Exception e) {
                            LoggerFactory.getLogger(ReadyState.class)
                                    .error("机器人自动开始失败", e);
                        }
                    }
                };

                fallTimer.schedule(botAutoStartTask, delayMs);

                LoggerFactory.getLogger(ReadyState.class)
                        .info(String.format("已调度机器人[%s]在%.1f秒后自动开始",
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
                // 老协议：客户端每答一题就要一次词，服务端回 wordA（仅为兼容旧安装包保留）
                processAnswerReport(user, userCmd);
                getNextWordProcessor.processGetNextWordCmd(user, userCmd);
            }
            case "ANSWER" -> {
                // 新协议：客户端本地出题，答题结果只做单向上报，服务端不回 wordA
                // 顺便推演"客户端是不是根本没在出题"（退到后台挂起）
                applyAnswerGapPenalty(user);
                processAnswerReport(user, userCmd);
                getNextWordProcessor.processAnswerCmd(user, userCmd);
            }
            case "GET_WORD_PACK" -> getNextWordProcessor.processGetWordPackCmd(user, userCmd);
            case "START_EXERCISE" -> {
                // 单人练习命令
                getNextWordProcessor.reset();
                gameOverProcessor.reset();
                // 清空堆叠标记
                stackAddedOnce.clear();
                resetAnswerTiming(room.getUserPlayData(user));
                isPlaying = true;
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
                        if (opp.getStackRows() >= 10) {
                            gameOverProcessor.handleLoser(another);
                        }
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
                UserGameData playData = room.getUserPlayData(user);
                // 服务端自己按时间推演出来的行数更严时，以服务端为准：
                // 客户端报的是"它看见的漏答"，服务端推演的是"按时间它应该漏掉的"，
                // 同一个事实取更严的一方，客户端收到 stackSync 后会把血条校正过来。
                playData.setStackRows(Math.max(playData.getStackRows(), selfRows));
                if (playData.getStackRows() >= 10) {
                    gameOverProcessor.handleLoser(user);
                }
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
        if (botDelayStartTask != null) {
            botDelayStartTask.cancel();
            botDelayStartTask = null;
        }

        // 获取系统配置（每局游戏需要支付的魔法泡泡数）
        // 在socket线程中无事务环境，使用newSession方式避免获取currentSession失败
        SysParam sysParam = sysParamBo.findById(SysParam.COW_DUNG_PER_GAME, true);
        final int cowDungPerGame = Integer.parseInt(sysParam.getParamValue());

        // 检查用户是否有足够的魔法泡泡（机器人不需要检查）
        boolean isBot = user.getUserName() != null && user.getUserName().startsWith("bot_");
        if (!isBot && user.getCowDung() < cowDungPerGame) {
            LoggerFactory.getLogger(ReadyState.class)
                    .warn(String.format("用户[%s]魔法泡泡不足：需要%d，现有%d",
                            Util.getNickNameOfUser(user), cowDungPerGame, user.getCowDung()));
            room.sendEventToUser(user, "noEnoughCowDung", cowDungPerGame);
            return;
        }

        // 设置用户的游戏状态为"开始"
        UserGameData userPlayData1 = room.getUserPlayData(user);
        if (userPlayData1 == null) {
            return;
        }
        userPlayData1.setMatchStarted(true);
        room.broadcastEvent("userStarted", user.getId());

        // 获取另一位玩家的游戏状态信息
        UserVo anotherUser = room.getAnotherUser(user);
        UserGameData userPlayData2 = anotherUser != null ? room.getUserPlayData(anotherUser) : null;

        // 如果对手是机器人且机器人还未点击开始，延迟2-5秒后才设置机器人为已开始，让机器人显得更真实
        if (anotherUser != null && anotherUser.getUserName() != null && anotherUser.getUserName().startsWith("bot_")
                && userPlayData2 != null && !userPlayData2.isMatchStarted()) {
            // 随机延迟2-5秒（比之前更长，更像真人反应时间）
            long delayMs = 2000L + (long) (Math.random() * 3000L);
            final UserVo bot = anotherUser;
            final UserVo humanUser = user;
            botDelayStartTask = new TimerTask() {
                @Override
                public void run() {
                    try {
                        // 确保房间状态仍然是当前的 ReadyState 且游戏未开始
                        if (room.getState() != ReadyState.this || isPlaying) {
                            return;
                        }

                        // 检查机器人和人类玩家是否仍然在房间中
                        UserGameData botPlayData = room.getUserPlayData(bot);
                        UserGameData humanPlayData = room.getUserPlayData(humanUser);
                        if (botPlayData == null || humanPlayData == null) {
                            return;
                        }

                        // 机器人有10%的概率选择离开而不是开始游戏，更真实
                        // （因为人类已经点击开始，所以离开概率略低于主动开始时的概率）
                        double leaveChance = 0.10;
                        if (Math.random() < leaveChance) {
                            LoggerFactory.getLogger(ReadyState.class)
                                    .info(String.format("机器人[%s]在人类玩家开始后选择离开游戏（延迟%.1f秒后的决定）",
                                            Util.getNickNameOfUser(bot), delayMs / 1000.0));
                            // 让机器人离开房间
                            room.userLeave(bot);
                            return;
                        }

                        // 90%概率：先广播机器人点击了开始
                        room.broadcastEvent("userStarted", bot.getId());
                        LoggerFactory.getLogger(ReadyState.class)
                                .info(String.format("已广播机器人[%s]的userStarted事件",
                                        Util.getNickNameOfUser(bot)));

                        // 设置机器人为已开始状态
                        botPlayData.setMatchStarted(true);

                        // 检查双方是否都已开始，如果是则开始游戏
                        if (botPlayData.isMatchStarted() && humanPlayData.isMatchStarted()) {
                            startGame(humanUser, bot, humanPlayData, botPlayData);
                        }
                    } catch (Exception e) {
                        LoggerFactory.getLogger(ReadyState.class)
                                .error("机器人延迟开始失败", e);
                    } finally {
                        botDelayStartTask = null;
                    }
                }
            };
            fallTimer.schedule(botDelayStartTask, delayMs);
            return; // 机器人需要延迟，直接返回，不继续执行后面的开始游戏逻辑
        }

        // 如果两个用户都点击了【开始】按钮，则开始新游戏
        if (userPlayData2 != null && userPlayData1.isMatchStarted() && userPlayData2.isMatchStarted()) {
            startGame(user, anotherUser, userPlayData1, userPlayData2);
        }
    }

    /**
     * 开始游戏的核心逻辑（提取为独立方法，便于在延迟回调中复用）
     */
    /**
     * 复位一名玩家在本局里的状态（新一局开打时调用）。
     */
    private void resetUserGameData(UserGameData playData) {
        playData.setMatchStarted(false);
        playData.setCorrectCount(0);
        playData.getPropsCounts()[0] = 0;
        playData.getPropsCounts()[1] = 0;
        playData.setStackRows(0);
        playData.setExercise(false);
        resetAnswerTiming(playData);
    }

    /**
     * 复位答题计时基准：新的一局（或新开的单人练习）必须从现在开始计时，
     * 否则开局第一题的间隔会把"在房间里等对手的那几分钟"算成挂起，凭空扣血。
     */
    private void resetAnswerTiming(UserGameData playData) {
        playData.setDisconnectedSinceMs(-1);
        playData.setTotalDisconnectedMs(0);
        playData.setLastAnswerAtMs(System.currentTimeMillis());
    }

    /**
     * 开始游戏的核心逻辑（提取为独立方法，便于在延迟回调中复用）
     */
    private void startGame(UserVo user1, UserVo user2, UserGameData playData1, UserGameData playData2) {
        // 复位用户的游戏状态信息
        resetUserGameData(playData1);
        resetUserGameData(playData2);

        // 复位游戏状态
        gameOverProcessor.reset();
        getNextWordProcessor.reset();

        room.broadcastEvent("sysCmd", "BEGIN");
        isPlaying = true;
        for (TimerTask task : fallTasks.values()) {
            if (task != null) {
                task.cancel();
            }
        }
        fallTasks.clear();
        // 清空堆叠标记，避免上一局游戏状态影响新游戏
        stackAddedOnce.clear();
        if (botPropsDelayTask != null) {
            botPropsDelayTask.cancel();
            botPropsDelayTask = null;
        }

        // 确定哪个是机器人，哪个是真人
        UserVo botUser = null;
        if (user1 != null && user1.getUserName() != null && user1.getUserName().startsWith("bot_")) {
            botUser = user1;
        } else if (user2 != null && user2.getUserName() != null && user2.getUserName().startsWith("bot_")) {
            botUser = user2;
        }

        // 若存在机器人：根据对手历史胜率动态模拟答题
        if (botUser != null) {
            this.botUserObj = botUser;
            this.humanUserObj = (user1 == botUser) ? user2 : user1;
            this.botTimer = new Timer(true);
            this.botWordIdx = 0;
            // 首次调度：设置合理的初始延迟，让机器人与人类基本同步开始
            scheduleBotNext(800L);
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
        // 取消机器人延迟开始的任务
        if (botDelayStartTask != null) {
            botDelayStartTask.cancel();
            botDelayStartTask = null;
        }
        // 取消机器人道具延迟任务
        if (botPropsDelayTask != null) {
            botPropsDelayTask.cancel();
            botPropsDelayTask = null;
        }
        if (botTimer != null) {
            botTimer.cancel();
            botTimer = null;
        }
        if (botActionTask != null) {
            botActionTask.cancel();
            botActionTask = null;
        }
        for (TimerTask task : fallTasks.values()) {
            if (task != null) {
                task.cancel();
            }
        }
        fallTasks.clear();

        // 游戏正在进行中，用户退出，判为输家，另一方判为赢家
        if (isPlaying) {
            assert (room.getUsers().size() == 1);
            UserVo remaining = room.getUsers().keySet().iterator().next();
            if (isUserGone(remaining)) {
                // 对手早就掉线了，是我等不下去自己走的：判掉线方负（照常扣分），
                // 我这一局不背锅，否则"先断网拖着、等对手走人"就能白拿一胜
                log.info(String.format("玩家[%s]掉线期间对手[%s]离开本局，判掉线方负",
                        Util.getNickNameOfUser(remaining), Util.getNickNameOfUser(user)));
                room.broadcastEvent("loser", remaining.getId());
                gameOverProcessor.adjustUserScore(user, remaining);
                SocketService.getInstance().noticeGameResult(remaining.getId(),
                        "上一局因断线时间过长被判负，积分已按战败结算");
                isPlaying = false;
                stackAddedOnce.clear();
                room.broadcastUsersInfo();
                return;
            }
            UserVo winer = remaining;
            UserVo loser = user;
            room.broadcastEvent("loser", loser.getId());
            gameOverProcessor.adjustUserScore(winer, loser);
            isPlaying = false;
            // 清空堆叠标记
            stackAddedOnce.clear();
            room.broadcastUsersInfo();
        }
    }

}
