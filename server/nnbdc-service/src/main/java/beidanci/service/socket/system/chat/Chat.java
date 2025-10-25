package beidanci.service.socket.system.chat;

import java.util.ArrayList;
import java.util.List;

import org.apache.commons.lang3.NotImplementedException;
import org.springframework.stereotype.Component;

import beidanci.api.model.UserVo;
import beidanci.service.socket.UserCmd;
import beidanci.service.socket.system.MySystem;
import beidanci.service.socket.system.game.russia.Hall;

@Component
public class Chat implements MySystem {
    private static final Chat instance = new Chat();

    public static Chat getInstance() {
        return instance;
    }

    private final ChatRoom chatRoom = new ChatRoom();

    private Chat() {
    }

    @Override
    public void processUserCmd(UserVo user, UserCmd userCmd) {
        switch (userCmd.getCmd()) {
            case "ENTER_CHAT_ROOM" -> chatRoom.userEnter(user);
            case "LEAVE_CHAT_ROOM" -> chatRoom.userLeave(user);
            case "USER_SPEAK" -> chatRoom.userSpeak(user, userCmd.getArgs()[0]);
            default -> {
            }
        }
    }

    @Override
    public void onUserLogout(UserVo user) throws IllegalAccessException {
        chatRoom.userLeave(user);
    }

    @Override
    public void onConnectionBroken(UserVo user, String reason) {
        chatRoom.userLeave(user);
    }

    @Override
    public void onUserLeaveHall(UserVo user, Hall hall) {
        throw new NotImplementedException("");
    }

    @Override
    public List<UserVo> getIdleUsers(UserVo except, int count) {
        return new ArrayList<>();
    }

    @Override
    public String getName() {
        return SYSTEM_CHAT;
    }
}
