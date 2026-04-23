import fitz
import os
import glob
from collections import Counter

def discover_new_mappings():
    source_dir = "/Volumes/ssd/ppdc/tools/book/考研"
    pdf_files = glob.glob(os.path.join(source_dir, "*.pdf"))
    
    known_chars = {'\x87', '\x8a', '\x8c', '\x8e', '\x90', '\x91', '\x92', '\x93', '\x94', '\x95'}
    safe_chars = {'é'} # Add other known safe non-ascii chars if needed
    
    unusual_char_context = {}
    
    for pdf_file in pdf_files:
        doc = fitz.open(pdf_file)
        for page in doc:
            text = page.get_text()
            for i, char in enumerate(text):
                if ord(char) >= 128 and char not in known_chars and char not in safe_chars:
                    # Capture context: 10 chars before and after
                    start = max(0, i - 15)
                    end = min(len(text), i + 15)
                    context = text[start:end].replace('\n', ' ')
                    
                    if char not in unusual_char_context:
                        unusual_char_context[char] = []
                    
                    if len(unusual_char_context[char]) < 10: # Store up to 10 examples
                        unusual_char_context[char].append(context)
        doc.close()

    if not unusual_char_context:
        print("No new unusual characters found.")
    else:
        print(f"Found {len(unusual_char_context)} potential new mapping candidates:")
        for char, contexts in unusual_char_context.items():
            print(f"\nCharacter: {repr(char)} (Hex: {hex(ord(char))})")
            print("Contexts:")
            for ctx in contexts:
                print(f"  - ...{ctx}...")

if __name__ == "__main__":
    discover_new_mappings()
