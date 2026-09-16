package beidanci.service.controller;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import beidanci.service.bo.WechatPushBo;

/**
 * 微信开放平台「消息推送」回调。
 *
 * 配置位置: 开放平台 → 管理中心 → 移动应用 → 开发配置 → 消息推送，
 * URL 填 https://back.nnbdc.com/wechatPush.do，加解密方式选「安全模式」，数据格式选 JSON。
 */
@RestController
public class WechatPushController {

    private static final Logger logger = LoggerFactory.getLogger(WechatPushController.class);

    @Autowired
    private WechatPushBo wechatPushBo;

    /** 开放平台点击「提交」时的 URL 校验: 验签通过后原样返回 echostr */
    @GetMapping(value = "/wechatPush.do", produces = MediaType.TEXT_PLAIN_VALUE)
    public ResponseEntity<String> verifyUrl(@RequestParam String signature, @RequestParam String timestamp,
            @RequestParam String nonce, @RequestParam String echostr) {
        if (!wechatPushBo.verifyUrl(timestamp, nonce, signature)) {
            logger.warn("微信推送 URL 校验失败: timestamp={}, nonce={}, signature={}", timestamp, nonce, signature);
            return ResponseEntity.status(HttpStatus.FORBIDDEN).body("");
        }
        return ResponseEntity.ok(echostr);
    }

    /** 接收授权变更事件（安全模式密文），落库后回 success */
    @PostMapping(value = "/wechatPush.do", produces = MediaType.TEXT_PLAIN_VALUE)
    public ResponseEntity<String> receiveEvent(@RequestParam String timestamp, @RequestParam String nonce,
            @RequestParam(name = "msg_signature") String msgSignature, @RequestBody String body) {
        try {
            wechatPushBo.handlePush(timestamp, nonce, msgSignature, body);
        } catch (WechatPushBo.InvalidSignatureException e) {
            logger.warn("微信推送验签失败，已拒绝: timestamp={}, nonce={}", timestamp, nonce);
            return ResponseEntity.status(HttpStatus.FORBIDDEN).body("");
        }
        return ResponseEntity.ok("success");
    }
}
