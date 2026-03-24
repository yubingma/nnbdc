import nltk
import wordninja
import re
import collections

# Load standard dictionary
try:
    from nltk.corpus import words as nltk_words
    from nltk.corpus import brown
    # Combine NLTK words and Brown corpus for a richer vocabulary
    english_dict = set(nltk_words.words())
    english_dict.update([w.lower() for w in english_dict])
    brown_words = set(brown.words())
    english_dict.update([w.lower() for w in brown_words])
except Exception as e:
    print("NLTK corpus issue:", e)
    english_dict = set()

files = [
    "/Volumes/ssd/ppdc/tools/book/高考/gaokao_3500_words.txt", 
    "/Volumes/ssd/ppdc/tools/book/专升本/zsb_3500_words.txt",
    "/Volumes/ssd/ppdc/tools/book/hbs_2027_zx/hbs_2027_words.txt"
]

# Words we already know are correct but NLTK might not know
known_safe = {"waggon", "workmate", "spokesman", "Tibetan", "industrialise", 
              "mechanise", "appetising", "overexcited", "transgene", "reflexion",
              "longline", "paediatrics", "futurologist", "biophilia", "carcase", 
              "pushback", "skint", "airflow", "unsurprisingly", "jobseeker", "uncool"}

suspicious = collections.defaultdict(list)

for file_path in files:
    with open(file_path, "r", encoding="utf-8") as f:
        words = [line.strip() for line in f if line.strip()]

    for w in words:
        # Ignore things that are already phrases (they contain spaces)
        if " " in w:
            continue
            
        # Strip trailing slashes, punctuation etc if any
        clean_w = re.sub(r'[^a-zA-Z\']', '', w).lower()
        if len(clean_w) < 4:
            continue
            
        if clean_w not in english_dict and clean_w not in known_safe:
            # It's not in the dictionary. Let's ask wordninja what it thinks.
            parts = wordninja.split(clean_w)
            if len(parts) > 1 and "".join(parts) == clean_w:
                # Wordninja actually thinks this should be split
                # Let's check if the split parts are purely real words
                valid_parts = all(p in english_dict for p in parts if len(p) > 1)
                
                if valid_parts:
                    suspicious[file_path].append((w, " ".join(parts)))

for file_path, items in suspicious.items():
    print(f"\n--- In {file_path.split('/')[-1]} ---")
    print(f"Found {len(items)} potentially glued words that NLTK suggests splitting:")
    for w, split_suggestion in items[:20]: # Show top 20
        print(f"  {w} -> NLTK suggests: {split_suggestion}")

if not suspicious:
    print("\nVerification Passed: 0 unhandled glued words detected by NLTK across all 3 files!")
