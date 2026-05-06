package beidanci.api.model;

import java.util.List;

public class DictGroupVo extends UuidVo {

    private String name;
    private String parentId;
    private Integer displayIndex;
    private List<DictVo> dicts;
    private DictGroupVo dictGroup;
    private List<DictVo> allDicts;

    public String getName() {
        return name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public String getParentId() {
        return parentId;
    }

    public void setParentId(String parentId) {
        this.parentId = parentId;
    }

    public Integer getDisplayIndex() {
        return displayIndex;
    }

    public void setDisplayIndex(Integer displayIndex) {
        this.displayIndex = displayIndex;
    }

    public List<DictVo> getDicts() {
        return dicts;
    }

    public void setDicts(List<DictVo> dicts) {
        this.dicts = dicts;
    }

    public DictGroupVo getDictGroup() {
        return dictGroup;
    }

    public void setDictGroup(DictGroupVo dictGroup) {
        this.dictGroup = dictGroup;
    }

    public List<DictVo> getAllDicts() {
        return allDicts;
    }

    public void setAllDicts(List<DictVo> allDicts) {
        this.allDicts = allDicts;
    }
}
