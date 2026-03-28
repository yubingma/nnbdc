package beidanci.service.po;

import javax.persistence.*;
import java.util.Set;

@Entity
@Table(name = "cigen")
public class Cigen extends UuidPo {



    @Column(name = "description", length = 1024, nullable = false)
    private String description;

    @Column(name = "spell", length = 64)
    private String spell;

    @Column(name = "category", length = 20)
    private String category;

    @Column(name = "meaning_cn", length = 512)
    private String meaningCn;

    @Column(name = "meaning_en", length = 512)
    private String meaningEn;

    private Set<CigenWordLink> cigenWordLinks;

    // Constructors

    /**
     * default constructor
     */
    public Cigen() {
    }

    /**
     * minimal constructor
     */
    public Cigen(String id, String description) {
        this.id = id;
        this.description = description;
    }

    // Property accessors


    public String getDescription() {
        return this.description;
    }

    public void setDescription(String description) {
        this.description = description;
    }

    public String getSpell() {
        return spell;
    }

    public void setSpell(String spell) {
        this.spell = spell;
    }

    public String getCategory() {
        return category;
    }

    public void setCategory(String category) {
        this.category = category;
    }

    public String getMeaningCn() {
        return meaningCn;
    }

    public void setMeaningCn(String meaningCn) {
        this.meaningCn = meaningCn;
    }

    public String getMeaningEn() {
        return meaningEn;
    }

    public void setMeaningEn(String meaningEn) {
        this.meaningEn = meaningEn;
    }

    public Set<CigenWordLink> getCigenWordLinks() {
        return cigenWordLinks;
    }

    public void setCigenWordLinks(Set<CigenWordLink> cigenWordLinks) {
        this.cigenWordLinks = cigenWordLinks;
    }

}
