import os

# 读取抓取到的专八单词
words_file = "/Volumes/ssd/ppdc/tools/book/专八/专八2000核心词汇表.txt"
if not os.path.exists(words_file):
    print(f"Error: {words_file} not found.")
    exit(1)

words = []
with open(words_file, "r", encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        if "|" in line:
            word = line.split("|", 1)[1].strip()
        else:
            word = line
        if word:
            words.append(word)

print(f"Loaded {len(words)} words from file.")

# 生成 SQL
sql_file = "/Volumes/ssd/ppdc/tools/book/scratch/check_words.sql"
with open(sql_file, "w", encoding="utf-8") as f:
    f.write("CREATE TEMP TABLE temp_check_words (spell text);\n")
    f.write("INSERT INTO temp_check_words (spell) VALUES\n")
    # 转义单引号以防 SQL 语法错误
    escaped_values = []
    for w in words:
        escaped_w = w.replace("'", "''")
        escaped_values.append(f"('{escaped_w}')")
    
    f.write(",\n".join(escaped_values))
    f.write(";\n\n")
    
    # 统计已存在单词的数量
    f.write("SELECT 'EXISTS_COUNT' as marker, COUNT(*) FROM temp_check_words WHERE spell IN (SELECT spell FROM word);\n")
    
    # 列出不存在的单词
    f.write("SELECT 'NOT_FOUND' as marker, spell FROM temp_check_words WHERE spell NOT IN (SELECT spell FROM word) ORDER BY spell;\n")

print(f"SQL file generated at {sql_file}")
