package beidanci.service.po;

import java.util.List;
import java.util.Objects;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Index;
import javax.persistence.Table;

import beidanci.api.model.Ownerable;

/**
 * 单词书
 *
 * @author Administrator
 */
@Entity
@Table(name = "dict", indexes = {@Index(name = "idx_dictname", columnList = "name", unique = true)})
public class Dict extends UuidPo implements Ownerable {

    @Column(name = "name", nullable = false, length = 50)
    private String name;

    @Column(name = "owner_id")
    private User owner;

    @Override
    public String getOwnerId() {
        return owner != null ? owner.getId() : null;
    }

    /**
     * 对于用户自定义的单词书，该标志指明该单词书是否已经共享给其他用户
     */
    @Column(name = "is_shared", nullable = false)
    private Boolean isShared;

    /**
     * 该单词书是否已经准备就绪（只有准备就绪的单词书才能供用户使用，并且一旦就绪后就不能再编辑）
     */
    @Column(name = "is_ready", nullable = false)
    private Boolean isReady;

    private  List<DictWord> dictWords;

    /**
     * 该单词书的单词数量
     */
    @Column(name = "word_count", nullable = false)
    private Integer wordCount;

    public Boolean getVisible() {
        return visible;
    }

    public void setVisible(Boolean visible) {
        this.visible = visible;
    }

    /**
     * 该单词书是否可见（用于屏蔽一些老的词书）
     */
    @Column(name = "visible", nullable = false)
    private Boolean visible;

    /**
     * 专业领域，值为导入时用户提供的输入
     */
    @Column(name = "domain", nullable = true, length = 100)
    private String domain;

    /**
     * 过滤展示给用户的单词释义，如果某个单词没有该dict的定制释义，从而只能使用通用词典释义时，
     * popularity大于该设定的通用词典释义项(不太常用的释义项)会被用户隐藏，避免释义项过多。
     * 如果为null，表示不限制。
     */
    @Column(name = "popularity_limit", nullable = true)
    private Integer popularityLimit;

    /**
     * 是否允许用户对词书中的单词进行增删改（生词本、已掌握和用户自定义词书为 true）
     */
    @Column(name = "editable", nullable = false)
    private Boolean editable = false;

    /**
     * 是否允许用户删除词书本身（系统词书、生词本、已掌握 不可删除）
     */
    @Column(name = "deletable", nullable = false)
    private Boolean deletable = true;

    /**
	 * 对于衍生版词书（例如乱序版词书），指向其基础版词书的ID
	 */
	@Column(name = "base_dict_id", length = 50)
	private String baseDictId;

    /**
     * 排序算法, 目前仅支持 md5
     */
    @Column(name = "sort_alg", nullable = true, length = 50)
    private String sortAlg;

    @Column(name = "description", nullable = true, length = 1000)
    private String description;

    public Integer getPopularityLimit() {
        return popularityLimit;
    }

    public void setPopularityLimit(Integer popularityLimit) {
        this.popularityLimit = popularityLimit;
    }

    public String getDomain() {
        return domain;
    }

    public void setDomain(String domain) {
        this.domain = domain;
    }

    public Boolean getEditable() {
        return editable;
    }

    public void setEditable(Boolean editable) {
        this.editable = editable;
    }

    	public String getBaseDictId() {
		return baseDictId;
	}

	public void setBaseDictId(String baseDictId) {
		this.baseDictId = baseDictId;
	}
    public String getSortAlg() {
        return sortAlg;
    }

    public void setSortAlg(String sortAlg) {
        this.sortAlg = sortAlg;
    }

    public String getDescription() {
        return description;
    }

    public void setDescription(String description) {
        this.description = description;
    }

    public Boolean getDeletable() {
        return deletable;
    }

    public void setDeletable(Boolean deletable) {
        this.deletable = deletable;
    }

    public List<DictWord> getDictWords() {
        return dictWords;
    }

    public void setDictWords(List<DictWord> dictWords) {
        this.dictWords = dictWords;
    }

    /**
     * default constructor
     */
    public Dict() {
    }

    /**
     * minimal constructor
     */
    public Dict(String name) {
        this.name = name;
    }

    // Property accessors

    public String getName() {
        return this.name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public Integer getWordCount() {
        return wordCount;
    }

    public void setWordCount(Integer wordCount) {
        this.wordCount = wordCount;
    }

    public String getShortName() {
        if (name == null) {
            return null;
        }
        final int dotPos = name.lastIndexOf(".");
        return dotPos == -1 ? name : name.substring(0, dotPos);
    }

    public User getOwner() {
        return owner;
    }

    public void setOwner(User owner) {
        this.owner = owner;
    }

    public Boolean getIsReady() {
        return isReady;
    }

    public void setIsReady(Boolean isReady) {
        this.isReady = isReady;
    }

    public Boolean getIsShared() {
        return isShared;
    }

    public void setIsShared(Boolean isShared) {
        this.isShared = isShared;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        Dict dict = (Dict) o;
        return id.equals(dict.id);
    }

    @Override
    public int hashCode() {
        return Objects.hash(id);
    }


}
