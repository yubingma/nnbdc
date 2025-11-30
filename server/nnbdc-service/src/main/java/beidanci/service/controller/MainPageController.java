package beidanci.service.controller;

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
        User user = userBo.findById(userId);
        if (user == null) {
            return Result.fail("用户不存在");
        }

        int rank = userSorter.getOrderOfUser(user.getUserName());
        return Result.success(rank);
    }
}
