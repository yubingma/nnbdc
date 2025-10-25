package beidanci.service.socket.system.game.russia.state;

import beidanci.api.model.UserVo;
import beidanci.service.socket.UserCmd;
import beidanci.service.socket.system.game.russia.RussiaRoom;

public abstract class RoomState {
    protected RussiaRoom room;

    public RoomState(RussiaRoom room) {
        this.room = room;
    }

    public abstract void enter();

    public abstract void processUserCmd(UserVo user, UserCmd userCmd) throws IllegalAccessException;

    public abstract void exit(UserVo user) throws IllegalAccessException;
}
