package beidanci.api.model;

/**
 * 分页后一页的数据
 *
 * @author Administrator
 */
public class PagedData<T> {
    private PageCtrl pageCtrl;
    private T[] data;

    public PageCtrl getPageCtrl() {
        return pageCtrl;
    }

    public void setPageCtrl(PageCtrl pageCtrl) {
        this.pageCtrl = pageCtrl;
    }

    public T[] getData() {
        return data;
    }

    public void setData(T[] data) {
        this.data = data;
    }
}
