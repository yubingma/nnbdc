#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
验证后端 PostgreSQL 数据库所有词书的单词顺序号是否连续
检查dict_word表中的seq字段是否从1开始连续编号
检查dict表中的wordCount字段是否与dict_word表中实际单词数量一致
检测用户日志表中的数据库版本，确保不大于用户的当前数据库版本
检查词书学习进度不得大于词书单词数量
检查通用词典（id='0'）的所有单词都有释义项，且每个释义项都有例句
"""

import psycopg2
import sys
import traceback
from datetime import datetime

# 数据库配置
DB_CONFIG = {
    'host': 'localhost',
    'port': 5432,
    'user': 'root',
    'password': 'root',
    'database': 'bdc'
}

def connect_db():
    """连接数据库"""
    try:
        db = psycopg2.connect(**DB_CONFIG)
        return db
    except Exception as e:
        print(f"❌ 数据库连接失败: {e}")
        sys.exit(1)

def get_all_dicts(cursor):
    """获取所有词书信息"""
    sql = """
    SELECT id, name, ownerId, wordCount, createTime 
    FROM dict 
    WHERE visible = 1 AND isReady = 1
    ORDER BY createTime DESC
    """
    cursor.execute(sql)
    return cursor.fetchall()

def validate_dict_word_order(cursor, dict_id, dict_name, owner, owner_id, expected_word_count):
    """验证单个词书的单词顺序号和数量"""
    # 获取词书中的所有单词，按seq排序
    sql = """
    SELECT dw.wordId, dw.seq, w.spell
    FROM dict_word dw
    JOIN word w ON dw.wordId = w.id
    WHERE dw.dictId = %s
    ORDER BY dw.seq ASC
    """
    cursor.execute(sql, (dict_id,))
    dict_words = cursor.fetchall()
    
    if not dict_words:
        # 系统词书（owner_id == '15118'）如果为空，是异常情况
        if owner_id == '15118':
            print(f"\n📚 检查词书: {dict_name} (ID: {dict_id}, 所有者: {owner})")
            print(f"   ❌ 系统词书为空，需要删除")
            issue = {
                'type': 'empty_system_dict',
                'expected_count': expected_word_count,
                'actual_count': 0,
                'dict_id': dict_id,
                'dict_name': dict_name,
                'owner_id': owner_id,
                'cached_problem': f"系统词书为空：需要删除该词书"
            }
            return False, [issue]
        
        # 如果词书为空但dict表记录的wordCount不为0，这也是个问题
        if expected_word_count != 0:
            print(f"\n📚 检查词书: {dict_name} (ID: {dict_id}, 所有者: {owner})")
            print(f"   ⚠️  词书为空，但dict表记录wordCount={expected_word_count}")
            issue = {
                'type': 'word_count_mismatch',
                'expected_count': expected_word_count,
                'actual_count': 0,
                'dict_id': dict_id,
                'dict_name': dict_name,
                'owner_id': owner_id,
                'cached_problem': f"单词数量不匹配：实际0个，dict表记录{expected_word_count}个"
            }
            return False, [issue]
        return True, []
    
    total_words = len(dict_words)
    
    issues = []
    cached_problems = []  # 缓存完整的问题信息
    has_printed_header = False  # 标记是否已打印词书标题
    
    # 检查单词数量是否和dict表一致
    if total_words != expected_word_count:
        if not has_printed_header:
            print(f"\n📚 检查词书: {dict_name} (ID: {dict_id}, 所有者: {owner})")
            print(f"   📊 实际单词数: {total_words}, dict表记录: {expected_word_count}")
            has_printed_header = True
        print(f"   ❌ 单词数量不一致: 差异={total_words - expected_word_count}")
        issues.append({
            'type': 'word_count_mismatch',
            'expected_count': expected_word_count,
            'actual_count': total_words,
            'dict_id': dict_id,
            'dict_name': dict_name
        })
        cached_problems.append(f"单词数量不匹配：实际{total_words}个，dict表记录{expected_word_count}个")
    
    # 检查序号是否从1开始
    first_index = dict_words[0][1]
    if first_index != 1:
        if not has_printed_header:
            print(f"\n📚 检查词书: {dict_name} (ID: {dict_id}, 所有者: {owner})")
            print(f"   📊 实际单词数: {total_words}, dict表记录: {expected_word_count}")
            has_printed_header = True
        print(f"   ❌ 序号不是从1开始: 第一个序号={first_index}")
        issues.append({
            'position': 1,
            'word_id': dict_words[0][0],
            'spell': dict_words[0][2],
            'expected': 1,
            'actual': first_index,
            'type': 'not_start_from_one'
        })
        cached_problems.append(f"不是从1开始：第一个序号是{first_index}，应该是1")
    
    # 检查序号是否连续
    for i, (word_id, index_no, spell) in enumerate(dict_words):
        expected_index = i + 1
        if index_no != expected_index:
            if not has_printed_header:
                print(f"\n📚 检查词书: {dict_name} (ID: {dict_id}, 所有者: {owner})")
                print(f"   📊 实际单词数: {total_words}, dict表记录: {expected_word_count}")
                has_printed_header = True
            issues.append({
                'position': i + 1,
                'word_id': word_id,
                'spell': spell,
                'expected': expected_index,
                'actual': index_no,
                'type': 'discontinuous'
            })
            cached_problems.append(f"序号不连续：位置{expected_index}断开，期望{expected_index}，实际{index_no}")
    
    # 检查最大序号是否等于总单词数
    max_index = dict_words[-1][1]
    if max_index != total_words:
        if not has_printed_header:
            print(f"\n📚 检查词书: {dict_name} (ID: {dict_id}, 所有者: {owner})")
            print(f"   📊 实际单词数: {total_words}, dict表记录: {expected_word_count}")
            has_printed_header = True
        print(f"   ❌ 最大序号不等于总单词数: 最大序号={max_index}, 总单词数={total_words}")
        issues.append({
            'position': total_words,
            'word_id': dict_words[-1][0],
            'spell': dict_words[-1][2],
            'expected': total_words,
            'actual': max_index,
            'type': 'max_index_error'
        })
        cached_problems.append(f"最大序号异常：最大序号是{max_index}，应该是{total_words}")
    
    # 将缓存的问题信息添加到issues中
    for i, issue in enumerate(issues):
        if i < len(cached_problems):
            issue['cached_problem'] = cached_problems[i]
    
    if issues:
        # 统计序号相关的问题数量
        order_issues = [iss for iss in issues if iss['type'] != 'word_count_mismatch']
        
        if order_issues:
            print(f"   ❌ 发现 {len(order_issues)} 个序号问题:")
            for issue in order_issues:
                print(f"      位置 {issue['position']}: 单词 '{issue['spell']}' (ID: {issue['word_id']})")
                print(f"        期望序号: {issue['expected']}, 实际序号: {issue['actual']}")
        
        return False, issues
    
    # 没有问题，静默返回
    return True, []

def validate_user_db_version_consistency(cursor):
    """验证用户日志表中的数据库版本一致性"""
    # 获取所有用户的当前数据库版本
    sql_user_versions = """
    SELECT udv.userId, udv.version, u.userName
    FROM user_db_version udv
    JOIN user u ON udv.userId = u.id
    ORDER BY udv.version DESC
    """
    cursor.execute(sql_user_versions)
    user_versions = cursor.fetchall()
    
    if not user_versions:
        print(f"\n🔍 检查用户日志表数据库版本一致性...")
        print("   ⚠️  没有找到任何用户数据库版本记录")
        return True, []
    
    issues = []
    total_logs_checked = 0
    total_logs_with_issues = 0
    has_printed_header = False
    
    for user_id, current_version, user_name in user_versions:
        # 检查该用户的日志表中是否有版本号大于当前数据库版本的记录
        sql_logs = """
        SELECT id, version, operate, tblName, recordId, createTime
        FROM user_db_log
        WHERE userId = %s AND version > %s
        ORDER BY version DESC
        """
        cursor.execute(sql_logs, (user_id, current_version))
        invalid_logs = cursor.fetchall()
        
        if invalid_logs:
            if not has_printed_header:
                print(f"\n🔍 检查用户日志表数据库版本一致性...")
                has_printed_header = True
            
            print(f"   👤 用户: {user_name} (ID: {user_id}, 当前版本: {current_version})")
            print(f"      ❌ 发现 {len(invalid_logs)} 条版本号异常的日志记录:")
            for log_id, log_version, operate, table_name, record_id, create_time in invalid_logs:
                issue_info = {
                    'user_id': user_id,
                    'user_name': user_name,
                    'current_version': current_version,
                    'log_id': log_id,
                    'log_version': log_version,
                    'operate': operate,
                    'table_name': table_name,
                    'record_id': record_id,
                    'create_time': create_time,
                    'type': 'version_exceeds_current'
                }
                issues.append(issue_info)
                
                print(f"         日志ID: {log_id}, 版本: {log_version}, 操作: {operate}, 表: {table_name}")
                print(f"         记录ID: {record_id}, 创建时间: {create_time}")
                print(f"         问题: 日志版本号({log_version}) > 用户当前版本({current_version})")
            
            total_logs_with_issues += len(invalid_logs)
        
        total_logs_checked += 1
    
    # 输出总结（只在有问题时输出）
    if issues:
        print(f"\n   📊 版本一致性检查结果:")
        print(f"     检查用户数: {total_logs_checked}")
        print(f"     异常用户数: {len(set(issue['user_id'] for issue in issues))}")
        print(f"     异常日志数: {total_logs_with_issues}")
        print(f"   ❌ 发现 {len(issues)} 个版本号异常问题")
        return False, issues
    
    # 没有问题，静默返回
    return True, []

def validate_learning_progress(cursor):
    """验证词书学习进度一致性"""
    # 查找学习进度大于词书单词数量的记录
    # learning_dict 表使用复合主键 (userId, dictId)，没有单独的 id 字段
    # 学习进度字段名为 currentWordSeq (首字母大写!)
    sql = """
    SELECT 
        ld.userId,
        u.userName,
        ld.dictId,
        d.name as dict_name,
        ld.currentWordSeq,
        d.wordCount
    FROM learning_dict ld
    JOIN user u ON ld.userId = u.id
    JOIN dict d ON ld.dictId = d.id
    WHERE ld.currentWordSeq > d.wordCount
    ORDER BY ld.userId, ld.dictId
    """
    cursor.execute(sql)
    invalid_records = cursor.fetchall()
    
    if not invalid_records:
        # 没有问题，静默返回
        return True, []
    
    # 有问题，打印信息
    print(f"\n🔍 检查词书学习进度一致性...")
    print(f"   ❌ 发现 {len(invalid_records)} 个学习进度异常的记录:")
    
    issues = []
    for user_id, user_name, dict_id, dict_name, cur_index, word_count in invalid_records:
        print(f"\n   👤 用户: {user_name} (ID: {user_id})")
        print(f"      📚 词书: {dict_name} (ID: {dict_id})")
        print(f"      ❌ 学习进度异常: 当前进度={cur_index}, 词书单词数={word_count}")
        
        issue_info = {
            'user_id': user_id,
            'user_name': user_name,
            'dict_id': dict_id,
            'dict_name': dict_name,
            'cur_learning_index': cur_index,
            'word_count': word_count,
            'type': 'learning_progress_exceeds'
        }
        issues.append(issue_info)
    
    print(f"\n   📊 学习进度检查结果:")
    print(f"     异常记录数: {len(issues)}")
    print(f"     涉及用户数: {len(set(issue['user_id'] for issue in issues))}")
    
    return False, issues

def validate_common_dict_completeness(cursor):
    """验证通用词典的所有单词都有释义项，且每个释义项都有例句"""
    # 获取通用词典（id='0'）
    sql_common_dict = """
    SELECT id, name, wordCount
    FROM dict
    WHERE id = '0'
    """
    cursor.execute(sql_common_dict)
    common_dict = cursor.fetchone()
    
    if not common_dict:
        # 没有通用词典，静默返回
        return True, []
    
    dict_id, dict_name, word_count = common_dict
    
    # 获取该词书中的所有单词
    sql_words = """
    SELECT dw.wordId, w.spell
    FROM dict_word dw
    JOIN word w ON dw.wordId = w.id
    WHERE dw.dictId = %s
    ORDER BY dw.seq ASC
    """
    cursor.execute(sql_words, (dict_id,))
    words = cursor.fetchall()
    
    if not words:
        # 词书为空，静默返回
        return True, []
    
    all_issues = []
    has_printed_header = False
    total_words_checked = 0
    total_meanings_checked = 0
    words_without_meanings = 0
    meanings_without_sentences = 0
    
    for word_id, spell in words:
        total_words_checked += 1
        
        # 获取该单词的所有释义项（字段已规范化为 wordId）
        sql_meanings = """
        SELECT id, meaning
        FROM meaning_item 
        WHERE wordId = %s AND dictId = %s
        ORDER BY id
        """
        cursor.execute(sql_meanings, (word_id, dict_id))
        meanings = cursor.fetchall()
        
        # 检查是否有释义项
        if not meanings:
            words_without_meanings += 1
            all_issues.append({
                'word_id': word_id,
                'spell': spell,
                'issue_type': 'no_meaning',
                'meaning_id': None,
                'meaning_text': None,
                'has_meaning': False,
                'has_sentence': False,
                'meaning_count': 0,
                'sentence_count': 0
            })
            continue
        
        # 检查每个释义项是否有例句
        for meaning_id, meaning_text in meanings:
            total_meanings_checked += 1
            
            # 检查该释义项是否有例句
            sql_sentence_count = """
            SELECT COUNT(*) 
            FROM sentence 
            WHERE meaningItemId = %s
            """
            cursor.execute(sql_sentence_count, (meaning_id,))
            sentence_count = cursor.fetchone()[0]
            
            if sentence_count == 0:
                meanings_without_sentences += 1
                all_issues.append({
                    'word_id': word_id,
                    'spell': spell,
                    'issue_type': 'meaning_without_sentence',
                    'meaning_id': meaning_id,
                    'meaning_text': meaning_text[:50] + '...' if len(meaning_text) > 50 else meaning_text,
                    'has_meaning': True,
                    'has_sentence': False,
                    'meaning_count': len(meanings),
                    'sentence_count': 0
                })
    
    # 输出结果（只在有问题时输出）
    if all_issues:
        print(f"\n🔍 检查通用词典完整性（释义项和例句）...")
        print(f"\n   📚 词书: {dict_name} (ID: {dict_id})")
        
        # 统计问题类型
        no_meaning_issues = [iss for iss in all_issues if iss['issue_type'] == 'no_meaning']
        no_sentence_issues = [iss for iss in all_issues if iss['issue_type'] == 'meaning_without_sentence']
        
        # 统计受影响的单词数（去重）
        affected_words = set(iss['word_id'] for iss in all_issues)
        
        print(f"      ❌ 发现问题:")
        print(f"         受影响的单词数: {len(affected_words)}")
        if no_meaning_issues:
            print(f"         缺少释义项的单词: {len(no_meaning_issues)} 个")
        if no_sentence_issues:
            print(f"         缺少例句的释义项: {len(no_sentence_issues)} 个")
        
        # 显示前10个问题
        displayed_count = 0
        for i, issue in enumerate(all_issues):
            if displayed_count >= 10:
                break
            
            if issue['issue_type'] == 'no_meaning':
                print(f"         {displayed_count+1}. '{issue['spell']}' - 缺少释义项")
            else:
                print(f"         {displayed_count+1}. '{issue['spell']}' - 释义项无例句: \"{issue['meaning_text']}\"")
            displayed_count += 1
        
        if len(all_issues) > 10:
            print(f"         ... 还有 {len(all_issues) - 10} 个问题")
        
        # 输出总结
        print(f"\n   📊 通用词典完整性检查结果:")
        print(f"     检查单词数: {total_words_checked}")
        print(f"     检查释义项数: {total_meanings_checked}")
        print(f"     缺少释义项的单词数: {words_without_meanings}")
        print(f"     缺少例句的释义项数: {meanings_without_sentences}")
        print(f"     受影响的单词总数: {len(affected_words)}")
        print(f"   ❌ 发现 {len(all_issues)} 个问题")
        
        # 将问题添加额外的字段供后续使用
        for issue in all_issues:
            issue['dict_id'] = dict_id
            issue['dict_name'] = dict_name
            issue['type'] = 'incomplete_word_data'
        
        return False, all_issues
    
    # 没有问题，静默返回
    return True, []

def get_dict_owner_name(cursor, owner_id):
    """获取词书所有者名称"""
    if owner_id == '15118':
        return '系统'
    
    sql = "SELECT userName FROM user WHERE id = %s"
    cursor.execute(sql, (owner_id,))
    result = cursor.fetchone()
    return result[0] if result else f'用户{owner_id}'

def delete_empty_dict(cursor, dict_id, dict_name):
    """删除空的系统词书"""
    print(f"   🗑️  删除空词书: '{dict_name}' (ID: {dict_id})")
    
    try:
        # 1. 先删除 sentence 表中的关联记录（sentence -> meaning_item -> dict）
        delete_sentence_sql = """
        DELETE FROM sentence 
        WHERE meaningItemId IN (
            SELECT id FROM meaning_item WHERE dictId = %s
        )
        """
        cursor.execute(delete_sentence_sql, (dict_id,))
        deleted_count = cursor.rowcount
        if deleted_count > 0:
            print(f"      删除 sentence 记录: {deleted_count} 条")
        
        # 2. 删除 meaning_item 表中的关联记录
        delete_meaning_item_sql = """
        DELETE FROM meaning_item 
        WHERE dictId = %s
        """
        cursor.execute(delete_meaning_item_sql, (dict_id,))
        deleted_count = cursor.rowcount
        if deleted_count > 0:
            print(f"      删除 meaning_item 记录: {deleted_count} 条")
        
        # 3. 删除 learning_dict 表中的关联记录
        delete_learning_dict_sql = """
        DELETE FROM learning_dict 
        WHERE dictId = %s
        """
        cursor.execute(delete_learning_dict_sql, (dict_id,))
        deleted_count = cursor.rowcount
        if deleted_count > 0:
            print(f"      删除 learning_dict 记录: {deleted_count} 条")
        
        # 4. 删除 dict_word 表中的关联记录
        delete_dict_word_sql = """
        DELETE FROM dict_word 
        WHERE dictId = %s
        """
        cursor.execute(delete_dict_word_sql, (dict_id,))
        deleted_count = cursor.rowcount
        if deleted_count > 0:
            print(f"      删除 dict_word 记录: {deleted_count} 条")
        
        # 5. 最后删除 dict 表中的记录
        delete_dict_sql = """
        DELETE FROM dict 
        WHERE id = %s
        """
        cursor.execute(delete_dict_sql, (dict_id,))
        
        print(f"   ✅ 词书及相关记录已删除")
        return True
    except Exception as e:
        print(f"   ❌ 删除失败: {e}")
        return False

def fix_dict_word_count(cursor, dict_id, dict_name, actual_count):
    """修复词书的单词数量记录"""
    print(f"   🔢 更新词书 '{dict_name}' 的单词数量为: {actual_count}")
    
    update_sql = """
    UPDATE dict 
    SET wordCount = %s, updateTime = CURRENT_TIMESTAMP
    WHERE id = %s
    """
    cursor.execute(update_sql, (actual_count, dict_id))
    print(f"   ✅ 单词数量已更新")
    return True

def fix_dict_word_order(cursor, dict_id, dict_name, owner):
    """修复单个词书的单词顺序号"""
    print(f"\n🔧 修复词书: {dict_name} (ID: {dict_id}, 所有者: {owner})")
    
    # 获取词书中的所有单词，按seq排序
    sql = """
    SELECT dw.wordId, dw.seq, w.spell
    FROM dict_word dw
    JOIN word w ON dw.wordId = w.id
    WHERE dw.dictId = %s
    ORDER BY dw.seq ASC
    """
    cursor.execute(sql, (dict_id,))
    dict_words = cursor.fetchall()
    
    if not dict_words:
        print(f"   ✅ 词书为空，无需修复")
        return True
    
    # 重新分配序号
    fixed_count = 0
    for i, (word_id, old_index, spell) in enumerate(dict_words):
        new_index = i + 1
        if old_index != new_index:
            # 更新序号
            update_sql = """
            UPDATE dict_word 
            SET seq = %s, updateTime = CURRENT_TIMESTAMP
            WHERE dictId = %s AND wordId = %s
            """
            cursor.execute(update_sql, (new_index, dict_id, word_id))
            fixed_count += 1
            print(f"      🔄 修复: '{spell}' 序号 {old_index} -> {new_index}")
    
    if fixed_count > 0:
        print(f"   ✅ 修复完成，共修复 {fixed_count} 个序号")
    else:
        print(f"   ✅ 词书序号正常，无需修复")
    
    return True

def fix_learning_progress_issues(cursor, issues):
    """修复学习进度异常问题"""
    print(f"\n🔧 开始修复学习进度异常问题...")
    
    if not issues:
        print("   ✅ 没有需要修复的问题")
        return True
    
    fixed_count = 0
    failed_count = 0
    
    for issue in issues:
        try:
            # 将学习进度设置为词书单词数量
            # learning_dict 使用复合主键 (userId, dictId)
            # 学习进度字段为 currentWordSeq (首字母大写!)
            update_sql = """
            UPDATE learning_dict 
            SET currentWordSeq = %s, updateTime = CURRENT_TIMESTAMP
            WHERE userId = %s AND dictId = %s
            """
            cursor.execute(update_sql, (issue['word_count'], issue['user_id'], issue['dict_id']))
            
            print(f"   🔄 修复用户 {issue['user_name']} 的学习进度:")
            print(f"      词书: {issue['dict_name']}")
            print(f"      进度: {issue['cur_learning_index']} -> {issue['word_count']}")
            
            fixed_count += 1
            
        except Exception as e:
            print(f"   ❌ 修复失败 - 用户: {issue['user_name']}, 词书: {issue['dict_name']}, 错误: {e}")
            failed_count += 1
    
    print(f"\n   📊 修复结果:")
    print(f"     成功修复: {fixed_count} 条记录")
    print(f"     修复失败: {failed_count} 条记录")
    
    return failed_count == 0

def fix_user_db_version_issues(cursor, issues):
    """修复用户日志表版本号问题"""
    print(f"\n🔧 开始修复用户日志表版本号问题...")
    
    if not issues:
        print("   ✅ 没有需要修复的问题")
        return True
    
    deleted_count = 0
    failed_count = 0
    
    for issue in issues:
        try:
            # 删除版本号大于用户当前版本号的异常日志记录
            delete_sql = """
            DELETE FROM user_db_log 
            WHERE id = %s
            """
            cursor.execute(delete_sql, (issue['log_id'],))
            
            print(f"   🗑️  删除用户 {issue['user_name']} 的异常日志记录:")
            print(f"      日志ID: {issue['log_id']}")
            print(f"      异常版本号: {issue['log_version']} (用户当前版本: {issue['current_version']})")
            print(f"      表: {issue['table_name']}, 操作: {issue['operate']}")
            print(f"      记录ID: {issue['record_id']}, 创建时间: {issue['create_time']}")
            
            deleted_count += 1
            
        except Exception as e:
            print(f"   ❌ 删除失败 - 日志ID: {issue['log_id']}, 错误: {e}")
            failed_count += 1
    
    print(f"\n   📊 修复结果:")
    print(f"     成功删除: {deleted_count} 条异常记录")
    print(f"     删除失败: {failed_count} 条记录")
    
    return failed_count == 0

def main():
    """主函数"""
    start_time = datetime.now()
    print("🔍 开始验证数据库...")
    print(f"⏰ 开始时间: {start_time.strftime('%Y-%m-%d %H:%M:%S')}")
    
    db = connect_db()
    cursor = db.cursor()
    
    try:
        # 1. 验证词书单词顺序号
        print("\n" + "="*60)
        print("📚 第一阶段：验证词书单词顺序号")
        print("="*60)
        
        dicts = get_all_dicts(cursor)
        print(f"\n📋 正在检查 {len(dicts)} 个词书...")
        
        if not dicts:
            print("❌ 没有找到任何词书")
        else:
            # 验证每个词书
            total_dicts = len(dicts)
            valid_dicts = 0
            invalid_dicts = 0
            invalid_dict_names = []  # 存储有问题的词书名称
            invalid_dicts_info = []  # 存储有问题的词书详细信息
            
            for dict_id, dict_name, owner_id, word_count, create_time in dicts:
                owner_name = get_dict_owner_name(cursor, owner_id)
                is_valid, issues = validate_dict_word_order(cursor, dict_id, dict_name, owner_name, owner_id, word_count)
                
                if is_valid:
                    valid_dicts += 1
                else:
                    invalid_dicts += 1
                    invalid_dict_names.append(f"{dict_name} ({owner_name})")
                    invalid_dicts_info.append({
                        'dict_id': dict_id,
                        'dict_name': dict_name,
                        'owner_name': owner_name,
                        'issues': issues
                    })
            
            # 输出词书检查总结
            print(f"\n" + "="*60)
            print(f"📊 词书序号验证结果总结:")
            print(f"   总词书数: {total_dicts}")
            print(f"   ✅ 正常词书: {valid_dicts}")
            print(f"   ❌ 异常词书: {invalid_dicts}")
            print(f"   正确率: {valid_dicts/total_dicts*100:.1f}%")
        
        # 2. 验证用户日志表数据库版本一致性
        print("\n" + "="*60)
        print("🔍 第二阶段：验证用户日志表数据库版本一致性")
        print("="*60)
        print(f"\n📋 正在检查用户日志表...")
        
        version_consistency_valid, version_issues = validate_user_db_version_consistency(cursor)
        
        # 3. 验证词书学习进度一致性
        print("\n" + "="*60)
        print("📖 第三阶段：验证词书学习进度一致性")
        print("="*60)
        print(f"\n📋 正在检查学习进度...")
        
        learning_progress_valid, learning_progress_issues = validate_learning_progress(cursor)
        
        # 4. 验证通用词典完整性（释义项和例句）
        print("\n" + "="*60)
        print("📝 第四阶段：验证通用词典完整性（释义项和例句）")
        print("="*60)
        print(f"\n📋 正在检查通用词典...")
        
        common_dict_valid, common_dict_issues = validate_common_dict_completeness(cursor)
        
        # 输出总体总结
        print(f"\n" + "="*60)
        print(f"📊 总体验证结果总结:")
        
        if 'dicts' in locals() and dicts:
            print(f"   词书序号验证:")
            print(f"     ✅ 正常词书: {valid_dicts}/{total_dicts}")
            print(f"     ❌ 异常词书: {invalid_dicts}/{total_dicts}")
        
        print(f"   用户日志版本一致性:")
        if version_consistency_valid:
            print(f"     ✅ 通过")
        else:
            print(f"     ❌ 发现 {len(version_issues)} 个问题")
        
        print(f"   学习进度一致性:")
        if learning_progress_valid:
            print(f"     ✅ 通过")
        else:
            print(f"     ❌ 发现 {len(learning_progress_issues)} 个问题")
        
        print(f"   通用词典完整性:")
        if common_dict_valid:
            print(f"     ✅ 通过")
        else:
            print(f"     ❌ 发现 {len(common_dict_issues)} 个单词缺少释义项或例句")
        
        # 询问是否修复问题
        has_issues = ('invalid_dicts' in locals() and invalid_dicts > 0) or not version_consistency_valid or not learning_progress_valid or not common_dict_valid
        
        if has_issues:
            print(f"\n🔧 是否要修复这些问题？")
            confirm = input("请输入 'y' 确认修复，其他键跳过: ").strip().lower()
            
            if confirm == 'y':
                print(f"\n🚀 开始修复...")
                
                # 修复词书序号问题
                if 'invalid_dicts' in locals() and invalid_dicts > 0:
                    print(f"\n📚 修复词书问题...")
                    fixed_dict_count = 0
                    fixed_count_issues = 0
                    deleted_empty_dicts = 0
                    
                    for dict_info in invalid_dicts_info:
                        try:
                            # 检查是否是空的系统词书，需要删除
                            has_empty_system_dict = False
                            has_count_issue = False
                            actual_count = None
                            
                            for issue in dict_info['issues']:
                                if issue['type'] == 'empty_system_dict':
                                    has_empty_system_dict = True
                                    break
                                elif issue['type'] == 'word_count_mismatch':
                                    has_count_issue = True
                                    actual_count = issue['actual_count']
                            
                            # 如果是空的系统词书，删除它
                            if has_empty_system_dict:
                                success = delete_empty_dict(cursor, dict_info['dict_id'], dict_info['dict_name'])
                                if success:
                                    deleted_empty_dicts += 1
                                    fixed_dict_count += 1
                                    db.commit()  # 提交事务
                                else:
                                    print(f"   ❌ 删除失败: {dict_info['dict_name']}")
                                    db.rollback()  # 回滚事务
                            else:
                                # 修复单词顺序号
                                success = fix_dict_word_order(cursor, dict_info['dict_id'], dict_info['dict_name'], dict_info['owner_name'])
                                
                                # 修复单词数量
                                if has_count_issue and actual_count is not None:
                                    fix_dict_word_count(cursor, dict_info['dict_id'], dict_info['dict_name'], actual_count)
                                    fixed_count_issues += 1
                                
                                if success:
                                    fixed_dict_count += 1
                                    db.commit()  # 提交事务
                                else:
                                    print(f"   ❌ 修复失败: {dict_info['dict_name']}")
                                    db.rollback()  # 回滚事务
                        except Exception as e:
                            print(f"   ❌ 修复出错: {dict_info['dict_name']} - {e}")
                            db.rollback()  # 回滚事务
                    
                    print(f"\n📚 词书修复结果:")
                    print(f"   成功修复词书: {fixed_dict_count}/{invalid_dicts} 个")
                    if deleted_empty_dicts > 0:
                        print(f"   删除空词书: {deleted_empty_dicts} 个")
                    if fixed_count_issues > 0:
                        print(f"   修复单词数量: {fixed_count_issues} 个")
                
                # 修复用户日志版本问题
                if not version_consistency_valid:
                    print(f"\n🔍 修复用户日志版本问题...")
                    try:
                        success = fix_user_db_version_issues(cursor, version_issues)
                        if success:
                            db.commit()  # 提交事务
                            print(f"🔍 用户日志版本问题修复完成（已删除异常版本号记录）")
                        else:
                            print(f"🔍 用户日志版本问题部分修复失败")
                            db.rollback()  # 回滚事务
                    except Exception as e:
                        print(f"🔍 修复用户日志版本问题出错: {e}")
                        db.rollback()  # 回滚事务
                
                # 修复学习进度问题
                if not learning_progress_valid:
                    print(f"\n📖 修复学习进度问题...")
                    try:
                        success = fix_learning_progress_issues(cursor, learning_progress_issues)
                        if success:
                            db.commit()  # 提交事务
                            print(f"📖 学习进度问题修复完成")
                        else:
                            print(f"📖 学习进度问题部分修复失败")
                            db.rollback()  # 回滚事务
                    except Exception as e:
                        print(f"📖 修复学习进度问题出错: {e}")
                        db.rollback()  # 回滚事务
                
                print(f"\n🎉 修复完成！")
                return 0
            else:
                print(f"\n⏭️  跳过修复")
                return 1
        else:
            print(f"\n🎉 所有检查都通过，数据库状态正常！")
            return 0
            
    except Exception as e:
        print(f"❌ 验证过程中出现错误: {e}")
        print(traceback.format_exc())
        return 1
    finally:
        cursor.close()
        db.close()
        print(f"\n⏰ 耗时: {datetime.now() - start_time}")

if __name__ == "__main__":
    exit_code = main()
    sys.exit(exit_code)
