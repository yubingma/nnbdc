import pymysql
from typing import TypedDict, List
from flask import jsonify
import json

class SentenceUpdateData(TypedDict):
    sentenceId: int
    popularity: int
    partOfSpeech: str
    wordMeaning: str

class UpdateWordSentencesRequest(TypedDict):
    sentences: List[SentenceUpdateData]

def update_word_sentences_word_meaning(request_data: UpdateWordSentencesRequest) -> dict:
    """更新例句表的单词释义数据"""
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
 
            
            # 批量更新例句数据
            sentences = request_data.get('sentences', [])
            if not sentences:
                return {"error": "没有提供例句数据"}
            
            updated_count = 0
            for sentence_data in sentences:
                sentence_id = sentence_data.get('sentenceId')
                popularity = sentence_data.get('popularity', 0)
                part_of_speech = sentence_data.get('partOfSpeech', '')
                word_meaning = sentence_data.get('wordMeaning', '')
                
                if not sentence_id:
                    continue
                
                # 更新例句数据
                sql = """
                UPDATE sentence 
                SET popularity = %s, 
                    partOfSpeech = %s, 
                    wordMeaning = %s, 
                    updateTime = NOW(),
                    isUpdating = 0,
                    updatingStartAt = NULL
                WHERE id = %s
                """
                
                cursor.execute(sql, (popularity, part_of_speech, word_meaning, sentence_id))
                if cursor.rowcount > 0:
                    updated_count += 1
            
            connection.commit()
            
            return {
                "success": True,
                "message": f"成功更新 {updated_count} 条例句数据",
                "updatedCount": updated_count,
                "totalCount": len(sentences)
            }
            
    except Exception as e:
        connection.rollback()
        return {"error": f"更新失败: {str(e)}"}
    finally:
        connection.close()

def update_word_sentences_word_meaning_handler(params):
    """单词例句释义更新服务的HTTP处理器"""
    try:

        
        # 验证请求数据
        if not isinstance(params, dict):
            return jsonify({"error": "请求数据格式错误"}), 400
        
        sentences = params.get('sentences')
        if not sentences or not isinstance(sentences, list):
            return jsonify({"error": "sentences字段必须是数组"}), 400
        
        # 验证每个例句数据的格式
        for sentence in sentences:
            if not isinstance(sentence, dict):
                return jsonify({"error": "例句数据格式错误"}), 400
            
            sentence_id = sentence.get('sentenceId')
            if not sentence_id:
                return jsonify({"error": "sentenceId字段不能为空"}), 400
            
            popularity = sentence.get('popularity')
            if popularity is not None and not isinstance(popularity, int):
                return jsonify({"error": "popularity字段必须是整数"}), 400
            
            part_of_speech = sentence.get('partOfSpeech')
            if part_of_speech is not None and not isinstance(part_of_speech, str):
                return jsonify({"error": "partOfSpeech字段必须是字符串"}), 400
            
            word_meaning = sentence.get('wordMeaning')
            if word_meaning is not None and not isinstance(word_meaning, str):
                return jsonify({"error": "wordMeaning字段必须是字符串"}), 400
        
        result = update_word_sentences_word_meaning(params)
        return jsonify(result)
        
    except Exception as e:
        return jsonify({"error": str(e)}), 500



