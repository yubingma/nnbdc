package beidanci.service.po;

import java.util.Objects;

import javax.persistence.Column;
import javax.persistence.Embeddable;

@Embeddable
public class BookMarkId implements java.io.Serializable {

    private static final long serialVersionUID = 1L;



    @Column(name = "userId", nullable = false)
    private String userId;

    @Column(name = "bookMarkName", nullable = false)
    private String bookMarkName;

    public BookMarkId() {
    }

    public BookMarkId(String userId, String bookMarkName) {
        this.userId = userId;
        this.bookMarkName = bookMarkName;
    }

    @Override
    public boolean equals(Object o) {
        if (this == o) return true;
        if (o == null || getClass() != o.getClass()) return false;
        BookMarkId that = (BookMarkId) o;
        return Objects.equals(userId, that.userId) && Objects.equals(bookMarkName, that.bookMarkName);
    }

    @Override
    public int hashCode() {
        return Objects.hash(userId, bookMarkName);
    }
}
