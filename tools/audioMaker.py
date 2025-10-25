"""
音频下载(由coze生成)与入库标记工具

功能概述：
- 批量读取数据库 `sentence` 表中 `theType='temp_sound'` 的记录；
- 从每条记录的 `temp_sound_url` 下载 MP3 到 `mp3_target_dir`；
- 下载成功后，将该句子的 `needTts=0`、`producer='coze'`、`theType='tts'`，并更新 `updateTime`；
- 采用线程池并发下载与处理，加速批量任务执行。

使用前提：
- 可访问的 MySQL 数据库（参见下方 `db_config`）与 `sentence` 表字段：
  `English, englishDigest, id, temp_sound_url, needTts, producer, theType, updateTime`；
- 目标目录 `mp3_target_dir` 可写；
- 稳定的网络访问以下载音频文件。

快速使用：
- 根据实际环境修改 `db_config` 与 `mp3_target_dir`；
- 执行：`python3 audioMaker.py`

健壮性：
- 采用 `requests` 超时与状态码检查；
- 每个线程独立数据库连接，出错回滚并记录日志；
- 失败任务不会影响其他任务继续执行。
"""

import pymysql
import os
import logging
import requests
import concurrent.futures
from time import strftime, localtime
import threading

# 配置日志
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# 数据库配置
db_config = {
    "host": "127.0.0.1",
    "user": "root",
    "passwd": "root",
    "db": "bdc",
    "charset": "utf8"
}

mp3_target_dir = "/var/www/html/sound/sentence"
os.makedirs(mp3_target_dir, exist_ok=True)

# 下载音频函数
def download_mp3(english_digest, temp_sound_url):
    if not temp_sound_url or not english_digest:
        logging.error(f"无效的 URL 或 digest：{temp_sound_url}, {english_digest}")
        return None

    target_mp3 = os.path.join(mp3_target_dir, f"{english_digest}.mp3")
    try:
        response = requests.get(temp_sound_url, stream=True, timeout=15)  # 增加超时限制
        response.raise_for_status()  # 如果状态码不是 200，会抛出异常
        with open(target_mp3, 'wb') as f:
            for chunk in response.iter_content(chunk_size=1024):
                f.write(chunk)
        logging.info(f"成功下载：{temp_sound_url}")
        return target_mp3
    except requests.exceptions.RequestException as e:
        logging.error(f"下载失败：{temp_sound_url}, 错误：{e}")
        return None

# 处理单条记录
def process_sentence(row):
    english, english_digest, sentence_id, temp_sound_url = row
    logging.info(f"处理句子：[{sentence_id}] {english} - {temp_sound_url}")
    
    # 检查temp_sound_url和english_digest是否有效
    if not temp_sound_url or not english_digest:
        logging.error(f"无效的 URL 或 digest，跳过：{sentence_id}, {english}")
        return

    # 下载音频
    mp3_path = download_mp3(english_digest, temp_sound_url)
    if mp3_path is None:
        raise Exception(f"下载失败：{temp_sound_url}")

    # 使用每个线程自己的数据库连接
    db = pymysql.connect(**db_config)
    try:
        with db.cursor() as cursor:
            cursor.execute("""
                UPDATE sentence
                SET needTts=0, producer='coze', theType='tts', updateTime=NOW()
                WHERE id=%s
            """, (sentence_id,))
        db.commit()
        logging.info(f"数据库更新成功：{sentence_id}")
    except Exception as e:
        db.rollback()
        logging.error(f"数据库更新失败：{sentence_id}, 错误：{e}")
        raise e
    finally:
        db.close()  # 每个线程完成后关闭数据库连接

# 主函数
def main():
    db = None
    try:
        db = pymysql.connect(**db_config)  # 主线程的数据库连接
        with db.cursor() as cursor:
            cursor.execute("SELECT English, englishDigest, id, temp_sound_url FROM sentence WHERE theType='temp_sound' LIMIT 20")
            results = cursor.fetchall()
            logging.info(f"从数据库读取 {len(results)} 条记录")

        if not results:
            logging.info("没有需要处理的句子")
            return

        # 限制线程池大小
        with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
            future_to_sentence = {executor.submit(process_sentence, row): row for row in results}
            for future in concurrent.futures.as_completed(future_to_sentence):
                try:
                    future.result()
                except Exception as e:
                    logging.error(f"处理失败：{e}")

    except Exception as e:
        logging.error(f"主流程异常：{e}")
    finally:
        if db:
            db.close()  # 确保主线程数据库连接被关闭
        logging.info("程序结束")

if __name__ == "__main__":
    main()
