package beidanci.service.socket.system.game.russia.state;

import org.apache.commons.lang.NotImplementedException;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import beidanci.api.model.UserVo;
import beidanci.service.socket.UserCmd;
import beidanci.service.socket.system.game.russia.RussiaRoom;

public class EmptyState extends RoomState {
    private static final Logger log = LoggerFactory.getLogger(EmptyState.class);

    public EmptyState(RussiaRoom room) {
        super(room);
    }

    @Override
    public void enter() {
        log.info(String.format("RussiaRoom[%d] is empty now.", room.getId()));
    }

    @Override
    public void processUserCmd(UserVo user, UserCmd userCmd) {
        throw new NotImplementedException();
    }

    @Override
    public void exit(UserVo user) {

    }

}
