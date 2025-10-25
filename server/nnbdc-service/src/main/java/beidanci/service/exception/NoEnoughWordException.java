package beidanci.service.exception;

public class NoEnoughWordException extends Exception {

    /**
     *
     */

    public Integer[] getTodayWords() {
        return todayWords;
    }

    /**
     * 今日学习单词数量，含两个元素。0-新词数 1-旧词数
     */
    private final Integer[] todayWords;

    public NoEnoughWordException(String message, Integer[] todayWords) {
        super(message);
        this.todayWords = todayWords;
    }


}
