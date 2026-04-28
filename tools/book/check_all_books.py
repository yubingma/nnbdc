import os
import glob
import re
import collections
import nltk
import wordninja

# Ensure necessary NLTK data is downloaded
try:
    nltk.data.find('corpora/words')
except LookupError:
    nltk.download('words')
try:
    nltk.data.find('corpora/brown')
except LookupError:
    nltk.download('brown')

from nltk.corpus import words as nltk_words
from nltk.corpus import brown

print("Loading NLTK dictionary...")
# Combine NLTK words and Brown corpus for a richer vocabulary
english_dict = set(nltk_words.words())
english_dict.update([w.lower() for w in english_dict])
brown_words = set(brown.words())
english_dict.update([w.lower() for w in brown_words])

# Add common prefixes/suffixes or known safe words that NLTK might miss
known_safe = {
    "waggon", "workmate", "spokesman", "Tibetan", "industrialise", 
    "mechanise", "appetising", "overexcited", "transgene", "reflexion",
    "longline", "paediatrics", "futurologist", "biophilia", "carcase", 
    "pushback", "skint", "airflow", "unsurprisingly", "jobseeker", "uncool",
    "cellphone", "online", "website", "email", "internet", "offline",
    "smartphone", "screenshot", "database", "cybersecurity", "cyber",
    "blockchain", "crypto", "bitcoin", "ecommerce", "app", "apps",
    "podcast", "vlog", "vlogger", "influencer", "hashtag", "selfie"
}

# Directory containing the txt files
data_dir = "/Volumes/ssd/ppdc/tools/book/大学/toimport/"
txt_files = glob.glob(os.path.join(data_dir, "*.txt"))

print(f"Found {len(txt_files)} txt files to check.")

report_lines = []
report_lines.append("# University Vocabulary Books - Word Quality Check Report\n")

glued_count_total = 0
typo_count_total = 0

for file_path in sorted(txt_files):
    file_name = os.path.basename(file_path)
    print(f"Checking {file_name}...")
    
    with open(file_path, "r", encoding="utf-8") as f:
        lines = f.readlines()
        
    glued_words = []
    unknown_words = []
    
    for line in lines:
        line = line.strip()
        if not line:
            continue
            
        # Parse "0|word"
        if "|" in line:
            word = line.split("|", 1)[1].strip()
        else:
            word = line
            
        if not word:
            continue
            
        # Ignore phrases with spaces
        if " " in word:
            continue
            
        # Clean word for dictionary lookup (remove non-alphabetic chars except ')
        clean_w = re.sub(r'[^a-zA-Z\']', '', word).lower()
        
        if len(clean_w) < 4:
            continue
            
        if clean_w not in english_dict and clean_w not in known_safe:
            # Check if it can be split by wordninja into valid words
            parts = wordninja.split(clean_w)
            if len(parts) > 1 and "".join(parts) == clean_w:
                valid_parts = all(p in english_dict or p in known_safe for p in parts if len(p) > 1)
                if valid_parts:
                    glued_words.append((word, " ".join(parts)))
                else:
                    unknown_words.append(word)
            else:
                unknown_words.append(word)
                
    if glued_words or unknown_words:
        report_lines.append(f"## {file_name}")
        
        if glued_words:
            report_lines.append("### 疑似粘连词 (Glued Words)")
            for w, suggestion in glued_words:
                report_lines.append(f"- `{w}` -> 建议拆分: `{suggestion}`")
            glued_count_total += len(glued_words)
            
        if unknown_words:
            report_lines.append("### 疑似拼写错误或生僻词 (Unknown/Typos)")
            # Deduplicate unknown words for better reporting
            unique_unknown = sorted(list(set(unknown_words)))
            report_lines.append(", ".join([f"`{w}`" for w in unique_unknown]))
            typo_count_total += len(unique_unknown)
            
        report_lines.append("\n---\n")

report_lines.append(f"\n## Summary")
report_lines.append(f"- Total Files Checked: {len(txt_files)}")
report_lines.append(f"- Total Glued Words Found: {glued_count_total}")
report_lines.append(f"- Total Unknown/Typo Words Found: {typo_count_total}")

report_path = "/Volumes/ssd/ppdc/tools/book/check_report.md"
with open(report_path, "w", encoding="utf-8") as f:
    f.write("\n".join(report_lines))

print(f"Check complete. Report saved to {report_path}")
print(f"Found {glued_count_total} glued words and {typo_count_total} unknown/typo words across all files.")
