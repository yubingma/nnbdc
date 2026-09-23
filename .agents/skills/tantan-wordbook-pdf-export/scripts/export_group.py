#!/usr/bin/env python3
"""批量把炭炭背单词某个「分类 tab + 出版社分组」的全部词书导出为整本 PDF。

用法：
    python3 export_group.py 小学 北京版                       # 默认落到 tools/book/小学/
    python3 export_group.py 初中 人教版 --out tools/book/初中
    python3 export_group.py 高中 外研版 --books books.json --phonetic
"""
import argparse
import json
import os
import sys

import tantan

ROOT = "/Volumes/ssd/ppdc"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tab")
    ap.add_argument("chip")
    ap.add_argument("--out", help="PDF 输出目录（默认 <repo>/tools/book/<tab>）")
    ap.add_argument("--books", help="现成的 [(书名, 词数)] json，跳过枚举")
    ap.add_argument("--phonetic", action="store_true", help="显示音标（默认隐藏）")
    ap.add_argument("--columns", type=int, default=1, choices=(1, 2))
    ap.add_argument("--no-resume", action="store_true", help="已存在的也重导")
    a = ap.parse_args()

    out_dir = a.out or os.path.join(ROOT, "tools/book", a.tab)
    books = json.load(open(a.books)) if a.books else None
    if books:
        books = [(n, int(c)) for n, c in books]

    report = tantan.export_group(a.tab, a.chip, out_dir,
                                 phonetic=a.phonetic, columns=a.columns,
                                 books=books, resume=not a.no_resume)

    print("\n===== 汇总 =====")
    bad = 0
    for name, exp, got, pages, ok, fname in report:
        bad += 0 if ok else 1
        print(f"  {'OK ' if ok else 'BAD'} {name:32} 期望{exp:4} 实得{got:4} 页{pages}  {fname}")
    print(f"\n输出目录: {out_dir}   失败 {bad} 本")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
