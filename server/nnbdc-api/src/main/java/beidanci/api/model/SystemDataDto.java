package beidanci.api.model;

import java.util.List;

public class SystemDataDto {
    private long version;
    private List<LevelDto> levels;
    private List<DictGroupDto> dictGroups;
    private List<GroupAndDictLinkDto> groupAndDictLinks;
    private List<DictDto> dicts;
    // 可以添加其他系统数据

    public long getVersion() {
        return version;
    }

    public void setVersion(long version) {
        this.version = version;
    }

    public List<LevelDto> getLevels() {
        return levels;
    }

    public void setLevels(List<LevelDto> levels) {
        this.levels = levels;
    }

    public List<DictGroupDto> getDictGroups() {
        return dictGroups;
    }

    public void setDictGroups(List<DictGroupDto> dictGroups) {
        this.dictGroups = dictGroups;
    }

    public List<GroupAndDictLinkDto> getGroupAndDictLinks() {
        return groupAndDictLinks;
    }

    public void setGroupAndDictLinks(List<GroupAndDictLinkDto> groupAndDictLinks) {
        this.groupAndDictLinks = groupAndDictLinks;
    }

    public List<DictDto> getDicts() {
        return dicts;
    }

    public void setDicts(List<DictDto> dicts) {
        this.dicts = dicts;
    }
}
