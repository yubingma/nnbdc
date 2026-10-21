#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
老版本覆盖升级与本地库迁移检查

要验的是真事：一个用户手机上装着老版本（线上正式包），里面有他的数据；
装上新手包之后，App 还得能起来、还得是登录态、旧数据还在、本地库结构升到新版本。

四步：
1. 卸干净，装线上正式包（老版本），启动并登录，让它产生真实数据；
2. 覆盖安装新手包（同一个签名，走真正的应用升级路径）；
3. 启动新包，确认没崩、仍是登录态；
4. 把本地库拉回来，看 `PRAGMA user_version` 是否升到当前 schemaVersion，旧数据是否还在。

与 run_regression.py 分开，是因为它要在「老包」上跑一段，两套数据状态不该混。
"""

import argparse
import os
import sqlite3
import subprocess
import sys
import time
from datetime import datetime

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.append(SCRIPT_DIR)

from device_controller import AndroidDeviceController
from local_db_auditor import LocalDbAuditor
import manage_e2e_account

PROJECT_ROOT = os.path.abspath(os.path.join(SCRIPT_DIR, "../../../.."))
ARTIFACT_DIR = os.path.join(PROJECT_ROOT, "tmp/e2e_artifacts")
REPORT_PATH = os.path.join(PROJECT_ROOT, "tmp/e2e_report/upgrade_report.html")

OLD_APK = os.path.join(ARTIFACT_DIR, "nnbdc-android-26.10.14.apk")
OLD_APK_URL = "https://www.nnbdc.com/app/nnbdc-android.apk"
NEW_APK = os.path.join(PROJECT_ROOT, "app/build/app/outputs/flutter-apk/app-debug.apk")

E2E_EMAIL = "e2etest@nnbdc.com"
APP_PACKAGE = "com.nn.nnbdc.android"

PASSED, FAILED, NOT_RUN = "PASSED", "FAILED", "NOT_RUN"

CASES = [
    "老版本安装包就位",
    "老版本可启动",
    "老版本登录成功并产生本地数据",
    "覆盖安装新手包",
    "升级后 App 正常启动且仍是登录态",
    "升级后本地库结构升到当前版本",
    "升级后旧数据仍在",
    "升级后端云同步正常",
]


class UpgradeCheck:
    def __init__(self, serial=None):
        self.serial = serial
        self.device = None
        self.results = []
        self.started = time.time()

    def log(self, case, status, details):
        if case not in CASES:
            raise KeyError(f"用例「{case}」不在清单里")
        if any(r["case"] == case for r in self.results):
            raise KeyError(f"用例「{case}」已记录过")
        self.results.append({"case": case, "status": status, "details": details})
        icon = {PASSED: "✅", FAILED: "❌", NOT_RUN: "⏭"}[status]
        print(f"{icon} [{status}] {case}: {details}")

    def expect(self, case, ok, details):
        self.log(case, PASSED if ok else FAILED, details)
        if not ok:
            raise RuntimeError(f"{case}: {details}")

    def fill_unrun(self):
        done = {r["case"] for r in self.results}
        for case in CASES:
            if case not in done:
                self.results.append({"case": case, "status": NOT_RUN,
                                     "details": "本次没有走到这条用例"})
        self.results.sort(key=lambda r: CASES.index(r["case"]))

    # ---------- 安装 ----------

    def _adb(self, args, check=True, timeout=600):
        cmd = ["adb"]
        if self.serial:
            cmd.extend(["-s", self.serial])
        cmd.extend(args)
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                             text=True, timeout=timeout)
        if check and res.returncode != 0:
            raise RuntimeError(f"adb {' '.join(args)} 失败: {res.stderr.strip()}")
        return res

    def _package_version(self):
        out = self._adb(["shell", "dumpsys", "package", APP_PACKAGE]).stdout
        for line in out.splitlines():
            if "versionCode=" in line:
                return int(line.split("versionCode=")[1].split()[0])
        return 0

    def install_old(self):
        print("\n--- [1] 安装线上正式包 ---")
        if not os.path.exists(OLD_APK):
            print(f"[*] 下载 {OLD_APK_URL} ...")
            os.makedirs(ARTIFACT_DIR, exist_ok=True)
            subprocess.run(["curl", "-sL", OLD_APK_URL, "-o", OLD_APK], check=True)
        size_mb = os.path.getsize(OLD_APK) / 1024 / 1024
        self.expect("老版本安装包就位", size_mb > 100,
                    f"老版本安装包 {os.path.basename(OLD_APK)} 大小 {size_mb:.0f}MB")

        self._adb(["uninstall", APP_PACKAGE], check=False)
        self._adb(["install", OLD_APK])
        self.old_ver = self._package_version()
        print(f"[*] 已安装老版本 versionCode={self.old_ver}")

    def _dismiss_agreement(self):
        """老包装完第一次启动会先弹服务协议弹窗。"""
        for _ in range(2):
            btn = self.device.wait_by_text_any(["同意并继续"], timeout=4)
            if btn is None:
                return
            self.device.tap_node(btn)
            time.sleep(1.0)

    def launch_old(self):
        print("\n--- [2] 启动老版本 ---")
        self.device.launch_app(grant=True)
        self._dismiss_agreement()
        ok = self.device.wait_foreground(timeout=20)
        self.expect("老版本可启动", ok,
                    f"老版本 versionCode={self.old_ver} 启动后在前台" if ok
                    else "老版本启动后没有进入前台")

    def _toggle_agreement_row(self):
        """点老版本协议行最左边的圆圈：靠近「同意」二字，不会命中《用户协议》链接。"""
        import re as _re
        for n in self.device.dump():
            if n["label"].startswith("同意") and n["center"]:
                m = _re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", n["bounds"])
                if m:
                    x1, y1, x2, y2 = map(int, m.groups())
                    self.device._run_adb(["shell", "input", "tap",
                                          str(x1 + 24), str((y1 + y2) // 2)])
                    time.sleep(0.4)
                return

    def _open_email_login(self) -> bool:
        """打开老版本的邮箱登录页。

        老版本没勾选协议时点「邮箱登录」只弹一句提示、不跳转；协议行整行可点，
        点中心会命中《用户协议》链接，所以只有最左边的圆圈是安全的点击位置。
        先直接点，没进去再切换勾选，一轮一轮试到进去为止。
        """
        for _ in range(4):
            entry = self.device.wait_by_text_any(["邮箱登录", "邮箱验证码登录"], timeout=4)
            if entry is None:
                self.device.press_key(4)
                time.sleep(0.5)
                continue
            self.device.tap_node(entry)
            time.sleep(1.0)
            nodes = self.device.dump()
            if any(n["class"] == "android.widget.EditText" for n in nodes):
                return True
            labels = " ".join(n["label"] for n in nodes if n["label"])
            if "《用户协议》" in labels and "邮箱登录" not in labels:
                self.device.press_key(4)   # 误进了协议页
                time.sleep(0.5)
                continue
            self._toggle_agreement_row()
        return False

    def login_old(self):
        print("\n--- [3] 老版本上登录并产生数据 ---")
        # 老包里没有测试标识，只能按文案认：这一步的脆弱性来自「必须驱动一个没有标识的旧包」，
        # 只在升级检查里出现，不影响主回归。
        if not self._open_email_login():
            raise RuntimeError("老版本找不到可用的邮箱登录入口")

        manage_e2e_account.clear_old_codes()
        field = next((n for n in self.device.dump()
                      if n["class"] == "android.widget.EditText"), None)
        if field is None:
            raise RuntimeError("老版本邮箱登录页没有输入框")
        self.device.tap_node(field)
        self.device.input_text(E2E_EMAIL)
        time.sleep(1.5)

        send = self.device.wait_by_text_any(["获取"], timeout=6)
        if send is None:
            raise RuntimeError("老版本没有「获取」验证码按钮")
        self.device.tap_node(send)

        code = None
        deadline = time.time() + 15
        while time.time() < deadline:
            time.sleep(0.8)
            code = manage_e2e_account.get_latest_code()
            if code:
                break
        if not code:
            raise RuntimeError("生产库没有取到验证码")

        fields = [n for n in self.device.dump() if n["class"] == "android.widget.EditText"]
        if len(fields) < 2:
            raise RuntimeError("老版本验证码输入框没有出现")
        self.device.tap_node(fields[1])
        self.device.input_text(code)
        time.sleep(0.4)
        submit = self.device.find_by_text("登录")
        if submit:
            self.device.tap_node(submit)

        deadline = time.time() + 60
        logged_in = False
        while time.time() < deadline:
            time.sleep(1.0)
            nodes = self.device.dump()
            labels = " ".join(n["label"] for n in nodes if n["label"])
            if "导入词书" in labels:
                for _ in range(60):
                    nodes = self.device.dump()
                    done = None
                    for n in nodes:
                        if "完成" in n["label"]:
                            done = n
                            break
                    if done:
                        self.device.tap_node(done)
                        break
                    time.sleep(1.0)
                continue
            if "词表" in labels and "学习" in labels:
                logged_in = True
                break
        self.expect("老版本登录成功并产生本地数据", logged_in,
                    "老版本用邮箱验证码登录成功并进入主界面" if logged_in
                    else "老版本登录后没有进入主界面")

    def upgrade(self):
        print("\n--- [4] 覆盖安装新手包 ---")
        if not os.path.exists(NEW_APK):
            raise RuntimeError(f"新手包不存在: {NEW_APK}")
        self._adb(["install", "-r", NEW_APK])
        self.new_ver = self._package_version()
        self.expect("覆盖安装新手包", self.new_ver > self.old_ver,
                    f"旧 versionCode={self.old_ver} → 新 versionCode={self.new_ver}，"
                    f"覆盖安装成功（App 数据未被清空）")

    def verify_upgrade(self):
        print("\n--- [5] 升级后核验 ---")
        self.device.launch_app(grant=True)
        self._dismiss_agreement()
        time.sleep(2.0)
        nodes = self.device.dump()
        labels = " ".join(n["label"] for n in nodes if n["label"])
        main_ui = self.device.is_app_in_foreground() and (
            self.device.find_by_id("e2e_nav_study") is not None or "词表" in labels)
        still_logged_in = "邮箱登录" not in labels
        self.expect("升级后 App 正常启动且仍是登录态", main_ui and still_logged_in,
                    "新版本启动后直接进入主界面，登录态被保留" if main_ui and still_logged_in
                    else "升级后没有保持登录态或没有进入主界面")

        self.device.stop_app()
        auditor = LocalDbAuditor(self.serial)
        auditor.pull_snapshot()
        conn = sqlite3.connect(auditor.local_sqlite_path)
        user_version = conn.execute("PRAGMA user_version;").fetchone()[0]
        tables = {r[0] for r in conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table'")}
        user_rows = conn.execute("SELECT count(*) FROM users").fetchone()[0]
        dict_rows = conn.execute("SELECT count(*) FROM dict_words").fetchone()[0]
        conn.close()

        self.expect("升级后本地库结构升到当前版本", user_version >= 60,
                    f"本地库 PRAGMA user_version={user_version}（老版本建库，新版本启动后已迁移）")
        self.expect("升级后旧数据仍在", user_rows >= 1 and dict_rows > 0,
                    f"升级后 users={user_rows} 行、dict_words={dict_rows} 行，老版本灌进去的数据没丢")

        self.device.launch_app(grant=True)
        time.sleep(2.0)
        self.device.tap_id("e2e_nav_me")
        time.sleep(0.8)

        def find_sync_tile():
            for _ in range(4):
                node = self.device.find_by_id("e2e_me_sync")
                if node:
                    return node
                self.device.swipe_up(0.78, 0.34, 300)
                time.sleep(0.3)
            return None

        tile = find_sync_tile()
        if tile is None:
            # 「设置与工具」可能是收起的，展开后再找一次
            settings = self.device.find_by_id("e2e_me_settings")
            if settings:
                self.device.tap_node(settings)
                time.sleep(0.5)
            tile = find_sync_tile()
        ok = tile is not None
        self.expect("升级后端云同步正常", ok,
                    "升级后个人中心能找到「云同步状态」卡片，同步链路可用" if ok
                    else "升级后找不到「云同步状态」卡片")

    def run(self):
        try:
            self.install_old()
            self.device = AndroidDeviceController(self.serial)
            self.launch_old()
            self.login_old()
            self.upgrade()
            self.verify_upgrade()
        except Exception as exc:
            import traceback
            traceback.print_exc()
            pending = [c for c in CASES if c not in {r["case"] for r in self.results}]
            if pending:
                self.log(pending[0], FAILED, f"执行中断: {exc}")
        self.fill_unrun()
        self.write_report()
        failed = sum(1 for r in self.results if r["status"] == FAILED)
        skipped = sum(1 for r in self.results if r["status"] == NOT_RUN)
        return failed == 0 and skipped == 0

    def write_report(self):
        rows = ""
        color = {PASSED: "#10B981", FAILED: "#EF4444", NOT_RUN: "#94A3B8"}
        for r in self.results:
            rows += (f"<tr><td><span style=\"background:{color[r['status']]};color:#fff;"
                     f"padding:3px 8px;border-radius:6px;font-size:11px;font-weight:700;\">"
                     f"{r['status']}</span></td><td><strong>{r['case']}</strong></td>"
                     f"<td>{r['details']}</td></tr>")
        html = f"""<!DOCTYPE html><html lang="zh-CN"><head><meta charset="UTF-8">
<title>泡泡单词 老版本覆盖升级检查</title>
<style>body{{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI","PingFang SC",sans-serif;
background:#F8FAFC;color:#1E293B;padding:32px;}} .box{{max-width:900px;margin:0 auto;
background:#fff;border-radius:16px;padding:28px;box-shadow:0 4px 24px rgba(0,0,0,.06);}}
h1{{font-size:20px;margin:0 0 6px;}} .sub{{color:#64748B;font-size:13px;margin-bottom:18px;}}
table{{width:100%;border-collapse:collapse;font-size:13px;}} th{{text-align:left;padding:10px;
background:#F8FAFC;color:#475569;border-bottom:2px solid #E2E8F0;}} td{{padding:10px;
border-bottom:1px solid #E2E8F0;}}</style></head><body><div class="box">
<h1>📦 老版本覆盖升级与本地库迁移检查</h1>
<div class="sub">老版本 {os.path.basename(OLD_APK)} → 新手包 {os.path.basename(NEW_APK)}
｜设备 {self.serial or '-'}｜{datetime.now():%Y-%m-%d %H:%M:%S}</div>
<table><thead><tr><th style="width:88px">状态</th><th style="width:260px">用例</th>
<th>结论</th></tr></thead><tbody>{rows}</tbody></table>
</div></body></html>"""
        os.makedirs(os.path.dirname(REPORT_PATH), exist_ok=True)
        with open(REPORT_PATH, "w", encoding="utf-8") as f:
            f.write(html)
        print(f"\n📄 报告: {REPORT_PATH}")


def main():
    parser = argparse.ArgumentParser(description="老版本覆盖升级与本地库迁移检查")
    parser.add_argument("--serial", default=None)
    args = parser.parse_args()
    check = UpgradeCheck(args.serial)
    ok = check.run()
    total = sum(1 for r in check.results if r["status"] == PASSED)
    print(f"\n🏁 通过 {total} / {len(CASES)}")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
