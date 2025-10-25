package beidanci.service.util;

import beidanci.service.bo.SysParamBo;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;

@Component
public class SysParamUtil {
    @Autowired
    SysParamBo sysParamBO;


    public boolean isChatRoomOpen() {
        return Boolean.parseBoolean(sysParamBO.findById("IsChatRoomOpen", false).getParamValue());
    }

    public boolean isGameEnabled() {
        return Boolean.parseBoolean(sysParamBO.findById("gameEnabled", true).getParamValue());
    }


    public String getImageBaseDir() {
        return sysParamBO.findById("imgBaseDir", false).getParamValue();
    }

    public String getSocketServerAddr() {
        return sysParamBO.findById("SocketServerAddr", true).getParamValue();
    }

    public int getSocketServerPort() {
        return Integer.parseInt(sysParamBO.findById("SocketServerPort", true).getParamValue());
    }

    public int getDefaultWordsPerDay() {
        return Integer.parseInt(sysParamBO.findById("DefaultWordsPerDay", false).getParamValue());
    }

    public int getAwardCowDungForShare() {
        return Integer.parseInt(sysParamBO.findById("AwardCowDungForShare", false).getParamValue());
    }

    public int getFetchMsgInterval() {
        return Integer.parseInt(sysParamBO.findById("FetchMsgInterval", false).getParamValue());
    }

    public String getTempDirForUpload() {
        return sysParamBO.findById("TempDirForUpload", false).getParamValue();
    }

    public String getSaveDirForUpload() {
        return sysParamBO.findById("SaveDirForUpload", false).getParamValue();
    }

    public String getSoundPath() {
        return sysParamBO.findById("SoundPath", false).getParamValue();
    }

    public float getHolidayCowDungRatio() {
        return Float.parseFloat(sysParamBO.findById("HolidayCowDungRatio", false).getParamValue());
    }

    public String getHolidayCowDungDesc() {
        return sysParamBO.findById("HolidayCowDungDesc", false).getParamValue();
    }

    public String getExportFileDir() {
        return sysParamBO.findById("exportFileDir", false).getParamValue();
    }

    public String getExportFileUrl() {
        return sysParamBO.findById("exportFileUrl", false).getParamValue();
    }
}
