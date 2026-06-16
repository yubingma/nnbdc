import os
import psycopg2
import time
import sys

def hamming_distance(a, b):
    # Fast Hamming distance for 256-byte arrays
    dist = 0
    for x, y in zip(a, b):
        xor = x ^ y
        # popcount
        dist += bin(xor).count('1')
    return dist

def run_signature_filtered_tsp(words, dims, m=100):
    n = len(words)
    # Prebuild 64-bit signatures as lists of two 32-bit ints (or one 64-bit int)
    signatures = []
    for spell, emb in words:
        sig = 0
        for i, dim in enumerate(dims):
            byte_idx = dim // 8
            bit_idx = dim % 8
            is_one = (emb[byte_idx] & (1 << bit_idx)) != 0
            if is_one:
                sig |= (1 << i)
        signatures.append(sig)
        
    visited = [False] * n
    path = []
    
    curr = 0
    path.append(curr)
    visited[curr] = True
    
    for _ in range(1, n):
        sig_a = signatures[curr]
        emb_a = words[curr][1]
        
        # 1. 64-bit Signature XOR Popcount rough filter to find M candidates
        candidates = []
        for i in range(n):
            if visited[i]:
                continue
            sig_b = signatures[i]
            # 64-bit popcount on XOR
            dist_sig = bin(sig_a ^ sig_b).count('1')
            candidates.append((i, dist_sig))
            
        candidates.sort(key=lambda x: x[1])
        top_candidates = candidates[:m]
        
        # 2. Exact Hamming distance among M candidates to choose closest neighbor
        min_hamming = 999999
        next_idx = -1
        for idx, _ in top_candidates:
            dist = hamming_distance(emb_a, words[idx][1])
            if dist < min_hamming:
                min_hamming = dist
                next_idx = idx
                
        if next_idx == -1:
            break
        curr = next_idx
        path.append(curr)
        visited[curr] = True
        
    return path

def optimize_path_2opt(path, words, window_size=15):
    n = len(path)
    optimized = list(path)
    improved = True
    
    for _ in range(3):
        if not improved:
            break
        improved = False
        for i in range(n - 3):
            end = min(i + window_size, n - 2)
            for j in range(i + 2, end + 1):
                idx_i = optimized[i]
                idx_i1 = optimized[i + 1]
                idx_j = optimized[j]
                idx_j1 = optimized[j + 1]
                
                old_dist = hamming_distance(words[idx_i][1], words[idx_i1][1]) + \
                           hamming_distance(words[idx_j][1], words[idx_j1][1])
                new_dist = hamming_distance(words[idx_i][1], words[idx_j][1]) + \
                           hamming_distance(words[idx_i1][1], words[idx_j1][1])
                           
                if new_dist < old_dist:
                    # Reverse segment from i+1 to j
                    optimized[i+1:j+1] = reversed(optimized[i+1:j+1])
                    improved = True
                    
    return optimized

def calculate_metrics(path, words):
    total_dist = 0
    max_dist = 0
    for i in range(len(path) - 1):
        dist = hamming_distance(words[path[i]][1], words[path[i+1]][1])
        total_dist += dist
        if dist > max_dist:
            max_dist = dist
    avg_dist = total_dist / (len(path) - 1) if len(path) > 1 else 0.0
    return avg_dist, max_dist

def main():
    conn = psycopg2.connect(
        host="127.0.0.1",
        port=5432,
        user="myb",
        password="myb",
        database="bdc"
    )
    cursor = conn.cursor()
    
    cursor.execute("SELECT table_name FROM information_schema.tables WHERE table_schema='public'")
    tables = [row[0] for row in cursor.fetchall()]
    table_name = "word" if "word" in tables else "words"
    
    cursor.execute(f"SELECT column_name FROM information_schema.columns WHERE table_name='{table_name}'")
    columns = [row[0] for row in cursor.fetchall()]
    col_name = "embedding_1bit" if "embedding_1bit" in columns else "embedding1bit"
    
    cursor.execute(f"SELECT spell, {col_name} FROM {table_name} WHERE {col_name} IS NOT NULL AND spell IS NOT NULL LIMIT 5000")
    rows = cursor.fetchall()
    
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
        
    print(f"评估子集已加载，共 {len(words)} 个词。")
    
    # Dimensions to compare
    current_64 = [
        1897, 1105, 515, 511, 1852, 146, 1958, 252, 1630, 1420,
        1327, 1868, 454, 1805, 892, 1428, 1947, 35, 477, 855,
        1067, 1219, 381, 1879, 211, 486, 718, 29, 404, 986,
        787, 1312, 1059, 1429, 937, 503, 1913, 1921, 589, 598,
        969, 1071, 617, 440, 940, 1494, 18, 68, 874, 1800,
        1469, 783, 1863, 463, 972, 1514, 458, 1893, 1480, 1686,
        1096, 561, 723, 1039
    ]
    
    new_64 = [
        1319, 1115, 1596, 1897, 1278, 564, 3, 140, 568, 486, 1469, 1852, 1327, 1950, 53, 1630, 356, 779, 2020, 1322,
        493, 1161, 667, 458, 1173, 146, 625, 477, 874, 1169, 1442, 920, 1527, 1913, 395, 1474, 548, 1740, 533, 19,
        1217, 29, 511, 1420, 825, 230, 642, 521, 703, 877, 1615, 613, 128, 515, 1112, 1280, 749, 68, 454, 116,
        1479, 1529, 1921, 1381
    ]
    
    # Test on subset sizes
    for size in [1000, 2000, 5000]:
        if size > len(words):
            break
        print(f"\n--- 测试规模: N = {size} ---")
        subset = words[:size]
        
        # Run current_64
        t0 = time.time()
        path_cur = run_signature_filtered_tsp(subset, current_64, m=100)
        path_cur_opt = optimize_path_2opt(path_cur, subset)
        t_cur = (time.time() - t0) * 1000.0
        avg_cur, max_cur = calculate_metrics(path_cur_opt, subset)
        
        # Run new_64
        t0 = time.time()
        path_new = run_signature_filtered_tsp(subset, new_64, m=100)
        path_new_opt = optimize_path_2opt(path_new, subset)
        t_new = (time.time() - t0) * 1000.0
        avg_new, max_new = calculate_metrics(path_new_opt, subset)
        
        print("当前 64 维度:")
        print(f"  - 平均相邻汉明距离: {avg_cur:.3f}")
        print(f"  - 最大相邻汉明距离: {max_cur}")
        print(f"  - 计算耗时: {t_cur:.2f} ms")
        
        print("最新 64 黄金维度:")
        print(f"  - 平均相邻汉明距离: {avg_new:.3f} ({(avg_new - avg_cur):+.3f})")
        print(f"  - 最大相邻汉明距离: {max_new} ({max_new - max_cur:+=})")
        print(f"  - 计算耗时: {t_new:.2f} ms")
        
    cursor.close()
    conn.close()

if __name__ == "__main__":
    main()
