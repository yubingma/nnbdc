import os
import psycopg2
import sys

def edit_distance(s1, s2):
    m, n = len(s1), len(s2)
    prev = list(range(n + 1))
    curr = [0] * (n + 1)
    for i in range(1, m + 1):
        curr[0] = i
        for j in range(1, n + 1):
            if s1[i - 1] == s2[j - 1]:
                curr[j] = prev[j - 1]
            else:
                curr[j] = 1 + min(prev[j], curr[j - 1], prev[j - 1])
        prev, curr = curr, prev
    return prev[n]

def is_morphological_pair(s1, s2):
    if s1 == s2:
        return False
    if len(s1) < 4 or len(s2) < 4:
        return False
    if s1[:4].lower() != s2[:4].lower():
        return False
    if abs(len(s1) - len(s2)) > 3:
        return False
    return edit_distance(s1, s2) <= 3

def main():
    conn = psycopg2.connect(
        host="127.0.0.1",
        port=5432,
        user="myb",
        password="myb",
        database="bdc"
    )
    cursor = conn.cursor()
    print("成功连接到 PostgreSQL bdc 数据库。")
    
    cursor.execute("SELECT table_name FROM information_schema.tables WHERE table_schema='public'")
    tables = [row[0] for row in cursor.fetchall()]
    table_name = "word" if "word" in tables else "words"
    
    cursor.execute(f"SELECT column_name FROM information_schema.columns WHERE table_name='{table_name}'")
    columns = [row[0] for row in cursor.fetchall()]
    col_name = "embedding_1bit" if "embedding_1bit" in columns else "embedding1bit"
    
    cursor.execute(f"SELECT spell, {col_name} FROM {table_name} WHERE {col_name} IS NOT NULL AND spell IS NOT NULL")
    rows = cursor.fetchall()
    print(f"成功查询到 {len(rows)} 个有效单词的拼写和嵌入。")
    
    # Pre-parse word records
    words = []
    for spell, val in rows:
        if isinstance(val, memoryview):
            emb_bytes = val.tobytes()
        elif isinstance(val, bytes):
            emb_bytes = val
        else:
            emb_bytes = bytes.fromhex(val)
        if len(emb_bytes) < 256:
            continue
        words.append((spell, emb_bytes))
        
    print(f"有效加载 {len(words)} 个有完整 256B 嵌入的单词。")
    
    # 1. 提取局部形态近邻词对
    print("正在提取局部形态近邻词对...")
    groups = {}
    for i, (spell, _) in enumerate(words):
        if len(spell) >= 4:
            prefix = spell[:4].lower()
            groups.setdefault(prefix, []).append(i)
            
    pairs = []
    for prefix, indices in groups.items():
        n_indices = len(indices)
        for i in range(n_indices):
            for j in range(i + 1, n_indices):
                idx_a = indices[i]
                idx_b = indices[j]
                if is_morphological_pair(words[idx_a][0], words[idx_b][0]):
                    pairs.append((idx_a, idx_b))
                    
    print(f"共提取到 {len(pairs)} 对形态近邻词对。")
    if not pairs:
        print("未提取到有效词对，计算终止。")
        return
        
    # Print sample pairs
    print("近邻词对示例:")
    for i in range(min(10, len(pairs))):
        p = pairs[i]
        print(f"  - {words[p[0]][0]} <-> {words[p[1]][0]}")
        
    # 2. 计算 2048 维度的 1占比与翻转率
    print("\n正在计算 2048 个维度的占比与近邻翻转率...")
    counts = [0] * 2048
    for _, emb in words:
        for d in range(2048):
            byte_idx = d // 8
            bit_idx = d % 8
            if (emb[byte_idx] & (1 << bit_idx)) != 0:
                counts[d] += 1
                
    entropy_ratios = [c / len(words) for c in counts]
    
    flip_counts = [0] * 2048
    for idx_a, idx_b in pairs:
        emb_a = words[idx_a][1]
        emb_b = words[idx_b][1]
        for d in range(2048):
            byte_idx = d // 8
            bit_idx = d % 8
            bit_a = (emb_a[byte_idx] & (1 << bit_idx)) != 0
            bit_b = (emb_b[byte_idx] & (1 << bit_idx)) != 0
            if bit_a != bit_b:
                flip_counts[d] += 1
                
    flip_rates = [fc / len(pairs) for fc in flip_counts]
    
    # 3. 筛选高熵且低噪声的维度
    # 高熵定义: 1占比在 0.35 到 0.65 之间
    candidates = []
    for d in range(2048):
        ratio = entropy_ratios[d]
        flip = flip_rates[d]
        if 0.35 <= ratio <= 0.65:
            candidates.append((d, ratio, flip))
            
    # 按翻转率从低到高排序
    candidates.sort(key=lambda x: x[2])
    
    new_64 = [c[0] for c in candidates[:64]]
    
    print("\n=== 新筛选的 64 位【高熵低噪】黄金维度数组 ===")
    print(new_64)
    
    print("\n前 15 个筛选维度详情 (维度, 1占比, 翻转率):")
    for d, rat, flip in candidates[:15]:
        print(f"  - Dim {d:4d}: 1占比={rat:.3f}, 近邻翻转率={flip:.3f}")
        
    # 当前客户端使用的维度 (new64)
    current_64 = [
        1897, 1105, 515, 511, 1852, 146, 1958, 252, 1630, 1420,
        1327, 1868, 454, 1805, 892, 1428, 1947, 35, 477, 855,
        1067, 1219, 381, 1879, 211, 486, 718, 29, 404, 986,
        787, 1312, 1059, 1429, 937, 503, 1913, 1921, 589, 598,
        969, 1071, 617, 440, 940, 1494, 18, 68, 874, 1800,
        1469, 783, 1863, 463, 972, 1514, 458, 1893, 1480, 1686,
        1096, 561, 723, 1039
    ]
    
    overlap = len(set(new_64).intersection(set(current_64)))
    print(f"\n新计算的 64 维度与当前客户端所用 64 维度的重合度: {overlap} / 64")
    
    cursor.close()
    conn.close()

if __name__ == "__main__":
    main()
