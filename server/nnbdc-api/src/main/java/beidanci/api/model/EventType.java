package beidanci.api.model;

public enum EventType {
    NewWordImage("上传单词图片"), HandWordImage("赞单词图片"), FootWordImage("踩单词图片"), NewSentenceChinese(
            "添加例句翻译"), HandSentenceChinese("赞例句翻译"), HandSentenceEnglish("赞例句的英文"), FootSentenceChinese("踩例句翻译"),
    FootSentenceEnglsh("踩例句的英文"), NewWordShortDescChinese(
            "添加单词英文描述翻译"), HandWordShortDescChinese("赞单词英文描述翻译"), FootWordShortDescChinese("踩单词英文描述翻译");

    private String description;

    private EventType(String description) {
        this.description = description;
    }

    public String getDescription() {
        return description;
    }

    public void setDescription(String description) {
        this.description = description;
    }
}
