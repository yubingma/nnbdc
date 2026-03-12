package beidanci.service.po;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Table;

/**
 * 单词导入任务实体
 */
@Entity
@Table(name = "import_task")
public class ImportTask extends UuidPo {

    @Column(name = "status", length = 20, nullable = false)
    private String status;

    @Column(name = "total_words", nullable = false)
    private Integer totalWords = 0;

    @Column(name = "processed_words", nullable = false)
    private Integer processedWords = 0;

    @Column(name = "log", columnDefinition = "TEXT")
    private String log;

    @Column(name = "config", columnDefinition = "TEXT")
    private String config;

    @Column(name = "file_name", length = 200)
    private String fileName;

    @Column(name = "owner_id")
    private User owner;

    public ImportTask() {
    }

    public String getStatus() {
        return status;
    }

    public void setStatus(String status) {
        this.status = status;
    }

    public Integer getTotalWords() {
        return totalWords;
    }

    public void setTotalWords(Integer totalWords) {
        this.totalWords = totalWords;
    }

    public Integer getProcessedWords() {
        return processedWords;
    }

    public void setProcessedWords(Integer processedWords) {
        this.processedWords = processedWords;
    }

    public String getLog() {
        return log;
    }

    public void setLog(String log) {
        this.log = log;
    }

    public String getConfig() {
        return config;
    }

    public void setConfig(String config) {
        this.config = config;
    }

    public String getFileName() {
        return fileName;
    }

    public void setFileName(String fileName) {
        this.fileName = fileName;
    }

    public User getOwner() {
        return owner;
    }

    public void setOwner(User owner) {
        this.owner = owner;
    }
}
