#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
真机本地 SQLite 审计器

职责：
1. 从真机应用沙盒取一份**一致的**数据库快照（先停进程，避免 db.sqlite 与 WAL 在拉取途中被写入）；
2. 读单词释义（meaning_items），给「选择题答得对不对」提供地面真值；
3. 审计 learning_logs 的评分、复习间隔、2000ms 内重复评分；
4. 与云端 PostgreSQL 做端云对比；
5. 供跨天用例把本地打卡与学习日期整体前移一天。
"""

import os
import sqlite3
from datetime import datetime
import subprocess
from typing import Dict, List, Optional, Tuple

APP_PACKAGE = "com.nn.nnbdc.android"
DB_REL = "app_flutter/db.sqlite"


class LocalDbAuditor:
    def __init__(self, serial: Optional[str] = None,
                 work_dir: str = "/Volumes/ssd/ppdc/tmp"):
        self.serial = serial
        self.work_dir = os.path.abspath(work_dir)
        os.makedirs(self.work_dir, exist_ok=True)
        self.local_sqlite_path = os.path.join(self.work_dir, "e2e_local_snapshot.sqlite")

    def _run_adb(self, args: List[str], binary: bool = False):
        cmd = ["adb"]
        if self.serial:
            cmd.extend(["-s", self.serial])
        cmd.extend(args)
        return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              text=not binary)

    # ---------- 快照 ----------

    def pull_snapshot(self) -> str:
        """把 db.sqlite 与 WAL、SHM 一起取回本地。

        调用方必须先 `stop_app()`：进程还活着时三份文件可能在不同时刻被写入，
        拉回来的就是撕裂快照，会凭空造出「端云不一致」。
        """
        dest = self.local_sqlite_path
        for suffix, required in (("", True), ("-wal", False), ("-shm", False)):
            local_path = dest + suffix
            res = self._run_adb(
                ["exec-out", "run-as", APP_PACKAGE, "cat", DB_REL + suffix], binary=True
            )
            if res.returncode != 0 or not res.stdout:
                if required:
                    raise RuntimeError(
                        f"拉取 {DB_REL}{suffix} 失败: {res.stderr.decode('utf-8', 'ignore')}"
                    )
                if os.path.exists(local_path):
                    os.remove(local_path)
                continue
            with open(local_path, "wb") as f:
                f.write(res.stdout)
        return dest

    def push_snapshot(self) -> None:
        """把本地改过的快照推回真机（时间旅行用），并清掉旧的 WAL/SHM。"""
        remote_tmp = "/sdcard/e2e_push.sqlite"
        for suffix in ("", "-wal", "-shm"):
            local_path = self.local_sqlite_path + suffix
            if os.path.exists(local_path):
                self._run_adb(["push", local_path, remote_tmp + suffix])
                self._run_adb(["shell", "run-as", APP_PACKAGE, "cp",
                               remote_tmp + suffix, DB_REL + suffix])
            else:
                self._run_adb(["shell", "run-as", APP_PACKAGE, "rm", "-f", DB_REL + suffix])
        self._run_adb(["shell", "rm", "-f", remote_tmp, remote_tmp + "-wal", remote_tmp + "-shm"])

    def _connect(self) -> sqlite3.Connection:
        return sqlite3.connect(self.local_sqlite_path)

    # ---------- 释义地面真值 ----------

    def word_meanings(self, spells: List[str]) -> Dict[str, List[str]]:
        """spell -> 中文释义列表。选择题选项就是「词性. 释义；释义」拼出来的。"""
        if not spells:
            return {}
        conn = self._connect()
        try:
            marks = ",".join("?" * len(spells))
            rows = conn.execute(
                f"SELECT w.spell, m.meaning FROM words w "
                f"JOIN meaning_items m ON m.word_id = w.id "
                f"WHERE w.spell IN ({marks}) ORDER BY m.popularity ASC",
                spells,
            ).fetchall()
        finally:
            conn.close()
        result: Dict[str, List[str]] = {}
        for spell, meaning in rows:
            result.setdefault(spell, []).append(meaning)
        return result

    def meanings_by_spell(self) -> Dict[str, List[str]]:
        conn = self._connect()
        try:
            rows = conn.execute(
                "SELECT w.spell, m.meaning FROM words w "
                "JOIN meaning_items m ON m.word_id = w.id"
            ).fetchall()
        finally:
            conn.close()
        result: Dict[str, List[str]] = {}
        for spell, meaning in rows:
            result.setdefault(spell, []).append(meaning)
        return result

    # ---------- 学习数据审计 ----------

    def audit_local_learning_data(self, user_id: str) -> Dict:
        """只审当前账号的流水。

        本地库是全设备共用的一份：注销过的旧账号的 learning_logs / learning_words
        仍留在库里（实测一份快照里还躺着别的账号 5614 条流水）。不按 user_id 过滤，
        就会拿「所有历史账号的总和」去和云端比，必然对不上。
        """
        conn = self._connect()
        cur = conn.cursor()
        rows = cur.execute(
            "SELECT l.id, l.word_id, l.rating, l.stability, l.difficulty, "
            "l.elapsed_days, l.scheduled_days, l.create_time, w.spell "
            "FROM learning_logs l LEFT JOIN words w ON l.word_id = w.id "
            "WHERE l.user_id = ? ORDER BY l.create_time ASC", (user_id,)
        ).fetchall()

        logs: List[Dict] = []
        duplicate_violations: List[Dict] = []
        last_by_word: Dict[str, Dict] = {}
        for row in rows:
            item = {
                "id": row[0], "word_id": row[1], "rating": row[2],
                "stability": row[3], "difficulty": row[4], "elapsed_days": row[5],
                "scheduled_days": row[6], "create_time": row[7], "spell": row[8],
            }
            logs.append(item)
            prev = last_by_word.get(item["word_id"])
            if prev is not None:
                gap_ms = abs(item["create_time"] - prev["create_time"]) * 1000
                if gap_ms < 2000:
                    duplicate_violations.append({
                        "word_id": item["word_id"],
                        "first_log_id": prev["id"],
                        "second_log_id": item["id"],
                        "gap_ms": gap_ms,
                        "rating": item["rating"],
                    })
            last_by_word[item["word_id"]] = item

        mastered = cur.execute(
            "SELECT dw.word_id FROM dict_words dw "
            "JOIN dicts d ON dw.dict_id = d.id "
            "WHERE d.name = '已掌握' AND d.owner_id = ?", (user_id,)
        ).fetchall()
        learning_word_count = cur.execute(
            "SELECT COUNT(*) FROM learning_words WHERE user_id = ?", (user_id,)
        ).fetchone()[0]
        conn.close()

        return {
            "total_logs": len(logs),
            "logs": logs,
            "duplicate_violations": duplicate_violations,
            "total_learning_words": learning_word_count,
            "mastered_words": [{"word_id": r[0]} for r in mastered],
        }

    def local_dakas(self, user_id: str) -> List[Dict]:
        """本地打卡：把 epoch 秒换成 YYYY-MM-DD，和云端按日期对齐。"""
        conn = self._connect()
        try:
            rows = conn.execute(
                "SELECT for_learning_date, COALESCE(text_content, '') FROM dakas "
                "WHERE user_id = ?", (user_id,)).fetchall()
        finally:
            conn.close()
        result = []
        for epoch, text in rows:
            day = datetime.fromtimestamp(int(epoch)).strftime("%Y-%m-%d") if epoch else ""
            result.append({"date": day, "text": (text or "").strip()})
        return result

    def local_daily_stats(self, user_id: str) -> List[Dict]:
        conn = self._connect()
        try:
            rows = conn.execute(
                "SELECT date, COALESCE(review_count, 0) FROM user_study_daily_stats "
                "WHERE user_id = ?", (user_id,)).fetchall()
        finally:
            conn.close()
        result = []
        for epoch, count in rows:
            day = datetime.fromtimestamp(int(epoch)).strftime("%Y-%m-%d") if epoch else ""
            result.append({"date": day, "review_count": int(count or 0)})
        return result

    @staticmethod
    def _same_number(a, b, tolerance: float = 1e-6) -> bool:
        if a is None or b is None:
            return a is b
        try:
            fa, fb = float(a), float(b)
        except (TypeError, ValueError):
            return a == b
        return abs(fa - fb) <= tolerance * max(1.0, abs(fa), abs(fb))

    def diff_logs(self, local_logs: List[Dict], cloud_logs: List[Dict],
                  max_detail: int = 3) -> List[str]:
        """逐条、逐字段比对评分流水：先比有哪些条，再比同一条里的数值。"""
        issues: List[str] = []
        local_by_id = {str(x["id"]): x for x in local_logs}
        cloud_by_id = {str(x["id"]): x for x in cloud_logs}
        only_local = sorted(set(local_by_id) - set(cloud_by_id))
        only_cloud = sorted(set(cloud_by_id) - set(local_by_id))
        if only_local:
            issues.append(f"本地有 {len(only_local)} 条流水云端没有（如 {only_local[:max_detail]}）")
        if only_cloud:
            issues.append(f"云端有 {len(only_cloud)} 条流水本地没有（如 {only_cloud[:max_detail]}）")

        mismatches: List[str] = []
        for log_id in sorted(set(local_by_id) & set(cloud_by_id)):
            local, cloud = local_by_id[log_id], cloud_by_id[log_id]
            for field, label in (("rating", "评分"), ("stability", "稳定性"),
                                 ("difficulty", "难度"),
                                 ("scheduled_days", "复习间隔"),
                                 ("elapsed_days", "经过天数")):
                lv, cv = local.get(field), cloud.get(field)
                if lv is None and cv is None:
                    continue
                if not self._same_number(lv, cv):
                    mismatches.append(
                        f"{local.get('spell') or log_id} 的{label}: 本地={lv} 云端={cv}")
        if mismatches:
            issues.append(f"{len(mismatches)} 处字段值端云不一致："
                          + "；".join(mismatches[:max_detail]))
        return issues

    def diff_dakas(self, local_dakas: List[Dict], cloud_dakas: List[Dict],
                   max_detail: int = 3) -> List[str]:
        issues: List[str] = []
        local_by_day = {d["date"]: d for d in local_dakas if d["date"]}
        cloud_by_day = {d["date"]: d for d in cloud_dakas if d["date"]}
        only_local = sorted(set(local_by_day) - set(cloud_by_day))
        only_cloud = sorted(set(cloud_by_day) - set(local_by_day))
        if only_local:
            issues.append(f"本地有 {len(only_local)} 天打卡云端没有: {only_local[:max_detail]}")
        if only_cloud:
            issues.append(f"云端有 {len(only_cloud)} 天打卡本地没有: {only_cloud[:max_detail]}")
        text_diffs = []
        for day in sorted(set(local_by_day) & set(cloud_by_day)):
            lt = local_by_day[day]["text"]
            ct = cloud_by_day[day]["text"]
            if lt != ct:
                text_diffs.append(f"{day} 文案 本地={lt[:24]!r} 云端={ct[:24]!r}")
        if text_diffs:
            issues.append(f"{len(text_diffs)} 天打卡文案端云不一致：" + "；".join(text_diffs[:max_detail]))
        return issues

    def diff_daily_stats(self, local_stats: List[Dict], cloud_stats: List[Dict],
                         max_detail: int = 3) -> List[str]:
        """只比复习条数：专注时长是本地一直在跑的计数器，同步时点不同必然有差。"""
        issues: List[str] = []
        local_by_day = {d["date"]: d for d in local_stats if d["date"]}
        cloud_by_day = {d["date"]: d for d in cloud_stats if d["date"]}
        only_local = sorted(set(local_by_day) - set(cloud_by_day))
        only_cloud = sorted(set(cloud_by_day) - set(local_by_day))
        if only_local:
            issues.append(f"本地有 {len(only_local)} 天学习统计云端没有: {only_local[:max_detail]}")
        if only_cloud:
            issues.append(f"云端有 {len(only_cloud)} 天学习统计本地没有: {only_cloud[:max_detail]}")
        diffs = []
        for day in sorted(set(local_by_day) & set(cloud_by_day)):
            lv = local_by_day[day]["review_count"]
            cv = cloud_by_day[day]["review_count"]
            if lv != cv:
                diffs.append(f"{day} 复习条数 本地={lv} 云端={cv}")
        if diffs:
            issues.append(f"{len(diffs)} 天复习条数端云不一致：" + "；".join(diffs[:max_detail]))
        return issues

    def verify_local_and_cloud_alignment(self, cloud_logs: List[Dict],
                                         cloud_words: List[Dict],
                                         user_id: str,
                                         cloud_dakas: List[Dict] = None,
                                         cloud_daily_stats: List[Dict] = None
                                         ) -> Tuple[bool, str]:
        local = self.audit_local_learning_data(user_id)
        issues: List[str] = []
        if local["total_logs"] != len(cloud_logs):
            issues.append(f"评分流水条数端云不一致: 本地={local['total_logs']}, 云端={len(cloud_logs)}")
        if local["duplicate_violations"]:
            issues.append(f"本地发现 {len(local['duplicate_violations'])} 处 2000ms 内重复评分")
        if local["total_learning_words"] != len(cloud_words):
            issues.append(f"记忆词数端云不一致: 本地={local['total_learning_words']}, 云端={len(cloud_words)}")
        for log in local["logs"]:
            if log["rating"] not in (1, 2, 3, 4):
                issues.append(f"非法评分 rating={log['rating']} (log {log['id']})")
            if log["scheduled_days"] <= 0:
                issues.append(f"复习间隔未生效 scheduled_days={log['scheduled_days']} (log {log['id']})")
            if log["stability"] <= 0:
                issues.append(f"稳定性异常 stability={log['stability']} (log {log['id']})")
        # 逐字段值比对：条数对上不代表数值对上
        issues.extend(self.diff_logs(local["logs"], cloud_logs))
        if cloud_dakas is not None:
            issues.extend(self.diff_dakas(self.local_dakas(user_id), cloud_dakas))
        if cloud_daily_stats is not None:
            issues.extend(self.diff_daily_stats(self.local_daily_stats(user_id),
                                                cloud_daily_stats))

        passed = not issues
        detail = ("条数与逐字段取值全部一致：评分流水、打卡日期与文案、每日复习条数都对得上"
                  if passed else "；".join(issues))
        return passed, detail

    # ---------- 跨天时间旅行 ----------

    def shift_one_day_back(self, user_id: str) -> int:
        """把当前账号的打卡、学习日期整体前移 86400 秒，模拟「昨天学过」。"""
        conn = self._connect()
        cur = conn.cursor()
        changed = 0
        for sql in (
            "UPDATE dakas SET for_learning_date = for_learning_date - 86400, "
            "create_time = create_time - 86400, update_time = update_time - 86400 "
            "WHERE user_id = ?",
            "UPDATE learning_words SET last_learning_date = last_learning_date - 86400, "
            "update_time = update_time - 86400 WHERE user_id = ?",
            "UPDATE user_study_daily_stats SET date = date - 86400, "
            "update_time = update_time - 86400 WHERE user_id = ?",
        ):
            cur.execute(sql, (user_id,))
            changed += cur.rowcount if cur.rowcount > 0 else 0
        conn.commit()
        conn.close()
        return changed
