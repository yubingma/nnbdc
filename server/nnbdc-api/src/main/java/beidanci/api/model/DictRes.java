package beidanci.api.model;

import java.util.List;

/** 单词书资源，包含单词、音标、释义，例句 */
public class DictRes {
    /**
     * 词书记录，对于通用词典，此对象为null
     */
    DictDto dict;

    List<DictWordDto> dictWords;
    List<WordDto> words;
    List<MeaningItemDto> meaningItems;
    List<SimilarWordDto> similarWords;
    List<SynonymDto> synonyms;
    List<SentenceDto> sentences;
    List<WordImageDto> images;
    List<WordCoreImageDto> wordCoreImages;
    List<CigenDto> cigens;
    List<CigenWordLinkDto> cigenWordLinks;

    public DictRes() {
    }

    public DictRes(DictDto dict, List<DictWordDto> dictWords, List<WordDto> words, List<MeaningItemDto> meaningItems,
            List<SimilarWordDto> similarWords,
            List<SynonymDto> synonyms, List<SentenceDto> sentences, List<WordImageDto> images) {
        this(dict, dictWords, words, meaningItems, similarWords, synonyms, sentences, images, null, null, null);
    }

    public DictRes(DictDto dict, List<DictWordDto> dictWords, List<WordDto> words, List<MeaningItemDto> meaningItems,
            List<SimilarWordDto> similarWords,
            List<SynonymDto> synonyms, List<SentenceDto> sentences, List<WordImageDto> images,
            List<WordCoreImageDto> wordCoreImages) {
        this(dict, dictWords, words, meaningItems, similarWords, synonyms, sentences, images, wordCoreImages, null, null);
    }

    public DictRes(DictDto dict, List<DictWordDto> dictWords, List<WordDto> words, List<MeaningItemDto> meaningItems,
            List<SimilarWordDto> similarWords,
            List<SynonymDto> synonyms, List<SentenceDto> sentences, List<WordImageDto> images,
            List<WordCoreImageDto> wordCoreImages, List<CigenDto> cigens, List<CigenWordLinkDto> cigenWordLinks) {
        this.dict = dict;
        this.dictWords = dictWords;
        this.words = words;
        this.meaningItems = meaningItems;
        this.similarWords = similarWords;
        this.synonyms = synonyms;
        this.sentences = sentences;
        this.images = images;
        this.wordCoreImages = wordCoreImages;
        this.cigens = cigens;
        this.cigenWordLinks = cigenWordLinks;
    }

    public List<SentenceDto> getSentences() {
        return sentences;
    }

    public void setSentences(List<SentenceDto> sentences) {
        this.sentences = sentences;
    }

    public DictDto getDict() {
        return dict;
    }

    public void setDict(DictDto dict) {
        this.dict = dict;
    }

    public List<DictWordDto> getDictWords() {
        return dictWords;
    }

    public void setDictWords(List<DictWordDto> dictWords) {
        this.dictWords = dictWords;
    }

    public List<WordDto> getWords() {
        return words;
    }

    public void setWords(List<WordDto> words) {
        this.words = words;
    }

    public List<MeaningItemDto> getMeaningItems() {
        return meaningItems;
    }

    public void setMeaningItems(List<MeaningItemDto> meaningItems) {
        this.meaningItems = meaningItems;
    }

    public List<SimilarWordDto> getSimilarWords() {
        return similarWords;
    }

    public void setSimilarWords(List<SimilarWordDto> similarWords) {
        this.similarWords = similarWords;
    }

    public List<SynonymDto> getSynonyms() {
        return synonyms;
    }

    public void setSynonyms(List<SynonymDto> synonyms) {
        this.synonyms = synonyms;
    }

    public List<WordImageDto> getImages() {
        return images;
    }

    public void setImages(List<WordImageDto> images) {
        this.images = images;
    }

    public List<WordCoreImageDto> getWordCoreImages() {
        return wordCoreImages;
    }

    public void setWordCoreImages(List<WordCoreImageDto> wordCoreImages) {
        this.wordCoreImages = wordCoreImages;
    }

    public List<CigenDto> getCigens() {
        return cigens;
    }

    public void setCigens(List<CigenDto> cigens) {
        this.cigens = cigens;
    }

    public List<CigenWordLinkDto> getCigenWordLinks() {
        return cigenWordLinks;
    }

    public void setCigenWordLinks(List<CigenWordLinkDto> cigenWordLinks) {
        this.cigenWordLinks = cigenWordLinks;
    }
}
