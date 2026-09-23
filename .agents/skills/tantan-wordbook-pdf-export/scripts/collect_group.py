#!/usr/bin/env python3
"""枚举炭炭背单词某「分类 tab + 出版社分组」下的全部词书。

用法：
    python3 collect_group.py 小学 北京版 [-o books.json]
"""
import argparse
import json

import tantan


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tab", help="分类 tab，如 小学 / 初中 / 高中 / 大学")
    ap.add_argument("chip", help="出版社分组，如 北京版 / 人教版 / 外研版")
    ap.add_argument("-o", "--out", help="输出 json（默认只打印）")
    a = ap.parse_args()

    books = tantan.collect_group(a.tab, a.chip)
    print(f"{a.tab}/{a.chip} 共 {len(books)} 本，合计 {sum(n for _, n in books)} 词")
    for name, n in books:
        print(f"  {name:34} {n}")
    if a.out:
        json.dump(books, open(a.out, "w"), ensure_ascii=False, indent=1)
        print(f"已写入 {a.out}")


if __name__ == "__main__":
    main()
