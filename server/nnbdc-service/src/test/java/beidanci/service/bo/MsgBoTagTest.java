package beidanci.service.bo;

import java.lang.reflect.Field;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.Mockito;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@SuppressWarnings("null")
public class MsgBoTagTest {

    private MsgBo msgBo;
    private NamedParameterJdbcTemplate jdbcTemplate;

    @BeforeEach
    public void setUp() throws Exception {
        msgBo = new MsgBo();
        jdbcTemplate = Mockito.mock(NamedParameterJdbcTemplate.class);

        Field jdbcField = MsgBo.class.getDeclaredField("namedParameterJdbcTemplate");
        jdbcField.setAccessible(true);
        jdbcField.set(msgBo, jdbcTemplate);
    }

    @Test
    public void testUpdateMsgTagToRequirement() {
        when(jdbcTemplate.update(any(String.class), any(MapSqlParameterSource.class))).thenReturn(1);

        msgBo.updateMsgTag("msg_001", "需求");

        ArgumentCaptor<String> sqlCaptor = ArgumentCaptor.forClass(String.class);
        ArgumentCaptor<MapSqlParameterSource> paramCaptor = ArgumentCaptor.forClass(MapSqlParameterSource.class);
        verify(jdbcTemplate).update(sqlCaptor.capture(), paramCaptor.capture());

        assertEquals("UPDATE msg SET tag = :tag WHERE id = :id", sqlCaptor.getValue());
        assertEquals("msg_001", paramCaptor.getValue().getValue("id"));
        assertEquals("需求", paramCaptor.getValue().getValue("tag"));
    }

    @Test
    public void testUpdateMsgTagToNullWhenEmpty() {
        when(jdbcTemplate.update(any(String.class), any(MapSqlParameterSource.class))).thenReturn(1);

        msgBo.updateMsgTag("msg_002", "  ");

        ArgumentCaptor<MapSqlParameterSource> paramCaptor = ArgumentCaptor.forClass(MapSqlParameterSource.class);
        verify(jdbcTemplate).update(any(String.class), paramCaptor.capture());

        assertEquals("msg_002", paramCaptor.getValue().getValue("id"));
        assertNull(paramCaptor.getValue().getValue("tag"));
    }

    @Test
    public void testCleanupOldAdviceProtectsTaggedRequirements() {
        when(jdbcTemplate.update(any(String.class), any(MapSqlParameterSource.class))).thenReturn(5);

        int deleted = msgBo.cleanupOldAdvice(30);

        assertEquals(5, deleted);
        ArgumentCaptor<String> sqlCaptor = ArgumentCaptor.forClass(String.class);
        verify(jdbcTemplate).update(sqlCaptor.capture(), any(MapSqlParameterSource.class));

        String sql = sqlCaptor.getValue();
        // 验证清理SQL必须包含对tag的保护条件，避免误删已打标的需求
        assertTrue(sql.contains("tag IS NULL OR tag = ''"), "清理SQL必须保护已打标签的消息: " + sql);
    }
}
