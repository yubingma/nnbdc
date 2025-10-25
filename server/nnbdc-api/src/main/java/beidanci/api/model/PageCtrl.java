package beidanci.api.model;

/**
 * 分页控制对象
 *
 * @author Administrator
 */
public class PageCtrl {
    /**
     * 记录总数
     */
    private int totalRecordCount;
    /**
     * 每页记录数
     */
    private int pageSize;

    /**
     * 当前页序号（从1开始）
     */
    private long currPageNo;

    public int getTotalRecordCount() {
        return totalRecordCount;
    }

    public void setTotalRecordCount(int totalRecordCount) {
        this.totalRecordCount = totalRecordCount;
    }

    public int getPageSize() {
        return pageSize;
    }

    public void setPageSize(int pageSize) {
        this.pageSize = pageSize;
    }

    public int getPageCount() {
        return (int) Math.round(Math.ceil((totalRecordCount + 0.0) / pageSize));
    }

    public long getCurrPageNo() {
        return currPageNo;
    }

    public void setCurrPageNo(long currPageNo) {
        this.currPageNo = currPageNo;
    }
}
