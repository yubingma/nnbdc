package beidanci.service.po;

import javax.persistence.Column;
import javax.persistence.Entity;
import javax.persistence.Table;

@Entity
@Table(name = "word_embedding")
public class WordEmbedding extends UuidPo {

    @Column(name = "embedding", nullable = false)
    private byte[] embedding;

    @Column(name = "dimension", nullable = false)
    private Integer dimension;

    @Column(name = "model_name", nullable = false, length = 100)
    private String modelName;

    public WordEmbedding() {
    }

    public WordEmbedding(String wordId, byte[] embedding, Integer dimension, String modelName) {
        this.id = wordId;
        this.embedding = embedding;
        this.dimension = dimension;
        this.modelName = modelName;
    }

    public byte[] getEmbedding() {
        return embedding;
    }

    public void setEmbedding(byte[] embedding) {
        this.embedding = embedding;
    }

    public Integer getDimension() {
        return dimension;
    }

    public void setDimension(Integer dimension) {
        this.dimension = dimension;
    }

    public String getModelName() {
        return modelName;
    }

    public void setModelName(String modelName) {
        this.modelName = modelName;
    }
}
