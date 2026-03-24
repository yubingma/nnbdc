import wordninja

# List of known FALSE POSITIVES from wordninja on this corpus
BLACKLIST = {
    "federal", "tibetan", "spokesman", "workmate", "waggon", 
    "appetising", "industrialise", "mechanise", "insureagainst", 
    "overexcited", "reflexion", "transgene", "longline", "paediatrics",
    "futurologist", "biophilia", "carcase", "pushback", "skint", "airflow",
    "unsurprisingly", "jobseeker", "uncool"
}

# Explicit overrides for tricky ones
OVERRIDES = {
    "diedown": "die down",
    "catchupwith": "catch up with",
    "setup": "set up",
    "makeup": "make up",
    "wakeup": "wake up",
    "agreeonsth.": 'agree on sth.',
    "agreewithsb.": 'agree with sb.',
    "insureagainst": "insure against"
}

def safe_split(word):
    # exact overrides logic
    if word in OVERRIDES:
        return OVERRIDES[word]
        
    lower_w = word.lower()
    if lower_w in BLACKLIST:
        return word # Do not split
        
    parts = wordninja.split(word)
    # If wordninja didn't split, or just changed case
    if len(parts) <= 1 or "".join(parts).lower() != lower_w:
        return word
        
    # We accept the split
    return " ".join(parts)

for file_path in ["/Volumes/ssd/ppdc/tools/book/高考/gaokao_3500_words.txt", 
                  "/Volumes/ssd/ppdc/tools/book/专升本/zsb_3500_words.txt",
                  "/Volumes/ssd/ppdc/tools/book/hbs_2027_zx/hbs_2027_words.txt"]:
    with open(file_path, "r", encoding="utf-8") as f:
        words = [line.strip() for line in f if line.strip()]

    new_words = []
    changed_count = 0
    
    for w in words:
        if " " in w: # already split (or manually corrected)
            new_words.append(w)
            continue
            
        split_w = safe_split(w)
        if split_w != w:
            # Fix wordninja bad spacing habits on sb/sth
            split_w = split_w.replace("s th", "sth.")
            split_w = split_w.replace("s th.", "sth.")
            split_w = split_w.replace("s b", "sb.")
            split_w = split_w.replace("s b.", "sb.")
            split_w = split_w.replace("catchup", "catch up")
            split_w = split_w.replace("died own", "die down")
            
            new_words.append(split_w)
            changed_count += 1
        else:
            new_words.append(w)
            
    with open(file_path, "w", encoding="utf-8") as f:
        for xw in new_words:
            f.write(xw + "\n")
            
    print(f"File: {file_path}, fixed {changed_count} glued physical words.")
