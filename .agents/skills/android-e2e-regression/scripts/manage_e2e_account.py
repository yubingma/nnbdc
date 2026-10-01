#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
E2E 回归测试辅助模块 (e2etest@nnbdc.com)
端到端原则：
1. 真实用户注册链路：账号由手机 App 输入邮箱和验证码自助触发注册与初始化；
2. 真实用户注销链路：账号通过手机端「注销账号」功能自助销毁；
3. 本模块唯一在日常回归中使用的核心功能：从生产库截获最新邮箱验证码 (get_latest_code)。
   (自动化测试无法人肉收取邮件，读取 verification_code 表是唯一必要的外部配合)。
"""

import os
import sys
import argparse
import subprocess
from datetime import datetime
import time

PROD_HOST = "47.108.27.205"
PROD_PORT = "22"
PROD_USER = "root"
PROD_DB_NAME = "bdc"
PROD_DB_USER = "myb"
E2E_EMAIL = "e2etest@nnbdc.com"

def get_server_pwd():
    pwd = os.environ.get("nnbdc_server_pwd")
    if not pwd:
        try:
            with open(os.path.expanduser("~/.zprofile"), "r", encoding="utf-8") as f:
                for line in f:
                    if "nnbdc_server_pwd=" in line:
                        pwd = line.split("nnbdc_server_pwd=")[1].strip().strip('"').strip("'")
                        break
        except Exception:
            pass
    return pwd

def run_psql(sql: str) -> str:
    """通过 SSH 隧道在生产 docker pg 容器中执行 SQL (带重试机制)"""
    pwd = get_server_pwd()
    if not pwd:
        raise RuntimeError("未检测到环境变量 nnbdc_server_pwd，请在环境或 ~/.zprofile 中配置。")
    
    escaped_sql = sql.replace('"', '\\"')
    cmd = [
        "sshpass", "-p", pwd,
        "ssh", "-o", "StrictHostKeyChecking=no",
        "-o", "ConnectTimeout=10",
        "-p", PROD_PORT,
        f"{PROD_USER}@{PROD_HOST}",
        f'docker exec -i pg psql -U{PROD_DB_USER} -d {PROD_DB_NAME} -A -t -c "{escaped_sql}"'
    ]
    
    last_err = None
    for attempt in range(3):
        try:
            res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20)
            if res.returncode == 0:
                return res.stdout.strip()
            last_err = res.stderr.strip() or res.stdout.strip()
        except Exception as e:
            last_err = str(e)
        time.sleep(1)

    raise RuntimeError(f"SQL 执行失败: {last_err}")

def clear_old_codes():
    """清理发往 e2etest 邮箱的历史旧验证码，确保后续获取的一定是当前测试生成的"""
    sql = f"DELETE FROM email_verification_code WHERE email = '{E2E_EMAIL}';"
    run_psql(sql)

def get_latest_code() -> str:
    """获取发往 e2etest@nnbdc.com 的最新有效验证码 (回归核心：唯一连库操作)"""
    sql = f"""
    SELECT code FROM email_verification_code
    WHERE email = '{E2E_EMAIL}' AND used = false
    ORDER BY create_time DESC LIMIT 1;
    """
    code = run_psql(sql)
    return code.strip() if code else None

def check_user():
    """只读检查 e2etest 用户在云端是否存在"""
    sql = f'SELECT id, user_name, email, cow_dung, words_per_day, create_time FROM "user" WHERE email = \'{E2E_EMAIL}\';'
    out = run_psql(sql)
    if not out:
        return None
    parts = out.split("|")
    return {
        "id": parts[0],
        "user_name": parts[1],
        "email": parts[2],
        "cow_dung": parts[3] if len(parts) > 3 else "0",
        "words_per_day": parts[4] if len(parts) > 4 else "10",
        "create_time": parts[5] if len(parts) > 5 else ""
    }

def check_user_daka(user_id: str = None):
    """查询该用户在云端是否存在打卡记录"""
    if not user_id:
        user = check_user()
        if not user:
            return None
        user_id = user["id"]
    sql = f"SELECT user_id, for_learning_date, text, create_time FROM daka WHERE user_id = '{user_id}' ORDER BY create_time DESC LIMIT 1;"
    out = run_psql(sql)
    if not out:
        return None
    parts = out.split("|")
    return {
        "user_id": parts[0],
        "for_learning_date": parts[1] if len(parts) > 1 else "",
        "text": parts[2] if len(parts) > 2 else "",
        "create_time": parts[3] if len(parts) > 3 else ""
    }

def purge_e2e_user_db_only():
    """
    【仅限应急清理】：当真机由于客户端严重 Bug 无法进入设置进行「注销账号」时，
    才使用此函数在云端执行级联删除，彻底抹除 e2etest 账号以恢复初始环境。
    安全红线：硬编码 WHERE email = 'e2etest@nnbdc.com'，绝不触碰生产任何其他用户。
    """
    user = check_user()
    if not user:
        print(f"[*] 生产库中已无 {E2E_EMAIL} 账号，无需清理。")
        return

    uid = user["id"]
    print(f"[!] 触发云端安全物理删除: {E2E_EMAIL} (userId={uid})...")
    sql = f"""
    BEGIN;
    DELETE FROM email_verification_code WHERE email = '{E2E_EMAIL}';
    DELETE FROM user_study_step WHERE user_id = '{uid}';
    DELETE FROM learning_dict WHERE user_id = '{uid}';
    DELETE FROM user_db_log WHERE user_id = '{uid}';
    DELETE FROM user_db_version WHERE user_id = '{uid}';
    DELETE FROM daka WHERE user_id = '{uid}';
    DELETE FROM user_oper WHERE user_id = '{uid}';
    DELETE FROM user_study_daily_stat WHERE user_id = '{uid}';
    DELETE FROM user_study_record WHERE user_id = '{uid}';
    DELETE FROM dict_word WHERE dict_id IN (SELECT id FROM dict WHERE owner_id = '{uid}');
    DELETE FROM dict WHERE owner_id = '{uid}';
    DELETE FROM "user" WHERE id = '{uid}';
    COMMIT;
    """
    run_psql(sql)
    print(f"✅ 生产库已彻底清除 {E2E_EMAIL} 遗留数据。")

def main():
    parser = argparse.ArgumentParser(description="E2E 回归测试生产数据库辅助工具")
    parser.add_argument("--get-code", action="store_true", help="获取最新登录验证码")
    parser.add_argument("--check", action="store_true", help="只读核验测试账号是否存在")
    parser.add_argument("--purge", action="store_true", help="应急物理清理测试账号")

    args = parser.parse_args()

    if args.get_code:
        code = get_latest_code()
        if code:
            print(f"CODE:{code}")
        else:
            print("未找到有效的验证码")
    elif args.check:
        user = check_user()
        if user:
            print(f"✅ 账号存在: ID={user['id']}, 用户名={user['user_name']}, 泡泡={user['cow_dung']}")
        else:
            print(f"ℹ️ 账号不存在: {E2E_EMAIL}")
    elif args.purge:
        purge_e2e_user_db_only()
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
