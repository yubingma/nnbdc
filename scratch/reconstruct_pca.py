import sys
import json
import numpy as np

def pca_3d(X):
    mean = np.mean(X, axis=0)
    X_centered = X - mean
    # 协方差矩阵
    cov = np.cov(X_centered, rowvar=False)
    # 特征分解
    eigenvalues, eigenvectors = np.linalg.eigh(cov)
    # 降序排列
    idx = np.argsort(eigenvalues)[::-1]
    eigenvectors = eigenvectors[:, idx]
    # 前 3 个主成分
    W = eigenvectors[:, :3]
    projected = np.dot(X_centered, W)
    return projected, W, mean

def main():
    if len(sys.argv) < 3:
        print("Usage: python reconstruct_pca.py <input_json_path> <output_json_path>")
        sys.exit(1)
        
    input_path = sys.argv[1]
    output_path = sys.argv[2]
    
    # 读取输入高维向量
    with open(input_path, 'r', encoding='utf-8') as f:
        data = json.load(f)
        
    if not data:
        print("Error: Input data is empty")
        sys.exit(1)
        
    word_ids = [item['id'] for item in data]
    embeddings = np.array([item['embedding'] for item in data], dtype=np.float32)
    
    print(f"正在进行 PCA 降维拟合，样本数: {len(embeddings)}, 维度: {embeddings.shape[1]}...")
    
    # 如果样本数量少于 3 个，PCA 无法计算 3 维投影。我们将通过填充零或者简单投影解决
    if len(embeddings) < 3:
        print("Warning: Sample count is less than 3, fallback to simple projection")
        mean = np.mean(embeddings, axis=0) if len(embeddings) > 0 else np.zeros(1024, dtype=np.float32)
        W = np.zeros((1024, 3), dtype=np.float32)
        W[0, 0] = 1.0
        W[1, 1] = 1.0
        W[2, 2] = 1.0
        projected = np.dot(embeddings - mean, W)
    else:
        projected, W, mean = pca_3d(embeddings)
        
    print("降维矩阵拟合完成，正在生成输出结果...")
    
    # 构造输出坐标 Map
    word_coords = {}
    for idx, word_id in enumerate(word_ids):
        word_coords[word_id] = projected[idx].tolist()
        
    output_data = {
        "mean": mean.tolist(),
        "components": W.tolist(),
        "word_coords": word_coords,
        "fittedWordCount": len(word_ids)
    }
    
    # 写入输出 JSON
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(output_data, f)
        
    print(f"重构降维完成！结果已写入: {output_path}")

if __name__ == "__main__":
    main()
