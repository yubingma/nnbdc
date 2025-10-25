# -*- coding: utf-8 -*-
# 对指定单词书的所有例句置"needTts"标记，这些例句随后会被tts程序进行处理，生成tts语音
import pymysql;
import hashlib;
import sys;
import shutil;
import traceback;
import os;
import requests;
import re;
import urllib3
import urllib.parse;
from shutil import copyfile
from bs4 import BeautifulSoup
from wordUtil import Word, MeaningItem, parseMeaningItems
Soup = BeautifulSoup
http = urllib3.PoolManager()

cacheDir = '/tmp/cache/youdao_com'
if not os.path.exists(cacheDir):
    os.makedirs(cacheDir)

def genCacheFileName(spell):
    spell = spell if spell != "con" else (spell + "_")
    return "%s/%s.html" % (cacheDir, spell)

# 获取单词的html页面，首先尝试从缓存获取，如果获取不到则从网上获取
def getHtmlOfWord(spell):
    html = ""
    cacheFileName = genCacheFileName(spell)
    if(os.path.isfile(cacheFileName)):
        fh = open(cacheFileName)
        html = fh.read()
        fh.close()
    else:
        url = 'http://www.youdao.com/w/%s' % (urllib.parse.quote(spell))
        print(url)
        response = requests.get(url, allow_redirects=True)
        html = response.text
        if (response.status_code == 200):
            fh = open(cacheFileName, 'w')
            fh.write(html)
            fh.close
    return html

def parsePronounces(soup):
    pronounces = []
    baavDiv = soup.find("div", {"class":"baav"})
    print (baavDiv)

    # 无音标
    if(baavDiv is None):
        return []

    pronDivs = baavDiv.find_all("span", {"class":"pronounce"})
    for pronDiv in  pronDivs:
        parts = re.split('\n', pronDiv.text)
        purifiedParts = []
        for part in parts:
            part = part.strip()
            if part != '':
                purifiedParts.append(part)
        if len(purifiedParts) == 2: # 形如: ['英', '[feis]']  
            pronounces.append(purifiedParts)
    return pronounces

def parseMeaningItems_(soup):
    meaningItems = []
    transDiv = soup.find("div", {"class":"trans-container"})
    lis = transDiv.find_all("li")
    for li in lis:
        items = parseMeaningItems(li.text)
        meaningItems.extend(items)
    return meaningItems

def downloadPronounce(spell, soundBasePath):
    firstChar = spell[0].lower()
    subDir = firstChar
    if firstChar < 'a' or firstChar > 'z':
        subDir = 'other'
    dir_ = '%s/%s' % (soundBasePath, subDir)
    if not os.path.exists(dir_):
        os.makedirs(dir_)
    mp3File = '%s/%s.mp3' % (dir_, spell)
    print(mp3File)
    if(not os.path.isfile(mp3File)):
        response = requests.get('http://dict.youdao.com/dictvoice?audio=%s&type=2' % (spell.replace(' ', '%20')), allow_redirects=True)
        if not os.path.exists('/tmp/mp3'):
            os.makedirs('/tmp/mp3')
        tmpFile = '/tmp/mp3/%s.mp3' % (spell)
        fh = open(tmpFile, 'wb')
        fh.write(response.content)
        fh.close
        copyfile(tmpFile, mp3File)

def crawle(spell, soundBasePath):
    html = getHtmlOfWord(spell)
    soup = Soup(html, "html.parser")
    
    # 解析单词音标
    pronounces = parsePronounces(soup)
    britishPronounce = ''
    americaPronounce = ''
    for pron in pronounces:
        if pron[0] == '英':
            britishPronounce = pron[1]
        if pron[0] == '美':
            americaPronounce = pron[1]
    
    # 解析单词释义
    meaningItems = parseMeaningItems_(soup)

    # 下载单词发音文件(mp3)
    downloadPronounce(spell, soundBasePath)
   
    word = Word(None, spell, '', americaPronounce, britishPronounce, '', meaningItems)
    return word
