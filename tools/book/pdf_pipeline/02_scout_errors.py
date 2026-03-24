import os
import sys
import wordninja
from spellchecker import SpellChecker
import nltk

# ==========================================
# 02_scout_errors.py
# 用法：python 02_scout_errors.py <input.txt> <output_report.txt>
# 此脚本负责排雷：找出版面的黏贴错误和拼写错误
# 为 AI 或人类排错提供一份“疑似错字报告” (report)
# 绝不会修改原始的 raw_words.txt。
# ==========================================
if len(sys.argv) < 3:
    print("Usage: python 02_scout_errors.py <input.txt> <output_report.txt>")
    sys.exit(1)

INPUT_TXT = sys.argv[1]
OUTPUT_REPORT = sys.argv[2]

try:
    from nltk.corpus import words as nltk_words
    english_dict = set(nltk_words.words())
    english_dict.update([w.lower() for w in english_dict])
except Exception:
    print("NLTK error! Please run: python -c \"import nltk; nltk.download('words')\"")
    sys.exit(1)

def is_safe_word(word):
    # known common but non-nltk words
    safe_set = {"workmate", "spokesman", "Tibetan", "waggon", "paediatrics"}
    return word.lower() in english_dict or word.lower() in safe_set

if __name__ == "__main__":
    if not os.path.exists(INPUT_TXT):
        print(f"File {INPUT_TXT} not found!")
        sys.exit(1)
        
    spell = SpellChecker()
    # disable spellchecker enforcing lowercase only if possible
    
    with open(INPUT_TXT, "r", encoding="utf-8") as f:
        words = [line.strip() for line in f if line.strip()]

    report_lines = []
    report_lines.append("=== AI Scouter Report for Suspicious Words ===\n")
    
    # 1. 探测未带空格的连字 (如 bringhometo -> bring home to)
    report_lines.append(">> --- [A] 物理空格缺失 (WordNinja 分词探测) ---\n")
    for w in words:
        if " " in w or not w.isalpha(): continue
        if len(w) > 4 and not is_safe_word(w):
            parts = wordninja.split(w)
            # If wordninja thinks this string can be split into valid parts
            if len(parts) > 1 and "".join(parts).lower() == w.lower():
                suggestion = " ".join(parts)
                report_lines.append(f"连词嫌疑: '{w}' -> 可能应为: '{suggestion}'")
                
    # 2. 探测纯字母拼写错别字 (如 federa -> federal)
    report_lines.append("\n>> --- [B] 原生拼写错误 (SpellChecker 探伤) ---\n")
    for w in words:
        if " " in w or not w.isalpha(): continue
        # Ignore upper case words (acronyms usually like TV, CD) from spell checking
        if w.isupper() or len(w) <= 2: continue
        
        if not is_safe_word(w):
            known = spell.known([w.lower()])
            if not known:
                correction = spell.correction(w.lower())
                if correction and correction != w.lower():
                    report_lines.append(f"拼写嫌疑: '{w}' -> 可能应为: '{correction}'")
                    
    with open(OUTPUT_REPORT, "w", encoding="utf-8") as f:
        f.write("\n".join(report_lines))
        
    print(f"✅ 质检扫描完成！探测报告已生成在: {OUTPUT_REPORT}")
    print("👉 下一步: 请人工查看该 report 文件，将你认同的出错词条抄出来，写进 03_apply_fixes.py 的 WHITELIST 内！")
