package beidanci.service.controller;

import java.io.IOException;
import java.util.List;

import org.apache.commons.lang3.StringUtils;
import org.apache.commons.mail.EmailException;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.data.util.Pair;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.bind.annotation.RestController;

import beidanci.api.Result;
import beidanci.api.model.MsgVo;
import beidanci.service.bo.MsgBo;
import beidanci.service.bo.UserBo;
import beidanci.service.po.Msg;
import beidanci.service.po.User;
import beidanci.service.util.BeanUtils;

@RestController
public class MsgController {

    @Autowired
    MsgBo msgBo;

    @Autowired
    UserBo userBo;

    @PostMapping("/sendAdvice.do")
    @PreAuthorize("hasAnyRole('USER','ADMIN')")
    @ResponseBody
    public Result<Void> sendAdvice(String content, String clientType, String userId) throws EmailException {
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
            BeanUtils.setPropertiesToNull(msgVo.getFromUser(), new String[]{"id", "displayNickName"});
            BeanUtils.setPropertiesToNull(msgVo.getToUser(), new String[]{"id", "displayNickName"});
        }
    }

    /**
     * 获取指定的用户和系统之间的最近一批消息
     *
     * @throws IOException
     */
    @GetMapping("/getLastestMsgsBetweenUserAndSys.do")
    @PreAuthorize("hasAnyRole('USER', 'ADMIN')")
    public List<MsgVo> getLastestMsgsBetweenUserAndSys(String user, int msgCount) throws IllegalAccessException {
        List<Msg> msgs = msgBo.getLastestMsgsBetweenUserAndSys(user, msgCount, userBo);

        List<MsgVo> vos = BeanUtils.makeVos(msgs, MsgVo.class, new String[]{"invitedBy", "StudyGroupVo.creator",
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
    @PreAuthorize("hasAnyRole('USER', 'ADMIN')")
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
    public Result<Pair<Integer, Integer>> getMsgCounts(@RequestParam(name = "userId") String userId) {
        User user = userBo.findById(userId);
        if (user == null) {
            return Result.success(Pair.of(0, 0));
        }
        return Result.success(Pair.of(msgBo.getAllPersistentMsgCountToUser(user.getId()),
                msgBo.getUnViewedPersistentMsgCountToUser(user.getId())));
    }

    /**
     * 获取所有用户的意见建议（管理员功能）
     *
     * @throws IllegalAccessException
     */
    @GetMapping("/getAllAdviceMessages.do")
    @PreAuthorize("hasAnyRole('ADMIN')")
    public List<MsgVo> getAllAdviceMessages() throws IllegalAccessException {
        List<Msg> msgs = msgBo.getAllAdviceMessages();
        List<MsgVo> vos = BeanUtils.makeVos(msgs, MsgVo.class, new String[]{"invitedBy", "StudyGroupVo.creator",
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
    @PreAuthorize("hasAnyRole('ADMIN')")
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
}
