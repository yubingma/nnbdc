import fitz
import os
import glob

def find_stripped_chars():
    source_dir = "/Volumes/ssd/ppdc/tools/book/考研"
    pdf_files = glob.glob(os.path.join(source_dir, "*.pdf"))
    
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
    
    stripped_chars = {}
    
    for pdf_file in pdf_files:
        doc = fitz.open(pdf_file)
        for page in doc:
            lines = page.get_text().split('\n')
            i = 0
            while i < len(lines):
                line = lines[i].strip()
                if line.isdigit():
                    if i + 1 < len(lines):
                        word = lines[i+1].strip()
                        if word and not word.isdigit() and word not in ["Word", "Meaning", "N0.", "Vocabula• List"]:
                            for char, rep in replacements.items():
                                word = word.replace(char, rep)
                            
                            for c in word:
                                if ord(c) >= 128 and c != 'é':
                                    if c not in stripped_chars:
                                        stripped_chars[c] = []
                                    if len(stripped_chars[c]) < 5:
                                        stripped_chars[c].append(word)
                            i += 1
                i += 1
        doc.close()

    if not stripped_chars:
        print("No characters were stripped (all non-ASCII were handled or are 'é').")
    else:
        print(f"Found {len(stripped_chars)} stripped characters:")
        for char, examples in stripped_chars.items():
            print(f"Char: {repr(char)} (Hex: {hex(ord(char))}), Examples: {examples}")

if __name__ == "__main__":
    find_stripped_chars()
