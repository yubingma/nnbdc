package beidanci.service.po;

import java.util.List;
import java.util.Objects;

import javax.persistence.CascadeType;
import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.FetchType;
import javax.persistence.Index;
import javax.persistence.JoinColumn;
import javax.persistence.ManyToOne;
import javax.persistence.OneToMany;
import javax.persistence.Table;

/**
 * 单词书
 *
 * @author Administrator
 */
@Entity
@Table(name = "dict", indexes = {@Index(name = "idx_dictname", columnList = "name", unique = true)})
public class Dict extends UuidPo {

    @Column(name = "name", nullable = false, length = 50)
    private String name;

    @ManyToOne
    @JoinColumn(name = "ownerId", nullable = false)
    private User owner;

    /**
     * 对于用户自定义的单词书，该标志指明该单词书是否已经共享给其他用户
     */
    @Column(name = "isShared", nullable = false)
    private Boolean isShared;

    /**
     * 该单词书是否已经准备就绪（只有准备就绪的单词书才能供用户使用，并且一旦就绪后就不能再编辑）
     */
    @Column(name = "isReady", nullable = false)
    private Boolean isReady;

    @OneToMany(cascade = {CascadeType.PERSIST, CascadeType.REMOVE,
            CascadeType.MERGE}, mappedBy = "dict", fetch = FetchType.LAZY)
    private  List<DictWord> dictWords;

    /**
     * 该单词书的单词数量
     */
    @Column(name = "wordCount", nullable = false)
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
