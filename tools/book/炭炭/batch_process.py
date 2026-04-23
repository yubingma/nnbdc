import fitz
import os
import glob

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

def batch_process():
    source_dir = "/Volumes/ssd/ppdc/tools/book/考研"
    pdf_files = glob.glob(os.path.join(source_dir, "*.pdf"))
    
    if not pdf_files:
        print(f"No PDF files found in {source_dir}")
        return

    print(f"Found {len(pdf_files)} PDF files to process.")
    
    for pdf_file in pdf_files:
        # Generate output path: same name but .txt
        filename = os.path.basename(pdf_file)
        # Remove the timestamp if possible, or just change extension
        # The user's example in the original script: "../考研/2026硕士研究生英语大纲词汇.txt"
        # I'll keep the name similar but remove the extension.
        txt_filename = os.path.splitext(filename)[0] + ".txt"
        output_path = os.path.join(source_dir, txt_filename)
        
        print(f"Processing: {filename} ...")
        extract_and_clean_words(pdf_file, output_path)

if __name__ == "__main__":
    batch_process()
