package beidanci.service.socket;


import beidanci.service.bo.UserBo;
import beidanci.service.po.User;
import beidanci.service.util.Util;

public class UserCmd {
    private String userId;
    private String system;
    private String cmd;
    private String[] args;

    public void setUserBo(UserBo userBo) {
        this.userBo = userBo;
    }

    private UserBo userBo;

    public UserCmd() {
    }

    public UserCmd(UserBo userBo) {
        this.userBo = userBo;
    }

    @Override
    public String toString() {
        User user = userBo.findById(userId, true);
        return String.format("User[%s] system[%s] Cmd[%s] args%s", Util.getNickNameOfUser(user), system, cmd,
                Util.array2Str(args));
    }

    public String getUserId() {
        return userId;
    }

    public String getCmd() {
        return cmd;
    }

    public String getSystem() {
        return system;
    }

    public String[] getArgs() {
        return args;
    }
}
