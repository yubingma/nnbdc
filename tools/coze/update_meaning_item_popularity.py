import pymysql
from typing import TypedDict, List
from flask import jsonify

class MeaningItemUpdate(TypedDict):
    id: str
    popularity: int

class UpdateMeaningItemsRequest(TypedDict):
    meaningItems: List[MeaningItemUpdate]

def update_meaning_item_popularity(request_data: UpdateMeaningItemsRequest) -> dict:
    """批量更新释义项的 popularity"""
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
        charset='utf8mb4',
        cursorclass=pymysql.cursors.DictCursor
    )
    
    try:
        with connection.cursor() as cursor:
            meaning_items = request_data.get('meaningItems', [])
            if not meaning_items:
                return {"error": "没有提供释义项数据"}
            
            updated_count = 0
            failed_count = 0
            
            for item in meaning_items:
                meaning_id = item.get('id')
                popularity = item.get('popularity')
                
                if not meaning_id:
                    failed_count += 1
                    continue
                
                # popularity 可以为 None，表示不更新
                if popularity is None:
                    popularity = 999  # 默认值
                
                try:
                    # 更新 popularity，同时清除更新标记
                    sql = """
                    UPDATE meaning_item 
                    SET popularity = %s,
                        updateTime = NOW(),
                        isUpdating = 0,
                        updatingStartAt = NULL
                    WHERE id = %s
                    """
                    
                    cursor.execute(sql, (popularity, meaning_id))
                    if cursor.rowcount > 0:
                        updated_count += 1
                    else:
                        failed_count += 1
                        
                except Exception as e:
                    failed_count += 1
                    print(f"更新释义项 {meaning_id} 失败: {str(e)}")
            
            connection.commit()
            
            return {
                "success": True,
                "message": f"成功更新 {updated_count} 条释义项数据",
                "updatedCount": updated_count,
                "failedCount": failed_count,
                "totalCount": len(meaning_items)
            }
            
    except Exception as e:
        connection.rollback()
        return {"success": False, "error": f"更新失败: {str(e)}"}
    finally:
        connection.close()

def update_meaning_item_popularity_handler(params):
    """更新释义项 popularity 的HTTP处理器"""
    try:
        # 验证请求数据
        if not isinstance(params, dict):
            return jsonify({"error": "请求数据格式错误"}), 400
        
        meaning_items = params.get('meaningItems')
        if not meaning_items or not isinstance(meaning_items, list):
            return jsonify({"error": "meaningItems字段必须是数组"}), 400
        
        # 验证每个释义项数据的格式
        for item in meaning_items:
            if not isinstance(item, dict):
                return jsonify({"error": "释义项数据格式错误"}), 400
            
            item_id = item.get('id')
            if not item_id:
                return jsonify({"error": "id字段不能为空"}), 400
            
            popularity = item.get('popularity')
            if popularity is not None and not isinstance(popularity, int):
                return jsonify({"error": "popularity字段必须是整数"}), 400
        
        result = update_meaning_item_popularity(params)
        
        if result.get('success'):
            return jsonify(result)
        else:
            return jsonify(result), 500
            
    except Exception as e:
        return jsonify({"error": str(e)}), 500

