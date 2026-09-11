package beidanci.service.socket.system.game.russia;

import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.Timer;
import java.util.TimerTask;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import beidanci.api.ChatObject;
import beidanci.api.model.UserGameInfo;
import beidanci.api.model.UserGameVo;
import beidanci.api.model.UserVo;
import beidanci.service.Global;
import beidanci.service.bo.DictBo;
import beidanci.service.bo.DictWordBo;
import beidanci.service.bo.LearningDictBo;
import beidanci.service.bo.SysParamBo;
import beidanci.service.bo.UserBo;
import beidanci.service.bo.UserGameBo;
import beidanci.service.bo.WordBo;
import beidanci.service.socket.UserCmd;
import beidanci.service.socket.system.game.russia.state.EmptyState;
import beidanci.service.socket.system.game.russia.state.GameOverProcessor;
import beidanci.service.socket.system.game.russia.state.ReadyState;
import beidanci.service.socket.system.game.russia.state.RoomState;
import beidanci.service.socket.system.game.russia.state.WaitState;
import beidanci.service.store.WordCache;
import beidanci.service.util.UserSorter;
import beidanci.service.util.Util;

public class RussiaRoom {
    private static final Logger log = LoggerFactory.getLogger(RussiaRoom.class);

    /**
     * 新游戏室编号由此值加1生成
     */
    private static final AtomicInteger roomSerialNo = new AtomicInteger(0);

    /**
     * 游戏室编号
     */
    private final int roomId;

    /**
     * 游戏室中的用户（两人）及状态
     */
    private final Map<UserVo, UserGameData> users = new ConcurrentHashMap<>();

    /**
     * 游戏室的当前状态，如果有一个人，为WaitSate；有两个人，为ReadyState; 没有人，为ExistingState
     */
    private RoomState state;

    /**
     * 是否为私有房间（仅通过房号进入，不参与大厅匹配）
     */
    private final boolean privateRoom;

    private final WordCache wordCache;

    private final WordBo wordBo;

    private final UserGameBo userGameBo;

    private final DictWordBo dictWordBo;

    private final UserSorter userSorter;

    private final SysParamBo sysParamBo;

    private final UserBo userBo;

    private final DictBo dictBo;

    /**
     * 游戏室所属的大厅
     */
    private final Hall hall;

    public RussiaRoom(UserVo user, Hall hall, WordCache wordCache, WordBo wordBo, UserGameBo userGameBo,
                      DictWordBo dictWordBo, UserSorter userSorter, SysParamBo sysParamBo, UserBo userBo,
                      LearningDictBo selectedDictBo, DictBo dictBo) {
        this(user, hall, wordCache, wordBo, userGameBo, dictWordBo, userSorter, sysParamBo, userBo, selectedDictBo, dictBo, false);
    }

    public RussiaRoom(UserVo user, Hall hall, WordCache wordCache, WordBo wordBo, UserGameBo userGameBo,
                      DictWordBo dictWordBo, UserSorter userSorter, SysParamBo sysParamBo, UserBo userBo,
                      LearningDictBo selectedDictBo, DictBo dictBo, boolean privateRoom) {
        this.roomId = roomSerialNo.incrementAndGet();
        this.hall = hall;
        this.wordCache = wordCache;
        this.wordBo = wordBo;
        this.userGameBo = userGameBo;
        this.dictWordBo = dictWordBo;
        this.userSorter = userSorter;
        this.sysParamBo = sysParamBo;
        this.userBo = userBo;
        this.dictBo = dictBo;
        this.privateRoom = privateRoom;
    }

    /**
     * 游戏室中用户数发生变化时，调用此函数切换游戏室状态
     */
    private void onUserCountChanged(UserVo user) throws IllegalAccessException {
        assert (users.size() <= 2);

        if (state != null) {
            state.exit(user);
        }

        state = switch (users.size()) {
            case 1 -> new WaitState(this, wordCache, wordBo, userGameBo, dictWordBo, userSorter, sysParamBo, userBo, dictBo);
            case 2 -> new ReadyState(this, wordCache, wordBo, userGameBo, dictWordBo, userSorter, sysParamBo, userBo, dictBo);
            default -> new EmptyState(this);
        };
        state.enter();
        hall.onRoomStateChanged(this);
        
        // 如果机器人离开后，房间中还剩下人类玩家，则自动进入新的机器人（私房间不允许机器人）
        if (!privateRoom && users.size() == 1 && state instanceof WaitState) {
            // 检查剩余的用户是否为人类玩家
            UserVo remainingUser = users.keySet().iterator().next();
            if (remainingUser.getUserName() == null || !remainingUser.getUserName().startsWith("bot_")) {
                scheduleBotEntry(remainingUser);
            }
        }
    }

    public RoomState getState() {
        return state;
    }

    public void broadcastEvent(String event, Object data) {
        for (UserVo user : users.keySet()) {
            hall.sendEvent2User(user, event, data);
        }
    }

    /**
     * 获取游戏室中的另一个用户
     *
     * @param user
     * @return
     */
    public UserVo getAnotherUser(UserVo user) {
        for (UserVo aUser : users.keySet()) {
            if (!aUser.equals(user)) {
                return aUser;
            }
        }

        return null;
    }

    public void sendEventToUser(UserVo toUser, String event, Object data) {
        hall.sendEvent2User(toUser, event, data);
    }

    /**
     * 判断用户是否在该游戏室中
     *
     * @param user
     * @return
     */
    public boolean hasUser(UserVo user) {
        for (UserVo aUser : users.keySet()) {
            if (aUser.equals(user)) {
                return true;
            }
        }
        return false;
    }

    public void userEnter(final UserVo user) throws IllegalAccessException {
        assert (users.size() < 2);

        // 创建用户的游戏数据
        UserGameData userPlayData = new UserGameData(user.getId());
        userPlayData.setMatchStarted(false);
        userPlayData.setExercise(false);
        users.put(user, userPlayData);

        // 向新进入房间的用户发送房间中现存用户的通知
        UserVo existingUser = getAnotherUser(user);
        if (existingUser != null) {
            hall.sendEvent2User(user, "enterRoom",
                    new Object[]{existingUser.getId(), Util.getNickNameOfUser(existingUser)});
        }

        // 广播用户进入消息
        broadcastEvent("enterRoom", new Object[]{user.getId(), Util.getNickNameOfUser(user)});

        // 通知用户进入的房间号
        hall.sendEvent2User(user, "roomId", roomId);

        onUserCountChanged(user);
        broadcastUsersInfo();

        // 如果是私房间，则不自动加入机器人
        if (!privateRoom && users.size() == 1 && (user.getUserName() == null || !user.getUserName().startsWith("bot_"))) {
            scheduleBotEntry(user);
        }
    }

    /**
     * 延迟调度机器人进入房间
     * @param humanUser 人类玩家，用于创建机器人
     */
    private void scheduleBotEntry(UserVo humanUser) {
        // 延迟2-8秒后机器人进入房间，模拟真实用户的行为
        long delayMs = 2000 + (long)(Math.random() * 6000);
        new Timer().schedule(new TimerTask() {
            @Override
            public void run() {
                try {
                    // 再次检查房间状态，确保用户还在等待
                    if (users.size() == 1 && state instanceof WaitState) {
                        UserVo bot = createBot(humanUser);
                        if (bot != null) {
                            userEnter(bot);
                        }
                    }
                } catch (IllegalAccessException e) {
                    log.error("机器人进入房间失败", e);
                }
            }
        }, delayMs);
    }

    /**
     * 创建机器人用户。
     * 机器人只借用真实用户（一年以上未登录）的昵称，积分、魔法泡泡、战绩全部虚构：
     * 它不携带任何真实用户 ID，因此比赛结果不会落库，也不会影响任何真实账号。
     */
    private UserVo createBot(UserVo humanUser) {
        UserVo bot = new UserVo();
        bot.setId(Util.uuid());
        // userName 仅作为机器人的识别标记（就绪、自动开始等逻辑依赖它）
        bot.setUserName("bot_" + roomId);

        String nickName = null;
        try {
            nickName = Global.getUserBo().pickRandomInactiveNickName(365, 50);
        } catch (Exception e) {
            log.error("选取机器人昵称失败", e);
        }
        if (nickName == null || nickName.trim().isEmpty()) {
            // 兜底：昵称池取不到时用一个临时的名字
            nickName = Util.getNickNameOfUser(humanUser) + "·朋友";
        }
        // 直接使用真实用户的昵称，避免把 bot_xx 暴露给玩家
        bot.setDisplayNickName(nickName);
        bot.setNickName(nickName);

        fillFakeUserData(bot, humanUser);
        return bot;
    }

    /**
     * 为机器人虚构用户数据。
     * 强度（胜率，进而决定答题正确率与速度，见 ReadyState#triggerBotAnswer）跟随玩家自身水平；
     * 场次与积分再由强度派生，保证显示出来的“场次-胜率-积分”三者互相自洽。
     */
    private void fillFakeUserData(UserVo bot, UserVo humanUser) {
        // 强度基准：玩家自己的历史胜率，战绩不足 3 局时按五五开（与 ReadyState 判定胜率的阈值一致）
        double humanWinRatio = 0.5;
        int humanTotalCount = 0;
        UserGameVo humanGame = humanUser.getGameByName("russia");
        if (humanGame != null && humanGame.getWinCount() != null && humanGame.getLoseCount() != null) {
            humanTotalCount = humanGame.getWinCount() + humanGame.getLoseCount();
            if (humanTotalCount >= 3) {
                humanWinRatio = (double) humanGame.getWinCount() / humanTotalCount;
            }
        }

        // 在玩家水平附近小幅波动，并限制在 [0.15, 0.85]，避免出现 0%/100% 这类一眼假的战绩
        double botWinRatio = Math.min(0.85, Math.max(0.15, humanWinRatio + (Math.random() - 0.5) * 0.2));

        // 场次与玩家同量级（否则积分会明显偏离玩家分段，结算收益会掉到 ±10/±60 的极值），胜负由强度反解
        int totalCount = Math.max(20, (int) Math.round(humanTotalCount * (0.6 + Math.random() * 0.8)));
        int winCount = (int) Math.round(totalCount * botWinRatio);
        int loseCount = totalCount - winCount;

        // 积分按每局净得分折算（calculateWinerScoreAdjustment(0, 0) 即势均力敌时每局的净得分）
        int score = Math.max(0, (winCount - loseCount) * GameOverProcessor.calculateWinerScoreAdjustment(0, 0));

        bot.setGameScore(score);
        // 魔法泡泡只作展示，按同量级玩家的水平虚构
        bot.setCowDung((int) Math.round(humanUser.getCowDung() * (0.5 + Math.random())));
        bot.setUserGames(new ArrayList<>(List.of(new UserGameVo(bot, winCount, loseCount, score, "russia"))));
    }

    /**
     * 检查机器人是否应该离开房间
     * 在非比赛状态下，机器人有15%的概率离开房间
     */
    public void checkBotLeaveProbability() {
        if (!(state instanceof ReadyState) || ((ReadyState) state).isGamePlaying()) {
            return; // 如果正在比赛，机器人不离开
        }
        
        for (UserVo user : users.keySet()) {
            if (user.getUserName() != null && user.getUserName().startsWith("bot_")) {
                // 机器人有15%的概率离开房间（因为离开后会自动进入新机器人，所以适当提高概率）
                if (Math.random() < 0.15) {
                    try {
                        log.info(String.format("机器人[%s]随机离开房间", Util.getNickNameOfUser(user)));
                        userLeave(user);
                    } catch (IllegalAccessException e) {
                        log.error("机器人离开房间失败", e);
                    }
                }
            }
        }
    }

    public void userLeave(final UserVo user) throws IllegalAccessException {
        for (Iterator<UserVo> i = users.keySet().iterator(); i.hasNext(); ) {
            UserVo aUser = i.next();
            if (aUser.equals(user)) {
                // 广播用户离开消息
                broadcastEvent("leaveRoom", new Object[]{user.getId(), Util.getNickNameOfUser(user)});

                i.remove();

                onUserCountChanged(user);
            }
        }
        broadcastUsersInfo();
    }

    public void processUserCmd(UserVo user, UserCmd userCmd) throws IllegalAccessException {
        log.info("Processing cmd: " + userCmd);

        if (userCmd.getCmd().equals("CHAT")) {// 聊天命令，直接处理
            broadcastEvent("Chat", new ChatObject(user.getId(), Util.getNickNameOfUser(user), userCmd.getArgs()[0]));
        } else {// 交给当前的State处理
            state.processUserCmd(user, userCmd);
        }

        // 更新用户的状态数据
        UserGameData userPlayData = users.get(user);
        userPlayData.setLastUserCmd(userCmd);
        userPlayData.setLastOperationTime(System.currentTimeMillis());
    }

    public int getId() {
        return roomId;
    }

    public boolean isPrivateRoom() {
        return privateRoom;
    }

    public UserGameData getUserPlayData(UserVo user) {
        return users.get(user);
    }

    public Map<UserVo, UserGameData> getUsers() {
        return users;
    }

    /**
     * 在本游戏室范围内广播所有用户（其实就是两个玩家）的用户信息
     */
    public void broadcastUsersInfo() {
        for (UserVo user : users.keySet()) {

            // 用户级信息
            UserGameInfo userGameInfo = new UserGameInfo(user.getId());
            userGameInfo.setCowDung(user.getCowDung());
            userGameInfo.setScore(user.getGameScore());
            userGameInfo.setNickName(Util.getNickNameOfUser(user));

            // 游戏级信息
            userGameInfo.setWinCount(0);
            userGameInfo.setLostCount(0);
            for (UserGameVo userGame : user.getUserGames()) {
                if (userGame.getGame().equals("russia")) {
                    userGameInfo.setWinCount(userGame.getWinCount());
                    userGameInfo.setLostCount(userGame.getLoseCount());
                }
            }

            broadcastEvent("userGameInfo", userGameInfo);
        }

    }

    public Hall getHall() {
        return hall;
    }

}
