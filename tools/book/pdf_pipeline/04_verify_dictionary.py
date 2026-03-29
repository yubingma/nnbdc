import nltk
from spellchecker import SpellChecker
import os

# 确保有基本的语料库 (常用词库)
try:
    from nltk.corpus import words as nltk_words
    english_vocab = set(w.lower() for w in nltk_words.words())
except:
    nltk.download('words')
    from nltk.corpus import words as nltk_words
    english_vocab = set(w.lower() for w in nltk_words.words())

spell = SpellChecker()

def verify_and_report(file_path):
    with open(file_path, 'r', encoding='utf-8') as f:
        words = [line.strip() for line in f if line.strip()]
    
    total = len(words)
    unrecognized = []
    
    # 我们认为一个词条是合法的，只要：
    # 1. 它是 nltk 词典里的成员
    # 2. 或者是拼写检查器认出来的
    # 3. 如果是词组，拆开来每个分词都是合法的
    
    for entry in words:
        is_valid = False
        # 处理连字符，转为空格进行分词检查
        parts = entry.replace('-', ' ').replace('_', ' ').split()
        
        # 只要词组中所有的单词都在任一词典中能找到，就认为合法
        parts_valid = []
        for p in parts:
            p_low = p.lower()
            if p_low in english_vocab or len(spell.known([p_low])) > 0:
                parts_valid.append(True)
            else:
                parts_valid.append(False)
        
        if all(parts_valid):
            is_valid = True
            
        if not is_valid:
            unrecognized.append(entry)
            
    print(f"📊 审计统计 (Total: {total})")
    print(f"✅ 机器完美识别率: {(total - len(unrecognized)) / total * 100:.2f}%")
    print(f"❌ 机器不认识的词 (建议人工复核): {len(unrecognized)} 个")
    
    if unrecognized:
        print("\n--- 疑似“非标准词”清单 (前30个) ---")
        for uw in unrecognized[:30]:
            print(f"  [!] {uw}")

if __name__ == '__main__':
    verify_and_report('final_ielts_words.txt')
