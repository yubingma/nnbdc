package beidanci.api.model;

public class CigenVo extends UuidVo {


    private String description;


    // Constructors

    /**
     * default constructor
     */
    public CigenVo() {
    }

    /**
     * minimal constructor
     */
    public CigenVo(String id, String description) {
        this.id = id;
        this.description = description;
    }

    public String getDescription() {
        return this.description;
    }

    public void setDescription(String description) {
        this.description = description;
    }


}
