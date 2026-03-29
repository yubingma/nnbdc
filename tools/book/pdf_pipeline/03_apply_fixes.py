import os
import sys

# ==========================================
# 03_apply_fixes.py
# 用法：python 03_apply_fixes.py <input.txt> <final.txt>
# 此脚本负责接受人工审查后的白名单字典，并生成最终纯净 TXT
# 绝不会自发改变任何未在白名单中的单词，保证安全兜底
# ==========================================
if len(sys.argv) < 3:
    print("Usage: python 03_apply_fixes.py <input.txt> <final.txt>")
    sys.exit(1)

INPUT_TXT = sys.argv[1]
FINAL_OUT = sys.argv[2]

# 🔴 在这里粘贴你从 02_suspicious_report.txt 审查并剔除掉乱猜词后的“真实出错映射字典” 🔴
# 例如:
MY_WHITELIST = {
    "comdemn": "condemn",
    "commemoratv": "commemorative",
    "complicatedadj": "complicated",
    "constructiv": "constructive",
    "demograph": "demography",
    "demographicadj": "demographic",
    "engagemen": "engagement",
    "epartment": "department",
    "escalato": "escalator",
    "fasle": "false",
    "federationn": "federation",
    "refrigeratio": "refrigeration",
    "neighbourhoo": "neighbourhood",
    "significancen": "significance",
    "simulative adj": "simulative",
    "father-in-lawn": "father-in-law",
    "independen": "independent",
    "hydroge": "hydrogen",
    "manoeuvren": "manoeuvre",
    "merchandisn": "merchandise",
    "carbon dioxiden": "carbon dioxide",
    "magnetic adj therapy": "magnetic therapy",
    "Mediterraneaadj": "Mediterranean",
    "monumentaadj": "monumental",
    "neighbourhoon": "neighbourhood"
}

if __name__ == "__main__":
    if not os.path.exists(INPUT_TXT):
        print(f"File {INPUT_TXT} not found!")
        sys.exit(1)
        
    with open(INPUT_TXT, "r", encoding="utf-8") as f:
        words = [line.strip() for line in f if line.strip()]

    fixed_count = 0
    final_words = []
    
    for w in words:
        if w in MY_WHITELIST:
            # 命中白名单，替换为专家核实的格式
            final_words.append(MY_WHITELIST[w])
            fixed_count += 1
        else:
            final_words.append(w)
            
    with open(FINAL_OUT, "w", encoding="utf-8") as f:
        for xw in final_words:
            f.write(xw + "\n")
            
    print(f"🎉 修复完成！成功进行了 {fixed_count} 处人工指派的精准替换操作！")
    print(f"📁 最终成果文件绝对安全、完美提纯版已保存至: {FINAL_OUT}")
