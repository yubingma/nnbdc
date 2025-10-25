package beidanci.service.socket.system.game.russia.state;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import beidanci.api.model.UserVo;
import beidanci.service.bo.DictBo;
import beidanci.service.bo.DictWordBo;
import beidanci.service.bo.SysParamBo;
import beidanci.service.bo.UserBo;
import beidanci.service.bo.UserGameBo;
import beidanci.service.bo.WordBo;
import beidanci.service.socket.UserCmd;
import beidanci.service.socket.system.game.russia.RussiaRoom;
import beidanci.service.store.WordCache;
import beidanci.service.util.UserSorter;

public class WaitState extends RoomState {
    private static final Logger log = LoggerFactory.getLogger(WaitState.class);

    private final GetNextWordProcessor getNextWordProcessor;
    private final GameOverProcessor gameOverProcessor;
    private final StartExerciseProcessor startExerciseProcessor;

    public WaitState(RussiaRoom room, WordCache wordCache, WordBo wordBo, UserGameBo userGameBo, DictWordBo rawWordBo,
                     UserSorter userSorter, SysParamBo sysParamBo, UserBo userBo, DictBo dictBo) {
        super(room);
        getNextWordProcessor = new GetNextWordProcessor(room);
        gameOverProcessor = new GameOverProcessor(room, sysParamBo, userBo);
        startExerciseProcessor = new StartExerciseProcessor(room);
    }

    @Override
    public void enter() {
        room.broadcastEvent("enterWait", null);
    }

    @Override
    public void processUserCmd(UserVo user, UserCmd userCmd) throws IllegalAccessException {
        switch (userCmd.getCmd()) {
            case "GET_NEXT_WORD" -> getNextWordProcessor.processGetNextWordCmd(user, userCmd);
            case "START_EXERCISE" -> {
                // 单人练习命令
                getNextWordProcessor.reset();
                gameOverProcessor.reset();
                startExerciseProcessor.process(user, userCmd);
            }
            case "GAME_OVER" -> gameOverProcessor.processGameOverCmd(user, userCmd);
            default -> log.warn(String.format("WaitState received an unexpected command: [%s]", userCmd.getCmd()));
        }
    }

    @Override
    public void exit(UserVo user) {

    }

}
