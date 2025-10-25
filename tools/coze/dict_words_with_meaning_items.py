import pymysql
from typing import TypedDict, List
from flask import jsonify

class MeaningItemData(TypedDict):
    id: str
    ciXing: str
    meaning: str
    popularity: int

class WordWithMeaningItems(TypedDict):
    wordId: str
    spell: str
    meaningItems: List[MeaningItemData]

def query_words_with_meaning_items(limit: int) -> dict:
    """查询通用词典的单词及其释义项"""
    db_host = 'localhost'
    db_port = 3306
    db_user = 'root'
    db_password = 'root'
    db_name = 'bdc'

    connection = pymysql.connect(
        host=db_host,
        port=db_port,
        user=db_user,
        password=db_password,
        database=db_name,
        charset='utf8mb4'
    )
    
    try:
        with connection.cursor() as cursor:
            # 查询通用词典（dictId = '0'）的释义项
            # 只查询未更新或更新超时的数据
            cursor.execute("""
                SELECT 
                    w.id as wordId,
                    w.spell,
                    mi.id as meaningItemId,
                    mi.ciXing,
                    mi.meaning,
                    IFNULL(mi.popularity, 999) as popularity
                FROM word w
                JOIN meaning_item mi ON mi.wordId = w.id
                WHERE mi.dictId = '0'
                and (mi.updateTime is null or mi.updateTime<'2025-10-08 17:00:00') # 数据是老版本
                AND (mi.isUpdating = 0 OR TIMESTAMPDIFF(HOUR, mi.updatingStartAt, NOW()) >= 2) # 数据不是正在更新
                ORDER BY w.spell, mi.popularity, mi.createTime
                LIMIT %s
            """, (limit * 20,))
            
            results = cursor.fetchall()
            
            # 按单词分组
            words_dict = {}
            for row in results:
                word_id, spell, meaning_id, ci_xing, meaning, popularity = row
                
                if word_id not in words_dict:
                    words_dict[word_id] = {
                        'wordId': word_id,
                        'spell': spell,
                        'meaningItems': []
                    }
                
                words_dict[word_id]['meaningItems'].append({
                    'id': meaning_id,
                    'ciXing': ci_xing if ci_xing else '',
                    'meaning': meaning,
                    'popularity': popularity
                })
            
            # 只取前 limit 个单词
            words = list(words_dict.values())[:limit]
            
            # 收集所有需要标记的 meaning_item id
            all_meaning_ids = []
            for word in words:
                for mi in word['meaningItems']:
                    all_meaning_ids.append(mi['id'])
            
            # 标记为正在更新
            if all_meaning_ids:
                placeholders = ','.join(['%s'] * len(all_meaning_ids))
                cursor.execute(
                    f"UPDATE meaning_item SET isUpdating = 1, updatingStartAt = NOW() WHERE id IN ({placeholders})",
                    all_meaning_ids
                )
                connection.commit()
            
            return {
                "success": True,
                "words": words,
                "totalWords": len(words),
                "totalMeaningItems": len(all_meaning_ids)
            }
            
    except Exception as e:
        return {"success": False, "error": str(e)}
    finally:
        connection.close()

def query_words_with_meaning_items_handler(params):
    """查询单词及释义项的HTTP处理器"""
    try:
        # 从GET参数或POST数据中获取参数
        if hasattr(params, 'get'):  # GET请求的args
            limit_str = params.get('limit', '10')
        else:  # POST请求的JSON数据
            limit_str = params.get('limit', '10')
        
        # 安全地转换limit参数
        try:
            limit = int(limit_str)
        except (ValueError, TypeError):
            return jsonify({"error": "limit参数必须是有效的数字"}), 400
        
        if limit <= 0 or limit > 1000:
            return jsonify({"error": "limit参数必须在1-1000之间"}), 400
            
        result = query_words_with_meaning_items(limit)
        
        # 创建 response 对象并设置 ensure_ascii=False 以显示中文
        from flask import current_app, make_response
        import json
        
        response = make_response(
            json.dumps(result, ensure_ascii=False, indent=2),
            200 if result.get('success') else 500
        )
        response.headers['Content-Type'] = 'application/json; charset=utf-8'
        return response
            
    except Exception as e:
        return jsonify({"error": str(e)}), 500

