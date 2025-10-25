package beidanci.service.socket.system.game.russia;

import java.util.Iterator;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import beidanci.api.ChatObject;
import beidanci.api.model.UserGameInfo;
import beidanci.api.model.UserGameVo;
import beidanci.api.model.UserVo;
import beidanci.service.bo.DictBo;
import beidanci.service.bo.DictWordBo;
import beidanci.service.bo.LearningDictBo;
import beidanci.service.bo.SysParamBo;
import beidanci.service.bo.UserBo;
import beidanci.service.bo.UserGameBo;
import beidanci.service.bo.WordBo;
import beidanci.service.socket.UserCmd;
import beidanci.service.socket.system.game.russia.state.EmptyState;
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
        new java.util.Timer().schedule(new java.util.TimerTask() {
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
     * 创建机器人用户
     */
    private UserVo createBot(UserVo humanUser) {
        UserVo bot = new UserVo();
        // 选取"超过一年未登录且玩过游戏"的真实用户作为机器人，比赛结果会反映到该用户账户
        beidanci.service.po.User real = null;
        try {
            real = beidanci.service.Global.getUserBo().pickRandomInactiveGamer(365, 50);
        } catch (Exception ignored) {}

        if (real != null) {
            bot.setId(real.getId());
            // 使用真实用户的ID以便比赛结果落库，但将userName标记为bot以便就绪逻辑识别为机器人
            bot.setUserName("bot_" + roomId);
            // 直接使用真实用户的展示昵称，避免显示为 bot_xx
            bot.setDisplayNickName(real.getDisplayNickName());
            bot.setNickName(real.getDisplayNickName());
            bot.setCowDung(real.getCowDung());
            bot.setGameScore(real.getGameScore());
            java.util.List<beidanci.api.model.UserGameVo> games = new java.util.ArrayList<>();
            java.util.List<beidanci.service.po.UserGame> realGames = beidanci.service.Global.getUserGameBo()
                    .getUserGamesOfUser(real.getId(), true);
            for (beidanci.service.po.UserGame ug : realGames) {
                games.add(new beidanci.api.model.UserGameVo(bot, ug.getWinCount(), ug.getLoseCount(), ug.getScore(), ug.getId().getGame()));
            }
            bot.setUserGames(games);
        } else {
            // 兜底：若找不到符合条件的老用户，则使用游客数据作为临时bot（仅前端显示，不持久化）
            bot.setId("bot_" + roomId);
            bot.setUserName("bot_" + roomId);
            bot.setNickName(Util.getNickNameOfUser(humanUser) + "·朋友");
            bot.setCowDung(0);
            bot.setGameScore(0);
            bot.setUserGames(new java.util.ArrayList<>());
        }
        
        return bot;
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
