package beidanci.service.bo;

import java.io.IOException;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import beidanci.api.Result;
import okhttp3.OkHttpClient;
import okhttp3.Request;
import okhttp3.Response;

/**
 * 微信相关业务逻辑
 */
@Service
public class WechatBo {

    private static final Logger logger = LoggerFactory.getLogger(WechatBo.class);

    // 微信开放平台配置
    // TODO: 在application.properties中配置这些值
    @Value("${wechat.app.id:YOUR_APP_ID}")
    private String appId;

    @Value("${wechat.app.secret:YOUR_APP_SECRET}")
    private String appSecret;

    private static final String WECHAT_AUTH_URL = "https://api.weixin.qq.com/sns/oauth2/access_token";
    private static final String WECHAT_USERINFO_URL = "https://api.weixin.qq.com/sns/userinfo";

    private final OkHttpClient httpClient = new OkHttpClient();
    private final ObjectMapper objectMapper = new ObjectMapper();

    /**
     * 微信用户信息
     */
    public static class WechatUserInfo {
        public String openId;
        public String unionId;
        public String nickname;
        public String headImgUrl;
        public String accessToken;

        public WechatUserInfo(String openId, String unionId, String nickname, String headImgUrl, String accessToken) {
            this.openId = openId;
            this.unionId = unionId;
            this.nickname = nickname;
            this.headImgUrl = headImgUrl;
            this.accessToken = accessToken;
        }
    }

    /**
     * 使用微信授权码获取用户信息
     * 
     * @param code 微信授权码
     * @return 用户信息
     */
    public Result<WechatUserInfo> getUserInfoByCode(String code) {
        try {
            // 检查配置
            if ("YOUR_APP_ID".equals(appId) || "YOUR_APP_SECRET".equals(appSecret)) {
                logger.error("微信开放平台配置未设置，请在application.properties中配置wechat.app.id和wechat.app.secret");
                return new Result<>(false, "微信登录功能未配置，请联系管理员", null);
            }

            // 1. 使用code换取access_token和openid
            String tokenUrl = String.format("%s?appid=%s&secret=%s&code=%s&grant_type=authorization_code",
                    WECHAT_AUTH_URL, appId, appSecret, code);

            Request tokenRequest = new Request.Builder()
                    .url(tokenUrl)
                    .get()
                    .build();

            Response tokenResponse = httpClient.newCall(tokenRequest).execute();
            if (!tokenResponse.isSuccessful()) {
                logger.error("微信token请求失败: {}", tokenResponse.code());
                return new Result<>(false, "微信授权失败", null);
            }

            String tokenBody = tokenResponse.body().string();
            logger.info("微信token响应: {}", tokenBody);

            JsonNode tokenJson = objectMapper.readTree(tokenBody);
            if (tokenJson.has("errcode")) {
                int errcode = tokenJson.get("errcode").asInt();
                String errmsg = tokenJson.get("errmsg").asText();
                logger.error("微信token错误: {} - {}", errcode, errmsg);
                return new Result<>(false, "微信授权失败: " + errmsg, null);
            }

            String accessToken = tokenJson.get("access_token").asText();
            String openId = tokenJson.get("openid").asText();
            String unionId = tokenJson.has("unionid") ? tokenJson.get("unionid").asText() : null;

            // 2. 使用access_token获取用户信息
            String userInfoUrl = String.format("%s?access_token=%s&openid=%s",
                    WECHAT_USERINFO_URL, accessToken, openId);

            Request userInfoRequest = new Request.Builder()
                    .url(userInfoUrl)
                    .get()
                    .build();

            Response userInfoResponse = httpClient.newCall(userInfoRequest).execute();
            if (!userInfoResponse.isSuccessful()) {
                logger.error("微信用户信息请求失败: {}", userInfoResponse.code());
                return new Result<>(false, "获取用户信息失败", null);
            }

            String userInfoBody = userInfoResponse.body().string();
            logger.info("微信用户信息响应: {}", userInfoBody);

            JsonNode userInfoJson = objectMapper.readTree(userInfoBody);
            if (userInfoJson.has("errcode")) {
                int errcode = userInfoJson.get("errcode").asInt();
                String errmsg = userInfoJson.get("errmsg").asText();
                logger.error("微信用户信息错误: {} - {}", errcode, errmsg);
                return new Result<>(false, "获取用户信息失败: " + errmsg, null);
            }

            String nickname = userInfoJson.get("nickname").asText();
            String headImgUrl = userInfoJson.get("headimgurl").asText();
            if (unionId == null && userInfoJson.has("unionid")) {
                unionId = userInfoJson.get("unionid").asText();
            }

            WechatUserInfo wechatUserInfo = new WechatUserInfo(openId, unionId, nickname, headImgUrl, accessToken);
            return new Result<>(true, "获取用户信息成功", wechatUserInfo);

        } catch (IOException e) {
            logger.error("微信API调用异常", e);
            return new Result<>(false, "网络异常，请稍后重试", null);
        } catch (Exception e) {
            logger.error("微信登录处理异常", e);
            return new Result<>(false, "登录失败，请稍后重试", null);
        }
    }
}

