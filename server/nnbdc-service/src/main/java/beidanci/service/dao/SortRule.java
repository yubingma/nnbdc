
package beidanci.service.dao;

import java.util.ArrayList;
import java.util.List;

/**
 * 排序规则，用于指定对某个字段如何排序（升序还是降序）
 *
 * @author MaYubing
 */
public class SortRule {

    private String fieldName;

    private Boolean asc;

    public SortRule() {
    }

    public SortRule(String fieldName, boolean asc) {
        this.fieldName = fieldName;
        this.asc = asc;
    }

    public String getFieldName() {
        return fieldName;
    }

    public void setFieldName(String orderField) {
        this.fieldName = orderField;
    }

    @Override
    public int hashCode() {
        final int prime = 31;
        int result = 1;
        result = prime * result + ((fieldName == null) ? 0 : fieldName.hashCode());
        return result;
    }

    @Override
    public boolean equals(Object obj) {
        if (this == obj)
            return true;
        if (obj == null)
            return false;
        if (getClass() != obj.getClass())
            return false;
        SortRule other = (SortRule) obj;
        if (fieldName == null) {
            if (other.fieldName != null)
                return false;
        } else if (!fieldName.equals(other.fieldName))
            return false;
        return true;
    }

    public static List<SortRule> makeSortRules(String[] fields) {
        List<SortRule> sortRules = new ArrayList<>();

        for (String field : fields) {
            SortRule sortRule = makeSortRule(field);
            sortRules.add(sortRule);
        }

        return sortRules;
    }

    public static SortRule makeSortRule(String field) {
        SortRule sortRule = new SortRule();
        String[] parts = field.split(" ");
        assert (parts.length == 1 || parts.length == 2);
        String fieldName = parts[0];
        sortRule.setFieldName(fieldName);
        if (parts.length == 1) {
            sortRule.setAsc(true);
        } else {
            String order = parts[1];
            assert (order.equals("asc") || order.equals("desc"));
            sortRule.setAsc(order.equalsIgnoreCase("asc"));
        }
        return sortRule;
    }

    public Boolean getAsc() {
        return asc;
    }

    public void setAsc(Boolean asc) {
        this.asc = asc;
    }

}
