package beidanci.service.po;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Id;
import javax.persistence.JoinColumn;
import javax.persistence.ManyToOne;
import javax.persistence.Table;

@Entity
@Table(name = "daka")
public class Daka extends Po {

    @Id
    private DakaId id;

    @ManyToOne
    @JoinColumn(name = "userId", nullable = false, updatable = false, insertable = false)
    private User user;

    @Column(name = "text", length = 4000)
    private String text;

    // Constructors

    /**
     * default constructor
     */
    public Daka() {
    }

    /**
     * full constructor
     */
    public Daka(DakaId id, User user, String text) {
        this.id = id;
        this.user = user;
        this.text = text;
    }


    public DakaId getId() {
        return this.id;
    }

    public void setId(DakaId id) {
        this.id = id;
    }

    public User getUser() {
        return this.user;
    }

    public void setUser(User user) {
        this.user = user;
    }

    public String getText() {
        return this.text;
    }

    public void setText(String text) {
        this.text = text;
    }

}
