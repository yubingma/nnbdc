package beidanci.service.controller;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import beidanci.api.Result;
import beidanci.service.bo.LearningDictBo;
import beidanci.service.bo.LearningWordBo;
import beidanci.service.bo.UserBo;
import beidanci.service.po.User;
import beidanci.service.util.UserSorter;

@RestController
public class MainPageController {
    private static final Logger log = LoggerFactory.getLogger(MainPageController.class);

    @Autowired
    LearningDictBo selectedDictBo;

    @Autowired
    UserSorter userSorter;

    @Autowired
    UserBo userBo;

    @Autowired
    LearningWordBo learningWordBo;

    @Autowired
    LearningDictBo learningDictBo;

    @GetMapping("getUserRank.do")
    @PreAuthorize("hasAnyRole('USER', 'ADMIN')")
    public Result<Integer> getUserRank(@RequestParam("userId") String userId) throws IllegalAccessException {
        try {
            User user = userBo.findById(userId);
            if (user == null) {
                return Result.fail("用户不存在");
            }

            int rank = userSorter.getOrderOfUser(user.getUserName());
            return Result.success(rank);
        } catch (Exception e) {
            log.error("获取用户排名失败", e);
            return Result.fail("获取排名失败: " + e.getMessage());
        }
    }
}
