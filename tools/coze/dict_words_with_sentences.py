import psycopg2
from psycopg2.extras import RealDictCursor
from typing import TypedDict, List
from flask import jsonify

class Sentence(TypedDict):
    sentenceId: int
    englishRaw: str
    chineseRaw: str
    wordMeaning: str

class WordWithSentences(TypedDict):
    wordId: int
    wordSpell: str
    sentences: List[Sentence]

def query_dict_words_with_sentences(dictName: str, limit: int) -> dict:
    """查询词典单词及其例句的核心函数"""
    db_host = 'localhost'
    db_port = 5432
    db_user = 'root'
    db_password = 'root'
    db_name = 'bdc'

    connection = psycopg2.connect(
        host=db_host,
        port=db_port,
        user=db_user,
        password=db_password,
        database=db_name
    )
    
    try:
        with connection.cursor(cursor_factory=RealDictCursor) as cursor:
            # 第一步：查询指定数量的单词（不包含例句）
            if dictName == '通用词典':
                sql_words = """
                SELECT DISTINCT w.id as wordId, w.spell as wordSpell
                FROM sentence s
                LEFT JOIN meaning_item mi ON mi.id = s.meaningItemId
                LEFT JOIN word w ON w.id = mi.wordId
                WHERE mi.dictId = '0'
                and (s.updateTime is null or s.updateTime<'2025-08-30 00:00:00') -- 数据是老版本
                and (s.isUpdating = 0 or EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - s.updatingStartAt))/3600 >= 2) -- 数据不是正在更新 
                ORDER BY w.id
                LIMIT %s
                """
                cursor.execute(sql_words, (limit,))
            else:
                sql_words = """
                SELECT DISTINCT w.id as wordId, w.spell as wordSpell
                FROM sentence s
                LEFT JOIN meaning_item mi ON mi.id = s.meaningItemId
                LEFT JOIN word w ON w.id = mi.wordId
                left join dict d on d.id = mi.dictId
                WHERE d.name = %s
                and (s.updateTime is null or s.updateTime<'2025-08-30 00:00:00') -- 数据是老版本
                and (s.isUpdating = 0 or EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - s.updatingStartAt))/3600 >= 2) -- 数据不是正在更新    
                ORDER BY w.id
                LIMIT %s
                """
                cursor.execute(sql_words, (dictName, limit))
            
            word_results = cursor.fetchall()
            words = []

            # 第二步：为每个单词查询所有例句
            for word_row in word_results:
                word_id = word_row['wordId']
                
                # 查询该单词的所有例句
                if dictName == '通用词典':
                    sql_sentences = """
                    SELECT s.id as sentenceId, s.english as englishRaw, s.chinese as chineseRaw, s.wordMeaning
                    FROM sentence s
                    LEFT JOIN meaning_item mi ON mi.id = s.meaningItemId
                    WHERE mi.wordId = %s AND mi.dictId = '0'
                    ORDER BY s.id
                    """
                    cursor.execute(sql_sentences, (word_id,))
                else:
                    sql_sentences = """
                    SELECT s.id as sentenceId, s.english as englishRaw, s.chinese as chineseRaw, s.wordMeaning
                    FROM sentence s
                    LEFT JOIN meaning_item mi ON mi.id = s.meaningItemId
                    left join dict d on d.id = mi.dictId
                    WHERE mi.wordId = %s AND d.name = %s
                    ORDER BY s.id
                    """
                    cursor.execute(sql_sentences, (word_id, dictName))
                
                sentence_results = cursor.fetchall()
                sentences = []
                
                for sentence_row in sentence_results:
                    sentence = Sentence(
                        sentenceId=sentence_row['sentenceId'],
                        englishRaw=sentence_row['englishRaw'],
                        chineseRaw=sentence_row['chineseRaw'],
                        wordMeaning=sentence_row['wordMeaning']
                    )
                    sentences.append(sentence)
                
                # 创建单词对象
                word = WordWithSentences(
                    wordId=word_row['wordId'],
                    wordSpell=word_row['wordSpell'],
                    sentences=sentences
                )
                words.append(word)

                # 给数据至正在更新标记, 避免重复更新
                ids = [item['sentenceId'] for item in sentences]
                if ids:
                    cursor.execute("UPDATE sentence SET isUpdating = 1, updatingStartAt=CURRENT_TIMESTAMP WHERE id IN (%s)" % ','.join(['%s'] * len(ids)), ids)
                    connection.commit()
            
            return {"dictName": dictName, "words": words}
    finally:
        connection.close()

def query_dict_words_with_sentences_handler(params):
    """词典单词例句查询服务的HTTP处理器"""
    try:
        # 从GET参数或POST数据中获取参数
        if hasattr(params, 'get'):  # GET请求的args
            dict_name = params.get('dictName', '通用词典')
            limit_str = params.get('limit', '10')
        else:  # POST请求的JSON数据
            dict_name = params.get('dictName', '通用词典')
            limit_str = params.get('limit', '10')
        
        # 安全地转换limit参数
        try:
            limit = int(limit_str)
        except (ValueError, TypeError):
            return jsonify({"error": "limit参数必须是有效的数字"}), 400
        
        if limit <= 0 or limit > 1000:
            return jsonify({"error": "limit参数必须在1-1000之间"}), 400
            
        result = query_dict_words_with_sentences(dict_name, limit)
        return jsonify(result)
    except Exception as e:
        return jsonify({"error": str(e)}), 500
