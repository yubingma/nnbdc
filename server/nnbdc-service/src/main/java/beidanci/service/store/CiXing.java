package beidanci.service.store;

import java.util.HashMap;
import java.util.Map;
import java.util.Map.Entry;

import beidanci.service.exception.InvalidWordTypeException;

public enum CiXing {

    abbr, // （介）介系词；前置词，preposition的缩写
    ad_prep_conj, // （代）代名词，pronoun的缩写
    adj, // （名）名词，noun的缩写
    adv, // （动）动词，兼指及物动词和不及物动词，verb的缩写
    art, // （连）连接词 ，conjunction的缩写
    aux, // （主）主词
    b, // 主词补语
    c, // 受词
    comb_form, // 受词补语
    conj, // 不及物动词，intransitive verb的缩写
    conj_prep, // 及物动词， transitive verb的缩写
    def, // （助）助动词 ，auxiliary的缩写
    det, // （形）形容词，adjective的缩写
    eg, // （副）副词，adverb的缩写
    esp, // （冠）冠词，article的缩写
    etc, // （数）数词，numeral的缩写
    ie, // （感）感叹词，interjection的缩写
    indef, // 不可数名词，uncountable noun的缩写
    inf, // 可数名词，countable noun的缩写
    int_, // 复数，plural的缩写
    n, // abbreviation（略）略语
    neg, // art definite article（定冠）定冠词
    none, // for example（例如）例如
    num, // especially（尤指）尤指
    o, // and the others（等）等等
    oc, // which is to say（意即）意即
    part_adj, // art indefinite article（不定冠词）不定冠词
    pers, // infinitive（不定词）不定词
    pers_pron, // negative(ly）（否定）否定的（地）
    ph, // participial adjective（分形）分词形容词
    pl, // person(人称）人称
    pp, // personal pronoun（人称代）人称代名词
    pref, // past participle （过去分词）过去分词
    prep, // prefix（字首）字首
    pron, // （代）代名词
    pron_pronoun, // past tense（过去）过去式
    pt, // somebody（某人）某人
    s, // singular（单）单数（的）
    sb, // something（某事物）某物或某事
    sc, // suffix（字尾）字尾
    sing, // America(n）（美）美国（的）
    sth, // Verb Pattern（动型）动词类型s
    suf, // 复合形
    u, US, v, // 固定词组
    v_aux, vb, // 助词
    vbl, vi, VP, vt;

    private static final Map<CiXing, String[]> ciXingMap = new HashMap<>();

    static {
        ciXingMap.put(adj, new String[]{"adj.", "a."});
        ciXingMap.put(adv, new String[]{"adv.", "ad."});
        ciXingMap.put(n, new String[]{"n."});
        ciXingMap.put(prep, new String[]{"prep."});
        ciXingMap.put(v, new String[]{"v."});
        ciXingMap.put(vi, new String[]{"vi."});
        ciXingMap.put(vt, new String[]{"vt."});
        ciXingMap.put(pron, new String[]{"pron."});
        ciXingMap.put(abbr, new String[]{"abbr."});
        ciXingMap.put(int_, new String[]{"int.", "interj."});
        ciXingMap.put(vbl, new String[]{"vbl."});
        ciXingMap.put(conj, new String[]{"conj."});
        ciXingMap.put(pl, new String[]{"pl."});
        ciXingMap.put(art, new String[]{"art."});
        ciXingMap.put(none, new String[]{"none."});
        ciXingMap.put(num, new String[]{"num."});
        ciXingMap.put(aux, new String[]{"aux."});
        ciXingMap.put(vb, new String[]{"vb."});
        ciXingMap.put(det, new String[]{"det."});
        ciXingMap.put(b, new String[]{"b."});
        ciXingMap.put(ph, new String[]{"ph."});
        ciXingMap.put(pref, new String[]{"pref."});
        ciXingMap.put(comb_form, new String[]{"comb.form"});
        ciXingMap.put(v_aux, new String[]{"v.aux."});
        ciXingMap.put(suf, new String[]{"suf."});
        ciXingMap.put(ad_prep_conj, new String[]{"ad.prep.conj."});
        ciXingMap.put(conj_prep, new String[]{"conj.prep."});
    }

    public static CiXing parse(String wordTypeStr) throws InvalidWordTypeException {
        for (Entry<CiXing, String[]> entry : ciXingMap.entrySet()) {
            String[] strs = entry.getValue();
            for (String _str : strs) {
                if (_str.equalsIgnoreCase(wordTypeStr)) {
                    return entry.getKey();
                }
            }

        }

        throw new InvalidWordTypeException("Unknown CiXing: " + wordTypeStr);
    }

    @Override
    public String toString() {
        return ciXingMap.get(this)[0];
    }
}
