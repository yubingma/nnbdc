package beidanci.service.bo;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;

import java.util.Date;

import org.junit.jupiter.api.Test;

import com.fasterxml.jackson.databind.ObjectMapper;

import beidanci.service.po.WechatAuthEvent;

public class WechatPushBoTest {

    private final ObjectMapper objectMapper = new ObjectMapper();

    @Test
    public void testParseRevokeEvent() {
        String payload = "{\"ToUserName\":\"gh_unknown\",\"FromUserName\":\"oaKk346BaWE\","
                + "\"CreateTime\":1789446945,\"MsgType\":\"event\",\"Event\":\"user_authorization_revoke\","
                + "\"OpenID\":\"olP_Y6xJBOCP-98LZlrG06JgoaBk\",\"UnionID\":\"oW-TY6_26T2nqKjOU7NDfmk27Cms\","
                + "\"AppID\":\"wx42e6014d1927e5f0\",\"RevokeInfo\":\"301\"}";

        WechatAuthEvent event = WechatPushBo.parseEvent(objectMapper, payload);

        assertEquals("user_authorization_revoke", event.getEvent());
        assertEquals("wx42e6014d1927e5f0", event.getAppId());
        assertEquals("olP_Y6xJBOCP-98LZlrG06JgoaBk", event.getOpenId());
        assertEquals("oW-TY6_26T2nqKjOU7NDfmk27Cms", event.getUnionId());
        assertEquals("301", event.getRevokeInfo());
        assertEquals(new Date(1789446945L * 1000L), event.getEventTime());
        assertEquals(payload, event.getRawPayload());
        // 主键与创建时间由 createEntity 落库时生成
        assertNull(event.getId());
    }

    @Test
    public void testParseEventWithoutOptionalFields() {
        String payload = "{\"CreateTime\":1789446945,\"Event\":\"user_authorization_cancellation\","
                + "\"OpenID\":\"olP_Y6xJBOCP-98LZlrG06JgoaBk\",\"AppID\":\"wx42e6014d1927e5f0\"}";

        WechatAuthEvent event = WechatPushBo.parseEvent(objectMapper, payload);

        assertEquals("user_authorization_cancellation", event.getEvent());
        assertNull(event.getUnionId());
        assertNull(event.getRevokeInfo());
    }

    @Test
    public void testParseEventRejectsMissingFields() {
        assertThrows(IllegalArgumentException.class,
                () -> WechatPushBo.parseEvent(objectMapper, "{\"OpenID\":\"olP_Y6xJBOCP-98LZlrG06JgoaBk\"}"));
        assertThrows(IllegalArgumentException.class,
                () -> WechatPushBo.parseEvent(objectMapper,
                        "{\"Event\":\"user_authorization_revoke\",\"AppID\":\"wx42e6014d1927e5f0\"}"));
        assertThrows(IllegalArgumentException.class, () -> WechatPushBo.parseEvent(objectMapper, "not a json"));
    }
}
