package beidanci.service.po;

import javax.persistence.*;
import java.util.Set;

@Entity
@Table(name = "cigen")
public class Cigen extends UuidPo {



    @Column(name = "description", length = 1024, nullable = false)
    private String description;

    @OneToMany(cascade = {CascadeType.PERSIST, CascadeType.REMOVE,
            CascadeType.MERGE}, mappedBy = "cigen", fetch = FetchType.LAZY)
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

    public Set<CigenWordLink> getCigenWordLinks() {
        return cigenWordLinks;
    }

    public void setCigenWordLinks(Set<CigenWordLink> cigenWordLinks) {
        this.cigenWordLinks = cigenWordLinks;
    }

}
