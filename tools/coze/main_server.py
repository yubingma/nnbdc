#!/usr/bin/env python3
"""
主服务器文件 - 注册所有API服务并启动HTTP服务器
"""

# 导入HTTP服务器框架
from http_server import register_service, start_server

# 导入各个服务模块
from dict_meaning_items import query_dict_meaning_items_handler
from dict_words_with_sentences import query_dict_words_with_sentences_handler
from update_word_sentences_word_meaning import update_word_sentences_word_meaning_handler
from dict_words_with_meaning_items import query_words_with_meaning_items_handler
from update_meaning_item_popularity import update_meaning_item_popularity_handler

def main():
    """注册所有服务并启动服务器"""
    
    # 注册词典查询服务
    register_service(
        route='/api/query_dict_meaning_items',
        service_func=query_dict_meaning_items_handler,
        methods=['GET', 'POST']
    )
    
    # 注册词典单词例句查询服务
    register_service(
        route='/api/query_dict_words_with_sentences',
        service_func=query_dict_words_with_sentences_handler,
        methods=['GET', 'POST']
    )
    
    # 注册例句数据更新服务
    register_service(
        route='/api/update_word_sentences_word_meaning',
        service_func=update_word_sentences_word_meaning_handler,
        methods=['POST']
    )
    
    # 注册单词释义项查询服务
    register_service(
        route='/api/query_words_with_meaning_items',
        service_func=query_words_with_meaning_items_handler,
        methods=['GET', 'POST']
    )
    
    # 注册释义项 popularity 更新服务
    register_service(
        route='/api/update_meaning_item_popularity',
        service_func=update_meaning_item_popularity_handler,
        methods=['POST']
    )
    
    # 在这里可以继续注册更多服务
    # register_service('/api/other_service', other_service_handler)
    
    # 启动服务器
    start_server(host='0.0.0.0', port=5001, debug=True)

if __name__ == '__main__':
    main()
