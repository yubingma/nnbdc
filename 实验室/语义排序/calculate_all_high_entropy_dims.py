import os
import psycopg2

def main():
    # PostgreSQL Connection parameters from environment or defaults
    conn = psycopg2.connect(
        host="127.0.0.1",
        port=5432,
        user="myb",
        password="myb",
        database="bdc"
    )
    
    cursor = conn.cursor()
    print("成功连接到 PostgreSQL bdc 数据库。")
    
    # Inspect tables to see if it's 'word' or 'words'
    cursor.execute("SELECT table_name FROM information_schema.tables WHERE table_schema='public'")
    tables = [row[0] for row in cursor.fetchall()]
    print(f"数据库中的公开表: {tables}")
    
    table_name = "word" if "word" in tables else ("words" if "words" in tables else None)
    if not table_name:
        raise Exception(f"未在数据库中找到 'word' 或 'words' 表，可用表有: {tables}")
        
    print(f"正在查询表: {table_name}")
    
    # Check column names
    cursor.execute(f"SELECT column_name FROM information_schema.columns WHERE table_name='{table_name}'")
    columns = [row[0] for row in cursor.fetchall()]
    print(f"{table_name} 表的字段: {columns}")
    
    col_name = "embedding_1bit" if "embedding_1bit" in columns else ("embedding1bit" if "embedding1bit" in columns else None)
    if not col_name:
        raise Exception(f"未找到嵌入向量字段，可用列有: {columns}")
        
    cursor.execute(f"SELECT {col_name} FROM {table_name} WHERE {col_name} IS NOT NULL")
    rows = cursor.fetchall()
    print(f"成功查询到 {len(rows)} 个有效单词的嵌入。")
    
    # 2048 dimensions
    counts = [0] * 2048
    
    for row in rows:
        val = row[0]
        if isinstance(val, memoryview):
            emb_bytes = val.tobytes()
        elif isinstance(val, bytes):
            emb_bytes = val
        else:
            emb_bytes = bytes.fromhex(val)
        # 256 bytes = 2048 bits
        for d in range(2048):
            byte_idx = d // 8
            bit_idx = d % 8
            if (emb_bytes[byte_idx] & (1 << bit_idx)) != 0:
                counts[d] += 1
                
    # Calculate deviation from 0.5 ratio
    total_words = len(rows)
    deviations = []
    for d in range(2048):
        ratio = counts[d] / total_words
        deviation = abs(ratio - 0.5)
        deviations.append((d, deviation, ratio))
        
    # Sort by deviation ascending
    deviations.sort(key=lambda x: x[1])
    
    # Take top 64 dims
    top_64 = deviations[:64]
    
    # Print the resulting indices
    indices = [d[0] for d in top_64]
    print("\n--- 70000/47000词全库计算结果 ---")
    print(f"选取的 64 位高熵索引列表（按信息量排序）:")
    print(indices)
    
    # Verify values
    print("\n排名前 10 的特征维度详情 (维度, 偏离度, 1的比例):")
    for d, dev, rat in top_64[:10]:
        print(f"Dim {d}: Deviation = {dev:.4f}, Ratio of 1s = {rat:.4f}")
        
    cursor.close()
    conn.close()

if __name__ == "__main__":
    main()
