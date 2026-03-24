import pdfplumber
import re
import sys
import os

# ==========================================
# 01_extract_raw.py 
# 用法：python 01_extract_raw.py <input.pdf> <output.txt>
# ==========================================
if len(sys.argv) < 3:
    print("Usage: python 01_extract_raw.py <input.pdf> <output.txt>")
    sys.exit(1)

PDF_PATH = sys.argv[1]
OUTPUT_TXT = sys.argv[2]

# 这个正则用来匹配纯文本列表型 PDF 中的 "1. word" 或 "1 word"（带编号结构）
# 对于表格型 PDF，建议使用 pdf.pages[x].extract_tables() (参考此前高考词汇脚本文本)
NUMBERED_PATTERN = r'(?:\s|^)(\d+)\.\s*(?=[A-Za-z])' 

def clean_word(raw_word):
    """
    无脑物理裁剪功能：
    仅去除词性（n. adj. v. 等）和括号内的无用注解
    """
    tags = [r'\badj\.', r'\badv\.', r'\bn\.', r'\bv\.', r'\bprep\.', r'\bconj\.', r'\bpron\.', r'\bnum\.', r'\bart\.', r'\bint\.', r'\bphr\.']
    for tag in tags:
        raw_word = re.sub(tag, '', raw_word)
        
    # 直接斩断括号 (英中皆可)
    clean_w = re.split(r'[\(（\[【]', raw_word)[0].strip()
    return clean_w

if __name__ == "__main__":
    if not os.path.exists(PDF_PATH):
        print(f"请先将 PDF 路径修改为您自己的文件 ({PDF_PATH})")
        sys.exit(1)

    words_dict = {}
    with pdfplumber.open(PDF_PATH) as pdf:
        full_text = ""
        for page in pdf.pages:
            text = page.extract_text()
            if text:
                full_text += text.replace('\n', ' ') + " "
                
        parts = re.split(NUMBERED_PATTERN, full_text)
        for i in range(1, len(parts), 2):
            num = int(parts[i])
            chunk = parts[i+1]
            # 依中文字符或括号切断后面解释
            match1 = re.split(r'\[|[\u4e00-\u9fa5]', chunk)
            if match1:
                clean_w = clean_word(match1[0].strip())
                if clean_w:
                    words_dict[num] = clean_w
                    
    # 按从1开始的序列检测漏字情况
    max_num = max(words_dict.keys()) if words_dict else 0
    missing = [i for i in range(1, max_num+1) if i not in words_dict]
    if missing:
        print(f"⚠️ 警告: 原生提取发现缺漏序号 (可能被格式吃掉): {missing[:20]}...")
        
    # 全局去重 (不同形态但切掉括号长得一样的单词合并)
    seen = set()
    with open(OUTPUT_TXT, "w", encoding="utf-8") as f:
        for i in range(1, max_num + 1):
            if i in words_dict:
                w = words_dict[i]
                if w and w not in seen:
                    seen.add(w)
                    f.write(w + "\n")
                    
    print(f"✅ 完成！已将 {len(seen)} 个绝对原生纯净但可能带有排版黏连问题的单词提取至 {OUTPUT_TXT}")
