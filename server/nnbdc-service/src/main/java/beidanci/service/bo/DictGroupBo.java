package beidanci.service.bo;

import javax.annotation.PostConstruct;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import beidanci.service.dao.BaseDao;
import beidanci.service.dao.EntityRowMapper;
import beidanci.service.po.Dict;
import beidanci.service.po.DictGroup;

@Service
@Transactional(rollbackFor = Throwable.class)
public class DictGroupBo extends BaseBo<DictGroup> {
    @Autowired
    private NamedParameterJdbcTemplate namedParameterJdbcTemplate;

    @PostConstruct
    public void init() {
        setDao(new BaseDao<DictGroup>() {
        });
    }

    // 获取所有单词书分组
    public List<DictGroup> getAllDictGroups() {
        String sql = "SELECT * FROM dict_group ORDER BY displayIndex ASC";
        return namedParameterJdbcTemplate.query(sql, 
            new beidanci.service.dao.EntityRowMapper<>(DictGroup.class));
    }

    /**
     * 加载 DictGroup 的 dictGroups（子分组）和 dicts（直接包含的单词书）集合
     * 递归加载所有子分组的集合
     */
    public void loadDictGroupsAndDicts(DictGroup dictGroup) {
        if (dictGroup == null) {
            return;
        }

        // 加载子分组（dictGroups）
        // 注意：数据库中的外键列名是 parentId，而不是 dictGroupId
        String childGroupsSql = "SELECT * FROM dict_group WHERE parentId = :parentId ORDER BY displayIndex ASC";
        MapSqlParameterSource childGroupsParams = new MapSqlParameterSource("parentId", dictGroup.getId());
        List<DictGroup> childGroups = namedParameterJdbcTemplate.query(childGroupsSql, childGroupsParams,
                new EntityRowMapper<>(DictGroup.class));
        dictGroup.setDictGroups(childGroups);

        // 加载直接包含的单词书（dicts）
        String dictsSql = "SELECT d.* FROM dict d " +
                "INNER JOIN group_and_dict_link gdl ON gdl.dictId = d.id " +
                "WHERE gdl.groupId = :groupId";
        MapSqlParameterSource dictsParams = new MapSqlParameterSource("groupId", dictGroup.getId());
        List<Dict> dicts = namedParameterJdbcTemplate.query(dictsSql, dictsParams,
                new EntityRowMapper<>(Dict.class));
        dictGroup.setDicts(dicts);

        // 递归加载所有子分组的集合
        if (childGroups != null) {
            for (DictGroup childGroup : childGroups) {
                loadDictGroupsAndDicts(childGroup);
            }
        }
    }

    /**
     * 批量加载多个 DictGroup 的 dictGroups 和 dicts 集合
     */
    public void loadDictGroupsAndDictsForDictGroups(List<DictGroup> dictGroups) {
        if (dictGroups == null || dictGroups.isEmpty()) {
            return;
        }

        // 收集所有 DictGroup 的 ID
        Set<String> dictGroupIds = dictGroups.stream()
                .map(DictGroup::getId)
                .collect(Collectors.toSet());

        if (dictGroupIds.isEmpty()) {
            return;
        }

        // 批量查询所有子分组
        // 注意：数据库中的外键列名是 parentId，而不是 dictGroupId
        String childGroupsSql = "SELECT * FROM dict_group WHERE parentId IN (:parentIds) ORDER BY displayIndex ASC";
        MapSqlParameterSource childGroupsParams = new MapSqlParameterSource("parentIds", new ArrayList<>(dictGroupIds));
        List<DictGroup> allChildGroups = namedParameterJdbcTemplate.query(childGroupsSql, childGroupsParams,
                new EntityRowMapper<>(DictGroup.class));

        // 按父分组ID分组
        Map<String, List<DictGroup>> childGroupsByParentId = new HashMap<>();
        for (DictGroup childGroup : allChildGroups) {
            if (childGroup.getDictGroup() != null && childGroup.getDictGroup().getId() != null) {
                String parentId = childGroup.getDictGroup().getId();
                childGroupsByParentId.computeIfAbsent(parentId, k -> new ArrayList<>()).add(childGroup);
            }
        }

        // 批量查询所有直接包含的单词书关联
        String linksSql = "SELECT groupId, dictId FROM group_and_dict_link WHERE groupId IN (:groupIds)";
        MapSqlParameterSource linksParams = new MapSqlParameterSource("groupIds", new ArrayList<>(dictGroupIds));
        List<Map<String, Object>> linkRows = namedParameterJdbcTemplate.queryForList(linksSql, linksParams);
        
        // 收集所有 dictId
        Set<String> dictIds = linkRows.stream()
                .map(row -> (String) row.get("dictId"))
                .collect(Collectors.toSet());

        // 批量查询所有 Dict
        Map<String, Dict> dictMap = new HashMap<>();
        if (!dictIds.isEmpty()) {
            String dictsSql = "SELECT * FROM dict WHERE id IN (:dictIds)";
            MapSqlParameterSource dictsParams = new MapSqlParameterSource("dictIds", new ArrayList<>(dictIds));
            List<Dict> allDicts = namedParameterJdbcTemplate.query(dictsSql, dictsParams,
                    new EntityRowMapper<>(Dict.class));
            dictMap = allDicts.stream()
                    .collect(Collectors.toMap(Dict::getId, d -> d));
        }

        // 按 groupId 分组
        Map<String, List<Dict>> dictsByGroupId = new HashMap<>();
        for (Map<String, Object> row : linkRows) {
            String groupId = (String) row.get("groupId");
            String dictId = (String) row.get("dictId");
            Dict dict = dictMap.get(dictId);
            if (dict != null) {
                dictsByGroupId.computeIfAbsent(groupId, k -> new ArrayList<>()).add(dict);
            }
        }

        // 为每个 DictGroup 设置子分组和单词书
        for (DictGroup dictGroup : dictGroups) {
            List<DictGroup> childGroups = childGroupsByParentId.getOrDefault(dictGroup.getId(), new ArrayList<>());
            dictGroup.setDictGroups(childGroups);
            
            List<Dict> dicts = dictsByGroupId.getOrDefault(dictGroup.getId(), new ArrayList<>());
            dictGroup.setDicts(dicts);
        }

        // 递归加载所有子分组的集合
        if (!allChildGroups.isEmpty()) {
            loadDictGroupsAndDictsForDictGroups(allChildGroups);
        }
    }
}
