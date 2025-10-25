package beidanci.api;

import java.util.ArrayList;
import java.util.List;

public class PageVo<T> {
    // 总条数
    private long totalCount = 0;
    // 总页数
    private int totalPage = 0;
    // 当前页
    private int pageNumber = 1;
    // 每页条数
    private int pageSize = 10;
    // 数据集
    private List<T> dataList = new ArrayList<>(0);

    public PageVo(List<T> dataList, int pageNumber, int pageSize, long totalCount,  int totalPage) {
        this.totalCount = totalCount;
        this.totalPage = totalPage;
        this.pageNumber = pageNumber;
        this.pageSize = pageSize;
        this.dataList = dataList;
    }

    public long getTotalCount() {
        return /*totalCount == 0 ? 1 : */totalCount;
    }

    public void setTotalCount(long totalCount) {
        this.totalCount = totalCount;
    }

    public int getTotalPage() {
        return totalPage;
    }

    public void setTotalPage(int totalPage) {
        this.totalPage = totalPage;
    }

    public int getPageNumber() {
        return pageNumber;
    }

    public void setPageNumber(int pageNumber) {
        this.pageNumber = pageNumber;
    }

    public int getPageSize() {
        return pageSize;
    }

    public void setPageSize(int pageSize) {
        this.pageSize = pageSize;
    }

    public List<T> getDataList() {
        return dataList;
    }

    public void setDataList(List<T> dataList) {
        this.dataList = dataList;
    }
}
