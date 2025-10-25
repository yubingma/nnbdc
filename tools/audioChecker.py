# 检查例句的mp3文件是否存在或为空, 同时复制所有通过检查的例句mp3到/tmp/sentence/, 对于未通过检查的例句，置重新生成mp3标志, 或重新下载

# 打开数据库连接
import pymysql;
import os;
import time;
db = pymysql.connect(host="127.0.0.1",
  user="root", passwd="root", db="bdc",
  charset="utf8");

# 使用cursor()方法获取操作游标
cursor = db.cursor()
cursor.execute("select English, englishDigest, id, temp_sound_url from sentence where theType='tts' and producer = 'coze' ") 
results = cursor.fetchall()
print("%s - 从数据库读出%d条待检查的例句" % (time.strftime('%Y-%m-%d %H:%M:%S', time.localtime()), cursor.rowcount))
if cursor.rowcount == 0:
  os._exit(0)

import pymysql;
import hashlib;
import sys;
import shutil;
import traceback;
import gc
import objgraph


# 初始化tts
# set path
env=os.environ
mp3_target_dir="/var/www/html/sound/sentence"
copy_to_dir="/tmp/sentence"

# add path
import sys


import time

import librosa

try:
    count = 0
    sentenceIndex = 0;
    errorCount = 0
    for row in results:
        english = row[0]
        englishDigest = row[1]
        sentenceId = row[2]
        tempSoundUrl = row[3]
        sentenceIndex = sentenceIndex + 1
        
        # 检查mp3是否存在，以及是否是空文件
        targetMp3 = mp3_target_dir+'/'+englishDigest+'.mp3'
        if (not os.path.exists(targetMp3) or os.path.getsize(targetMp3) == 0):
            print ("no mp3 [%s] [%s] [%s]" % (sentenceId, english, tempSoundUrl))
            errorCount += 1

            if (tempSoundUrl == ''): # 未生成例句音频, 重新生成
                cursor.execute("""
                    UPDATE sentence
                    SET needTts=1, producer='coze', theType='no_sound', updateTime=NOW()
                    WHERE id=%s
                """, (sentenceId,))
            else: # 已生成例句音频(但下载失败)，重新下载
                cursor.execute("""
                    UPDATE sentence
                    SET theType='temp_sound', updateTime=NOW()
                    WHERE id=%s
                """, (sentenceId,)) 

            
        else:
            status = os.system('cp ' + targetMp3 + ' ' + copy_to_dir + '/')
            if (not os.path.exists(f"{copy_to_dir}/{englishDigest}.mp3")):
                raise Exception(f"复制mp3失败: {targetMp3} ==> {copy_to_dir}")
        
        db.commit()
        count = count + 1
        if (count % 1000 == 0):
            print(f"{count} sentences checked, failed count: {errorCount} \n")
    cursor.close();
    print(f"{count} sentences checked, failed count: {errorCount} \n")

except Exception as e:
    db.rollback();
    print(traceback.format_exc())
    
# 关闭数据库连接
db.close()

