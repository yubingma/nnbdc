import os
import collections

with open("/Volumes/ssd/ppdc/tools/book/gaokao_temp.txt", "r", encoding="utf-8") as f:
    orig_words = [line.strip() for line in f if line.strip()]

counts = collections.Counter(orig_words)
duplicates = {w: c for w, c in counts.items() if c > 1}

print(f"Original list length: {len(orig_words)}")
print(f"Unique words count: {len(set(orig_words))}")
print(f"Number of duplicates: {sum(c - 1 for c in duplicates.values())}")

print("\nSample duplicates:")
for i, (w, c) in enumerate(list(duplicates.items())[:20]):
    print(f"{w}: {c} times")
