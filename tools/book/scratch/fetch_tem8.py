from urllib.request import Request, urlopen
import re
import sys

headers = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
}

all_words = []
seen_words = set()

for page in range(1, 10):
    url = f"https://www.koolearn.com/dict/tag_1211_{page}.html"
    print(f"Fetching {url}...")
    try:
        req = Request(url, headers=headers)
        with urlopen(req, timeout=10) as response:
            status_code = response.status
            if status_code != 200:
                print(f"Finished at page {page-1} (Status code {status_code})")
                break
            html = response.read().decode('utf-8')
        words = re.findall(r'<a class="word" href="[^"]+">([^<]+)</a>', html)
        if not words:
            print(f"No words found on page {page}. Stopping.")
            break
            
        print(f"Page {page}: found {len(words)} words.")
        for w in words:
            w_clean = w.strip()
            if w_clean and w_clean.lower() not in seen_words:
                seen_words.add(w_clean.lower())
                all_words.append(w_clean)
                
    except Exception as e:
        print(f"Error fetching page {page}: {e}")
        break

print(f"\nTotal unique words extracted: {len(all_words)}")
# Let's sort alphabetically
all_words_sorted = sorted(all_words, key=lambda s: s.lower())

output_path = "/Volumes/ssd/ppdc/tools/book/专八/专八2000核心词汇表.txt"
with open(output_path, "w", encoding="utf-8") as f:
    for w in all_words_sorted:
        f.write(f"0|{w}\n")

print(f"Saved to {output_path}")
