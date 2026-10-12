package beidanci.service.socket.system.game.russia;

import java.io.IOException;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.Timer;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import beidanci.api.model.UserVo;
import beidanci.api.model.WordVo;
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
import beidanci.service.po.GameHall;
import beidanci.service.socket.SocketService;
import beidanci.service.socket.UserCmd;
import beidanci.service.socket.system.MySystem;
import beidanci.service.socket.system.game.russia.state.ReadyState;
import beidanci.service.socket.system.game.russia.state.WaitState;
import beidanci.service.store.WordCache;
import beidanci.service.util.UserSorter;
import beidanci.service.util.Util;

/**
 * Russia游戏大厅
 *
 * @author Administrator
 */
public class Hall {
    private static final Logger logger = LoggerFactory.getLogger(Hall.class);
    private final List<RussiaRoom> readyRooms = new ArrayList<>();
    private final List<RussiaRoom> waitingRooms = new ArrayList<>();
    private final SocketService socketService;
    private final String name;
    private final String id;
    /**
     * 当天的用词池：同一天内不变，跨天换一批（惰性重建见 {@link #getWordPool()}）
     */
    private volatile HallWordPool wordPool;

    public MySystem getSystem() {
        return system;
    }

    private final MySystem system;

    private final WordCache wordCache;

    private final WordBo wordBo;

    private final UserGameBo userGameBo;

    private final DictWordBo rawWordBo;

    private final UserSorter userSorter;

    private final GameHallBo gameHallBo;

    private final SysParamBo sysParamBo;

    private final LearningDictBo selectedDictBo;

    private final UserBo userBo;

    private final DictBo dictBo;

    /**
     * 检查游戏室健康状况的定时器
     */
    private final Timer timer = new Timer();

    public Hall(String id, MySystem system, SocketService socketService, WordCache wordCache, WordBo wordBo,
                UserGameBo userGameBo, DictWordBo rawWordBo, UserSorter userSorter, GameHallBo gameHallBo,
                SysParamBo sysParamBo, DictWordBo dictWordBo, UserBo userBo, LearningDictBo selectedDictBo,
                DictBo dictBo)
            throws IOException, InvalidMeaningFormatException, EmptySpellException, ParseException {
        this.id = id;
        this.socketService = socketService;
        this.system = system;
        this.wordCache = wordCache;
        this.wordBo = wordBo;
        this.userGameBo = userGameBo;
        this.rawWordBo = rawWordBo;
        this.userSorter = userSorter;
        this.gameHallBo = gameHallBo;
        this.sysParamBo = sysParamBo;
        this.userBo = userBo;
        this.selectedDictBo = selectedDictBo;
        this.dictBo = dictBo;

        GameHall gameHall = gameHallBo.findById(id, true);
        this.name = gameHall.getHallName();

        logger.info(String.format("大厅[%s]已创建（词池在第一次用到时按当天抽样加载）", name));
    }

    /**
     * 构造完成后再启动定时任务，避免在构造函数中将 this 发布到其他线程引发 this-escape 警告
     */
    public void startMonitoring() {
        timer.scheduleAtFixedRate(new CheckRussiaRoomTask(readyRooms, waitingRooms, this), 0, 10000);
    }

    /**
     * 为游戏大厅生成相应的单词列表
     *
     * @throws EmptySpellException
     * @throws InvalidMeaningFormatException
     * @throws ParseException
     * @throws IOException
     */
    /**
     * 取当天的用词池。跨天时自动换成新一天的（这是轮转的唯一判定来源；
     * 零点定时任务只是提前触发它，见 {@link #rotateWordPoolForNewDay()}）。
     *
     * 房间会持有拿到的池对象用到底，所以跨零点的对局不会中途换题源；
     * 旧池由还在用它的房间持有，最后一个房间打完自然回收。
     */
    public HallWordPool getWordPool() {
        LocalDate today = LocalDate.now();
        HallWordPool pool = wordPool;
        if (pool != null && pool.getDay().equals(today)) {
            return pool;
        }
        synchronized (this) {
            pool = wordPool;
            if (pool != null && pool.getDay().equals(today)) {
                return pool;
            }
            long startTime = System.currentTimeMillis();
            Map<String, WordVo> words = gameHallBo.getGameHallWords(id, today);
            HallWordPool newPool = new HallWordPool(today, new ArrayList<>(words.values()));
            wordPool = newPool;
            logger.info(String.format("大厅[%s]的当日词池已就绪：用词[%d]个，日期[%s]，耗时[%d]ms",
                    name, newPool.size(), today, System.currentTimeMillis() - startTime));
            return newPool;
        }
    }

    /**
     * 零点轮转：把已加载的大厅换成新一天的用词池。幂等，真正的日期判定在 {@link #getWordPool()} 里。
     */
    public void rotateWordPoolForNewDay() {
        HallWordPool pool = wordPool;
        if (pool != null && !pool.getDay().equals(LocalDate.now())) {
            getWordPool();
        }
    }

    /**
     * 尝试进入某个已存在且处于等待状态（还缺少一个玩家）的游戏室，如果没有已存在的游戏室或所有游戏室已满，则创建一个新的游戏室并进入其中.
     *
     * @return
     */
    private synchronized RussiaRoom assignRoomForUser(UserVo user, int exceptRoom) throws IllegalAccessException {
        // 尝试进入一个waiting状态的游戏室
        RussiaRoom roomToEnter = null;
        for (RussiaRoom room : waitingRooms) {
            if (!room.isPrivateRoom() && room.getId() != exceptRoom) {
                roomToEnter = room;
                break;
            }
        }

        if (roomToEnter == null) {
            roomToEnter = new RussiaRoom(user, this, wordCache, wordBo, userGameBo, rawWordBo, userSorter, sysParamBo, userBo, selectedDictBo, dictBo);
        }

        roomToEnter.userEnter(user);

        return roomToEnter;
    }

    /**
     * 创建一个私有房间（仅通过房号进入，不参与大厅匹配）并让用户进入。
     */
    public synchronized RussiaRoom createPrivateRoomForUser(UserVo user) throws IllegalAccessException {
        RussiaRoom room = new RussiaRoom(user, this, wordCache, wordBo, userGameBo, rawWordBo, userSorter, sysParamBo, userBo, selectedDictBo, dictBo, true);
        room.userEnter(user);
        return room;
    }

    /**
     * 通过房间号加入房间（满员则失败）。
     * @return true=成功，false=失败
     */
    public synchronized boolean joinRoomById(UserVo user, int roomId) throws IllegalAccessException {
        for (RussiaRoom room : waitingRooms) {
            if (room.getId() == roomId) {
                if (room.getUsers().size() < 2) {
                    room.userEnter(user);
                    return true;
                } else {
                    return false;
                }
            }
        }
        for (RussiaRoom room : readyRooms) {
            if (room.getId() == roomId) {
                if (room.getUsers().size() < 2) {
                    room.userEnter(user);
                    return true;
                } else {
                    return false;
                }
            }
        }
        return false;
    }

    /**
     * 获取指定用户所在的游戏室
     *
     * @param user
     * @return
     */
    public synchronized RussiaRoom getRoomOfUser(UserVo user) {
        for (RussiaRoom room : waitingRooms) {
            if (room.hasUser(user)) {
                return room;
            }
        }

        // 尝试从就绪的游戏室中退出,退出后，该游戏室变为等待状态
        for (RussiaRoom room : readyRooms) {
            if (room.hasUser(user)) {
                return room;
            }
        }

        return null;
    }

    /**
     * 删除一个游戏室
     */
    public synchronized void removeRoom(RussiaRoom roomToDel) {
        for (Iterator<RussiaRoom> i = waitingRooms.iterator(); i.hasNext(); ) {
            RussiaRoom room = i.next();
            if (room.equals(roomToDel)) {
                i.remove();
            }
        }

        for (Iterator<RussiaRoom> i = readyRooms.iterator(); i.hasNext(); ) {
            RussiaRoom room = i.next();
            if (room.equals(roomToDel)) {
                i.remove();
            }
        }
    }

    public synchronized void onRoomStateChanged(RussiaRoom theRoom) {
        // 首先将room从队列中删除
        removeRoom(theRoom);

        // 更具room的state，将其加入相应队列
        if (theRoom.getState() instanceof WaitState) {
            waitingRooms.add(theRoom);
        } else if (theRoom.getState() instanceof ReadyState) {
            readyRooms.add(theRoom);
        }
    }

    public void sendEvent2User(UserVo user, String event, Object data) {
        socketService.sendEventToUser(user, event, data);
    }

    public void userEnter(UserVo user, int exceptRoom) throws IllegalAccessException {
        RussiaRoom room = assignRoomForUser(user, exceptRoom);
        logger.info(String.format("%s 进入游戏大厅 %s, 房间:[%d,%s]", Util.getNickNameOfUser(user), name, room.getId(),
                room.getState().getClass().getSimpleName()));
    }

    public void userLeave(UserVo user) throws IllegalAccessException {
        RussiaRoom room = getRoomOfUser(user);
        if (room != null) {
            room.userLeave(user);
        }
        system.onUserLeaveHall(user, this);
        logger.info(String.format("%s 离开游戏大厅 %s", Util.getNickNameOfUser(user), name));
    }

    /**
     * 把断线宽限已经到点的用户按时结算掉（由房间监控任务每 10 秒调一次）。
     * 结算动作交给 system.onConnectionBroken：它会按"对手赢、他输；双方都没了就作废"处理。
     */
    public void settleExpiredDisconnects() throws IllegalAccessException {
        for (RussiaRoom room : new ArrayList<>(readyRooms)) {
            if (!(room.getState() instanceof ReadyState readyState)) {
                continue;
            }
            for (UserVo user : new ArrayList<>(room.getUsers().keySet())) {
                if (readyState.isDisconnectGraceExpired(user)) {
                    logger.info(String.format("玩家[%s]断线宽限到点，开始结算", Util.getNickNameOfUser(user)));
                    system.onConnectionBroken(user, "断线宽限到点");
                }
            }
        }
    }

    /**
     * 该用户是否正处于一局进行中的对局（正式对战或单人练习都算）。
     */
    public boolean isUserInPlayingGame(UserVo user) {
        RussiaRoom room = getRoomOfUser(user);
        return room != null && room.isUserPlaying(user);
    }

    public void processUserCmd(UserVo user, UserCmd userCmd) throws IllegalAccessException {
        if (userCmd.getCmd().equals("LEAVE_HALL")) {
            userLeave(user);
        } else {
            RussiaRoom room = getRoomOfUser(user);
            if (room != null) {
                room.processUserCmd(user, userCmd);
            }
        }
    }

    public String getName() {
        return name;
    }

    /**
     * 获取大厅中的人数
     *
     * @return
     */
    public int getUserCount() {
        int count = 0;
        for (RussiaRoom room : readyRooms) {
            count += room.getUsers().size();
        }
        for (RussiaRoom room : waitingRooms) {
            count += room.getUsers().size();
        }
        return count;
    }

    public List<RussiaRoom> getWaitingRooms() {
        return waitingRooms;
    }
}
