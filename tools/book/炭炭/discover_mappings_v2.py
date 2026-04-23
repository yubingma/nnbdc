import fitz
import os
import glob
import re

def discover_new_mappings_v2():
    source_dir = "/Volumes/ssd/ppdc/tools/book/考研"
    pdf_files = glob.glob(os.path.join(source_dir, "*.pdf"))
    
    known_chars = {'\x87', '\x8a', '\x8c', '\x8e', '\x90', '\x91', '\x92', '\x93', '\x94', '\x95'}
    
    unusual_char_context = {}
    
    for pdf_file in pdf_files:
        doc = fitz.open(pdf_file)
        for page in doc:
            text = page.get_text()
            for i, char in enumerate(text):
                code = ord(char)
                # Focus on 0x80 - 0x2000 range (excluding Chinese characters and common punctuation)
                # And avoid standard ASCII.
                if 128 <= code < 0x4e00 and char not in known_chars:
                    # Capture context
                    start = max(0, i - 15)
                    end = min(len(text), i + 15)
                    context = text[start:end].replace('\n', ' ')
                    
                    if char not in unusual_char_context:
                        unusual_char_context[char] = []
                    
                    if len(unusual_char_context[char]) < 10:
                        unusual_char_context[char].append(context)
        doc.close()

    if not unusual_char_context:
        print("No new unusual characters found in the targeted range.")
    else:
        print(f"Found {len(unusual_char_context)} potential new mapping candidates:")
        for char, contexts in sorted(unusual_char_context.items(), key=lambda x: ord(x[0])):
            print(f"\nCharacter: {repr(char)} (Hex: {hex(ord(char))})")
            print("Contexts:")
            for ctx in contexts:
                print(f"  - ...{ctx}...")

if __name__ == "__main__":
    discover_new_mappings_v2()
