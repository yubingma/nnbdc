package beidanci.service.socket.system.chat;

import java.util.HashMap;
import java.util.Map;

import beidanci.api.model.UserVo;
import beidanci.service.socket.SocketService;
import beidanci.service.util.Util;

public class ChatRoom {
    private final Map<String, UserVo> users = new HashMap<>();

    public void userEnter(UserVo user) {
        users.put(user.getId(), user);

        // 在聊天室内广播用户进入事件
        broadcast("USER_ENTERED", Util.getNickNameOfUser(user));
        broadcastUserCount();
    }

    public void userLeave(UserVo user) {
        users.remove(user.getId());

        // 在聊天室内广播用户离开事件
        broadcast("USER_LEFT", Util.getNickNameOfUser(user));
        broadcastUserCount();
    }

    private void broadcastUserCount() {
        broadcast("USER_COUNT", users.size());
    }

    private void broadcast(String event, Object data) {
        for (UserVo aUser : users.values()) {
            SocketService.getInstance().sendEventToUser(aUser, event, data);
        }
    }

    public void userSpeak(UserVo user, String content) {
        broadcast("USER_SPEAK", new Object[]{user, content});
    }
}
