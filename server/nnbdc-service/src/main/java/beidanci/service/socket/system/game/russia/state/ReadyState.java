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

    /**
     * 旧客户端不上报节奏时的兜底值：0 层堆叠时一题的下落时间。
     * 新客户端每局会通过 GAME_PACING 上报真实的 baseFallMs，这里只在没有上报时使用。
     */
    private static final long BOT_BASE_FALL_MS = 6200;

    /**
     * 旧客户端不上报节奏时的兜底份额：前端按 maxHp + 2 = 12 行堆叠，
     * 方块自身还有半个高度，实际行程约等于 11 行的份额。
     */
    private static final int BOT_STACK_SLOTS = 11;

    /** 本局客户端上报的初始下落时间（毫秒）；未上报时用兜底值。 */
    private volatile long gameBaseFallMs = BOT_BASE_FALL_MS;

    /** 本局客户端上报的"每堆一层消耗的行程比例"；未上报时用兜底值。 */
    private volatile double gameRowFraction = 1.0 / BOT_STACK_SLOTS;

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
     * 机器人在当前堆叠高度下，下一题最多还能等多久。
     * 堆得越高、剩余行程越短，可用时间就越少；到点还没答按触底处理。
     */
    private long botAnswerWindowMs(int stackRows) {
        double remaining = 1.0 - stackRows * gameRowFraction;
        if (remaining < 0) {
            remaining = 0;
        }
        return (long) (gameBaseFallMs * remaining);
    }

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

            // 2. 自救逻辑（治疗/减一行 - 索引1）：自己确实堆了死词才用。
            //    满血时用治疗不会改变堆叠行数，玩家在对面完全看不出效果，等于白白浪费一个道具。
            if (currentBotData.getPropsCounts()[1] > 0
                    && currentBotData.getStackRows() > 0
                    && botPropsDelayTask == null) {
                long delayMs = 500L + (long) (Math.random() * 1300L);
                botPropsDelayTask = new TimerTask() {
                    @Override
                    public void run() {
                        try {
                            if (!isPlaying) {
                                cancel();
                                return;
                            }
                            if (currentBotData.getPropsCounts()[1] > 0 && currentBotData.getStackRows() > 0) {
                                UserCmd propsCmd = new UserCmd(userBo);
                                propsCmd.setUserId(botUserObj.getId());
                                propsCmd.setSystem("russia");
                                propsCmd.setCmd("USE_PROPS");
                                propsCmd.setArgs(new String[] { "1" });
                                room.processUserCmd(botUserObj, propsCmd);
                                LoggerFactory.getLogger(ReadyState.class).info("🤖 机器人使用了治疗道具(修复防线)");
                            }
                        } catch (Exception ignored) {
                        } finally {
                            // 不论正常执行、提前返回还是异常，都要放开这个槽位，否则后续整局都不会再治疗
                            botPropsDelayTask = null;
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

            // 机器人也要受"堆得越高、触底行程越短"的约束：
            // 按当前堆叠高度给它这道题的可用时间，到点还没答就按触底补一层。
            // 否则它只剩 1 格血时仍会按固定 2-4.8 秒慢悠悠答，和玩家承受的压迫完全不对称。
            scheduleFallTask(botUserObj, botAnswerWindowMs(currentBotData.getStackRows()));

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
     *
     * 处理完必须把 stackAddedOnce 复位：它只负责"同一单词的触底与答错不重复计数"，
     * 不是"一局只加一次"。机器人每答一题都走这里，不复位的话它整局只会堆到第 1 层，
     * 人类永远等不到它堆满 10 层，对局也就结束不了。
     */
    private void processAnswerReport(UserVo user, UserCmd userCmd) {
        cancelFallTask(user);
        String[] args = userCmd.getArgs();
        if (args == null || args.length < 2) {
            return;
        }
        // 每作答一题就累计一次进度，并广播给双方，供名字旁的"已出词数"显示
        UserGameData playData = room.getUserPlayData(user);
        playData.setAnsweredCount(playData.getAnsweredCount() + 1);
        room.broadcastEvent("wordCountSync", new Object[]{user.getId(), playData.getAnsweredCount()});

        if (!"false".equals(args[1])) {
            // 本题答对：本词没有堆叠，清掉标记给下一题用
            stackAddedOnce.put(user.getId(), Boolean.FALSE);
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
        tryAddStackOnce(user, word.isEmpty() ? "答错[]" : ("答错[" + word + "]"), false);
        // 本题处理完（不管这次是否真的加了一行），清掉标记给下一题用
        stackAddedOnce.put(user.getId(), Boolean.FALSE);
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
     * 该用户的断线宽限是否已经到点（该结算了）。
     * 必须有这个独立判定：客户端干净地断开时（关掉 App、切网络），服务端会话当场就被清理了，
     * 心跳检查再也看不到它，只靠心跳超时的话宽限永远不会到期——对手白等、分也永不结算。
     */
    public boolean isDisconnectGraceExpired(UserVo user) {
        UserGameData playData = room.getUserPlayData(user);
        return playData != null && playData.getDisconnectedSinceMs() >= 0
                && System.currentTimeMillis() - playData.getDisconnectedSinceMs() > DISCONNECT_GRACE_MS;
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
     * 局中人主动离开房间（点离开、换房间、长时间无操作被清理）：
     * 判他战败、对手判胜，与断线宽限到点判负是同一套结果。
     */
    public void handleUserLeft(UserVo user) throws IllegalAccessException {
        UserGameData playData = room.getUserPlayData(user);
        boolean leaverIsExercise = playData == null || playData.isExercise();
        boolean anyUserInExercise = room.getUsers().values().stream()
                .anyMatch(u -> u != null && u.isExercise());
        if (!shouldPunishLeaving(isPlaying, leaverIsExercise, anyUserInExercise)) {
            return;
        }
        log.info(String.format("玩家[%s]主动离开对局，判为战败", Util.getNickNameOfUser(user)));
        gameOverProcessor.handleLoser(user);
    }

    /**
     * 有人离开房间时，这一局该不该判他战败。
     *
     * 三种情况不判：这一局根本没在进行（还在等人、已经结算）；离开的人自己在做单人练习
     * （练习不计分，没有胜负可判）；房间里混着练习者（这一局同样不计分，而且用"别人离开"
     * 去占用 gameOverProcessor 的 loser 位，会把练习者自己结束练习时的判负一起吃掉——
     * handleLoser 认了第一次就不再认第二次，练习就会卡死在场上）。
     */
    public static boolean shouldPunishLeaving(boolean isPlaying, boolean leaverIsExercise,
            boolean anyUserInExercise) {
        return isPlaying && !leaverIsExercise && !anyUserInExercise;
    }

    /**
     * 把某个玩家当前的堆叠行数广播给房间里的双方：
     * 自己的客户端据此校正血条，对手的客户端据此看到对方的堆叠高度。
     * 事件载荷为 [userId, 堆叠行数, 原因]。
     */
    private void broadcastStackRows(UserVo user, String reason) {
        UserGameData playData = room.getUserPlayData(user);
        if (playData == null) {
            return;
        }
        room.broadcastEvent("stackSync", new Object[]{user.getId(), playData.getStackRows(), reason});
    }

    /**
     * 按漏答给用户补扣堆叠行数，并把双方的权威行数同步给客户端。
     */
    private void addStackRows(UserVo user, int rows, String reason) {
        if (rows <= 0) {
            return;
        }
        UserGameData playData = room.getUserPlayData(user);
        playData.setStackRows(playData.getStackRows() + rows);
        log.info(String.format("🧱 玩家[%s] %s，堆叠+%d => %d",
                Util.getNickNameOfUser(user), reason, rows, playData.getStackRows()));
        broadcastStackRows(user, reason);
        if (playData.getStackRows() >= 10) {
            try {
                decideLoser(user);
            } catch (IllegalAccessException e) {
                log.error("处理游戏淘汰失败", e);
            }
        }
    }

    /**
     * 判定失败者并立刻结束本局。
     *
     * <p>{@code isPlaying} 必须先落地：机器人答题链、触底计时、道具调度全靠它在下一拍自行退出。
     * 漏掉这一步，结算之后机器人还会在这局里继续答题、继续丢道具，客户端就会在"游戏已经结束"
     * 的界面上一直收到 propsUsed / stackSync（听感就是游戏还在打），房间也会卡在 isPlaying 里，
     * 新一局（含点「再来一局」）永远开不起来。
     */
    private void decideLoser(UserVo loser) throws IllegalAccessException {
        isPlaying = false;
        stackAddedOnce.clear();
        for (UserVo u : room.getUsers().keySet()) {
            cancelFallTask(u);
        }
        gameOverProcessor.handleLoser(loser);
    }

    private void scheduleFallTask(UserVo user, long etaMs) {
        // 取消旧任务
        cancelFallTask(user);

        // 新词开始下落，重置“一次性+1”标记
        stackAddedOnce.put(user.getId(), Boolean.FALSE);

        if (etaMs <= 0) {
            // 立即处理触底
            tryAddStackOnce(user, "立即触底上报", true);
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
                    tryAddStackOnce(user, "触底周期完成", true);
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

    private void tryAddStackOnce(UserVo user, String reason, boolean botFellThrough) {
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
        broadcastStackRows(user, reason);

        // 如果堆叠达到 10 行（生命值耗尽淘汰），立即判定该玩家为失败者
        if (pd.getStackRows() >= 10) {
            try {
                decideLoser(user);
            } catch (IllegalAccessException e) {
                LoggerFactory.getLogger(ReadyState.class).error("处理游戏淘汰失败", e);
            }
            return;
        }

        // 只有机器人真的触底（不是它自己答错）才强制补一次答题；
        // 答错路径本来就会在 triggerBotAnswer 末尾调度下一题，这里再触发会重排出两条答题链。
        if (botFellThrough && botUserObj != null && user.getId().equals(botUserObj.getId())) {
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
                                    // 连败会烦、连赢也会腻：按它在当前房间的连胜/连败掷一次"走不走"
                                    double leaveChance = room.getBotLeaveChance();
                                    if (Math.random() < leaveChance) {
                                        LoggerFactory.getLogger(ReadyState.class).info(String.format(
                                                "机器人[%s]当前%d连胜/%d连败，不想再开一局（离开概率%.0f%%），离开房间",
                                                Util.getNickNameOfUser(botUser), botData.getConsecutiveWins(),
                                                botData.getConsecutiveLosses(), leaveChance * 100));
                                        room.userLeave(botUser);
                                        return;
                                    }
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
            case "GAME_PACING" -> processGamePacing(user, userCmd);
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

    /**
     * 客户端上报本局真实的答题节奏：初始下落毫秒 + 每堆一层消耗的行程比例。
     * 机器人触底窗口直接用它计算；以后客户端调速度或行高，服务端会自动跟随，
     * 不再依赖服务端抄一份常数。旧客户端不上报时保留兜底值。
     */
    private void processGamePacing(UserVo user, UserCmd userCmd) {
        try {
            String[] args = userCmd.getArgs();
            if (args == null || args.length < 2) {
                return;
            }
            long baseMs = Long.parseLong(args[0]);
            double rowFraction = Double.parseDouble(args[1]);
            if (baseMs < 1000 || baseMs > 30000 || rowFraction <= 0.0 || rowFraction >= 0.5) {
                log.warn(String.format("忽略非法的对局节奏上报: user=%s, baseMs=%d, rowFraction=%.4f",
                        Util.getNickNameOfUser(user), baseMs, rowFraction));
                return;
            }
            gameBaseFallMs = baseMs;
            gameRowFraction = rowFraction;
            log.info(String.format("对局节奏已更新: base=%dms, rowFraction=%.4f（机器人触底窗口将使用该值）",
                    baseMs, rowFraction));
        } catch (NumberFormatException e) {
            log.warn("解析对局节奏失败: user=" + Util.getNickNameOfUser(user));
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
                        broadcastStackRows(another, "对手导弹轰击");
                        if (opp.getStackRows() >= 10) {
                            decideLoser(another);
                        } else if (botUserObj != null && another.getId().equals(botUserObj.getId()) && isPlaying) {
                            // 机器人被导弹砸高了一层，触底窗口也要按新高度立即收紧
                            scheduleFallTask(another, botAnswerWindowMs(opp.getStackRows()));
                        }
                    }
                } else if (props == 1) {
                    playData.setStackRows(Math.max(0, playData.getStackRows() - 1));
                    broadcastStackRows(user, "海星修复防线");
                    // 机器人把自己治好后，按新的堆叠高度重算触底窗口；
                    // 否则旧窗口仍按治疗前的高度计时，会提前把刚治好的机器人压死。
                    if (botUserObj != null && user.getId().equals(botUserObj.getId()) && isPlaying) {
                        scheduleFallTask(user, botAnswerWindowMs(playData.getStackRows()));
                    }
                }
            } catch (Exception ignored) {
            }
        }
    }

    /**
     * 精准同步堆叠行数：
     * args[0] = 自己的 rows；服务端取更严的一方，并把结果广播给双方。
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
                broadcastStackRows(user, "堆叠校正");
                if (playData.getStackRows() >= 10) {
                    decideLoser(user);
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

        // 用户是从「单人练习」直接转正式对战：练习本身也算一局（START_EXERCISE 会把 isPlaying 置真）。
        // 不先把这局练习收掉，下面机器人"延迟开赛"的回调会以为对局还在进行、直接 return，
        // 新一局就永远起不来——表现就是"我已经就绪，机器人一直不点开始"。
        UserGameData callerData = room.getUserPlayData(user);
        if (callerData != null && callerData.isExercise()) {
            callerData.setExercise(false);
            isPlaying = false;
            stackAddedOnce.clear();
            cancelFallTask(user);
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
                        // 确保房间状态仍然是当前的 ReadyState 且没有对局在跑
                        if (room.getState() != ReadyState.this) {
                            return;
                        }
                        if (isPlaying) {
                            // 以前这里是静默 return：一旦 isPlaying 卡住，机器人永远不点开始，
                            // 日志里一个字都看不到。留一条 warn，让这类"开不了局"能被追溯到。
                            log.warn(String.format("机器人[%s]延迟开赛被跳过：本局仍在进行中（isPlaying=true）",
                                    Util.getNickNameOfUser(bot)));
                            return;
                        }

                        // 检查机器人和人类玩家是否仍然在房间中
                        UserGameData botPlayData = room.getUserPlayData(bot);
                        UserGameData humanPlayData = room.getUserPlayData(humanUser);
                        if (botPlayData == null || humanPlayData == null) {
                            return;
                        }

                        // 连败会烦、连赢也会腻：真人这两种情况下都会走，不再固定 10%
                        double leaveChance = room.getBotLeaveChance();
                        if (Math.random() < leaveChance) {
                            LoggerFactory.getLogger(ReadyState.class)
                                    .info(String.format(
                                            "机器人[%s]当前%d连胜/%d连败，在人类玩家开始后离开游戏（延迟%.1f秒后的决定）",
                                            Util.getNickNameOfUser(bot), botPlayData.getConsecutiveWins(),
                                            botPlayData.getConsecutiveLosses(), delayMs / 1000.0));
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
        playData.setAnsweredCount(0);
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
            // 首次调度：等画面真的开始再落子。
            // 客户端开局有 1.4 秒开场动画，第一块砖落地还要再等一会儿；以前固定 800ms 抢答，
            // 玩家还没看到第一块砖，机器人就已经答完一题——那题一旦判错，对面开局就白丢一格防线
            // （线上表现：新一局刚开始，对手那边已经有一格红色）。
            // 取"这一题下落窗口的一半"：既在开场动画之后，也不会慢到超过触底窗口。
            scheduleBotNext(Math.max(2600L, botAnswerWindowMs(0) / 2));
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
