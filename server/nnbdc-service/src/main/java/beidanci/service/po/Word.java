package beidanci.service.po;

import java.util.LinkedList;
import java.util.List;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Index;
import javax.persistence.Table;

import beidanci.api.model.Ownerable;
import beidanci.util.Constants;

// JDBC 不再支持 Hibernate 缓存和 Fetch 注解
// import org.hibernate.annotations.Cache;
// import org.hibernate.annotations.CacheConcurrencyStrategy;
// import org.hibernate.annotations.Fetch;
// import org.hibernate.annotations.FetchMode;
import org.springframework.util.Assert;

import net.sf.json.JSONObject;
import net.sf.json.JsonConfig;

@Entity
@Table(name = "word", indexes = {@Index(name = "idx_wordspell", columnList = "spell", unique = true)})
// @Cache(region = "wordCache", usage = CacheConcurrencyStrategy.READ_WRITE)  // JDBC 不支持缓存
public class Word extends UuidPo implements Ownerable {

    @Override
    public String getOwnerId() {
        return Constants.SYS_USER_SYS_ID;
    }

    // serial marker removed; entities are not serialized via Java serialization

    @Column(name = "spell", length = 100)
    private String spell;

    @Column(name = "british_pronounce", length = 100)
    private String britishPronounce;

    @Column(name = "america_pronounce", length = 100)
    private String americaPronounce;

    @Column(name = "pronounce", length = 100)
    private String pronounce;

    @Column(name = "popularity", nullable = false)
    private Integer popularity;

    @Column(name = "group_info", length = 200)
    private String groupInfo;

    /**
     * 单词的简要描述
     */
    @Column(name = "short_desc", length = 500)
    private String shortDesc;

    /**
     * 单词的详细描述
     */
    @Column(name = "long_desc", length = 1000)
    private String longDesc;

    @Column(name = "is_updating", nullable = false)
    private Boolean isUpdating = false;

    @Column(name = "vec_x")
    private Float vecX;

    @Column(name = "vec_y")
    private Float vecY;

    @Column(name = "vec_z")
    private Float vecZ;

    private  List<MeaningItem> meaningItems;

    private  List<WordImage> images;

    private  List<WordShortDescChinese> wordShortDescChineses;

    private  List<VerbTense> verbTences;

    private  List<Word> similarWords;

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
        return spell != null && spell.trim().contains(" ");
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

    public Boolean getIsUpdating() {
        return isUpdating;
    }

    public void setIsUpdating(Boolean isUpdating) {
        this.isUpdating = isUpdating;
    }

    public Float getVecX() {
        return vecX;
    }

    public void setVecX(Float vecX) {
        this.vecX = vecX;
    }

    public Float getVecY() {
        return vecY;
    }

    public void setVecY(Float vecY) {
        this.vecY = vecY;
    }

    public Float getVecZ() {
        return vecZ;
    }

    public void setVecZ(Float vecZ) {
        this.vecZ = vecZ;
    }
}
