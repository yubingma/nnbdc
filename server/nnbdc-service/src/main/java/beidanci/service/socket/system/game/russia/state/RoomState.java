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

    /**
     * 本局作废（例如双方都掉线）：不判负、不计分，只把对局关掉。
     * 只有真正在打的状态才需要对局生命周期，其余状态什么都不用做。
     */
    public void voidGame() {
    }
}
