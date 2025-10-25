#!/bin/bash

# 词典API服务器启动脚本

echo "=== 词典API服务器启动脚本 ==="
echo ""

# 检查Python环境
if ! command -v python3 &> /dev/null; then
    echo "错误: 未找到Python3，请先安装Python3"
    exit 1
fi

# 检查依赖包
echo "检查依赖包..."
python3 -c "import flask, pymysql" 2>/dev/null
if [ $? -ne 0 ]; then
    echo "安装依赖包..."
    pip3 install -r requirements.txt
    if [ $? -ne 0 ]; then
        echo "错误: 依赖包安装失败"
        exit 1
    fi
fi

echo ""
echo "启动API服务器..."
echo "服务器地址: http://localhost:5001"
echo "API接口:"
echo "  GET  /api/query_dict_words_with_sentences?dictName=词典名&limit=数量"
echo ""
echo "按 Ctrl+C 停止服务器"
echo ""

# 启动服务器
python3 main_server.py
