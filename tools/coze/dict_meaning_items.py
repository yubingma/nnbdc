import pymysql
from typing import TypedDict
from flask import jsonify

class MeaningItem(TypedDict):
    id: int
    partOfSpeech: str
    meaning: str
    spell: str

def query_dict_meaning_items(dictName: str, limit: int) -> dict:
    """查询词典单词释义的核心函数"""
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
            if dictName == '*':
                cursor.execute("""SELECT mi.id, mi.ciXing, mi.meaning, w.spell FROM meaning_item mi 
                    left join dict d on d.id = mi.dictId
                    left join word w on w.id = mi.word
                    where (mi.updateTime is null or mi.updateTime<'2024-11-02 00:00:00') # 数据是老版本
                    and (mi.isUpdating = 0 or TIMESTAMPDIFF(HOUR, mi.updatingStartAt, now() ) >= 2) # 数据不是正在更新 
                    LIMIT %s """, (limit,))
            else: 
                cursor.execute("""SELECT mi.id, mi.ciXing, mi.meaning, w.spell FROM meaning_item mi 
                    left join dict d on d.id = mi.dictId
                    left join word w on w.id = mi.word
                     where d.name = %s and (mi.updateTime is null or mi.updateTime<'2024-11-02 00:00:00') # 数据是老版本
                     and (mi.isUpdating = 0 or TIMESTAMPDIFF(HOUR, mi.updatingStartAt, now() ) >= 2) # 数据不是正在更新 
                     LIMIT %s """, (dictName,limit,))
            result = cursor.fetchall()
            meaningItems = [MeaningItem(id=row[0], partOfSpeech=row[1], meaning=row[2], spell=row[3]) for row in result]

            # 给数据至正在更新标记, 避免重复更新
            ids = [item['id'] for item in meaningItems]
            if ids:
                cursor.execute("UPDATE meaning_item SET isUpdating = 1, updatingStartAt=now() WHERE id IN (%s)" % ','.join(['%s'] * len(ids)), ids)
                connection.commit()
            
            return {"dictName": dictName, "meaningItems": meaningItems}
    finally:
        connection.close()

def query_dict_meaning_items_handler(params):
    """词典查询服务的HTTP处理器"""
    try:
        # 从GET参数或POST数据中获取参数
        if hasattr(params, 'get'):  # GET请求的args
            dict_name = params.get('dictName', '*')
            limit_str = params.get('limit', '10')
        else:  # POST请求的JSON数据
            dict_name = params.get('dictName', '*')
            limit_str = params.get('limit', '10')
        
        # 安全地转换limit参数
        try:
            limit = int(limit_str)
        except (ValueError, TypeError):
            return jsonify({"error": "limit参数必须是有效的数字"}), 400
        
        if limit <= 0 or limit > 1000:
            return jsonify({"error": "limit参数必须在1-1000之间"}), 400
            
        result = query_dict_meaning_items(dict_name, limit)
        return jsonify(result)
    except Exception as e:
        return jsonify({"error": str(e)}), 500
