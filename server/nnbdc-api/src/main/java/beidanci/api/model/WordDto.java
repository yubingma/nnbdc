package beidanci.api.model;

import beidanci.util.Utils;

public class WordDto extends Dto implements Ownerable {
    @Override
    public String getOwnerId() {
        return beidanci.util.Constants.SYS_USER_SYS_ID;
    }

    private String id;
    private String spell;
    private String britishPronounce;
    private String americaPronounce;
    private String pronounce;
    private Integer popularity;
    private String groupInfo;
    private String shortDesc;
    private String longDesc;
    private Float vecX;
    private Float vecY;
    private Float vecZ;

    public WordDto() {

    }

    public WordDto(String spell) {
        this.spell = spell;

    }

    public String getId() {
        return id;
    }

    public void setId(String id) {
        this.id = id;
    }

    public boolean isPhrase() {
        return spell.trim().contains(" ");
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

    /*
     * public List<SynonymsItem> getSynonymsItems() {
     * return synonymsItems;
     * }
     *
     * public void setSynonymsItems(List<SynonymsItem> synonymsItems) {
     * this.synonymsItems = synonymsItems;
     * }
     */

    public String getShortDesc() {
        return shortDesc;
    }

    public void setShortDesc(String shortDesc) {
        this.shortDesc = shortDesc;
    }

    public String getSound() {
        return Utils.getFileNameOfWordSound(spell);
    }

    public String getLongDesc() {
        return longDesc;
    }

    public void setLongDesc(String longDesc) {
        this.longDesc = longDesc;
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
