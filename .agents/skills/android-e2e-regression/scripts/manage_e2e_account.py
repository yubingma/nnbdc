#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
管理 E2E 回归测试专属账号 (e2etest@nnbdc.com)
支持：检查账号、自动创建初始化、数据重置、提取最新验证码
安全红线：仅针对 e2etest@nnbdc.com 精确操作，绝不波及生产其他用户。
"""

import os
import sys
import uuid
import argparse
import subprocess
from datetime import datetime
import time

# 生产环境配置（支持读取环境变量或 ~/.zprofile）
PROD_HOST = "47.108.27.205"
PROD_PORT = "22"
PROD_USER = "root"
PROD_DB_NAME = "bdc"
PROD_DB_USER = "myb"
E2E_EMAIL = "e2etest@nnbdc.com"
E2E_USERNAME = "e2etest"
E2E_NICKNAME = "E2E测试用户"

def get_server_pwd():
    pwd = os.environ.get("nnbdc_server_pwd")
    if not pwd:
        # 尝试从 ~/.zprofile 解析
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
    """通过 SSH 隧道/命令在生产 docker pg 容器中执行 SQL (带重试机制)"""
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

def check_user():
    """检查 e2etest 用户是否存在"""
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

def create_e2e_user():
    """在生产库中创建 e2etest 账号及配套基础数据"""
    user_id = uuid.uuid4().hex
    raw_dict_id = uuid.uuid4().hex
    mastered_dict_id = uuid.uuid4().hex
    version_id = uuid.uuid4().hex

    print(f"[*] 正在为 {E2E_EMAIL} 创建用户实体 (userId={user_id})...")

    # 1. 插入 user 表
    sql_user = f"""
    INSERT INTO "user" (
        id, user_name, nick_name, email, password,
        words_per_day, daka_day_count, learned_days, mastered_words,
        cow_dung, throw_dice_chance, continuous_daka_day_count, max_continuous_daka_day_count,
        daka_score, game_score, total_learning_seconds, today_learning_seconds,
        is_admin, is_super_admin, is_inputor, is_sys_user, is_premium_ios,
        invite_award_taken, learning_finished, today_study_started,
        create_time, update_time
    ) VALUES (
        '{user_id}', '{E2E_USERNAME}', '{E2E_NICKNAME}', '{E2E_EMAIL}', '',
        10, 0, 0, 0,
        100, 5, 0, 0,
        0, 0, 0, 0,
        false, false, false, false, false,
        false, false, false,
        NOW(), NOW()
    );
    """

    # 2. 插入生词本与已掌握词书
    sql_dicts = f"""
    INSERT INTO dict (id, name, word_count, is_ready, is_shared, visible, editable, deletable, owner_id, popularity_limit, create_time, update_time)
    VALUES ('{raw_dict_id}', '生词本', 0, true, false, true, true, false, '{user_id}', 5, NOW(), NOW());

    INSERT INTO learning_dict (dict_id, user_id, is_privileged, fetch_mastered, sort_alg, create_time, update_time)
    VALUES ('{raw_dict_id}', '{user_id}', false, true, 'ORIGINAL', NOW(), NOW());

    INSERT INTO dict (id, name, word_count, is_ready, is_shared, visible, editable, deletable, owner_id, popularity_limit, create_time, update_time)
    VALUES ('{mastered_dict_id}', '已掌握', 0, true, false, true, false, false, '{user_id}', 5, NOW(), NOW());

    INSERT INTO learning_dict (dict_id, user_id, is_privileged, fetch_mastered, sort_alg, create_time, update_time)
    VALUES ('{mastered_dict_id}', '{user_id}', false, false, 'ORIGINAL', NOW(), NOW());
    """

    # 3. 插入用户学习步骤 (new / review)
    sql_steps = f"""
    INSERT INTO user_study_step (user_id, scope, group_name, study_step, seq, state, create_time, update_time)
    VALUES
        ('{user_id}', 'new', 'check', 'En2Ch', 0, 'Active', NOW(), NOW()),
        ('{user_id}', 'new', 'correct', 'Ch2En', 0, 'Active', NOW(), NOW()),
        ('{user_id}', 'new', 'wrong', 'Ch2En', 0, 'Active', NOW(), NOW()),
        ('{user_id}', 'review', 'check', 'En2Ch', 0, 'Active', NOW(), NOW()),
        ('{user_id}', 'review', 'wrong', 'Ch2En', 0, 'Active', NOW(), NOW());
    """

    # 4. 插入 user_db_version
    sql_version = f"""
    INSERT INTO user_db_version (id, user_id, version, create_time, update_time)
    VALUES ('{version_id}', '{user_id}', 1, NOW(), NOW());
    """

    full_sql = f"BEGIN;\n{sql_user}\n{sql_dicts}\n{sql_steps}\n{sql_version}\nCOMMIT;"
    run_psql(full_sql)
    print(f"✅ 用户 {E2E_EMAIL} 创建成功！(ID: {user_id})")
    return user_id

def reset_e2e_user(user_id: str):
    """重置测试用户数据，恢复到干净的初始回归测试状态"""
    print(f"[*] 正在重置用户 {E2E_EMAIL} (userId={user_id}) 的测试数据...")
    sql = f"""
    BEGIN;
    -- 清理打卡与学习流水
    DELETE FROM daka WHERE user_id = '{user_id}';
    DELETE FROM user_oper WHERE user_id = '{user_id}';
    DELETE FROM user_study_daily_stat WHERE user_id = '{user_id}';
    DELETE FROM user_study_record WHERE user_id = '{user_id}';
    DELETE FROM user_db_log WHERE user_id = '{user_id}';

    -- 清理生词本中的测试单词
    DELETE FROM dict_word WHERE dict_id IN (SELECT id FROM dict WHERE owner_id = '{user_id}');
    UPDATE dict SET word_count = 0 WHERE owner_id = '{user_id}';

    -- 恢复基础属性与测试魔法泡泡
    UPDATE "user" SET
        daka_day_count = 0,
        continuous_daka_day_count = 0,
        max_continuous_daka_day_count = 0,
        learned_days = 0,
        mastered_words = 0,
        cow_dung = 100,
        today_study_started = false,
        total_learning_seconds = 0,
        today_learning_seconds = 0,
        last_daka_date = NULL,
        last_learning_date = NULL,
        update_time = NOW()
    WHERE id = '{user_id}';

    -- 重置同步版本号为 1
    UPDATE user_db_version SET version = 1, update_time = NOW() WHERE user_id = '{user_id}';

    COMMIT;
    """
    run_psql(sql)
    print(f"✅ 用户 {E2E_EMAIL} 数据重置完成，状态已还原为纯净初始态。")

def get_latest_code():
    """获取发往 e2etest@nnbdc.com 的最新有效验证码"""
    sql = f"""
    SELECT code FROM email_verification_code
    WHERE email = '{E2E_EMAIL}' AND used = false
    ORDER BY create_time DESC LIMIT 1;
    """
    code = run_psql(sql)
    return code.strip()

def main():
    parser = argparse.ArgumentParser(description="E2E 回归测试数据库账号管理工具")
    parser.add_argument("--check", action="store_true", help="检查测试账号是否存在")
    parser.add_argument("--ensure", action="store_true", help="若不存在则自动创建，若存在则打印")
    parser.add_argument("--reset", action="store_true", help="重置测试账号数据到初始状态")
    parser.add_argument("--get-code", action="store_true", help="获取最新登录验证码")

    args = parser.parse_args()

    if args.get_code:
        code = get_latest_code()
        if code:
            print(f"CODE:{code}")
        else:
            print("未找到有效的验证码")
        return

    user = check_user()

    if args.check:
        if user:
            print(f"✅ 账号存在: ID={user['id']}, 用户名={user['user_name']}, 泡泡={user['cow_dung']}, 词/日={user['words_per_day']}")
        else:
            print(f"❌ 账号不存在: {E2E_EMAIL}")
        return

    if args.ensure:
        if not user:
            print(f"⚠️ 账号 {E2E_EMAIL} 不存在，开始自动创建...")
            user_id = create_e2e_user()
            user = check_user()
        else:
            print(f"✅ 账号已就绪: ID={user['id']}, 用户名={user['user_name']}")
        return

    if args.reset:
        if not user:
            print(f"⚠️ 账号不存在，正在创建并初始化...")
            create_e2e_user()
        else:
            reset_e2e_user(user["id"])
        return

    # 默认行为：ensure
    if not user:
        create_e2e_user()
    else:
        print(f"✅ 账号已就绪: {user}")

if __name__ == "__main__":
    main()
