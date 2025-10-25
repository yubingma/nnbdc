# -*- coding: utf-8 -*-
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
#sys.path.append(r'./util')
from util import string_rjust, string_ljust



class Word:
     def __init__(self, wordId, spell, pronounce, americaPronounce, britishPronounce, meaningStr, meaningItems):
        self.id = wordId
        self.spell = spell
        self.pronounce = pronounce
        self.americaPronounce = americaPronounce
        self.britishPronounce = britishPronounce
        self.meaningStr = meaningStr
        self.meaningItems = meaningItems
        m2 = hashlib.md5()
        m2.update(spell.encode("utf-8"))
        self.md5 = m2.hexdigest()
     def __repr__(self):
        pronounce = self.pronounce
        if pronounce == '':
            pronounce = self.americaPronounce
        if pronounce == '':
            pronounce = self.britishPronounce
        return '%30s | %s | %s | %s' % (self.spell, string_rjust(pronounce,30), string_rjust(self.meaningStr, 50), self.meaningItems)
class MeaningItem:
    def __init__(self, ciXing, content):
        if ciXing == 'a.':
            self.ciXing = 'adj.'
        elif ciXing == 'ad.':
            self.ciXing = 'adv.'
        elif ciXing == 'v.aux.':
            self.ciXing = 'aux.v.'
        else:
            self.ciXing = ciXing
        self.content = content
        assert(content.strip()!='')
        assert self.ciXing in ['', 'pron.', 'n.', 'adj.', 'vt.', 'adv.', 'vi.', 'v.', 'conj.', 'prep.', 'aux.v.', 'aux.', 'num.', 'int.', 'art.', 'abbr.', 'phr.', 'adv.prep.', 'adv.adj.']
    def __repr__(self):
        return "(" + self.ciXing + " " + self.content + ")"

def parseMeaningItems(meaningStr):
    # 分割出每个释义项内容字符串的起始和终止索引
    meaningStr = meaningStr.strip().strip('"').strip()
    delimiters = ['pron.', 'n.', 'adj.', 'a.', 'vt.', 'ad.', 'adv.', 'vi.', 'v.', 'conj.', 'prep.', 'aux.v.', 'v.aux.', 'aux.', 'num.', 'int.', 'art.', 'abbr.', 'phr.']
    indices = find_indices(meaningStr, delimiters)
    
    # 逐个生成释义项
    meaningItems = []
    ciXingStart = 0
    for i in range(0, len(indices), 1):
        start = indices[i][0]
        end = indices[i][1]
        ciXing = meaningStr[ciXingStart:start]
        content = meaningStr[start:end]
        meaningItem = MeaningItem(ciXing.strip(), content)
        meaningItems.append(meaningItem)
        ciXingStart = end

     # 反向遍历释义项，对于内容为&的释义，将&替换为上一个释义项的释义
    for i in range(len(meaningItems)-1, -1, -1):
        if meaningItems[i].content == '&' or meaningItems[i].content == '/':
            meaningItems[i].content = meaningItems[i+1].content

    print(meaningItems)
    return meaningItems

def parseWord(wordStr, hasPronounce):
    wordStr = wordStr.strip()
    print (wordStr)

    # 提取拼写（支持短语）
    spells = re.findall(r'^[a-zA-Z()／\'\s-]+\s', wordStr) 
    assert len(spells) == 1
    spell = spells[0].strip()

    # 如果单词字符串无音标，则插入音标，以便统一处理
    if not hasPronounce:
        wordStr = spells[0] +'[] ' + wordStr[len(spells[0]):]

    # 提取音标
    pronounces = re.findall(r'^[\[][^\[]*[\]]', wordStr[len(spells[0]):])
    assert(len(pronounces) == 1)
    pronounce = pronounces[0][1:-1]

    # 提取释义
    meaningStr = wordStr[len(spells[0]) + len(pronounces[0]) :].strip()
    meaningItems = parseMeaningItems(meaningStr)

    word = Word(None, spell.strip(), pronounce.strip(),'', '', meaningStr, meaningItems)
    return word


def getWordFromWords(spell, words):
    for word in words:
        if word.spell == spell:
            return word
    return None

def find_indices(text, delimiters):
    # 创建正则表达式模式
    pattern = f'({"|".join(map(re.escape, delimiters))})'

    # 使用 re.finditer 查找分隔符并获取起始和终止索引
    matches = list(re.finditer(pattern, text))

    indices = []
    start = 0

    for match in matches:
        # 获取分隔符前的子字符串
        if start < match.start():
            indices.append((start, match.start()))  # 记录子字符串的起始和终止索引

        start = match.end()  # 更新起始位置到分隔符之后

    # 处理最后一个子字符串
    if start < len(text):
        indices.append((start, len(text)))

    return indices

def readDictFile(fileName, hasPronounce):
    words = []
    for line in open(fileName):
        if not line.isspace():
            line = line.strip()
            word = parseWord(line, hasPronounce)
            existingWord = getWordFromWords(word.spell, words)
            if existingWord == None:
                words.append(word)
            else: # 同一个单词可能会在一个单词书文件中出现多次,所以会有这样的情况
                for meaningItem in word.meaningItems:
                    duplicated = False
                    for existingMeaningItem in existingWord.meaningItems:
                        if existingMeaningItem.ciXing == meaningItem.ciXing and existingMeaningItem.content == meaningItem.content:
                            duplicated = True

                    if not duplicated:
                        existingWord.meaningItems.append(meaningItem)

    return words

