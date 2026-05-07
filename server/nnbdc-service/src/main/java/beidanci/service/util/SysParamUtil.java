package beidanci.service.util;

import beidanci.service.bo.SysParamBo;
import beidanci.service.po.SysParam;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;
import java.util.*;

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

    public int getAiStoryConcurrencyLimit() {
        SysParam param = sysParamBO.findById("AiStoryConcurrencyLimit", false);
        return param == null ? 5 : Integer.parseInt(param.getParamValue());
    }

    public int getAiChatGlobalLimit() {
        SysParam param = sysParamBO.findById("AiChatGlobalLimit", false);
        return param == null ? 20 : Integer.parseInt(param.getParamValue());
    }

    public int getAiChatUserLimit() {
        SysParam param = sysParamBO.findById("AiChatUserLimit", false);
        return param == null ? 5 : Integer.parseInt(param.getParamValue());
    }


    public int getAiChatUserDailyLimit() {
        SysParam param = sysParamBO.findById("AiChatUserDailyLimit", false);
        return param == null ? 100 : Integer.parseInt(param.getParamValue());
    }

    public boolean isAiStoryEnTtsEnabled() {
        SysParam param = sysParamBO.findById("AiStoryEnTtsEnabled", false);
        return param != null && Boolean.parseBoolean(param.getParamValue().trim());
    }

    public boolean isAiStoryCnTtsEnabled() {
        SysParam param = sysParamBO.findById("AiStoryCnTtsEnabled", false);
        return param != null && Boolean.parseBoolean(param.getParamValue().trim());
    }

    /**
     * 获取代码中预期的所有系统参数及其默认值和描述
     */
    public List<SysParam> getAllExpectedParams() {
        List<SysParam> list = new java.util.ArrayList<>();
        list.add(new SysParam("IsChatRoomOpen", "false", "聊天室是否开放 (true/false)"));
        list.add(new SysParam("gameEnabled", "true", "游戏功能是否启用 (true/false)"));
        list.add(new SysParam("imgBaseDir", "/var/www/html/img", "图片存储基目录"));
        list.add(new SysParam("SocketServerAddr", "127.0.0.1", "Socket 服务器地址"));
        list.add(new SysParam("SocketServerPort", "8080", "Socket 服务器端口"));
        list.add(new SysParam("DefaultWordsPerDay", "30", "每日默认生词学习量"));
        list.add(new SysParam("AwardCowDungForShare", "10", "分享赠送牛粪数量"));
        list.add(new SysParam("FetchMsgInterval", "5", "拉取消息时间间隔 (秒)"));
        list.add(new SysParam("TempDirForUpload", "/tmp", "上传临时目录"));
        list.add(new SysParam("SaveDirForUpload", "/var/www/uploads", "上传保存目录"));
        list.add(new SysParam("SoundPath", "/var/www/html/sound", "发音文件路径"));
        list.add(new SysParam("HolidayCowDungRatio", "1.0", "节日牛粪奖励倍数"));
        list.add(new SysParam("HolidayCowDungDesc", "", "节日奖励描述"));
        list.add(new SysParam("exportFileDir", "/var/www/html/export", "导出文件目录"));
        list.add(new SysParam("exportFileUrl", "http://localhost/export", "导出文件访问URL"));
        list.add(new SysParam("AiStoryConcurrencyLimit", "5", "AI 短文生成并发上限"));
        list.add(new SysParam("AiChatGlobalLimit", "20", "AI 聊天全局并发上限"));
        list.add(new SysParam("AiChatUserLimit", "5", "AI 聊天单用户并发上限"));
        list.add(new SysParam("AiChatUserDailyLimit", "100", "AI 聊天单用户每日次数上限"));
        list.add(new SysParam("cdnRefreshFileUrls", "", "CDN文件刷新URL配置"));
        list.add(new SysParam("cdnRefreshDirUrls", "", "CDN目录刷新URL配置"));
        list.add(new SysParam("CowDungPerGame", "1", "每局游戏牛粪消耗"));
        list.add(new SysParam("AiStoryEnTtsEnabled", "false", "AI短文英文朗读是否启用 (true/false)"));
        list.add(new SysParam("AiStoryCnTtsEnabled", "false", "AI短文中文朗读是否启用 (true/false)"));
        return list;
    }

    /**
     * 将数据库中的参数列表与代码中预期的参数列表合并
     * 如果数据库中缺失某个参数，则使用预期参数中的默认值补全
     */
    public List<SysParam> mergeWithDefaults(List<SysParam> dbParams) {
        java.util.Map<String, SysParam> mergedMap = new java.util.LinkedHashMap<>();
        
        // 先按顺序放入所有预期的参数（默认值）
        for (SysParam expected : getAllExpectedParams()) {
            mergedMap.put(expected.getParamName(), expected);
        }
        
        // 用数据库中的实际值覆盖默认值
        if (dbParams != null) {
            for (SysParam dbParam : dbParams) {
                mergedMap.put(dbParam.getParamName(), dbParam);
            }
        }
        
        return new java.util.ArrayList<>(mergedMap.values());
    }
}
