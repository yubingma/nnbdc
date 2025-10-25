package beidanci.service.po;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Id;
import javax.persistence.Index;
import javax.persistence.Table;

import beidanci.api.model.BookMarkDto;

@Entity
@Table(name = "book_mark", indexes = {@Index(columnList = "userId")})
public class BookMark extends Po {

    // no Java serialization

    @Id
    private BookMarkId id;

    // 书签记录的单词位置（从0开始），并且这个位置是对所有单词而言（包括服务端的）
    @Column(name = "position", nullable = false)
    private int position;

    // 书签记录的单词拼写
    @Column(name = "spell", length = 100, nullable = false)
    private String spell;

    public BookMark() {
    }

    public BookMark(BookMarkId id) {
        this.id = id;
    }

    public BookMarkId getId() {
        return id;
    }

    public void setId(BookMarkId id) {
        this.id = id;
    }

    public int getPosition() {
        return position;
    }

    public void setPosition(int position) {
        this.position = position;
    }

    public String getSpell() {
        return spell;
    }

    public void setSpell(String spell) {
        this.spell = spell;
    }

    /**
     * 从DTO转换为实体对象
     */
    public static BookMark fromDto(BookMarkDto dto) {
        BookMarkId id = new BookMarkId(dto.getUserId(), dto.getBookMarkName());
        BookMark bookMark = new BookMark(id);
        bookMark.setPosition(dto.getPosition());
        bookMark.setSpell(dto.getSpell());
        return bookMark;
    }
}
