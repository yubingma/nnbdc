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
    """Detect which mapping table to use based on key header characters."""
    # The word "Vocabulary" is the best anchor. 
    # In standard, "ry" is \x95. In shifted, "ry" is \xa3.
    for i in range(min(10, len(doc))):
        text = doc[i].get_text()
        if '\xa3' in text: # Definitive for shifted "ry"
            return "shifted_14"
        if '\x95' in text: 
            # In standard, \x95 is "ry" (common in headers).
            # In shifted, \x95 is "ff" (rare in headers).
            # So if \x95 is found in a header area, it's almost certainly standard.
            return "standard"
            
    # Fallback to checking other common corrupted characters
    for i in range(min(10, len(doc))):
        text = doc[i].get_text()
        if '\xa0' in text or '\x9c' in text: # rt or fi in shifted
            return "shifted_14"
        if '\x92' in text or '\x8e' in text: # rt or fi in standard
            return "standard"
            
    return "standard"

def extract_pdf(pdf_path, output_path):
    if not os.path.exists(pdf_path):
        print(f"Error: File not found {pdf_path}")
        return

    doc = fitz.open(pdf_path)
    map_type = detect_mapping(doc)
    print(f"  Detected mapping: {map_type}")
    replacements = MAPPINGS[map_type]
    replacements['\xe9'] = 'e'
    
    words = []
    for page in doc:
        lines = page.get_text().split('\n')
        i = 0
        while i < len(lines):
            line = lines[i].strip()
            if line.isdigit():
                if i + 1 < len(lines):
                    word = lines[i+1].strip()
                    if word and not word.isdigit() and word not in ["Word", "Meaning", "N0.", "NO.", "Vocabulary List"]:
                        # Manual skip for corrupted header variations
                        if any(header in word for header in ["Vocabula", "List", "中英词表", "默写释义"]):
                            i += 1
                            continue

                        for char, rep in replacements.items():
                            word = word.replace(char, rep)
                        
                        cleaned_word = "".join(c for c in word if ord(c) < 128)
                        
                        if cleaned_word:
                            words.append(cleaned_word)
                        i += 1
            i += 1
    doc.close()

    seen = set()
    unique_words = []
    for w in words:
        if w not in seen:
            unique_words.append(w)
            seen.add(w)
            
    with open(output_path, 'w', encoding='utf-8') as f:
        for word in unique_words:
            f.write(f"0|{word}\n")
            
    print(f"  Success: Extracted {len(unique_words)} words to {os.path.basename(output_path)}")

def batch_process(source_dir):
    pdf_files = glob.glob(os.path.join(source_dir, "*.pdf"))
    if not pdf_files:
        print(f"No PDF files found in {source_dir}")
        return

    print(f"Batch processing {len(pdf_files)} files in {source_dir}...")
    for pdf_file in pdf_files:
        txt_file = os.path.splitext(pdf_file)[0] + ".txt"
        print(f"Processing {os.path.basename(pdf_file)}...")
        extract_pdf(pdf_file, txt_file)

if __name__ == "__main__":
    if len(sys.argv) > 1:
        batch_process(sys.argv[1])
    else:
        print("Usage: python tantan_master_extractor.py <directory>")
