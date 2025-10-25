package beidanci.service.po;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Id;
import javax.persistence.Table;

import org.hibernate.annotations.Cache;
import org.hibernate.annotations.CacheConcurrencyStrategy;

@Entity
@Table(name = "sys_param")
@Cache(region = "sysParamCache", usage = CacheConcurrencyStrategy.READ_WRITE)
public class SysParam extends Po {

    public static final String COW_DUNG_PER_GAME = "CowDungPerGame";
    // Fields

    @Id
    @Column(name = "paramName", length = 100)
    private String paramName;

    @Column(name = "paramValue", length = 4096)
    private String paramValue;

    @Column(name = "comment", length = 4096)
    private String comment;

    // Constructors

    /**
     * default constructor
     */
    public SysParam() {
    }

    /**
     * minimal constructor
     */
    public SysParam(String paramName, String paramValue) {
        this.paramName = paramName;
        this.paramValue = paramValue;
    }

    /**
     * full constructor
     */
    public SysParam(String paramName, String paramValue, String comment) {
        this.paramName = paramName;
        this.paramValue = paramValue;
        this.comment = comment;
    }

    // Property accessors

    public String getParamName() {
        return this.paramName;
    }

    public void setParamName(String paramName) {
        this.paramName = paramName;
    }

    public String getParamValue() {
        return this.paramValue;
    }

    public void setParamValue(String paramValue) {
        this.paramValue = paramValue;
    }

    public String getComment() {
        return this.comment;
    }

    public void setComment(String comment) {
        this.comment = comment;
    }


}
