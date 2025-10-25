package beidanci.api.model;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.HashSet;
import java.util.LinkedList;
import java.util.List;
import java.util.Map;
import java.util.Set;

import org.apache.commons.lang3.StringUtils;

import beidanci.util.Utils;

public class WordVo extends UuidVo {

    private String spell;
    private String britishPronounce;
    private String americaPronounce;
    private String pronounce;
    private Integer popularity;
    private String groupInfo;
    private String shortDesc;
    private String longDesc;
    private String meaningStr;
    private List<MeaningItemVo> meaningItems;
    /* private List<SynonymsItem> synonymsItems; */
    private List<WordVo> similarWords;
    private List<CigenWordLinkVo> cigenWordLinks;
    private List<WordShortDescChineseVo> shortDescChineses;
    private List<WordImageVo> images;


    public WordVo() {

    }


    public WordVo(String spell) {
        this.spell = spell;

        meaningItems = new LinkedList<>();
    }

    @Override
    public String getId() {
        return id;
    }

    @Override
    public void setId(String id) {
        this.id = id;
    }

    public List<CigenWordLinkVo> getCigenWordLinks() {
        return cigenWordLinks;
    }

    public void setCigenWordLinks(List<CigenWordLinkVo> cigenWordLinks) {
        this.cigenWordLinks = cigenWordLinks;
    }

    public List<WordVo> getSimilarWords() {
        return similarWords;
    }

    public void setSimilarWords(List<WordVo> similarWords) {
        this.similarWords = similarWords;
    }

    public void addMeaningItem(MeaningItemVo meaningItem) {
        meaningItems.add(meaningItem);
    }

    public String getMeaningStr() {
        if (this.meaningStr != null) {
            return meaningStr;
        }

        if (meaningItems == null) {
            return null;
        }

        // 释义合并
        Map<String, List<MeaningItemVo>> meaningItemsByCixing = new HashMap<>(); // 用于把相同词性的释义收集在一起
        for (MeaningItemVo meaningItemVo : meaningItems) {
            String ciXing = meaningItemVo.getCiXing();
            ciXing = StringUtils.isEmpty(ciXing) ? "" : ciXing;
            List<MeaningItemVo> meaningItems_ = meaningItemsByCixing.get(ciXing);
            if (meaningItems_ == null) {
                meaningItems_ = new ArrayList<>();
                meaningItemsByCixing.put(ciXing, meaningItems_);
            }
            meaningItems_.add(meaningItemVo);
        }
        List<MeaningItemVo> mergedMeaningItems = new ArrayList<>();
        for (Map.Entry<String, List<MeaningItemVo>> entry : meaningItemsByCixing.entrySet()) {
            String ciXing = entry.getKey();
            Set<String> meanings = new HashSet<>();
            for (MeaningItemVo meaningItemVo : entry.getValue()) {
                String[] parts = meaningItemVo.getMeaning().split(";|；");
                meanings.addAll(Arrays.asList(parts));
            }
            StringBuilder sb = new StringBuilder();
            for (String meaning : meanings) {
                sb.append(meaning);
                sb.append("；");
            }
            MeaningItemVo meaningItemVo = new MeaningItemVo(ciXing, sb.toString());
            mergedMeaningItems.add(meaningItemVo);
        }


        StringBuilder sb = new StringBuilder();
        for (MeaningItemVo item : mergedMeaningItems) {
            sb.append(item.toString());
        }
        meaningStr = sb.toString();
        if (meaningStr.length() > 0) {
            meaningStr = meaningStr.substring(0, meaningStr.length() - 1); // 删除末尾的分号
        }
        return meaningStr;
    }

    public void setMeaningStr(String meaningStr) {
        this.meaningStr = meaningStr;
    }

    public boolean isPhrase() {
        return spell.trim().contains(" ");
    }

    public boolean wordHasMeaning() {
        return !getMeaningItems().isEmpty();
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

    public List<MeaningItemVo> getMeaningItems() {
        return meaningItems;
    }

    public void setMeaningItems(List<MeaningItemVo> meaningItems) {
        this.meaningItems = meaningItems;
    }

/*     public List<SynonymsItem> getSynonymsItems() {
        return synonymsItems;
    }

    public void setSynonymsItems(List<SynonymsItem> synonymsItems) {
        this.synonymsItems = synonymsItems;
    } */

    public String getShortDesc() {
        return shortDesc;
    }

    public void setShortDesc(String shortDesc) {
        this.shortDesc = shortDesc;
    }

    public String getSound() {
        return Utils.getFileNameOfWordSound(spell);
    }

    public List<WordShortDescChineseVo> getShortDescChineses() {
        return shortDescChineses;
    }

    public void setShortDescChineses(List<WordShortDescChineseVo> shortDescChineses) {
        this.shortDescChineses = shortDescChineses;
    }

    public String getLongDesc() {
        return longDesc;
    }

    public void setLongDesc(String longDesc) {
        this.longDesc = longDesc;
    }

    public List<WordImageVo> getImages() {
        return images;
    }

    public void setImages(List<WordImageVo> images) {
        this.images = images;
    }
}
