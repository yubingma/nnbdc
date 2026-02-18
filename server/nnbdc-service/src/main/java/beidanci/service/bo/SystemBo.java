package beidanci.service.bo;

import java.util.ArrayList;
import java.util.List;

import javax.persistence.EntityManager;
import javax.persistence.PersistenceContext;

import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Service;

import beidanci.api.model.DictDto;
import beidanci.api.model.DictGroupDto;
import beidanci.api.model.GroupAndDictLinkDto;
import beidanci.api.model.SystemDataDto;
import beidanci.service.po.Dict;
import beidanci.service.po.DictGroup;
import beidanci.util.Constants;

@Service
public class SystemBo {

    @Autowired
    private DictGroupBo dictGroupBo;

    @PersistenceContext
    private EntityManager entityManager;

    @Autowired
    private DictBo dictBo;

    @Autowired
    private SysDbSyncBo sysDbLogBo;

    public SystemDataDto getSystemData() {
        System.out.println("开始获取系统数据...");
        SystemDataDto systemData = new SystemDataDto();

        // 使用统一的系统数据版本号
        systemData.setVersion(sysDbLogBo.getSysDbVersion());

        // 获取单词书分组数据
        List<DictGroup> dictGroups = dictGroupBo.getAllDictGroups();
        List<DictGroupDto> dictGroupDtos = new ArrayList<>();
        for (DictGroup dictGroup : dictGroups) {
            DictGroupDto dictGroupDto = new DictGroupDto();
            dictGroupDto.setId(dictGroup.getId());
            dictGroupDto.setName(dictGroup.getName());
            dictGroupDto.setDisplayIndex(dictGroup.getDisplayIndex());
            if (dictGroup.getDictGroup() != null) {
                dictGroupDto.setParentId(dictGroup.getDictGroup().getId());
            }
            dictGroupDtos.add(dictGroupDto);
        }
        systemData.setDictGroups(dictGroupDtos);
        System.out.println("获取到单词书分组数据: " + dictGroupDtos.size() + "条");

        // 获取单词书分组与词书关联数据
        List<GroupAndDictLinkDto> groupAndDictLinkDtos = new ArrayList<>();
        String sql = "SELECT group_id, dict_id FROM group_and_dict_link";
        List<Object[]> results = entityManager.createNativeQuery(sql).getResultList();
        for (Object[] row : results) {
            GroupAndDictLinkDto linkDto = new GroupAndDictLinkDto();
            linkDto.setGroupId((String) row[0]);
            linkDto.setDictId((String) row[1]);
            groupAndDictLinkDtos.add(linkDto);
        }
        systemData.setGroupAndDictLinks(groupAndDictLinkDtos);
        System.out.println("获取到分组与词书关联数据: " + groupAndDictLinkDtos.size() + "条");

        // 获取字典数据 - 只获取owner ID为15118的词典
        System.out.println("开始查询系统词典，SYS_USER_SYS_ID = " + Constants.SYS_USER_SYS_ID);
        List<Dict> dicts = dictBo.getDictsByOwnerId(Constants.SYS_USER_SYS_ID, null);
        List<DictDto> dictDtos = new ArrayList<>();
        System.out.println("查询到系统词典数量: " + (dicts != null ? dicts.size() : "null"));

        if (dicts != null) {
            for (Dict dict : dicts) {
                DictDto dictDto = new DictDto();
                dictDto.setId(dict.getId());
                dictDto.setName(dict.getName());
                dictDto.setOwnerId(dict.getOwner().getId());
                dictDto.setIsShared(dict.getIsShared());
                dictDto.setIsReady(dict.getIsReady());
                dictDto.setVisible(dict.getVisible());
                dictDto.setWordCount(dict.getWordCount());
                dictDto.setCreateTime(dict.getCreateTime());
                dictDto.setUpdateTime(dict.getUpdateTime());
                dictDtos.add(dictDto);

            }
        }
        systemData.setDicts(dictDtos);

        return systemData;
    }
}
