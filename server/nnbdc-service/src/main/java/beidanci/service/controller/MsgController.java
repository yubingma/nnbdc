package beidanci.service.controller;

import java.io.IOException;
import java.util.List;

import org.apache.commons.lang3.StringUtils;
import org.apache.commons.mail.EmailException;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.bind.annotation.DeleteMapping;

import beidanci.api.Result;
import beidanci.api.model.MsgCountVo;
import beidanci.api.model.MsgVo;
import beidanci.service.bo.MsgBo;
import beidanci.service.bo.UserBo;
import beidanci.service.po.Msg;
import beidanci.service.po.User;
import beidanci.service.util.PoVoUtils;

@RestController
public class MsgController {

    @Autowired
    MsgBo msgBo;

    @Autowired
    UserBo userBo;

    @PostMapping("/sendAdvice.do")
    @ResponseBody
    public Result<Void> sendAdvice(String content, String clientType, String userId) throws EmailException {
        System.out.println("DEBUG: MsgController.sendAdvice - content: " + content);
        System.out.println("DEBUG: MsgController.sendAdvice - clientType: " + clientType);
        System.out.println("DEBUG: MsgController.sendAdvice - userId: " + userId);
        
        if (StringUtils.isEmpty(content.trim())) {
            return Result.fail("内容不得为空");
        }
        
        User loggedInUser = userBo.findById(userId);
        if (loggedInUser == null) {
            return Result.fail("用户未登录");
        }
        
        msgBo.sendAdvice(content, clientType, loggedInUser);

        return Result.success(null);
    }

    private void shrinkUserInfoForMsgVos(List<MsgVo> vos) throws IllegalAccessException {
        for (MsgVo msgVo : vos) {
            PoVoUtils.setPropertiesToNull(msgVo.getFromUser(), new String[]{"id", "displayNickName"});
            PoVoUtils.setPropertiesToNull(msgVo.getToUser(), new String[]{"id", "displayNickName"});
        }
    }

    /**
     * 获取指定的用户和系统之间的最近一批消息
     *
     * @throws IOException
     */
    @GetMapping("/getLastestMsgsBetweenUserAndSys.do")
    public List<MsgVo> getLastestMsgsBetweenUserAndSys(String user, int msgCount) throws IllegalAccessException {
        List<Msg> msgs = msgBo.getLastestMsgsBetweenUserAndSys(user, msgCount, userBo);

        List<MsgVo> vos = PoVoUtils.makeVos(msgs, MsgVo.class, new String[]{"invitedBy", "StudyGroupVo.creator",
                "StudyGroupVo.users", "StudyGroupVo.managers", "studyGroupPosts", "userGames"});
        shrinkUserInfoForMsgVos(vos);
        return vos;
    }

    /**
     * 把指定的消息置为已读
     *
     * @throws IOException
     */
    @PutMapping("/setMsgsAsViewed.do")
    public Result<Void> setMsgsAsViewed(@RequestParam(name = "msgIds") List<String> msgIds,
                                        @RequestParam(name = "userId") String userId) {
        msgBo.setMsgsAsViewed(msgIds, userId, userBo);
        return Result.success(null);
    }

    /**
     * 获取用户消息数量（消息总数和未读数量）
     *
     * @throws IOException
     */
    @GetMapping("/getMsgCounts.do")
    public Result<MsgCountVo> getMsgCounts(@RequestParam(name = "userId") String userId) {
        User user = userBo.findById(userId);
        if (user == null) {
            return Result.success(new MsgCountVo(0, 0));
        }
        // 确保返回的值不为 null，避免 JSON 序列化时出现 null
        int allCount = msgBo.getAllPersistentMsgCountToUser(user.getId());
        int unviewedCount = msgBo.getUnViewedPersistentMsgCountToUser(user.getId());
        // 使用专门的 DTO 类，确保字段名与 Flutter 端匹配
        return Result.success(new MsgCountVo(allCount, unviewedCount));
    }

    /**
     * 获取所有用户的意见建议（管理员功能）
     *
     * @throws IllegalAccessException
     */
    @GetMapping("/getAllAdviceMessages.do")
    public List<MsgVo> getAllAdviceMessages() throws IllegalAccessException {
        List<Msg> msgs = msgBo.getAllAdviceMessages();
        List<MsgVo> vos = PoVoUtils.makeVos(msgs, MsgVo.class, new String[]{"invitedBy", "StudyGroupVo.creator",
                "StudyGroupVo.users", "StudyGroupVo.managers", "studyGroupPosts", "userGames"});
        // 管理员功能不需要清空用户信息，保留完整的用户数据
        return vos;
    }

    /**
     * 回复用户意见建议（管理员功能）
     *
     * @throws IllegalAccessException
     */
    @PostMapping("/replyAdvice.do")
    public Result<Void> replyAdvice(@RequestParam(name = "content") String content,
                                   @RequestParam(name = "toUserId") String toUserId,
                                   @RequestParam(name = "adminUserId") String adminUserId) throws IllegalAccessException {
        if (StringUtils.isEmpty(content.trim())) {
            return Result.fail("回复内容不得为空");
        }
        
        User toUser = userBo.findById(toUserId);
        if (toUser == null) {
            return Result.fail("目标用户不存在");
        }
        
        User adminUser = userBo.findById(adminUserId);
        if (adminUser == null || !adminUser.getIsAdmin()) {
            return Result.fail("管理员权限不足");
        }
        
        msgBo.replyAdvice(content, toUser, userBo);
        return Result.success(null);
    }

    /**
     * 清理旧的意见建议（管理员功能）
     *
     * @param daysAge 天数
     * @param adminUserId 管理员ID
     * @return 删除的记录数
     */
    @DeleteMapping("/cleanupOldAdvice.do")
    public Result<Integer> cleanupOldAdvice(@RequestParam(name = "daysAge") int daysAge,
                                         @RequestParam(name = "adminUserId") String adminUserId) {
        User adminUser = userBo.findById(adminUserId);
        if (adminUser == null || !adminUser.getIsAdmin()) {
            return Result.fail("管理员权限不足");
        }

        int deletedCount = msgBo.cleanupOldAdvice(daysAge);
        return Result.success(deletedCount);
    }
}
