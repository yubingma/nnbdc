package beidanci.service.po;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import javax.persistence.CascadeType;
import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.FetchType;
import javax.persistence.JoinColumn;
import javax.persistence.JoinTable;
import javax.persistence.ManyToMany;
import javax.persistence.ManyToOne;
import javax.persistence.OneToMany;
import javax.persistence.Table;

import org.hibernate.annotations.Fetch;
import org.hibernate.annotations.FetchMode;

@Entity
@Table(name = "dict_group")
public class DictGroup extends UuidPo {

    @Column(name = "name", length = 20)
    private String name;

    @ManyToOne
    @JoinColumn(name = "parentId")
    private DictGroup dictGroup;

    public Integer getDisplayIndex() {
        return displayIndex;
    }

    public void setDisplayIndex(Integer displayIndex) {
        this.displayIndex = displayIndex;
    }

    @Column(name = "displayIndex", nullable = false)
    private Integer displayIndex;

    @OneToMany(cascade = {CascadeType.PERSIST, CascadeType.REMOVE,
            CascadeType.MERGE}, mappedBy = "dictGroup", fetch = FetchType.LAZY)
    @Fetch(FetchMode.SUBSELECT)
    private List<DictGroup> dictGroups;

    @ManyToMany
    @JoinTable(name = "group_and_dict_link", joinColumns = {@JoinColumn(name = "groupId")}, inverseJoinColumns = {
            @JoinColumn(name = "dictId")})
    @Fetch(FetchMode.SUBSELECT)
    private List<Dict> dicts;

    @OneToMany(cascade = {CascadeType.PERSIST, CascadeType.REMOVE,
            CascadeType.MERGE}, mappedBy = "dictGroup", fetch = FetchType.LAZY)
    @Fetch(FetchMode.SUBSELECT)
    private Set<GameHall> gameHalls;

    // Constructors

    /**
     * default constructor
     */
    public DictGroup() {
    }

    /**
     * minimal constructor
     */
    public DictGroup(String name, DictGroup dictGroup, Integer displayIndex) {
        this.name = name;
        this.dictGroup = dictGroup;
        this.displayIndex = displayIndex;
    }

    /**
     * full constructor
     */
    public DictGroup(String name, DictGroup dictGroup, Integer displayIndex, List<DictGroup> dictGroups, List<Dict> dicts,
                     Set<GameHall> gameHalls) {
        this.name = name;
        this.dictGroup = dictGroup;
        this.displayIndex = displayIndex;
        this.dictGroups = dictGroups;
        this.dicts = dicts;
        this.gameHalls = gameHalls;
    }

    // Property accessors

    public String getName() {
        return this.name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public DictGroup getDictGroup() {
        return this.dictGroup;
    }

    public void setDictGroup(DictGroup dictGroup) {
        this.dictGroup = dictGroup;
    }

    public List<DictGroup> getDictGroups() {
        return this.dictGroups;
    }

    public void setDictGroups(List<DictGroup> dictGroups) {
        this.dictGroups = dictGroups;
    }

    public List<Dict> getDicts() {
        return dicts;
    }

    public void setDicts(List<Dict> dicts) {
        this.dicts = dicts;
    }

    public Set<GameHall> getGameHalls() {
        return this.gameHalls;
    }

    public void setGameHalls(Set<GameHall> gameHalls) {
        this.gameHalls = gameHalls;
    }

    /**
     * 获取群组之下的所有单词书，包括子孙群组之下的单词书
     *
     * @return
     */
    public List<Dict> getAllDicts() {
        Map<String, Dict> dictMap = new HashMap<>();

        // 加入子群组包含的单词书
        for (DictGroup childGroup : this.dictGroups) {
            // root群组的的父亲还是root，要避免无限递归
            if (childGroup.getName().equalsIgnoreCase("root")) {
                continue;
            }

            for (Dict dict : childGroup.getAllDicts()) {
                dictMap.put(dict.getName(), dict);
            }
        }

        // 加入直接包含的单词书
        for (Dict dict : this.dicts) {
            dictMap.put(dict.getName(), dict);
        }

        // 将单词书按字母顺序排序
        List<Dict> dicts2 = new ArrayList<>(dictMap.values());
        Collections.sort(dicts2, (Dict o1, Dict o2) -> o1.getName().compareTo(o2.getName()));

        return dicts2;
    }
}
