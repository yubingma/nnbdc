package beidanci.service.controller;

import java.util.List;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import beidanci.api.Result;
import beidanci.api.model.UserBadgeVo;
import beidanci.service.bo.BadgeBo;
import beidanci.service.bo.UserBo;
import beidanci.service.po.User;

@RestController
public class BadgeController {
    private static final Logger log = LoggerFactory.getLogger(BadgeController.class);

    @Autowired
    private BadgeBo badgeBo;

    @Autowired
    private UserBo userBo;

    /**
     * 获取用户全量勋章状态列表 (基于 Badge 枚举与用户达成记录装配)
     */
    @GetMapping("/badge/getMyBadges.do")
    public Result<List<UserBadgeVo>> getMyBadges(@RequestParam(required = false) String userId) {
        try {
            User user = (userId != null && !userId.trim().isEmpty()) ? userBo.findById(userId.trim()) : null;
            List<UserBadgeVo> badges = badgeBo.getMyBadges(user);
            return Result.success(badges);
        } catch (Exception e) {
            log.error("获取勋章列表失败", e);
            return Result.fail("获取勋章列表失败: " + e.getMessage());
        }
    }

    /**
     * 置顶佩戴 / 取消佩戴勋章
     */
    @PostMapping("/badge/equipBadge.do")
    public Result<Boolean> equipBadge(
            @RequestParam String userId,
            @RequestParam String badgeCode,
            @RequestParam boolean isEquipped) {
        try {
            User user = userBo.findById(userId);
            if (user == null) {
                return Result.fail("用户不存在");
            }
            boolean success = badgeBo.equipBadge(user, badgeCode, isEquipped);
            return success ? Result.success(true) : Result.fail("操作失败，未找到对应勋章记录");
        } catch (Exception e) {
            log.error("佩戴勋章失败", e);
            return Result.fail("佩戴勋章失败: " + e.getMessage());
        }
    }
}
