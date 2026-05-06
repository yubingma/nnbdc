import os
import json

def generate_meta_for_existing(output_dir):
    all_files = [f for f in os.listdir(output_dir) if f.endswith(".txt")]
    all_files.sort() # Optional: sort files for consistent order in meta.json
    
    meta = {
        "isSystemImport": True,
        "generateWordImage": False,
        "generateShuffledVersion": False,
        "targetDictGroupId": "",
        "targetGameHallIds": [],
        "books": []
    }
    
    for fname in all_files:
        meta["books"].append({
            "fileName": fname,
            "dictName": fname.replace(".txt", ""),
            "domain": "",
            "description": "",
            "targetDictGroupId": "",
            "targetGameHallIds": []
        })
        
    with open(os.path.join(output_dir, "meta.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=2)
    
    print(f"✅ Successfully generated meta.json with {len(all_files)} books based on existing TXT files.")

if __name__ == "__main__":
    output_dir = "/Volumes/ssd/ppdc/tools/book/多邻国/extracted/"
    generate_meta_for_existing(output_dir)
