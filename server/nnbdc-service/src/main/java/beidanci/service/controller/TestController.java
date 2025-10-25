package beidanci.service.controller;

import org.springframework.context.annotation.Profile;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/test")
@Profile("test")
public class TestController {
    // 所有方法已被删除，因为前端不使用TestController的任何接口
}
