import fitz
import os

def extract_and_clean_words(pdf_path, output_path):
    if not os.path.exists(pdf_path):
        print(f"Error: File not found {pdf_path}")
        return

    doc = fitz.open(pdf_path)
    words = []
    
    # Confirmed mappings for PDF text layer corruptions (Tantan Vocabulary App)
    replacements = {
        '\x87': 'ff',
        '\x8a': 'ffi',
        '\x8c': 'ffl',
        '\x8e': 'fi',
        '\x90': 'fl',
        '\x91': 'rf',
        '\x92': 'rt',
        '\x93': 'rv',
        '\x94': 'rx',
        '\x95': 'ry'
    }
    
    for page in doc:
        lines = page.get_text().split('\n')
        i = 0
        while i < len(lines):
            line = lines[i].strip()
            # The PDF format usually has a number followed by the word
            if line.isdigit():
                if i + 1 < len(lines):
                    word = lines[i+1].strip()
                    # Skip headers and empty lines
                    if word and not word.isdigit() and word not in ["Word", "Meaning", "N0.", "Vocabula• List"]:
                        # Apply confirmed replacements
                        for char, rep in replacements.items():
                            word = word.replace(char, rep)
                        
                        # Special case: keep 'é' but remove other non-ascii control characters
                        cleaned_word = "".join(c for c in word if ord(c) < 128 or c == 'é')
                        
                        if cleaned_word:
                            words.append(cleaned_word)
                        i += 1
            i += 1
            
    doc.close()
    
    # Remove duplicates while preserving order
    seen = set()
    unique_words = []
    for w in words:
        if w not in seen:
            unique_words.append(w)
            seen.add(w)
            
    with open(output_path, 'w', encoding='utf-8') as f:
        for word in unique_words:
            f.write(f"0|{word}\n")
            
    print(f"Extracted {len(unique_words)} unique words to {output_path}")

if __name__ == "__main__":
    # Default paths (adjust as needed)
    pdf_file = "../考研/2026硕士研究生英语（一）大纲词汇_20260420_135816.pdf"
    output_file = "../考研/2026硕士研究生英语大纲词汇.txt"
    
    extract_and_clean_words(pdf_file, output_file)
