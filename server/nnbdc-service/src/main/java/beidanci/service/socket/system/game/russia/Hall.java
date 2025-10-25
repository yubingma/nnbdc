package beidanci.service.socket.system.game.russia;

import java.io.IOException;
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
    private List<WordVo> wordList;

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

        logger.info(String.format("正在初始化大厅[%s]", name));
        long startTime = System.currentTimeMillis();
        generateWordList();
        long endTime = System.currentTimeMillis();
        logger.info(String.format("大厅[%s]初始化完成，共有[%d]个单词，耗时[%d]ms", name, wordList.size(), endTime - startTime));
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
    private void generateWordList()
            throws IOException, InvalidMeaningFormatException, EmptySpellException, ParseException {
        // 获取该游戏大厅所包含的单词书中的所有单词
        Map<String, WordVo> words = gameHallBo.getGameHallWords(id);

        assert (wordList == null);
        wordList = new ArrayList<>(words.values());
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
     * 随机选出一个单词，且与指定单词不同
     *
     * @param otherThan
     * @return
     */
    public WordVo getWordRandomly(WordVo otherThan) {
        int randomIndex = (int) (wordList.size() * Math.random());
        assert (randomIndex <= wordList.size());
        randomIndex = randomIndex == wordList.size() ? 0 : randomIndex;
        WordVo word = wordList.get(randomIndex);

        if (otherThan != null && otherThan.getSpell().equalsIgnoreCase(word.getSpell())) {
            randomIndex++;
            randomIndex = randomIndex == wordList.size() ? 0 : randomIndex;
            word = wordList.get(randomIndex);
        }

        return word;
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
