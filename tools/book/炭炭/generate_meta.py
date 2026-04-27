#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import json
import sys

def generate_meta(target_dir):
    if not os.path.isdir(target_dir):
        print(f"Error: {target_dir} is not a valid directory.")
        return

    # 获取目录下所有的 txt 文件
    txt_files = [f for f in os.listdir(target_dir) if f.endswith('.txt') and os.path.isfile(os.path.join(target_dir, f))]
    
    if not txt_files:
        print(f"No .txt files found in {target_dir}.")
        return

    # 构建 meta.json 框架
    meta_data = {
        "isSystemImport": True,
        "generateWordImage": False,
        "generateShuffledVersion": True,
        "targetDictGroupId": "",
        "targetGameHallIds": [],
        "books": []
    }

    for txt_file in sorted(txt_files):
        import re
        # 词书名称缺省为去除了 .txt 后缀的文件名
        dict_name = os.path.splitext(txt_file)[0]
        # 去除类似 _20260425_103634 这样的时间戳后缀
        dict_name = re.sub(r'_\d{8}_\d{6}$', '', dict_name)
        
        book_entry = {
            "fileName": txt_file,
            "dictName": dict_name,
            "domain": "",
            "description": "",
            "targetDictGroupId": "",
            "targetGameHallIds": []
        }
        meta_data["books"].append(book_entry)

    # 输出到目标目录下的 meta.json
    output_path = os.path.join(target_dir, 'meta.json')
    
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(meta_data, f, ensure_ascii=False, indent=2)

    print(f"Successfully generated meta.json with {len(txt_files)} books at: {output_path}")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        dir_path = sys.argv[1]
    else:
        # 如果未传入参数，默认使用当前脚本所在的同级“炭炭”目录，如果没有就用当前工作目录
        default_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), '炭炭')
        if os.path.isdir(default_path):
            dir_path = default_path
        else:
            dir_path = os.getcwd()
            
    print(f"Scanning directory: {dir_path}")
    generate_meta(dir_path)
