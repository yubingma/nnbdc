import olefile
import re
import struct
import os

def clean_word(raw_word):
    if not raw_word:
        return None
    raw_word = str(raw_word).replace('\n', ' ').strip()
    
    # 去除词性标记
    tags = [r'\badj\.', r'\badv\.', r'\bn\.', r'\bv\.', r'\bprep\.', r'\bconj\.', r'\bpron\.', r'\bnum\.', r'\bart\.', r'\bint\.', r'\bphr\.']
    for tag in tags:
        raw_word = re.sub(tag, '', raw_word)
    
    # 彻底去除星号和其他非字母修饰
    raw_word = raw_word.replace('*', '').strip()
    
    # 直接按第一个括号、中文或特殊符号切断
    clean_w = re.split(r'[\(（\[【\u4e00-\u9fa5]', raw_word)[0].strip()
    
    # 只保留纯字母的单词 (a-z, A-Z, 连字符)
    clean_w = re.sub(r'[^a-zA-Z\-]', '', clean_w)
    
    if not clean_w or len(clean_w) < 2:
        return None
    
    return clean_w.lower()

def extract_text_from_worddoc(stream_data):
    """从Word Document stream中提取文本"""
    words = []
    
    # 方法1: 提取所有可见的ASCII字符串（至少3个连续字符）
    text = stream_data.decode('latin-1', errors='ignore')
    
    # 寻找有意义的单词模式：纯字母序列
    # 过滤掉太短的、无意义的乱码
    pattern = re.compile(r'[a-zA-Z]{2,}')
    matches = pattern.findall(text)
    
    for match in matches:
        cleaned = clean_word(match)
        if cleaned and len(cleaned) >= 2:
            words.append(cleaned)
    
    return words

def extract_from_old_doc_v2(input_path, output_path):
    ole = olefile.OleFileIO(input_path)
    words = set()
    
    # 读取 WordDocument stream
    if ole.exists('WordDocument'):
        word_stream = ole.openstream('WordDocument').read()
        extracted = extract_text_from_worddoc(word_stream)
        words.update(extracted)
        print(f"从 WordDocument 提取了 {len(extracted)} 个词")
    
    # 读取 1Table
    if ole.exists('1Table'):
        try:
            table_stream = ole.openstream('1Table').read()
            extracted = extract_text_from_worddoc(table_stream)
            words.update(extracted)
            print(f"从 1Table 提取了 {len(extracted)} 个词")
        except:
            pass
    
    # 读取 0Table
    if ole.exists('0Table'):
        try:
            table_stream = ole.openstream('0Table').read()
            extracted = extract_text_from_worddoc(table_stream)
            words.update(extracted)
            print(f"从 0Table 提取了 {len(extracted)} 个词")
        except:
            pass
    
    ole.close()
    
    # 排序
    unique_words = sorted(list(words))
    
    with open(output_path, 'w', encoding='utf-8') as f:
        for w in unique_words:
            f.write(w + "\n")
    
    print(f"✅ 去重后剩余 {len(unique_words)} 个单词。")
    print(f"最终结果已保存至: {output_path}")

if __name__ == '__main__':
    extract_from_old_doc_v2('/Volumes/ssd/ppdc/tools/book/小学/译林版/最新译林版小学英语三-六年级单词汇总.doc', '/Volumes/ssd/ppdc/tools/book/pdf_pipeline/yilin_raw.txt')
