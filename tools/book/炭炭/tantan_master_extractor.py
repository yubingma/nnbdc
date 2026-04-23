import fitz
import os
import glob
import sys

# Mapping tables
MAPPINGS = {
    "standard": {
        '\x87': 'ff', '\x8a': 'ffi', '\x8c': 'ffl', '\x8e': 'fi', '\x90': 'fl',
        '\x91': 'rf', '\x92': 'rt', '\x93': 'rv', '\x94': 'rx', '\x95': 'ry'
    },
    "shifted_14": {
        '\x95': 'ff', '\x98': 'ffi', '\x9a': 'ffl', '\x9c': 'fi', '\x9e': 'fl',
        '\x9f': 'rf', '\xa0': 'rt', '\xa1': 'rv', '\xa2': 'rx', '\xa3': 'ry'
    }
}

def detect_mapping(doc):
    for i in range(min(10, len(doc))):
        text = doc[i].get_text()
        if '\xa3' in text: return "shifted_14"
        if '\x95' in text: return "standard"
    return "standard"

def extract_pdf(pdf_path, output_path):
    if not os.path.exists(pdf_path):
        print(f"Error: File not found {pdf_path}")
        return

    doc = fitz.open(pdf_path)
    map_type = detect_mapping(doc)
    replacements = MAPPINGS[map_type]
    replacements['\xe9'] = 'e'
    
    raw_entries = []
    max_seq_num = 0
    
    for page in doc:
        lines = page.get_text().split('\n')
        i = 0
        while i < len(lines):
            line = lines[i].strip()
            if line.isdigit():
                val = int(line)
                if val > max_seq_num: max_seq_num = val
                
                if i + 1 < len(lines):
                    # CRITICAL FIX: Do NOT strip() before character replacement
                    # because \xa0 (rt in shifted) might be stripped as whitespace.
                    word_raw = lines[i+1] 
                    word = word_raw
                    
                    if word_raw.strip() and not word_raw.strip().isdigit() and word_raw.strip() not in ["Word", "Meaning", "N0.", "NO.", "Vocabulary List"]:
                        if any(header in word_raw for header in ["Vocabula", "List", "中英词表", "默写释义"]):
                            i += 1
                            continue

                        for char, rep in replacements.items():
                            word = word.replace(char, rep)
                        
                        # Strip only AFTER replacement
                        word = word.strip()
                        cleaned_word = "".join(c for c in word if ord(c) < 128)
                        if cleaned_word:
                            raw_entries.append(cleaned_word)
                        i += 1
            i += 1
    doc.close()

    seen = set()
    unique_words = []
    duplicate_words = []
    for w in raw_entries:
        if w not in seen:
            unique_words.append(w)
            seen.add(w)
        else:
            duplicate_words.append(w)
            
    with open(output_path, 'w', encoding='utf-8') as f:
        for word in unique_words:
            f.write(f"0|{word}\n")
        
        f.write(f"\n# --- Extraction Audit Report ---\n")
        f.write(f"# PDF Max Sequence Number: {max_seq_num}\n")
        f.write(f"# Total Entries Extracted: {len(raw_entries)}\n")
        f.write(f"# Duplicate Words Merged : {len(duplicate_words)}\n")
        if duplicate_words:
            display_list = duplicate_words[:15]
            f.write(f"# Duplicate List Preview : {display_list}{'...' if len(duplicate_words) > 15 else ''}\n")
        f.write(f"# Final Unique Word Count: {len(unique_words)}\n")
        if max_seq_num > len(raw_entries):
            f.write(f"# Warning: {max_seq_num - len(raw_entries)} sequence numbers missing from PDF or skipped.\n")
        f.write(f"# -------------------------------\n")

    print(f"  Result: {len(unique_words)} words. Merged duplicates: {duplicate_words[:5]}...")

def batch_process(source_dir):
    pdf_files = glob.glob(os.path.join(source_dir, "*.pdf"))
    if not pdf_files: return
    print(f"Batch processing {len(pdf_files)} files...")
    for pdf_file in pdf_files:
        txt_file = os.path.splitext(pdf_file)[0] + ".txt"
        print(f"Processing {os.path.basename(pdf_file)}...")
        extract_pdf(pdf_file, txt_file)

if __name__ == "__main__":
    if len(sys.argv) > 1:
        batch_process(sys.argv[1])
    else:
        print("Usage: python tantan_master_extractor.py <directory>")
