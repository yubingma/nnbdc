
package beidanci.api.model;

import java.util.ArrayList;
import java.util.List;

/**
 * 分页数据的包装类，里面包含了一页的数据记录
 *
 * @param <E>
 * @author MaYubing
 */
public class PagedResults<E> {

    /**
     * 记录总数（所有数据页的记录总数，而不是当前页的记录数）
     */
    private Integer total;

    /**
     * 当前页的记录
     */
    private List<E> rows = new ArrayList<>();

    public PagedResults() {
    }

    public PagedResults(Integer total, List<E> rows) {
        this.total = total;
        this.rows = rows;
    }

    public Integer getTotal() {
        return total;
    }

    public void setTotal(Integer total) {
        this.total = total;
    }

    public List<E> getRows() {
        return rows;
    }

    public void setRows(List<E> rows) {
        this.rows = rows;
    }

}
