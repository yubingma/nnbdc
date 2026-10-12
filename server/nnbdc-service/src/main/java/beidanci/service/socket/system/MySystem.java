package beidanci.service.socket.system;

import beidanci.api.model.UserVo;
import beidanci.service.exception.EmptySpellException;
import beidanci.service.exception.InvalidMeaningFormatException;
import beidanci.service.exception.ParseException;
import beidanci.service.socket.UserCmd;
import beidanci.service.socket.system.game.russia.Hall;

import java.io.IOException;
import java.util.List;

public interface MySystem {
    String SYSTEM_RUSSIA = "russia";
    String SYSTEM_CHAT = "chat";

    void processUserCmd(UserVo user, UserCmd userCmd) throws InvalidMeaningFormatException, EmptySpellException,
            ParseException, IOException, IllegalAccessException, Exception;

    void onUserLogout(UserVo user) throws IllegalAccessException;

    void onConnectionBroken(UserVo user, String reason) throws IllegalAccessException;

    void onUserLeaveHall(UserVo user, Hall hall);

    /**
     * 该用户是否正处于一局进行中的对局。
     * 用户断线后重新连上来时，据此决定是"接管这一局继续打"还是按离场处理。
     */
    default boolean isUserInPlayingGame(UserVo user) {
        return false;
    }

    List<UserVo> getIdleUsers(UserVo except, int count);

    String getName();
}
