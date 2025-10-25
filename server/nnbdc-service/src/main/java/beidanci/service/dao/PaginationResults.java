
package beidanci.service.dao;

import java.util.ArrayList;
import java.util.List;

/**
 * @author Yongrui Wang
 */
// Object for pagination
public class PaginationResults<E> {

    private Integer total;

    private List<E> rows = new ArrayList<>();

    /**
     * @return the total
     */
    public Integer getTotal() {
        return total;
    }

    /**
     * @param total the total to set
     */
    public void setTotal(Integer total) {
        this.total = total;
    }

    /**
     * @return the results
     */
    public List<E> getRows() {
        return rows;
    }

    /**
     * @param rows the results to set
     */
    public void setRows(List<E> rows) {
        this.rows = rows;
    }

}
