package beidanci.service.bo;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

import java.util.HashMap;
import java.util.Map;

import org.junit.jupiter.api.Test;

import beidanci.api.model.UserDbLogDto;

/**
 * 词书主键迁移后，同一批日志里对旧词书 ID 的引用必须一并改写。
 *
 * 现场：客户端上传 INSERT dict(新ID) + INSERT dict_word(旧ID)，服务端因同名冲突把旧词书
 * 迁移成新 ID（级联搬走已有子表行并删除旧行），随后写 dict_word 旧ID 时外键约束失败，
 * 整批回滚，客户端携带同一批日志永久重试。
 */
public class UserDbSyncDictMigrationTest {

    private static final String OLD_DICT_ID = "81e35ce336af401b9c18cb9379629760";
    private static final String NEW_DICT_ID = "22fed9830fee418e952001a1d621858b";

    private final UserDbSyncBo syncBo = new UserDbSyncBo();

    private static UserDbLogDto log(String table, String recordId, String record) {
        return new UserDbLogDto("log-1", "28a4e2c0f9574c18bb19bc72611379d5", 0, "INSERT", table, recordId, record, null,
                null);
    }

    private static Map<String, String> migrations() {
        Map<String, String> map = new HashMap<>();
        map.put(OLD_DICT_ID, NEW_DICT_ID);
        return map;
    }

    @Test
    public void testRewritesDictWordRecordAndRecordId() {
        UserDbLogDto dto = log("dict_word", OLD_DICT_ID + "-23005",
                "{\"dictId\":\"" + OLD_DICT_ID
                        + "\",\"wordId\":\"23005\",\"seq\":21,\"unit\":0,\"semanticSeq\":null}");

        syncBo.applyDictIdMigrations(dto, migrations());

        assertTrue(dto.getRecord().contains("\"dictId\":\"" + NEW_DICT_ID + "\""));
        // 树模型改写不丢字段，也不把显式 null 变成缺省
        assertTrue(dto.getRecord().contains("\"semanticSeq\":null"));
        assertTrue(dto.getRecord().contains("\"wordId\":\"23005\""));
        assertEquals(NEW_DICT_ID + "-23005", dto.getRecordId());
    }

    @Test
    public void testRewritesLearningDictRecordAndRecordId() {
        UserDbLogDto dto = log("learning_dict", "28a4e2c0f9574c18bb19bc72611379d5-" + OLD_DICT_ID,
                "{\"userId\":\"28a4e2c0f9574c18bb19bc72611379d5\",\"dictId\":\"" + OLD_DICT_ID
                        + "\",\"isPrivileged\":false}");

        syncBo.applyDictIdMigrations(dto, migrations());

        assertTrue(dto.getRecord().contains("\"dictId\":\"" + NEW_DICT_ID + "\""));
        assertEquals("28a4e2c0f9574c18bb19bc72611379d5-" + NEW_DICT_ID, dto.getRecordId());
    }

    @Test
    public void testRewritesMeaningItemDictIdOnly() {
        UserDbLogDto dto = log("meaning_item", "meaning-1",
                "{\"id\":\"meaning-1\",\"wordId\":\"23005\",\"dictId\":\"" + OLD_DICT_ID + "\"}");

        syncBo.applyDictIdMigrations(dto, migrations());

        assertTrue(dto.getRecord().contains("\"dictId\":\"" + NEW_DICT_ID + "\""));
        assertEquals("meaning-1", dto.getRecordId());
    }

    @Test
    public void testKeepsUnrelatedDictReference() {
        String otherId = "db06d75d11864c349a6bab95048e1b72";
        UserDbLogDto dto = log("dict_word", otherId + "-23005",
                "{\"dictId\":\"" + otherId + "\",\"wordId\":\"23005\"}");

        syncBo.applyDictIdMigrations(dto, migrations());

        assertTrue(dto.getRecord().contains("\"dictId\":\"" + otherId + "\""));
        assertEquals(otherId + "-23005", dto.getRecordId());
    }

    @Test
    public void testDoesNothingWithoutMigration() {
        UserDbLogDto dto = log("dict_word", OLD_DICT_ID + "-23005",
                "{\"dictId\":\"" + OLD_DICT_ID + "\",\"wordId\":\"23005\"}");
        String record = dto.getRecord();

        syncBo.applyDictIdMigrations(dto, new HashMap<>());

        assertEquals(record, dto.getRecord());
        assertEquals(OLD_DICT_ID + "-23005", dto.getRecordId());
    }

    @Test
    public void testChainedMigrationsResolveToLatestDictId() {
        String middleDictId = "11111111111111111111111111111111";
        String latestDictId = "22222222222222222222222222222222";
        Map<String, String> migrations = new HashMap<>();

        UserDbSyncBo.recordDictIdMigration(migrations, OLD_DICT_ID, middleDictId);
        UserDbSyncBo.recordDictIdMigration(migrations, middleDictId, latestDictId);

        UserDbLogDto dto = log("dict_word", OLD_DICT_ID + "-23005",
                "{\"dictId\":\"" + OLD_DICT_ID + "\",\"wordId\":\"23005\"}");
        syncBo.applyDictIdMigrations(dto, migrations);

        assertTrue(dto.getRecord().contains("\"dictId\":\"" + latestDictId + "\""));
        assertEquals(latestDictId + "-23005", dto.getRecordId());
    }
}
