package beidanci.service.util;

import java.util.List;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

import beidanci.api.model.SysDbLogDto;

/**
 * 回归：老客户端（未声明 X-Supported-Tables）绝不能收到它不认识的新表日志，
 * 否则客户端会在「后端表名 → 本地表」映射上抛异常，整次同步（含用户数据）直接失败。
 *
 * 下面的 verCode 都是在网真实版本：26082001 = 线上 minVerCode，26091702 / 26092401 /
 * 26100201 / 26100601 为生产日志里实际出现过的客户端版本。
 */
public class SyncTableFilterTest {

    @Test
    public void 未登记的老表所有版本都放行() {
        for (int ver : new int[] {0, 26082001, 26091702, 26092401, 26100601}) {
            assertTrue(SyncTableFilter.isSupported("dict", null, ver), "ver=" + ver);
            assertTrue(SyncTableFilter.isSupported("cigen_word_link", null, ver), "ver=" + ver);
            assertTrue(SyncTableFilter.isSupported("user_study_step", null, ver), "ver=" + ver);
        }
    }

    @Test
    public void 新增表按引入版本放行() {
        // user_badge：26.09.13 起支持
        assertFalse(SyncTableFilter.isSupported("user_badge", null, 26082001));
        assertTrue(SyncTableFilter.isSupported("user_badge", null, 26091702));

        // word_core_image：26.09.24 起支持
        assertFalse(SyncTableFilter.isSupported("word_core_image", null, 26091702));
        assertTrue(SyncTableFilter.isSupported("word_core_image", null, 26092401));

        // user_pet_state：26.10.02 起支持
        assertFalse(SyncTableFilter.isSupported("user_pet_state", null, 26092401));
        assertTrue(SyncTableFilter.isSupported("user_pet_state", null, 26100201));
    }

    @Test
    public void 尚未发布的表任何老客户端都不发() {
        for (int ver : new int[] {0, 26082001, 26092401, 26100201, 26100601}) {
            assertFalse(SyncTableFilter.isSupported("word_phrase", null, ver), "ver=" + ver);
        }
    }

    @Test
    public void 基线之外且未登记的新表任何老客户端都不发() {
        // 关键安全边界：新表忘了登记版本号时，后果只能是「中间版本暂时收不到」，绝不能打挂老包
        for (int ver : new int[] {0, 26082001, 26091702, 26092401, 26100201, 26100601}) {
            assertFalse(SyncTableFilter.isSupported("brand_new_table", null, ver), "ver=" + ver);
            assertFalse(SyncTableFilter.isSupported("game_hall", null, ver), "ver=" + ver);
        }
    }

    @Test
    public void 声明了能力清单的客户端按清单放行() {
        String declared = "dict,word_phrase,user_pet_state";

        assertTrue(SyncTableFilter.isSupported("word_phrase", declared, 0));
        assertTrue(SyncTableFilter.isSupported("user_pet_state", " dict , user_pet_state ", 0));
        assertTrue(SyncTableFilter.isSupported("dict", declared, 0));
        assertFalse(SyncTableFilter.isSupported("cigen", declared, 0));
        assertFalse(SyncTableFilter.isSupported("game_hall", declared, 0));
    }

    @Test
    public void 版本号解析不出时按最老客户端处理() {
        assertEquals(0, SyncTableFilter.parseClientVersion(null));
        assertEquals(0, SyncTableFilter.parseClientVersion(""));
        assertEquals(0, SyncTableFilter.parseClientVersion("NONE"));
        assertEquals(26100601, SyncTableFilter.parseClientVersion("26100601"));
    }

    @Test
    public void 过滤日志时保持顺序并剔除未知表() {
        List<SysDbLogDto> logs = List.of(
                log("dict"),
                log("word_phrase"),
                log("cigen"),
                log("user_pet_state"));

        List<SysDbLogDto> kept = SyncTableFilter.filter(logs, "dict,cigen", 0, SysDbLogDto::getTblName);

        assertEquals(List.of("dict", "cigen"), kept.stream().map(SysDbLogDto::getTblName).toList());
    }

    private static SysDbLogDto log(String table) {
        SysDbLogDto dto = new SysDbLogDto();
        dto.setTblName(table);
        return dto;
    }
}
