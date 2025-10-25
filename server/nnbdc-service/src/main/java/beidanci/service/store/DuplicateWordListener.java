package beidanci.service.store;

import beidanci.api.model.WordVo;

public interface DuplicateWordListener {
    public void onDuplicateWord(WordVo word);
}
