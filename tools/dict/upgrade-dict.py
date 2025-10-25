# -*- coding: utf-8 -*-
# 升级单词书， 将词书中单词的释义更新为指定文件中的释义（一般词书使用的是词典释义，释义太多了）
import pymysql;
import hashlib;
import sys;
import shutil;
import traceback;
import os;
import time;
import requests;
import re;
from shutil import copyfile
from bs4 import BeautifulSoup
sys.path.append(r'../util')
from wordUtil import Word, MeaningItem, readDictFile
import util

def updateMeaningForDict(dictId, words, replaceIfExists):
    # 获取单词书名称
    cursor.execute("SELECT name from dict where id = %s", (dictId))
    dictName = cursor.fetchall()[0][0]
    print ('单词书(%s)开始升级...'%(dictName))
    
    # 获取释义的当前最大Id
    cursor.execute('select max(id) from meaning_item')
    maxMeaningItemId = cursor.fetchall()[0][0]

    count = 0
    for word in words:
        cursor.execute("SELECT wordId from dict_word dw left join word w on dw.wordId = w.id where dw.dictId = %s and w.spell = %s", (dictId, word.spell));
        records = cursor.fetchall();
        if (len(records) > 0): # 单词在目标单词书中
            wordId = records[0][0]
            
            # 为单词添加释义
            cursor.execute("select 0 from meaning_item where wordId = %s and dictId = %s", (wordId, dictId))
            existings = cursor.fetchall()
            if len(existings) > 0 and replaceIfExists:
                cursor.execute('delete from meaning_item where wordId = %s and dictId = %s', (wordId, dictId))    
            if len(existings) == 0 or replaceIfExists:
                for meaningItem in word.meaningItems:
                    maxMeaningItemId += 1
                    cursor.execute('insert into meaning_item (id, ciXing, meaning, wordId, dictId, createTime) values (%s, %s, %s, %s, %s, sysdate())', (maxMeaningItemId, meaningItem.ciXing, meaningItem.content, wordId, dictId))
                
                count += 1
            
       
    # 更新释义最大Id
    cursor.execute("update id_gen set next_val = %s where sequence_name = 'meaning_item'", (maxMeaningItemId + 40))

    print ("为 %d/%d 个单词添加了释义" % (count, len(words)))


Soup = BeautifulSoup

# 打开数据库连接
db = pymysql.connect(host="localhost", port=3306,
                     user="root", passwd="root", db="bdc",
                     charset="utf8");

# 使用cursor()方法获取操作游标 
cursor = db.cursor()

try:
    # 读取并解析单词书文件
    words = readDictFile("siji_word.txt", True)
    words2 = readDictFile("siji2_word.txt", False)
    words.extend(words2)
    for word in words:
        print (word)

    # 导入指定单词书的单词释义(四级)
    updateMeaningForDict(79, words, True)
    updateMeaningForDict(122, words, True)
    updateMeaningForDict(281, words, True)
    updateMeaningForDict(361, words, True)
    updateMeaningForDict(404, words, True)
    updateMeaningForDict(120, words, True)
    updateMeaningForDict(121, words, True)
    updateMeaningForDict(360, words, True)
    updateMeaningForDict(701, words, True)

    # 读取并解析单词书文件
    words = readDictFile("liuji_words.txt", False)
    for word in words:
        print (word)

    # 导入指定单词书的单词释义
    updateMeaningForDict(120, words, False)
    updateMeaningForDict(121, words, False)
    updateMeaningForDict(360, words, False)
    updateMeaningForDict(701, words, False)

    # 读取并解析单词书文件
    words = readDictFile("siji_word.txt", True)
    words2 = readDictFile("siji2_word.txt", False)
    words3 = readDictFile("liuji_words.txt", False)
    words.extend(words2)
    words.extend(words3)
    for word in words:
        print (word)

    #exit()

    # 导入指定单词书的单词释义(四级)
    updateMeaningForDict(22, words, True)
    updateMeaningForDict(23, words, True)
    updateMeaningForDict(24, words, True)
    updateMeaningForDict(25, words, True)
    updateMeaningForDict(86, words, True)
    updateMeaningForDict(87, words, True)
    updateMeaningForDict(88, words, True)
    updateMeaningForDict(89, words, True)
    updateMeaningForDict(90, words, True)
    updateMeaningForDict(91, words, True)
    updateMeaningForDict(92, words, True)
    updateMeaningForDict(93, words, True)
    updateMeaningForDict(94, words, True)
    updateMeaningForDict(95, words, True)
    updateMeaningForDict(96, words, True)
    updateMeaningForDict(152, words, True)
    updateMeaningForDict(153, words, True)
    updateMeaningForDict(154, words, True)
    updateMeaningForDict(155, words, True)
    updateMeaningForDict(205, words, True)
    updateMeaningForDict(206, words, True)
    updateMeaningForDict(207, words, True)
    updateMeaningForDict(208, words, True)

    time.sleep(3)

    cursor.close();
    db.commit();
except (Exception):
    db.rollback();
    print (traceback.format_exc())

# 关闭数据库连接
db.close()
