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
                    Hall currHall = users.get(user);
                    if (currHall != null && currHall != hall) {
                        currHall.userLeave(user);
                    }
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
                    Hall currHall = users.get(user);
                    if (currHall != null && currHall != hall) {
                        currHall.userLeave(user);
                    }
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
                        log.warn(String.format("用户[%s]尚未进入大厅，就开始发送命令[%s]", user.getDisplayNickName(), userCmd.getCmd()));
                    }                      }
        }
    }

    private Hall getHallOfUser(UserVo user) {
        Hall hall = users.get(user);
        return hall;
    }

    @Override
    public void onConnectionBroken(UserVo user, String reason) throws IllegalAccessException {
        Hall hall = getHallOfUser(user);
        if (hall != null) {
            hall.userLeave(user);
        }
        users.remove(user);
    }

    @Override
    public void onUserLogout(UserVo user) throws IllegalAccessException {
        Hall hall = getHallOfUser(user);
        if (hall != null) {
            hall.userLeave(user);
        }
        users.remove(user);
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
