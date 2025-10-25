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

    List<UserVo> getIdleUsers(UserVo except, int count);

    String getName();
}
