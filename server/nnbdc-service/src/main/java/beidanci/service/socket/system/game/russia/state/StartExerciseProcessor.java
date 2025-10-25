package beidanci.service.socket.system.game.russia.state;

import beidanci.api.model.UserVo;
import beidanci.service.socket.UserCmd;
import beidanci.service.socket.system.game.russia.RussiaRoom;
import beidanci.service.socket.system.game.russia.UserGameData;

public class StartExerciseProcessor {
    private final RussiaRoom room;

    public StartExerciseProcessor(RussiaRoom room) {
        this.room = room;
    }

    public void process(UserVo user, UserCmd userCmd) {
        UserGameData userPlayData = room.getUserPlayData(user);
        userPlayData.setExercise(true);
        room.sendEventToUser(user, "sysCmd", "BEGIN_EXERCISE");
    }
}
