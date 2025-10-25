package beidanci.api.model;

public class BookMarkVo extends Vo{

    // 书签记录的单词位置（从0开始），并且这个位置是对所有单词而言（包括服务端的）
    private int position;

    // 书签记录的单词拼写
    private String spell;

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
}
