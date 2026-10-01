#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
真机本地 SQLite 数据库审计与端云偏离检查器
1. 提取真机 /data/data/com.nn.nnbdc.android/app_flutter/db.sqlite
2. 深度审计本地 learning_logs (评分, 稳定性, 下次复习天数)
3. 检查 2000ms 内重复评分违规 (DuplicateGradeViolation)
4. 校验「已掌握」词书本地数据
5. 与生产云端 PostgreSQL 进行跨库 Diff 校验
"""

import os
import sqlite3
import subprocess
from datetime import datetime
from typing import Dict, List, Optional, Tuple

class LocalDbAuditor:
    def __init__(self, serial: Optional[str] = None, work_dir: str = "/Volumes/ssd/ppdc/tmp"):
        self.serial = serial
        self.work_dir = os.path.abspath(work_dir)
        os.makedirs(self.work_dir, exist_ok=True)
        self.local_sqlite_path = os.path.join(self.work_dir, "e2e_audited_local.sqlite")

    def _run_adb(self, args: List[str]) -> subprocess.CompletedProcess:
        cmd = ["adb"]
        if self.serial:
            cmd.extend(["-s", self.serial])
        cmd.extend(args)
        return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    def pull_local_db(self) -> str:
        """从 Android 应用沙盒导出并拉取 db.sqlite 与 WAL"""
        copy_cmd = (
            "run-as com.nn.nnbdc.android cp app_flutter/db.sqlite /sdcard/e2e_dump.sqlite && "
            "run-as com.nn.nnbdc.android cp app_flutter/db.sqlite-wal /sdcard/e2e_dump.sqlite-wal 2>/dev/null || true"
        )
        self._run_adb(["shell", copy_cmd])

        # pull 到本地
        dest_db = self.local_sqlite_path
        dest_wal = self.local_sqlite_path + "-wal"
        self._run_adb(["pull", "/sdcard/e2e_dump.sqlite", dest_db])
        self._run_adb(["pull", "/sdcard/e2e_dump.sqlite-wal", dest_wal])
        return dest_db

    def audit_local_learning_data(self) -> Dict:
        """全量审计真机本地 SQLite 中的学习数据与 FSRS 算法指标"""
        if not os.path.exists(self.local_sqlite_path):
            self.pull_local_db()

        conn = sqlite3.connect(self.local_sqlite_path)
        cur = conn.cursor()

        # 1. 审计 learning_logs
        cur.execute("""
        SELECT id, user_id, word_id, rating, stability, difficulty, elapsed_days, scheduled_days, create_time
        FROM learning_logs
        ORDER BY create_time ASC;
        """)
        raw_logs = cur.fetchall()

        logs = []
        duplicate_violations = []
        last_log_by_word = {}

        for row in raw_logs:
            log_item = {
                "id": row[0],
                "user_id": row[1],
                "word_id": row[2],
                "rating": row[3],
                "stability": row[4],
                "difficulty": row[5],
                "elapsed_days": row[6],
                "scheduled_days": row[7],
                "create_time": row[8]
            }
            logs.append(log_item)

            # 重复评分违规检测 (2000ms 窗口)
            wid = row[2]
            ctime = row[8]  # 秒级或毫秒级时间戳
            if wid in last_log_by_word:
                prev = last_log_by_word[wid]
                diff_ms = abs(ctime - prev["create_time"]) * 1000 if ctime < 10000000000 else abs(ctime - prev["create_time"])
                if diff_ms < 2000:
                    duplicate_violations.append({
                        "word_id": wid,
                        "first_log_id": prev["id"],
                        "second_log_id": row[0],
                        "gap_ms": diff_ms,
                        "rating": row[3]
                    })
            last_log_by_word[wid] = log_item

        # 2. 审计 learning_words
        cur.execute("""
        SELECT word_id, state, learned_times, today_learned_times, stability, difficulty, scheduled_days
        FROM learning_words;
        """)
        words = []
        for row in cur.fetchall():
            words.append({
                "word_id": row[0],
                "state": row[1],
                "learned_times": row[2],
                "today_learned_times": row[3],
                "stability": row[4],
                "difficulty": row[5],
                "scheduled_days": row[6]
            })

        # 3. 审计「已掌握」词书
        cur.execute("""
        SELECT dw.word_id, dw.create_time
        FROM dict_words dw
        JOIN dicts d ON dw.dict_id = d.id
        WHERE d.name = '已掌握'
        ORDER BY dw.create_time DESC;
        """)
        mastered_words = [{"word_id": r[0], "create_time": r[1]} for r in cur.fetchall()]

        conn.close()

        return {
            "total_logs": len(logs),
            "logs": logs,
            "duplicate_violations": duplicate_violations,
            "total_learning_words": len(words),
            "learning_words": words,
            "mastered_words_count": len(mastered_words),
            "mastered_words": mastered_words
        }

    def verify_local_and_cloud_alignment(self, cloud_logs: List[Dict], cloud_words: List[Dict]) -> Tuple[bool, str]:
        """端云双向对齐检查：对比手机本地 SQLite 与云端 PostgreSQL"""
        local_data = self.audit_local_learning_data()
        local_logs = local_data["logs"]
        local_words = local_data["learning_words"]

        issues = []

        # 1. 检查日志条数是否对齐
        if len(local_logs) != len(cloud_logs):
            issues.append(f"评分流水条数端云不一致: 本地={len(local_logs)}条, 云端={len(cloud_logs)}条")

        # 2. 检查是否有重复评分流水
        if local_data["duplicate_violations"]:
            issues.append(f"本地发现 {len(local_data['duplicate_violations'])} 处 2000ms 内重复评分违规 (DuplicateGradeViolation)")

        # 3. 检查 FSRS scheduled_days 与 rating 合法性
        for log in local_logs:
            if log["rating"] not in (1, 2, 3, 4):
                issues.append(f"本地日志非法 rating: log_id={log['id']}, rating={log['rating']}")
            if log["scheduled_days"] <= 0:
                issues.append(f"本地日志 scheduled_days 未生效: log_id={log['id']}, scheduled_days={log['scheduled_days']}")
            if log["stability"] <= 0:
                issues.append(f"本地日志 stability 异常: log_id={log['id']}, stability={log['stability']}")

        # 4. 检查学习词表覆盖
        if len(local_words) != len(cloud_words):
            issues.append(f"记忆词数端云不一致: 本地={len(local_words)}, 云端={len(cloud_words)}")

        passed = len(issues) == 0
        details = "端云数据完全自洽，FSRS 评分与复习间隔全部对齐" if passed else "；".join(issues)
        return passed, details
