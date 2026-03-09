import os

# Paths
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INPUT_RAW = os.path.join(BASE_DIR, 'output', '2027_hbs_raw.txt')
OUTPUT_EXTRACTED = os.path.join(BASE_DIR, 'output', '2027_hbs_extracted.txt')

def has_chinese(text):
    return any('\u4e00' <= char <= '\u9fff' for char in text)

def parse():
    print(f"Parsing raw text from: {INPUT_RAW}")
    if not os.path.exists(INPUT_RAW):
        print(f"Error: {INPUT_RAW} not found. Run step1 first.")
        return

    with open(INPUT_RAW, 'r', encoding='utf-8') as f:
        content = f.read()

    blocks = content.split("WordMeaning")
    print(f"Found {len(blocks)} content blocks.")

    english_words = {} 
    chinese_meanings = {}

    for block in blocks:
        lines = block.strip().split('\n')
        is_chinese_block = any(has_chinese(l) for l in lines)
        
        current_id = None
        current_content = []
        
        for line in lines:
            line = line.strip()
            if not line: continue
            if "2027考研英语红宝书" in line or "共 6550 词" in line:
                break
                
            if line.isdigit():
                if current_id and current_content:
                    val = " ".join(current_content)
                    if is_chinese_block: chinese_meanings[current_id] = val
                    else: english_words[current_id] = val
                
                current_id = line
                current_content = []
            else:
                if current_id:
                    current_content.append(line)
        
        if current_id and current_content:
            val = " ".join(current_content)
            if is_chinese_block: chinese_meanings[current_id] = val
            else: english_words[current_id] = val

    all_ids = sorted([int(k) for k in english_words.keys() if k in chinese_meanings])
    
    with open(OUTPUT_EXTRACTED, 'w', encoding='utf-8') as f:
        for i in all_ids:
            sid = str(i)
            f.write(f"{english_words[sid]}|{chinese_meanings[sid]}\n")

    print(f"Successfully matched and saved {len(all_ids)} words to {OUTPUT_EXTRACTED}")

if __name__ == "__main__":
    parse()
