package beidanci.service.po;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Table;

/**
 * 用户等级表
 */
@Entity
@Table(name = "level")
public class Level extends UuidPo {

    @Column(name = "level")
    private Integer level;

    @Column(name = "name", length = 45, nullable = false)
    private String name;

    @Column(name = "figure", length = 200)
    private String figure;

    @Column(name = "minScore", nullable = false)
    private Integer minScore;

    @Column(name = "maxScore", nullable = false)
    private Integer maxScore;

    @Column(name = "style", length = 1024, nullable = false)
    private String style;

    // Constructors

    /**
     * default constructor
     */
    public Level() {
    }

    // Property accessors

    public Integer getLevel() {
        return this.level;
    }

    public void setLevel(Integer level) {
        this.level = level;
    }

    public String getName() {
        return this.name;
    }

    public void setName(String name) {
        this.name = name;
    }

    public String getFigure() {
        return this.figure;
    }

    public void setFigure(String figure) {
        this.figure = figure;
    }

    public Integer getMinScore() {
        return this.minScore;
    }

    public void setMinScore(Integer minScore) {
        this.minScore = minScore;
    }

    public Integer getMaxScore() {
        return this.maxScore;
    }

    public void setMaxScore(Integer maxScore) {
        this.maxScore = maxScore;
    }

    public String getStyle() {
        return style;
    }

    public void setStyle(String style) {
        this.style = style;
    }

}
