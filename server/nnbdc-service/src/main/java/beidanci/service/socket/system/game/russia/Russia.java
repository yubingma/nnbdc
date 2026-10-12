package beidanci.service.socket.system.game.russia;

import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

import beidanci.api.model.UserVo;
import beidanci.service.bo.DictBo;
import beidanci.service.bo.DictWordBo;
import beidanci.service.bo.GameHallBo;
import beidanci.service.bo.LearningDictBo;
import beidanci.service.bo.SysParamBo;
import beidanci.service.bo.UserBo;
import beidanci.service.bo.UserGameBo;
import beidanci.service.bo.WordBo;
import beidanci.service.exception.EmptySpellException;
import beidanci.service.exception.InvalidMeaningFormatException;
import beidanci.service.exception.ParseException;
import beidanci.service.socket.SocketService;
import beidanci.service.socket.UserCmd;
import beidanci.service.socket.system.MySystem;
import beidanci.service.socket.system.game.russia.state.ReadyState;
import beidanci.service.socket.system.game.russia.state.RoomState;
import beidanci.service.store.WordCache;
import beidanci.service.util.UserSorter;

@Component
public class Russia implements MySystem {
    private static final Logger log = LoggerFactory.getLogger(Russia.class);

    @Autowired
    WordCache wordCache;

    @Autowired
    WordBo wordBo;

    @Autowired
    UserGameBo userGameBo;

    @Autowired
    DictWordBo rawWordBo;

    @Autowired
    UserSorter userSorter;

    @Autowired
    GameHallBo gameHallBo;

    @Autowired
    SysParamBo sysParamBo;

    @Autowired
    DictWordBo dictWordBo;

    @Autowired
    UserBo userBo;

    @Autowired
    LearningDictBo selectedDictBo;

    @Autowired
    DictBo dictBo;

    /**
     * 系统中所有游戏大厅, key 为大厅的Id
     */
    private final Map<String, Hall> gameHalls = new ConcurrentHashMap<>();

    /**
     * 用户到大厅的map，可以查询到用户在哪个大厅里
     */
    private final Map<UserVo, Hall> users = new ConcurrentHashMap<>();

    @Override
    public void processUserCmd(final UserVo user, UserCmd userCmd) throws IOException, IllegalAccessException, InvalidMeaningFormatException, EmptySpellException, ParseException {
        SocketService socketService = SocketService.getInstance();
        switch (userCmd.getCmd()) {
            case "ENTER_GAME_HALL" ->                 {
                    // 获取用户要进入的游戏大厅
                    String hallId = userCmd.getArgs()[0];
                    // 获取用户不想进入的房间（用户点击了【离开】按钮）
                    log.info("exceptRoom: " + userCmd.getArgs()[1]);
                    int exceptRoom = -1;
                    if (userCmd.getArgs()[1] != null && !userCmd.getArgs()[1].equals("")
                            && !userCmd.getArgs()[1].equals("undefined")) {
                        exceptRoom = Integer.parseInt(userCmd.getArgs()[1]);
                    }       Hall hall;
                    synchronized (gameHalls) {
                        hall = gameHalls.get(hallId);
                        if (hall == null) {
                            hall = new Hall(hallId, this, socketService, wordCache, wordBo, userGameBo, rawWordBo,
                                    userSorter, gameHallBo, sysParamBo, dictWordBo, userBo, selectedDictBo, dictBo);
                            // 构造完成后再启动定时任务，避免 this-escape
                            hall.startMonitoring();
                            gameHalls.put(hallId, hall);
                        }
                    }       // 用户进入游戏大厅
                    Hall currHall = users.get(user);
                    if (currHall != null) {
                        log.warn(String.format("用户[%s]试图进入大厅，但他目前已在[%s]大厅, 强制他从目前大厅退出。", user.getDisplayNickName(),
                                currHall.getName()));
                        currHall.userLeave(user);
                    }       hall.userEnter(user, exceptRoom);
                    users.put(user, hall);
                }
            case "CREATE_PRIVATE_ROOM" ->                 {
                    // hallId
                    String hallId = userCmd.getArgs()[0];
                    Hall hall;
                    synchronized (gameHalls) {
                        hall = gameHalls.get(hallId);
                        if (hall == null) {
                            hall = new Hall(hallId, this, socketService, wordCache, wordBo, userGameBo, rawWordBo,
                                    userSorter, gameHallBo, sysParamBo, dictWordBo, userBo, selectedDictBo, dictBo);
                            hall.startMonitoring();
                            gameHalls.put(hallId, hall);
                        }
                    }
                    leaveCurrentRoom(user, hall);
                    hall.createPrivateRoomForUser(user);
                    users.put(user, hall);
                }
            case "JOIN_ROOM_BY_ID" ->                 {
                    String hallId = userCmd.getArgs()[0];
                    int roomId = Integer.parseInt(userCmd.getArgs()[1]);
                    Hall hall;
                    synchronized (gameHalls) {
                        hall = gameHalls.get(hallId);
                        if (hall == null) {
                            hall = new Hall(hallId, this, socketService, wordCache, wordBo, userGameBo, rawWordBo,
                                    userSorter, gameHallBo, sysParamBo, dictWordBo, userBo, selectedDictBo, dictBo);
                            hall.startMonitoring();
                            gameHalls.put(hallId, hall);
                        }
                    }
                    leaveCurrentRoom(user, hall);
                    boolean ok = hall.joinRoomById(user, roomId);
                    if (!ok) {
                        socketService.sendEventToUser(user, "joinRoomFailed", "房间不存在或已满");
                    } else {
                        users.put(user, hall);
                    }
                }
            case "inviteUser" ->                 {
                    String targetUserId = userCmd.getArgs()[0];
                    String gameType = userCmd.getArgs()[1];
                    int room = Integer.parseInt(userCmd.getArgs()[2]);
                    Integer hallId = Integer.valueOf(userCmd.getArgs()[3]);
                    String hallName = gameHallBo.findById(hallId).getHallName();
                    socketService.sendEventToUser(targetUserId, "inviteYouToGame",
                            new Object[]{user, gameType, room, hallId, hallName});
                }
            default ->                 {
                    // 向用户所在的游戏大厅发送用户的命令
                    Hall hall = getHallOfUser(user);
                    if (hall != null) {
                        hall.processUserCmd(user, userCmd);
                    } else {
                        // 客户端并不知道自己已经不在对局里了（例如断线期间被判负、房间已解散），
                        // 必须明确告知它，否则它会一直停在"对战中"界面等一个永远不会来的单词
                        log.warn(String.format("用户[%s]尚未进入大厅，就开始发送命令[%s]", user.getDisplayNickName(), userCmd.getCmd()));
                        socketService.sendEventToUser(user, "gameNotInProgress", userCmd.getCmd());
                    }                      }
        }

        // 用户回到游戏里了：如果上一局是断线判负的，把结果补发给他（那时他不在线，发不出去）。
        // 不要求他此刻还在大厅里——恰恰是被判负的人已经不在大厅了，才会需要这条补发。
        socketService.sendGameResultNotice(user);
    }

    @Override
    public boolean isUserInPlayingGame(UserVo user) {
        Hall hall = getHallOfUser(user);
        return hall != null && hall.isUserInPlayingGame(user);
    }

    /**
     * 换房（开好友房、按房号进房）之前，先把人从当前房间里摘出来。
     * 必须连"同一个大厅里的旧房间"一起处理：否则他会同时挂在两个房间里，
     * 后续命令被路由到旧房间，旧房间也永远不空。
     */
    private void leaveCurrentRoom(UserVo user, Hall targetHall) throws IllegalAccessException {
        Hall currHall = users.get(user);
        if (currHall != null && currHall != targetHall) {
            currHall.userLeave(user);
            return;
        }
        if (targetHall != null) {
            RussiaRoom currentRoom = targetHall.getRoomOfUser(user);
            if (currentRoom != null) {
                currentRoom.userLeave(user);
            }
        }
    }

    private Hall getHallOfUser(UserVo user) {
        Hall hall = users.get(user);
        return hall;
    }

    @Override
    public void onConnectionBroken(UserVo user, String reason) throws IllegalAccessException {
        // 心跳都停了：断线宽限已经到点（传输层断开时给的那段宽限也一并到期），按断线判负
        if (trySettleDisconnectLoss(user)) {
            return;
        }
        Hall hall = getHallOfUser(user);
        if (hall != null) {
            hall.userLeave(user);
        }
        users.remove(user);
    }

    @Override
    public void onUserLogout(UserVo user) throws IllegalAccessException {
        // 传输层断了不等于用户走了：正在打的那一局先进入宽限，保留对局等他重连接管
        if (putUserIntoDisconnectGrace(user)) {
            return;
        }
        Hall hall = getHallOfUser(user);
        if (hall != null) {
            hall.userLeave(user);
        }
        users.remove(user);
    }

    @Override
    public boolean onUserReconnected(UserVo user) {
        Hall hall = getHallOfUser(user);
        RussiaRoom room = (hall == null) ? null : hall.getRoomOfUser(user);
        RoomState state = (room == null) ? null : room.getState();
        if (!(state instanceof ReadyState readyState) || !readyState.isGamePlaying()) {
            // 单人练习（还没等到对手）：没有对手也没有计分，保留房间让他重连后接着练
            return room != null && room.isUserPlaying(user);
        }
        if (readyState.markUserReconnected(user)) {
            return true;
        }
        // 本局累计断线已超上限：不能再接管，按断线判负
        log.info(String.format("玩家[%s]本局累计断线超过上限，不再接管对局",
                user.getDisplayNickName()));
        try {
            settleDisconnectLoss(user);
        } catch (IllegalAccessException e) {
            log.error("断线判负失败", e);
        }
        return false;
    }

    /**
     * 正在打的那一局让用户进入断线宽限（保留对局、不判负）。
     *
     * @return true 表示已进入宽限（调用方不要再按离场处理）
     */
    private boolean putUserIntoDisconnectGrace(UserVo user) {
        Hall hall = getHallOfUser(user);
        RussiaRoom room = (hall == null) ? null : hall.getRoomOfUser(user);
        RoomState state = (room == null) ? null : room.getState();
        if (state instanceof ReadyState readyState && readyState.isGamePlaying()) {
            readyState.markUserDisconnected(user);
            return true;
        }
        // 单人练习：没有对手也没有计分，保留房间等他重连接着练（长期不回来由 30 分钟无操作清理兜底）
        return room != null && room.isUserPlaying(user);
    }

    /**
     * 断线宽限到点：按断线判负。
     *
     * @return true 表示确实结算了一局（调用方不要再按普通离场处理，本方法内部已经处理完）
     */
    private boolean trySettleDisconnectLoss(UserVo user) throws IllegalAccessException {
        Hall hall = getHallOfUser(user);
        RussiaRoom room = (hall == null) ? null : hall.getRoomOfUser(user);
        RoomState state = (room == null) ? null : room.getState();
        if (!(state instanceof ReadyState readyState) || !readyState.isGamePlaying()) {
            return false;
        }
        settleDisconnectLoss(user);
        return true;
    }

    /**
     * 按断线判负结算这一局：对手判赢，他判输（照常扣分）。
     * 若对手也早就掉线了，则本局作废、双方都不计分——否则先超时的一方白输，
     * 纯看两个定时器谁先到，对用户毫无道理可讲。
     */
    private void settleDisconnectLoss(UserVo loser) throws IllegalAccessException {
        Hall hall = getHallOfUser(loser);
        if (hall == null) {
            users.remove(loser);
            return;
        }
        RussiaRoom room = hall.getRoomOfUser(loser);
        RoomState state = (room == null) ? null : room.getState();
        UserVo opponent = (room == null) ? null : room.getAnotherUser(loser);

        if (opponent != null && state instanceof ReadyState readyState && readyState.isUserGone(opponent)) {
            log.info(String.format("玩家[%s]与对手[%s]都已掉线，本局作废、不计分",
                    loser.getDisplayNickName(), opponent.getDisplayNickName()));
            readyState.voidGame();
            hall.userLeave(loser);
            hall.userLeave(opponent);
            return;
        }

        log.info(String.format("玩家[%s]断线超过宽限，判负", loser.getDisplayNickName()));
        SocketService.getInstance().noticeGameResult(loser.getId(),
                "上一局因断线时间过长被判负，积分已按战败结算");

        // 正常情况由房间状态里的判负逻辑完成扣分；作废情况下 isPlaying 已置 false，不会再结算
        hall.userLeave(loser);
    }

    @Override
    public void onUserLeaveHall(UserVo user, Hall hall) {
        if (users.containsKey(user)) {
            users.remove(user);
        }
    }

    @Override
    public List<UserVo> getIdleUsers(UserVo except, int count) {
        List<UserVo> idleUsers = new ArrayList<>();
        List<UserVo> allUsers = SocketService.getInstance().getUsers();
        Collections.shuffle(allUsers);
        for (UserVo user : allUsers) {
            Hall currHall = getHallOfUser(user);
            if (currHall == null || currHall.getRoomOfUser(user) == null
                    || !(currHall.getRoomOfUser(user).getState() instanceof ReadyState)) {
                UserVo vo = new UserVo();
                vo.setId(user.getId());
                vo.setDisplayNickName(user.getDisplayNickName());
                if (!user.equals(except)) {
                    idleUsers.add(vo);
                }
                if (idleUsers.size() >= count) {
                    break;
                }
            }
        }
        return idleUsers;
    }

    @Override
    public String getName() {
        return SYSTEM_RUSSIA;
    }

    public Map<String, Hall> getGameHalls() {
        return gameHalls;
    }
}
