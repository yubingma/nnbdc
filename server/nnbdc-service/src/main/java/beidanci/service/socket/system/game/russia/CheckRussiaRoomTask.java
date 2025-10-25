package beidanci.service.socket.system.game.russia;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.TimerTask;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import beidanci.api.model.UserVo;

/**
 * 检查指定大厅内所有游戏室健康情况的定时任务
 *
 * @author Administrator
 */
public class CheckRussiaRoomTask extends TimerTask {
    private static final Logger logger = LoggerFactory.getLogger(CheckRussiaRoomTask.class);
    private final List<RussiaRoom> readyRooms;
    private final List<RussiaRoom> waitingRooms;
    /**
     * 游戏室所属的大厅
     */
    private final Hall hall;

    public CheckRussiaRoomTask(List<RussiaRoom> readyRooms, List<RussiaRoom> waitingRooms, Hall hall) {
        this.readyRooms = readyRooms;
        this.waitingRooms = waitingRooms;
        this.hall = hall;
    }

    /**
     * 检查是否有长时间不操作用户，有则将其请出游戏室
     *
     * @param rooms
     */
    private void clearIdleUser(List<RussiaRoom> rooms) throws IllegalAccessException {
        // 创建临时游戏室列表（将用户从游戏室删除后，会自动引起该游戏室转移到另一个游戏室列表，这样在游戏室迭代过程中会引起ConcurrentModificationExecption,
        // 所以创建一个临时的游戏室列表避免这个问题）
        List<RussiaRoom> tempRooms = new ArrayList<>(rooms.size());
        for (RussiaRoom room : rooms) {
            tempRooms.add(room);
        }

        for (RussiaRoom room : tempRooms) {
            Map<UserVo, UserGameData> users = room.getUsers();
            List<UserVo> usersToRemove = new ArrayList<>();
            for (Map.Entry<UserVo, UserGameData> entry : users.entrySet()) {
                UserGameData userPlayData = entry.getValue();
                UserVo user = entry.getKey();
                long timeSpan = System.currentTimeMillis() - userPlayData.getLastOperationTime();
                if (timeSpan > 30 * 60 * 1000) {
                    usersToRemove.add(user);
                    logger.info(
                            String.format("[%s]: 发现用户[%s] %dms内没有任何操作 ", hall.getName(), user.getUserName(), timeSpan));
                }
            }

            for (UserVo user : usersToRemove) {
                room.userLeave(user);
                // service.disconnectExistingConnectionOfUser(user, null,"长时间未操作");
                // logger.info(String.format("[%s]: 长时间未操作， 用户[%s]被逐出游戏室并被断开连接 ",
                // hall.getName(), user.getUserName()));
                logger.info(String.format("[%s]: 长时间未操作， 用户[%s]被逐出游戏室 ", hall.getName(), user.getUserName()));
            }
        }
    }

    /**
     * 检查是否有处与Empty状态(空游戏室)的游戏室（正常情况下不该有）
     *
     * @param rooms
     */
    private void clearEmptyRoom(List<RussiaRoom> rooms) {
        List<RussiaRoom> roomsToRemove = new ArrayList<>();
        for (RussiaRoom room : rooms) {
            if (room.getUsers().isEmpty()) {
                roomsToRemove.add(room);
            }
        }

        // 清除空游戏室
        for (RussiaRoom room : roomsToRemove) {
            hall.removeRoom(room);
            logger.info(String.format("[%s]: 发现空游戏室[%d]并将其删除", hall.getName(), room.getId()));
        }
    }

    @Override
    public void run() {
        synchronized (hall) {

            logger.debug(String.format("[%s]: 共有[%d]个ready游戏室，[%d]个waiting游戏室", hall.getName(), readyRooms.size(),
                    waitingRooms.size()));

            // 清除长时间不操作的用户
            try {
                clearIdleUser(readyRooms);
                clearIdleUser(waitingRooms);
            } catch (IllegalAccessException e) {
                logger.error("", e);
            }

            // 清除空房间
            clearEmptyRoom(readyRooms);
            clearEmptyRoom(waitingRooms);

            // 检查机器人离开概率
            try {
                checkBotLeaveProbability(readyRooms);
                checkBotLeaveProbability(waitingRooms);
            } catch (Exception e) {
                logger.error("检查机器人离开概率时发生错误", e);
            }

            // 检查所有房间中的用户数是否正确
            for (RussiaRoom room : readyRooms) {
                if (room.getUsers().size() != 2) {
                    logger.error(String.format("[%s]: Found a ready room has [%d] users", hall.getName(),
                            room.getUsers().size()));
                }
            }
            for (RussiaRoom room : waitingRooms) {
                if (room.getUsers().size() != 1) {
                    logger.error(String.format("[%s]: Found a waiting room has [%d] users", hall.getName(),
                            room.getUsers().size()));
                }
            }
        }

    }

    /**
     * 检查机器人离开概率
     */
    private void checkBotLeaveProbability(List<RussiaRoom> rooms) {
        // 创建临时游戏室列表，避免在迭代过程中修改列表导致的并发修改异常
        List<RussiaRoom> tempRooms = new ArrayList<>(rooms.size());
        for (RussiaRoom room : rooms) {
            tempRooms.add(room);
        }

        for (RussiaRoom room : tempRooms) {
            room.checkBotLeaveProbability();
        }
    }
}
