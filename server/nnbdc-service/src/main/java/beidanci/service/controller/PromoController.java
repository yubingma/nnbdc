package beidanci.service.controller;

import java.util.Date;
import java.util.List;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import beidanci.api.Result;
import beidanci.api.model.PromoActivityVo;
import beidanci.api.model.UserVo;
import beidanci.service.bo.PromoActivityBo;
import beidanci.service.bo.PromoRedemptionBo;
import beidanci.service.bo.UserBo;
import beidanci.service.po.PromoActivity;
import beidanci.service.po.User;
import beidanci.service.util.PoVoUtils;

@RestController
public class PromoController {

    @Autowired
    private UserBo userBo;

    @Autowired
    private PromoActivityBo promoActivityBo;

    @Autowired
    private PromoRedemptionBo promoRedemptionBo;

    /**
     * 用户兑换活动码
     */
    @PostMapping("/redeemPromoCode.do")
    public Result<UserVo> redeemPromoCode(
            @RequestParam String userId,
            @RequestParam String promoCode) {
        try {
            User user = userBo.findById(userId);
            if (user == null) {
                return Result.fail("用户不存在");
            }

            if (promoCode == null || promoCode.trim().isEmpty()) {
                return Result.fail("活动码不能为空");
            }

            PromoActivity activity = promoActivityBo.findByCode(promoCode.trim());
            if (activity == null || !Boolean.TRUE.equals(activity.getIsActive())) {
                return Result.fail("无效的活动码");
            }

            Date now = new Date();
            if (activity.getStartTime() != null && activity.getStartTime().after(now)) {
                return Result.fail("该活动尚未开始");
            }
            if (activity.getEndTime() != null && activity.getEndTime().before(now)) {
                return Result.fail("该活动已结束");
            }

            if (activity.getMaxRedemptions() != null && activity.getMaxRedemptions() > 0) {
                if (activity.getRedemptionCount() >= activity.getMaxRedemptions()) {
                    return Result.fail("该活动码兑换次数已达上限");
                }
            }

            if (promoRedemptionBo.hasRedeemed(userId, activity.getId())) {
                return Result.fail("您已兑换过该活动码，不能重复兑换");
            }

            // 执行兑换操作
            User updatedUser = promoRedemptionBo.redeem(user, activity);

            UserVo userVo = PoVoUtils.makeVo(updatedUser, UserVo.class,
                    new String[] { "invitedBy", "StudyGroupVo.creator", "StudyGroupVo.users",
                            "StudyGroupVo.managers", "studyGroupPosts", "userGames" });

            return Result.success(userVo);
        } catch (Exception e) {
            return Result.fail("兑换失败: " + e.getMessage());
        }
    }

    /**
     * 获取当前最新的有效推广活动（用于前台展示倒计时与剩余名额）
     */
    @GetMapping("/getActivePromoActivity.do")
    public Result<PromoActivityVo> getActivePromoActivity() {
        try {
            PromoActivity activity = promoActivityBo.getLatestActiveActivity();
            if (activity == null) {
                return Result.success(null);
            }
            PromoActivityVo vo = PoVoUtils.makeVo(activity, PromoActivityVo.class, null);
            return Result.success(vo);
        } catch (Exception e) {
            return Result.fail("获取活动信息失败: " + e.getMessage());
        }
    }

    /**
     * 管理员创建推广活动
     */
    @PostMapping("/admin/createPromoActivity.do")
    public Result<Void> createPromoActivity(
            @RequestParam String userId,
            @RequestParam String name,
            @RequestParam String activityCode,
            @RequestParam(required = false) String duration,
            @RequestParam(required = false) Long endTime,
            @RequestParam(required = false) Integer maxRedemptions) {
        try {
            User admin = userBo.findById(userId);
            if (admin == null || !admin.getIsAdmin()) {
                return Result.fail("无权限");
            }

            if (name == null || name.trim().isEmpty()) {
                return Result.fail("活动名称不能为空");
            }
            if (activityCode == null || activityCode.trim().isEmpty()) {
                return Result.fail("活动码不能为空");
            }

            PromoActivity existing = promoActivityBo.findByCode(activityCode);
            if (existing != null) {
                return Result.fail("活动码已存在");
            }

            PromoActivity activity = new PromoActivity();
            activity.setName(name.trim());
            activity.setActivityCode(activityCode.trim());
            
            // 持续时间处理：留空表示永久，否则去除首尾空格
            if (duration != null && !duration.trim().isEmpty()) {
                activity.setDuration(duration.trim());
            } else {
                activity.setDuration(null);
            }
            
            if (endTime != null && endTime > 0) {
                activity.setEndTime(new Date(endTime));
            } else {
                activity.setEndTime(null);
            }

            activity.setMaxRedemptions(maxRedemptions);
            activity.setRedemptionCount(0);
            activity.setIsActive(true);
            activity.setCreateTime(new Date());
            activity.setUpdateTime(new Date());

            promoActivityBo.createEntity(activity);
            return Result.success(null);
        } catch (Exception e) {
            return Result.fail("创建活动失败: " + e.getMessage());
        }
    }

    /**
     * 管理员获取所有推广活动
     */
    @GetMapping("/admin/listPromoActivities.do")
    public Result<List<PromoActivityVo>> listPromoActivities(
            @RequestParam String userId) {
        try {
            User admin = userBo.findById(userId);
            if (admin == null || !admin.getIsAdmin()) {
                return Result.fail("无权限");
            }

            List<PromoActivity> activities = promoActivityBo.queryAll(null, "createTime", "desc", false);
            List<PromoActivityVo> vos = PoVoUtils.makeVos(activities, PromoActivityVo.class, null);
            return Result.success(vos);
        } catch (Exception e) {
            return Result.fail("获取活动列表失败: " + e.getMessage());
        }
    }

    /**
     * 管理员删除推广活动
     */
    @PostMapping("/admin/deletePromoActivity.do")
    public Result<Void> deletePromoActivity(
            @RequestParam String userId,
            @RequestParam String activityId) {
        try {
            User admin = userBo.findById(userId);
            if (admin == null || !admin.getIsAdmin()) {
                return Result.fail("无权限");
            }

            PromoActivity activity = promoActivityBo.findById(activityId);
            if (activity == null) {
                return Result.fail("活动不存在");
            }

            promoActivityBo.deleteEntity(activity);
            return Result.success(null);
        } catch (Exception e) {
            return Result.fail("删除活动失败: " + e.getMessage());
        }
    }
}
