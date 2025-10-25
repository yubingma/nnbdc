# -*- coding: utf-8 -*-
# 根据给定的单词书文件(包含或不包含释义项), 导入(创建)单词书
import uu
import uuid
import pymysql;
import hashlib;
import sys;
import shutil;
import traceback;
import os;
import requests;
import re;
from shutil import copyfile
from bs4 import BeautifulSoup
sys.path.append(r'../util')
from youdaoCrawler import crawle
from wordUtil import Word, MeaningItem, getWordFromWords, readDictFile, parseWord

def getMd5OfWord(word):
    return word.md5

Soup = BeautifulSoup

# 打开数据库连接
db = pymysql.connect(host="localhost", port=3306,
                     user="root", passwd="root", db="bdc",
                     charset="utf8");

# 使用cursor()方法获取操作游标 
cursor = db.cursor()

try:
    #w = parseWord('ruin v. 毁坏，破坏 n. 毁灭，[pl.]废墟', False)
    #print(w)
    #exit(0)
    
    # 读取并解析单词书文件
    dictName = "六级词汇2025"
    filename = f"/home/myb/badhorse/nnbdc/nnbdc-tools/dict/六级/{dictName}.txt"
    words = readDictFile(filename, False)
    words.sort(key = getMd5OfWord) # 把单词按拼写的md5排序
    for word in words:
        print (word)


    # 创建单词书
    dictId = str(uuid.uuid4()).replace('-', '')
    parts = filename.split('.')
    cursor.execute('insert into dict(id, isReady, isShared, name, wordCount, ownerId, createTime, visible) values (%s, 1, 0, %s, %s, %s, sysdate(), 1)', (dictId, f"{dictName}.dict", len(words), 15118))
    cursor.execute("update id_gen set next_val = next_val + 1 where sequence_name='dict'")

    # 导入牛牛数据库中没有的单词
    print ('从网络导入牛牛数据库中没有的单词 ...')
    count = 0
    for i in range(0, len(words), 1):
        word = words[i]
        cursor.execute('select spell from word where spell = %s', (word.spell))
        records = cursor.fetchall()
        if len(records) == 0:
            print ('crawling [%s] from youdao.com...' % (word.spell))
            newWord = crawle(word.spell, '/var/nnbdc/res/sound') 
            print (newWord)
            maxWordId = str(uuid.uuid4()).replace('-', '')
            cursor.execute('insert into word (id, americaPronounce, britishPronounce, popularity, pronounce, spell, createTime) values (%s, %s, %s, %s, %s, %s, sysdate())', \
                (maxWordId, newWord.americaPronounce, newWord.britishPronounce, 0, newWord.pronounce, newWord.spell))
            cursor.execute("update id_gen set next_val = next_val + 1 where sequence_name = 'word'")
            for meaningItem in newWord.meaningItems:
                maxMeaningItemId = str(uuid.uuid4()).replace('-', '')
                cursor.execute("insert into meaning_item (id, ciXing, meaning, wordId, dictId, createTime) values (%s, %s, %s, %s, '0', sysdate())", \
                    (maxMeaningItemId, meaningItem.ciXing, meaningItem.content, maxWordId)) # 为单词添加通用词典释义
                cursor.execute("update id_gen set next_val = next_val + 1 where sequence_name = 'meaning_item'")
            count += 1
    print ('导入了 %d 个新单词到数据库' % (count))    

    # 把单词导入到新单词书
    for i in range(0, len(words), 1):
        word = words[i]
        cursor.execute("select id from word where spell = %s", (word.spell))
        wordId = cursor.fetchall()[0][0]
        cursor.execute("insert into dict_word (dictId, wordId, seq, createTime) values (%s, %s, %s, sysdate())", (dictId, wordId, i + 1))
        for j in range(0, len(word.meaningItems), 1):
            meaningItem = word.meaningItems[j] 
            maxMeaningItemId = str(uuid.uuid4()).replace('-', '')
            cursor.execute("insert into meaning_item (id, ciXing, meaning, wordId, dictId, createTime) values (%s, %s, %s, %s, %s, sysdate())", \
                    (maxMeaningItemId, meaningItem.ciXing, meaningItem.content, wordId, dictId)) 
            cursor.execute("update id_gen set next_val = next_val + 1 where sequence_name = 'meaning_item'")
    print ("新单词书[%s]创建成功, %d个单词" % (dictName, len(words)))

    exit()
    cursor.close();
    db.commit();
except (Exception):
    db.rollback();
    print (traceback.format_exc())

# 关闭数据库连接
db.close()
