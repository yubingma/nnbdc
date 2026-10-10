package beidanci.service.bo;

import static org.junit.jupiter.api.Assertions.assertDoesNotThrow;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import java.lang.reflect.Field;
import java.util.Collections;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.mockito.InOrder;
import org.mockito.Mockito;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.jdbc.core.namedparam.SqlParameterSource;

import beidanci.service.dao.BaseDao;
import beidanci.service.po.Dict;
import beidanci.service.po.User;

@SuppressWarnings("all")
public class DictSyncConflictTest {

    private DictBo dictBo;
    private JdbcTemplate jdbcTemplate;
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;
    private BaseDao<Dict> baseDao;

    @BeforeEach
    public void setUp() throws Exception {
        dictBo = new DictBo();
        jdbcTemplate = mock(JdbcTemplate.class);
        namedParameterJdbcTemplate = mock(NamedParameterJdbcTemplate.class);
        baseDao = mock(BaseDao.class);

        // 通过反射注入依赖
        Field jdbcField = BaseBo.class.getDeclaredField("jdbcTemplate");
        jdbcField.setAccessible(true);
        jdbcField.set(dictBo, jdbcTemplate);

        Field daoField = BaseBo.class.getDeclaredField("baseDao");
        daoField.setAccessible(true);
        daoField.set(dictBo, baseDao);

        Field namedJdbcField = DictBo.class.getDeclaredField("namedParameterJdbcTemplate");
        namedJdbcField.setAccessible(true);
        namedJdbcField.set(dictBo, namedParameterJdbcTemplate);
    }

    @Test
    public void testMigrateDictIdWhenSameIdDoesNothing() {
        assertDoesNotThrow(() -> dictBo.migrateDictId("dict_123", "dict_123"));
        verify(jdbcTemplate, never()).update(anyString(), any(Object[].class));
    }

    @Test
    public void testMigrateDictIdWhenOldDictNotFoundThrowsException() {
        when(baseDao.getEntityById(jdbcTemplate, "non_existing")).thenReturn(null);
        assertThrows(IllegalArgumentException.class, () -> dictBo.migrateDictId("non_existing", "new_id"));
    }

    @Test
    public void testMigrateDictIdSequentiallyExecutesCascade() {
        String oldId = "old_dict_uuid_1111111111111111";
        String newId = "new_dict_uuid_2222222222222222";

        Dict oldDict = new Dict();
        oldDict.setId(oldId);
        oldDict.setName("你还在背单词吗？");
        User owner = new User();
        owner.setId("user_123");
        oldDict.setOwner(owner);

        when(baseDao.getEntityById(jdbcTemplate, oldId)).thenReturn(oldDict);

        dictBo.migrateDictId(oldId, newId);

        // 验证执行时序严格遵守：
        // 1. 临时重命名旧词书
        // 2. 插入新 ID 记录
        // 3. 级联迁移 dict_word, learning_dict, meaning_item, group_and_dict_link 子表
        // 4. 删除旧记录
        InOrder inOrder = Mockito.inOrder(jdbcTemplate);

        inOrder.verify(jdbcTemplate).update(
                eq("UPDATE dict SET name = ? WHERE id = ?"),
                Mockito.startsWith("你还在背单词吗？_migrating_"),
                eq(oldId));

        inOrder.verify(jdbcTemplate).update(
                Mockito.contains("INSERT INTO dict (id, name, owner_id"),
                eq(newId),
                eq("你还在背单词吗？"),
                eq(oldId));

        inOrder.verify(jdbcTemplate).update(
                eq("UPDATE dict_word SET dict_id = ? WHERE dict_id = ?"),
                eq(newId),
                eq(oldId));

        inOrder.verify(jdbcTemplate).update(
                eq("UPDATE learning_dict SET dict_id = ? WHERE dict_id = ?"),
                eq(newId),
                eq(oldId));

        inOrder.verify(jdbcTemplate).update(
                eq("UPDATE meaning_item SET dict_id = ? WHERE dict_id = ?"),
                eq(newId),
                eq(oldId));

        inOrder.verify(jdbcTemplate).update(
                eq("UPDATE group_and_dict_link SET dict_id = ? WHERE dict_id = ?"),
                eq(newId),
                eq(oldId));

        inOrder.verify(jdbcTemplate).update(
                eq("DELETE FROM dict WHERE id = ?"),
                eq(oldId));
    }

    @Test
    public void testFindByOwnerIdAndNameQuery() {
        Dict mockDict = new Dict();
        mockDict.setId("dict_found");
        mockDict.setName("我的单词本");

        when(namedParameterJdbcTemplate.query(anyString(), any(SqlParameterSource.class), any(RowMapper.class)))
                .thenReturn(Collections.singletonList(mockDict));

        Dict result = dictBo.findByOwnerIdAndName("user_456", "我的单词本");
        assertEquals("dict_found", result.getId());
        assertEquals("我的单词本", result.getName());
    }

    @Test
    public void testGetDictWordCount() {
        when(namedParameterJdbcTemplate.queryForObject(
                eq("SELECT COUNT(*) FROM dict_word WHERE dict_id = :dictId"),
                any(SqlParameterSource.class),
                eq(Long.class))).thenReturn(100L);

        Long count = dictBo.getDictWordCount("dict_123");
        assertEquals(100L, count);
    }
}
