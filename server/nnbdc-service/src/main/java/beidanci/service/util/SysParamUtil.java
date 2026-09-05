package beidanci.service.util;

import beidanci.service.bo.SysParamBo;
import beidanci.service.po.SysParam;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Component;
import java.util.*;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

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

    /**
     * 获取"下月即将上线功能"的中文展示文本。
     * 参数 UpcomingFeatures 形如 {@code <功能A><功能B>}，解析为 "功能A 和 功能B"；
     * 超过两个则用顿号分隔、最后两个用"和"（如 "功能A、功能B 和 功能C"）。
     * 该值由管理员在系统参数中维护，无需改代码。
     */
    public String getUpcomingFeaturesText() {
        SysParam param = sysParamBO.findById("UpcomingFeatures", false);
        if (param == null || param.getParamValue() == null || param.getParamValue().trim().isEmpty()) {
            return "神秘新功能";
        }
        Matcher m = Pattern.compile("<([^>]*)>").matcher(param.getParamValue().trim());
        List<String> items = new ArrayList<>();
        while (m.find()) {
            String s = m.group(1).trim();
            if (!s.isEmpty()) {
                items.add(s);
            }
        }
        if (items.isEmpty()) {
            return "神秘新功能";
        }
        if (items.size() == 1) {
            return items.get(0);
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < items.size(); i++) {
            if (i > 0) {
                sb.append(i == items.size() - 1 ? " 和 " : "、");
            }
            sb.append(items.get(i));
        }
        return sb.toString();
    }

    public int getAiStoryConcurrencyLimit() {
        SysParam param = sysParamBO.findById("AiStoryConcurrencyLimit", false);
        return param == null ? 5 : Integer.parseInt(param.getParamValue());
    }

    public int getAiChatGlobalConcurrencyLimit() {
        SysParam param = sysParamBO.findById("AiChatGlobalConcurrencyLimit", false);
        return param == null ? 20 : Integer.parseInt(param.getParamValue());
    }

    public int getAiChatUserConcurrencyLimit() {
        SysParam param = sysParamBO.findById("AiChatUserConcurrencyLimit", false);
        return param == null ? 5 : Integer.parseInt(param.getParamValue());
    }


    public int getAiChatUserDailyLimit() {
        SysParam param = sysParamBO.findById("AiChatUserDailyLimit", false);
        return param == null ? 100 : Integer.parseInt(param.getParamValue());
    }

    public int getAiRefereeGlobalConcurrencyLimit() {
        SysParam param = sysParamBO.findById("AiRefereeGlobalConcurrencyLimit", false);
        return param == null ? 30 : Integer.parseInt(param.getParamValue());
    }

    public int getAiRefereeUserConcurrencyLimit() {
        SysParam param = sysParamBO.findById("AiRefereeUserConcurrencyLimit", false);
        return param == null ? 5 : Integer.parseInt(param.getParamValue());
    }

    public int getAiRefereeUserDailyLimit() {
        SysParam param = sysParamBO.findById("AiRefereeUserDailyLimit", false);
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
        list.add(new SysParam("UpcomingFeatures", "", "下月即将上线的功能列表，多个功能用尖括号包裹，如 <功能A><功能B>；未配置时文案显示“神秘新功能”"));
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
