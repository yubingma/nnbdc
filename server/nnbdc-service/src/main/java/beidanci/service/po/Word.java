package beidanci.service.po;

import java.util.LinkedList;
import java.util.List;

import javax.persistence.CascadeType;
import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Index;
import javax.persistence.JoinColumn;
import javax.persistence.JoinTable;
import javax.persistence.ManyToMany;
import javax.persistence.OneToMany;
import javax.persistence.Table;

import org.hibernate.annotations.Cache;
import org.hibernate.annotations.CacheConcurrencyStrategy;
import org.hibernate.annotations.Fetch;
import org.hibernate.annotations.FetchMode;
import org.springframework.util.Assert;

import net.sf.json.JSONObject;
import net.sf.json.JsonConfig;

@Entity
@Table(name = "word", indexes = {@Index(name = "idx_wordspell", columnList = "spell", unique = true)})
@Cache(region = "wordCache", usage = CacheConcurrencyStrategy.READ_WRITE)
public class Word extends UuidPo {

    // serial marker removed; entities are not serialized via Java serialization

    @Column(name = "spell", length = 100)
    private String spell;

    @Column(name = "britishPronounce", length = 100)
    private String britishPronounce;

    @Column(name = "americaPronounce", length = 100)
    private String americaPronounce;

    @Column(name = "pronounce", length = 100)
    private String pronounce;

    @Column(name = "popularity", nullable = false)
    private Integer popularity;

    @Column(name = "groupInfo", length = 200)
    private String groupInfo;

    /**
     * 单词的简要描述
     */
    @Column(name = "shortDesc", length = 500)
    private String shortDesc;

    /**
     * 单词的详细描述
     */
    @Column(name = "longDesc", length = 1000)
    private String longDesc;

    @OneToMany(cascade = {CascadeType.PERSIST, CascadeType.REMOVE, CascadeType.MERGE}, mappedBy = "word")
    @Fetch(FetchMode.SUBSELECT)
    @Cache(region = "wordCache", usage = CacheConcurrencyStrategy.READ_WRITE)
    private  List<MeaningItem> meaningItems;

    @OneToMany(cascade = {CascadeType.ALL}, orphanRemoval = true, mappedBy = "word")
    @Fetch(FetchMode.SUBSELECT)
    @Cache(region = "wordCache", usage = CacheConcurrencyStrategy.READ_WRITE)
    private  List<WordImage> images;

    @OneToMany(cascade = {CascadeType.ALL}, orphanRemoval = true, mappedBy = "word")
    @Fetch(FetchMode.SUBSELECT)
    @Cache(region = "wordCache", usage = CacheConcurrencyStrategy.READ_WRITE)
    private  List<WordShortDescChinese> wordShortDescChineses;

    @OneToMany(cascade = {CascadeType.PERSIST, CascadeType.REMOVE, CascadeType.MERGE}, mappedBy = "word")
    @Fetch(FetchMode.SUBSELECT)
    @Cache(region = "wordCache", usage = CacheConcurrencyStrategy.READ_WRITE)
    private  List<VerbTense> verbTences;

    @ManyToMany
    @Fetch(FetchMode.SUBSELECT)
    @JoinTable(name = "similar_word", joinColumns = {@JoinColumn(name = "word")}, inverseJoinColumns = {
            @JoinColumn(name = "similarWord")})
    @Cache(region = "wordCache", usage = CacheConcurrencyStrategy.READ_WRITE)
    private  List<Word> similarWords;


    @OneToMany(cascade = {CascadeType.PERSIST, CascadeType.REMOVE, CascadeType.MERGE}, mappedBy = "word")
    @Fetch(FetchMode.SUBSELECT)
    @Cache(region = "wordCache", usage = CacheConcurrencyStrategy.READ_WRITE)
    private  List<CigenWordLink> cigenWordLinks;

    public List<VerbTense> getVerbTences() {
        return verbTences;
    }

    public void setVerbTences(List<VerbTense> verbTences) {
        this.verbTences = verbTences;
    }

    public Word() {

    }

    public Word(String spell) {
        Assert.isTrue(spell.length() == 32, "spell length must be 32");
        this.spell = spell;

        meaningItems = new LinkedList<>();
    }

    public List<WordImage> getImages() {
        return images;
    }

    public void setImages(List<WordImage> images) {
        this.images = images;
    }

    public void addMeaningItem(MeaningItem meaningItem) {
        meaningItems.add(meaningItem);
    }

    public String makeJSonForStore() {
        JsonConfig jsonConfig = new JsonConfig();
        jsonConfig.setExcludes(new String[]{"meaningStr", "phrase", "chinese", "english", "soundFileExists"});
        JSONObject jo = JSONObject.fromObject(this, jsonConfig);

        return jo.toString();
    }

    public String getMeaningStr() {
        if (meaningItems == null || meaningItems.isEmpty()) {
            return "";
        }
        StringBuilder sb = new StringBuilder();
        for (MeaningItem item : meaningItems) {
            sb.append(item.toString());
        }
        String str = sb.toString();
        if (str.length() > 0) {
            str = str.substring(0, str.length() - 1);
        }
        return str;
    }

    public boolean isPhrase() {
        return spell.trim().contains(" ");
    }

    public boolean wordHasMeaning() {
        return meaningItems != null && !meaningItems.isEmpty();
    }

    public String getSpell() {
        return spell;
    }

    public void setSpell(String spell) {
        this.spell = spell;
    }

    public String getBritishPronounce() {
        return britishPronounce;
    }

    public void setBritishPronounce(String britishPronounce) {
        this.britishPronounce = britishPronounce;
    }

    public String getAmericaPronounce() {
        return americaPronounce;
    }

    public void setAmericaPronounce(String americaPronounce) {
        this.americaPronounce = americaPronounce;
    }

    public String getPronounce() {
        return pronounce;
    }

    public void setPronounce(String pronounce) {
        this.pronounce = pronounce;
    }

    public Integer getPopularity() {
        return popularity;
    }

    public void setPopularity(Integer popularity) {
        this.popularity = popularity;
    }

    public String getGroupInfo() {
        return groupInfo;
    }

    public void setGroupInfo(String groupInfo) {
        this.groupInfo = groupInfo;
    }

    public List<MeaningItem> getMeaningItems() {
        if (this.meaningItems == null) {
            this.meaningItems = new LinkedList<>();
        }
        return this.meaningItems;
    }

    public void setMeaningItems(List<MeaningItem> meaningItems) {
        this.meaningItems = meaningItems;
    }


    public String getShortDesc() {
        return shortDesc;
    }

    public void setShortDesc(String shortDesc) {
        this.shortDesc = shortDesc;
    }

    public String getLongDesc() {
        return longDesc;
    }

    public void setLongDesc(String longDesc) {
        this.longDesc = longDesc;
    }

    @Override
    public boolean equals(Object obj) {
        if (!(obj instanceof Word)) {
            return false;
        }
        return this.getSpell().equals(((Word) obj).getSpell());
    }

    @Override
    public int hashCode() {
        return spell.hashCode();
    }

    public List<Word> getSimilarWords() {
        return similarWords;
    }

    public void setSimilarWords(List<Word> similarWords) {
        this.similarWords = similarWords;
    }

    public List<WordShortDescChinese> getWordShortDescChineses() {
        return wordShortDescChineses;
    }

    public void setWordShortDescChineses(List<WordShortDescChinese> wordShortDescChineses) {
        this.wordShortDescChineses = wordShortDescChineses;
    }

    public List<CigenWordLink> getCigenWordLinks() {
        return cigenWordLinks;
    }

    public void setCigenWordLinks(List<CigenWordLink> cigenWordLinks) {
        this.cigenWordLinks = cigenWordLinks;
    }
}
