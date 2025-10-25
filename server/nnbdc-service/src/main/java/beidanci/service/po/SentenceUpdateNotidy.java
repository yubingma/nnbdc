package beidanci.service.po;

import javax.persistence.Entity;
import javax.persistence.JoinColumn;
import javax.persistence.ManyToOne;
import javax.persistence.Table;

/**
 * 例句变更通知表，最新修改的例句id将被插入此表（ttsSentences.sh 生成tts语音后，插入变更通知），sentence store将会读此表，做相应处理后，清除响应通知
 */
@Entity
@Table(name = "sentence_update_notify")
public class SentenceUpdateNotidy extends UuidPo {

    @ManyToOne
    @JoinColumn(name = "sentenceId", nullable = false)
    private Sentence sentence;

    public Sentence getSentence() {
        return sentence;
    }

    public void setSentence(Sentence sentence) {
        this.sentence = sentence;
    }
}
