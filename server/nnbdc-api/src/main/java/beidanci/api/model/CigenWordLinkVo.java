package beidanci.api.model;

public class CigenWordLinkVo extends Vo  {

    private CigenVo cigen;

    private String theExplain;


    /**
     * default constructor
     */
    public CigenWordLinkVo() {
    }

    /**
     * full constructor
     */
    public CigenWordLinkVo(CigenVo cigen, String theExplain) {
        this.cigen = cigen;
        this.theExplain = theExplain;
    }

    public CigenVo getCigen() {
        return this.cigen;
    }

    public void setCigen(CigenVo cigen) {
        this.cigen = cigen;
    }

    public String getTheExplain() {
        return this.theExplain;
    }

    public void setTheExplain(String theExplain) {
        this.theExplain = theExplain;
    }

}
