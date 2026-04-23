import fitz
import os
import glob
from collections import Counter

def full_char_audit():
    source_dir = "/Volumes/ssd/ppdc/tools/book/考研"
    pdf_files = glob.glob(os.path.join(source_dir, "*.pdf"))
    
    char_counts = Counter()
    char_examples = {}
    
    for pdf_file in pdf_files:
        doc = fitz.open(pdf_file)
        for page in doc:
            text = page.get_text()
            for i, char in enumerate(text):
                code = ord(char)
                if 128 <= code < 0x4e00:
                    char_counts[char] += 1
                    if char not in char_examples:
                        start = max(0, i - 15)
                        end = min(len(text), i + 15)
                        char_examples[char] = text[start:end].replace('\n', ' ')
        doc.close()

    print(f"{'Char':<6} | {'Hex':<6} | {'Count':<6} | {'Example'}")
    print("-" * 50)
    for char, count in char_counts.most_common():
        hex_val = hex(ord(char))
        example = char_examples[char]
        print(f"{repr(char):<6} | {hex_val:<6} | {count:<6} | {example}")

if __name__ == "__main__":
    full_char_audit()
