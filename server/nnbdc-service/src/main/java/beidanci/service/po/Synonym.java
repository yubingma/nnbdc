package beidanci.service.po;

import beidanci.service.Global;
import org.hibernate.annotations.Cache;
import org.hibernate.annotations.CacheConcurrencyStrategy;

import javax.persistence.*;

/**
 * 某个单词释义的一个同义词
 *
 * @author MaYubing
 */
@Entity
@Table(name = "synonym")
@Cache(region = "wordCache", usage = CacheConcurrencyStrategy.READ_WRITE)
public class Synonym extends Po {
    /**
     *
     */

    @Id
    private SynonymId id;

    @ManyToOne
    @JoinColumn(name = "meaningItemId", nullable = false, updatable = false, insertable = false)
    private MeaningItem meaningItem;

    public String getWordId() {
        return id.getWordId();
    }


    public SynonymId getId() {
        return id;
    }

    public void setId(SynonymId id) {
        this.id = id;
    }

    public MeaningItem getMeaningItem() {
        return meaningItem;
    }

    public void setMeaningItem(MeaningItem meaningItem) {
        this.meaningItem = meaningItem;
    }

    public String getSpell() {
        return Global.getWordBo().findById(id.getWordId()).getSpell();
    }
}
