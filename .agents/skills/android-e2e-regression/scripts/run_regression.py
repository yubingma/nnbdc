#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
泡泡单词 Android 真机端到端回归测试

三条硬规矩：
1. **分母固定**：`CASES` 是全部用例清单。跑挂在哪一步不算「通过」也不算「失败」，
   而是记成「未执行」，报告里一眼能看出「这次根本没跑到」。
2. **只有通过和失败**：任何断言不成立就是失败，不用「警告」把业务结果糊弄过去。
3. **控件按稳定标识点**：所有要点的控件都靠 App 写进无障碍树的 resource-id 定位，
   文案改了、分辨率换了都不会点错；标识找不到就是失败，不退回按文案猜。

唯一的后端协同：从生产库读登录验证码、核对打卡与学习流水落库。
"""

import argparse
import fcntl
import os
import re
import sys
import time
from datetime import datetime

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.append(SCRIPT_DIR)

from device_controller import AndroidDeviceController
from local_db_auditor import LocalDbAuditor
import manage_e2e_account
import send_report_email

REPORT_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, "../../../../tmp/e2e_report"))
SCREENSHOT_DIR = os.path.join(REPORT_DIR, "screenshots")

E2E_EMAIL = "e2etest@nnbdc.com"

# 控件稳定标识，与 app/lib 里的 Semantics(identifier: ...) 一一对应。
ID_NAV_STUDY = "e2e_nav_study"
ID_NAV_WORD_LISTS = "e2e_nav_word_lists"
ID_NAV_SEARCH = "e2e_nav_search"
ID_NAV_GAME = "e2e_nav_game"
ID_NAV_ME = "e2e_nav_me"
ID_HOME_START = "e2e_home_start"
ID_HOME_EXTRA = "e2e_home_extra"
ID_HOME_SELECT_BOOK = "e2e_home_select_book"
ID_HOME_PLAN = "e2e_home_plan"
ID_PLAN_WORDS_PREFIX = "e2e_plan_words_"
ID_BOOK_SAVE = "e2e_book_save"
ID_BOOK_ROW_PREFIX = "e2e_book_row_"
ID_STUDY_MODE_SWITCH = "e2e_study_mode_switch"
ID_STUDY_OPTION_PREFIX = "e2e_study_option_"
ID_STUDY_DONT_KNOW = "e2e_study_dont_know"
ID_STUDY_AGAIN = "e2e_study_again"
ID_STUDY_NEXT_WORD = "e2e_study_next_word"
ID_STUDY_NEXT_GROUP = "e2e_study_next_group"
ID_STUDY_MASTER = "e2e_study_master"
ID_WORD_DETAIL = "e2e_word_detail"
ID_DETAIL_NEXT_WORD = "e2e_detail_next_word"
ID_FINISH_PAGE = "e2e_finish_page"
ID_FINISH_EXTRA = "e2e_finish_extra"
ID_BADGE_CLAIM = "e2e_badge_claim"
ID_ME_SYNC = "e2e_me_sync"
ID_ME_SETTINGS = "e2e_me_settings"
ID_ME_UNREGISTER = "e2e_me_unregister"
ID_LOGIN_AGREE = "e2e_login_agree"
ID_LOGIN_EMAIL_ENTRY = "e2e_login_email_entry"
ID_SEND_CODE = "e2e_send_code"
ID_LOGIN_SUBMIT = "e2e_login_submit"

# 全部用例，顺序即执行顺序，也是报告里的固定分母。
CASES = [
    "连接 Android 设备",
    "启动 App 前台校验",
    "初始环境核验",
    "截获生产验证码",
    "真实用户注册与登录",
    "导航切换: 学习",
    "导航切换: 词表",
    "导航切换: 查词",
    "导航切换: 比赛",
    "导航切换: 我",
    "词书就绪校验",
    "每日学习计划定制",
    "学习轨道配置与切换",
    "进入单词测评卡片",
    "选择题答错必须进入单词详情",
    "选择题答对自动进阶下一题",
    "学习中标记已掌握",
    "杀进程后学习进度不丢",
    "拒绝录音权限不崩溃",
    "当日计划学完进入打卡页",
    "断网时同步失败可见",
    "恢复网络后同步补齐",
    "端云打卡数据持久化核验",
    "本地Db与FSRS算法审计",
    "跨天复习与连续打卡",
    "主页与个人中心打卡状态",
    "端云同步健康度校验",
    "测试善后注销账号",
]

PASSED, FAILED, NOT_RUN = "PASSED", "FAILED", "NOT_RUN"


class CaseFailure(RuntimeError):
    """断言不成立：立刻记失败，不再往下假装继续。"""


class Runner:
    def __init__(self, serial=None, target_email="mmyybb3000@icloud.com",
                 send_email=True, plan_words=10):
        self.serial = serial
        self.target_email = target_email
        self.send_email = send_email
        self.plan_words = plan_words
        self.device = None
        self.auditor = None
        self.results = []
        self.snapshot_ready = False
        self.meanings = {}
        self._case_started = time.time()
        self._log_count = 0
        os.makedirs(SCREENSHOT_DIR, exist_ok=True)

    # ---------- 断言与记录 ----------

    def capture(self, name: str) -> str:
        self._log_count += 1
        path = os.path.join(SCREENSHOT_DIR, f"{self._log_count:02d}_{name}.png")
        try:
            self.device.take_screenshot(path)
            return path
        except Exception as exc:
            print(f"[!] 截图失败: {exc}")
            return None

    def log(self, case: str, status: str, details: str, shot: str = None):
        if case not in CASES:
            raise KeyError(f"用例「{case}」不在 CASES 清单里，先登记再断言")
        if any(r["case"] == case for r in self.results):
            raise KeyError(f"用例「{case}」已记录过，不能重复记")
        duration = round(time.time() - self._case_started, 2)
        self._case_started = time.time()
        self.results.append({
            "case": case, "status": status, "details": details,
            "duration": duration,
            "screenshot": os.path.relpath(shot, REPORT_DIR) if shot else None,
            "abs_screenshot": os.path.abspath(shot) if shot else None,
            "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        })
        icon = {PASSED: "✅", FAILED: "❌", NOT_RUN: "⏭"}[status]
        print(f"[{datetime.now().strftime('%H:%M:%S')}] {icon} [{status}] {case} "
              f"({duration}s): {details}")

    def expect(self, case: str, condition: bool, details: str, shot: str = None):
        """断言：成立记通过，不成立记失败并抛 CaseFailure 终止后续步骤。"""
        if condition:
            self.log(case, PASSED, details, shot)
            return
        self.log(case, FAILED, details, shot)
        raise CaseFailure(f"{case}: {details}")

    def fill_unrun(self):
        recorded = {r["case"] for r in self.results}
        missing = [c for c in CASES if c not in recorded]
        for case in missing:
            self.results.append({
                "case": case, "status": NOT_RUN,
                "details": "本次执行没有走到这条用例",
                "duration": 0.0, "screenshot": None, "abs_screenshot": None,
                "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
            })
        self.results.sort(key=lambda r: CASES.index(r["case"]))

    # ---------- 界面小工具 ----------

    @staticmethod
    def _has(nodes, rid: str) -> bool:
        return any(n["rid"] == rid for n in nodes)

    @staticmethod
    def _node(nodes, rid: str):
        for n in nodes:
            if n["rid"] == rid:
                return n
        return None

    @staticmethod
    def _header(nodes) -> str:
        for n in nodes:
            label = n["label"]
            if "组" in label and "/" in label:
                return label.replace("\n", " ")
        return ""

    def _options(self, nodes):
        return sorted(
            (n for n in nodes if n["rid"].startswith(ID_STUDY_OPTION_PREFIX)),
            key=lambda n: n["rid"],
        )

    def _current_word(self, nodes):
        """卡片顶部那个大号英文词。汉译英时卡片不显示英文，返回 None。"""
        candidates = []
        for n in nodes:
            label = n["label"]
            if not re.fullmatch(r"[a-zA-Z][a-zA-Z' -]{1,24}", label):
                continue
            if not n["center"]:
                continue
            match = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", n["bounds"])
            if not match:
                continue
            x1, y1, x2, y2 = map(int, match.groups())
            if y1 < 250 or y2 > 700 or (x2 - x1) < 150:
                continue
            candidates.append(n["label"])
        return candidates[0] if candidates else None

    @staticmethod
    def _pick_correct_option(option_texts, meanings):
        """用本地库里的真实释义判定哪个选项是对的；判不出唯一答案就返回 None。"""
        scores = []
        for text in option_texts:
            scores.append(sum(1 for m in meanings if m and m in text))
        if not scores or max(scores) < 1:
            return None
        best = scores.index(max(scores))
        if scores.count(max(scores)) > 1:
            return None
        return best

    # ---------- 流程 ----------

    def run_all(self) -> bool:
        started = time.time()
        self._case_started = started
        print("=" * 60)
        print(f"🚀 泡泡单词真机端到端回归（计划 {self.plan_words} 词，"
              f"{len(CASES)} 条用例）")
        print("=" * 60)
        try:
            self.step_connect()
            self.step_launch()
            self.step_clean_state()
            self.step_login()
            self.step_navigate_tabs()
            self.step_select_book()
            self.step_set_plan()
            self.step_study_track()
            self.step_study()
            self.step_offline_sync()
            self.step_audit()
            self.step_cross_day()
            self.step_home_status()
            self.step_sync_status()
            self.step_teardown()
        except CaseFailure as exc:
            # 抛异常时如果还没落地任何断言，也要把这条用例记成失败，绝不能悄悄变成「未执行」
            pending = [c for c in CASES if c not in {r["case"] for r in self.results}]
            if pending:
                self.log(pending[0], FAILED, str(exc) or "断言不成立",
                         self.capture("case_failed"))
        except Exception as exc:
            import traceback
            traceback.print_exc()
            # 意料之外的异常：给当前这条还没落地的用例记失败，剩余用例记未执行
            pending = [c for c in CASES if c not in {r["case"] for r in self.results}]
            if pending:
                self.log(pending[0], FAILED, f"执行中抛出异常: {exc}",
                         self.capture("unexpected_error"))

        self.fill_unrun()
        total = round(time.time() - started, 1)
        passed = sum(1 for r in self.results if r["status"] == PASSED)
        failed = sum(1 for r in self.results if r["status"] == FAILED)
        skipped = sum(1 for r in self.results if r["status"] == NOT_RUN)
        report = self.generate_report(total, passed, failed, skipped)
        if self.send_email:
            self.send_report(report, total, passed, failed, skipped)
        print("\n" + "=" * 60)
        print(f"🏁 结束：通过 {passed} / 失败 {failed} / 未执行 {skipped}，耗时 {total}s")
        print(f"📄 报告: {report}")
        print("=" * 60)
        return failed == 0 and skipped == 0

    def step_connect(self):
        print("\n--- [1] 连接设备 ---")
        self.device = AndroidDeviceController(self.serial)
        width, height = self.device.get_screen_size()
        self.device.wake_up_and_unlock()
        self.log("连接 Android 设备", PASSED,
                 f"已连接 {self.device.serial}，分辨率 {width}x{height}",
                 self.capture("device_connected"))

    def step_launch(self):
        print("\n--- [2] 启动 App ---")
        self.device.launch_app()
        # 首次启动的隐私政策弹窗
        agree = self.device.wait_by_text_any(["同意并继续"], timeout=3)
        if agree:
            self.device.tap_node(agree)
        ok = self.device.wait_foreground(timeout=15)
        self.expect("启动 App 前台校验", ok,
                    "App 已在前台运行" if ok else "App 未能进入前台",
                    self.capture("app_launched"))

    def _baseline(self) -> str:
        """认出当前是欢迎页还是主界面；都认不出就按返回键逐层退出到能认出来为止。"""
        for _ in range(4):
            nodes = self.device.dump()
            if self._has(nodes, ID_LOGIN_EMAIL_ENTRY) or "微信一键登录" in self._labels(nodes):
                return "welcome"
            if "导入词书" in self._labels(nodes):
                self._dismiss_import_dialog()
                continue
            if self._has(nodes, ID_NAV_STUDY):
                return "main"
            self.device.press_key(4)
            time.sleep(0.6)
        return "unknown"

    def step_clean_state(self):
        print("\n--- [3] 初始环境 ---")
        state = self._baseline()
        if state == "welcome":
            self.log("初始环境核验", PASSED, "当前为纯净未登录欢迎页",
                     self.capture("welcome_page"))
            return
        if state == "unknown":
            raise CaseFailure("既不在欢迎页也不在主界面，按返回键也退不出来")
        self._phone_unregister()
        self.expect("初始环境核验", self._baseline() == "welcome",
                    "已通过真机注销回到欢迎页", self.capture("after_unregister"))

    @staticmethod
    def _labels(nodes):
        return " ".join(n["label"] for n in nodes if n["label"])

    def _phone_unregister(self) -> bool:
        print("[*] 通过真机「注销账号」销毁旧账号...")
        self._goto_me_tab()
        self._open_settings_section()
        for _ in range(4):
            if self.device.wait(ID_ME_UNREGISTER, timeout=1.5):
                break
            self.device.swipe_up(0.8, 0.3, 300)
        node = self.device.find_by_id(ID_ME_UNREGISTER)
        if not node:
            return False
        self.device.tap_node(node)
        field = self._first_edit_text()
        if not field:
            return False
        self.device.tap_node(field)
        self.device.clear_text_input(10)
        self.device.input_text("okay")
        time.sleep(0.4)
        confirm = self.device.wait_by_text_any(["确认注销", "确定"], timeout=3)
        if confirm:
            self.device.tap_node(confirm)
        # 等回到欢迎页
        return self.device.wait(ID_LOGIN_EMAIL_ENTRY, timeout=10) is not None

    def _goto_me_tab(self):
        node = self.device.wait(ID_NAV_ME, timeout=5)
        if node:
            self.device.tap_node(node)
            time.sleep(0.3)

    def _open_settings_section(self):
        node = self.device.find_by_id(ID_ME_SETTINGS)
        if node:
            self.device.tap_node(node)
            time.sleep(0.4)

    def _first_edit_text(self):
        for n in self.device.dump():
            if n["class"] == "android.widget.EditText":
                return n
        return None

    def step_login(self):
        print("\n--- [4] 真机注册登录 ---")
        entry = self.device.wait(ID_LOGIN_EMAIL_ENTRY, timeout=5)
        if entry is None:
            raise CaseFailure("未能在欢迎页找到「邮箱登录」入口")
        agree = self.device.find_by_id(ID_LOGIN_AGREE)
        if agree is None:
            raise CaseFailure("欢迎页找不到协议勾选行")
        self.device.tap_node(agree)
        time.sleep(0.3)
        self.device.tap_node(entry)
        time.sleep(0.8)

        manage_e2e_account.clear_old_codes()
        email_field = self._first_edit_text()
        if not email_field:
            raise CaseFailure("邮箱登录页没有可输入的邮箱框")
        self.device.tap_node(email_field)
        self.device.clear_text_input(60)
        self.device.input_text(E2E_EMAIL)
        time.sleep(1.2)  # 输入框有防抖，要等它渲染出「获取」按钮

        send = self.device.wait(ID_SEND_CODE, timeout=4)
        if send is None:
            raise CaseFailure("未找到「获取」验证码按钮")
        self.device.tap_node(send)

        code = None
        deadline = time.time() + 15
        while time.time() < deadline:
            time.sleep(0.8)
            code = manage_e2e_account.get_latest_code()
            if code:
                break
        self.expect("截获生产验证码", bool(code),
                    f"生产库中取到最新验证码 {code}" if code else "生产库中没有取到验证码",
                    self.capture("code_intercepted"))

        fields = [n for n in self.device.dump() if n["class"] == "android.widget.EditText"]
        if len(fields) < 2:
            raise CaseFailure("验证码输入框没有出现")
        self.device.tap_node(fields[1])
        self.device.clear_text_input(10)
        self.device.input_text(code)
        time.sleep(0.4)

        submit = self.device.find_by_id(ID_LOGIN_SUBMIT)
        if submit:
            self.device.tap_node(submit)

        deadline = time.time() + 60
        ok = False
        while time.time() < deadline:
            time.sleep(0.5)
            nodes = self.device.dump()
            # 新账号登录后 App 会先自动导入一本起步词书（模态弹窗盖住主界面），
            # 看到弹性窗也算已经进入 App，接着把它关掉即可。
            if self._has(nodes, ID_NAV_STUDY):
                ok = True
                break
            if "导入词书" in self._labels(nodes):
                ok = True
                break
        shot = self.capture("login_success")
        self.expect("真实用户注册与登录", ok,
                    "手机端输入邮箱验证码完成注册并进入 App" if ok else "登录后未进入 App",
                    shot)
        manage_e2e_account.grant_e2e_admin()
        self._dismiss_import_dialog()

    def _dismiss_import_dialog(self, timeout: float = 180):
        """关掉「导入词书」进度弹窗（系统级模态，只能按文案认）。"""
        nodes = self.device.dump()
        if "导入词书" not in self._labels(nodes):
            return
        deadline = time.time() + timeout
        while time.time() < deadline:
            nodes = self.device.dump()
            if "导入词书" not in self._labels(nodes):
                return
            # 导入完成前没有「完成」，一出现就点，别干等弹窗自己消失
            for label in ("完成", "确定", "知道了"):
                hit = self.device.find_by_text(label, nodes)
                if hit:
                    self.device.tap_node(hit)
                    time.sleep(0.6)
                    return
            time.sleep(0.8)

    def step_navigate_tabs(self):
        print("\n--- [5] 底部导航 ---")
        tabs = [
            (ID_NAV_WORD_LISTS, "词表"),
            (ID_NAV_SEARCH, "查词"),
            (ID_NAV_GAME, "比赛"),
            (ID_NAV_ME, "我"),
            (ID_NAV_STUDY, "学习"),
        ]
        for rid, name in tabs:
            node = self.device.wait(rid, timeout=4)
            self.expect(f"导航切换: {name}", node is not None,
                        f"点到底栏「{name}」并完成切换" if node else f"底栏没有「{name}」")
            self.device.tap_node(node)
            time.sleep(0.25)

    def _stable_dump(self, attempts: int = 6) -> list:
        """等界面刷稳：连续两次抓到的词书行一致才算数，避免用半加载时的旧坐标去点。"""
        nodes = self.device.dump()
        rows = [n["rid"] for n in nodes if n["rid"].startswith(ID_BOOK_ROW_PREFIX)]
        for _ in range(attempts):
            time.sleep(0.35)
            nodes = self.device.dump()
            current = [n["rid"] for n in nodes if n["rid"].startswith(ID_BOOK_ROW_PREFIX)]
            if current and current == rows:
                return nodes
            rows = current
        return nodes

    def step_select_book(self):
        print("\n--- [6] 词书 ---")
        self._dismiss_import_dialog()
        if self.device.wait(ID_HOME_START, timeout=3):
            self.log("词书就绪校验", PASSED, "当前账号已有生效词书，主页已有学习入口",
                     self.capture("dict_ready"))
            return
        entry = self.device.wait(ID_HOME_SELECT_BOOK, timeout=3)
        if entry is None:
            raise CaseFailure("主页既没有学习入口也没有「选择词书」")
        self.device.tap_node(entry)
        time.sleep(0.8)

        # 默认停在「自定义」页签，里面只有 0 词的生词本；切到「大学」才有成规模的词书
        uni = self.device.wait_by_text_any(["大学"], timeout=4)
        if uni:
            self.device.tap_node(uni)
        nodes = self._stable_dump()

        chosen, chosen_count = None, None
        for row in nodes:
            if not row["rid"].startswith(ID_BOOK_ROW_PREFIX):
                continue
            text = " ".join(self.device.texts_within(row, nodes))
            match = re.search(r"([\d,]+)\s*词", text)
            if not match:
                continue
            count = int(match.group(1).replace(",", ""))
            # 挑词数最少但够今天计划的词书：导入最快，又不至于单词量不足
            if count >= self.plan_words and (chosen_count is None or count < chosen_count):
                chosen, chosen_count = row, count
        if chosen is None:
            raise CaseFailure(f"没有找到不少于 {self.plan_words} 词的词书")
        print(f"[*] 选中 {chosen_count} 词的词书（在够用的里面挑词数最少的，导入最快）")
        self.device.tap_node(chosen)
        time.sleep(0.6)

        save = self.device.wait(ID_BOOK_SAVE, timeout=3)
        if save is None:
            raise CaseFailure("词书页没有「保存」按钮")
        self.device.tap_node(save)
        self._dismiss_import_dialog(timeout=300)

        ok = self.device.wait(ID_HOME_START, timeout=20) is not None
        self.expect("词书就绪校验", ok,
                    f"已选中并导入 {chosen_count} 词的词书，主页出现学习入口" if ok
                    else "词书保存导入后主页仍无学习入口",
                    self.capture("dict_imported"))

    def step_set_plan(self):
        print("\n--- [7] 每日计划 ---")
        plan_entry = self.device.wait(ID_HOME_PLAN, timeout=4)
        if plan_entry is None:
            raise CaseFailure("主页找不到今日词数入口")
        self.device.tap_node(plan_entry)
        chip = self.device.wait(f"{ID_PLAN_WORDS_PREFIX}{self.plan_words}", timeout=3)
        if chip is None:
            raise CaseFailure(f"词量面板里没有 {self.plan_words} 词这一档")
        self.device.tap_node(chip)

        ok = False
        deadline = time.time() + 8
        while time.time() < deadline:
            nodes = self.device.dump()
            entry = self._node(nodes, ID_HOME_PLAN)
            if entry and f"今日 {self.plan_words} 词" in " ".join(self.device.texts_within(entry, nodes)):
                ok = True
                break
            time.sleep(0.3)
        self.expect("每日学习计划定制", ok,
                    f"主页今日目标已确认为 {self.plan_words} 词" if ok
                    else f"主页今日目标没有变成 {self.plan_words} 词",
                    self.capture("plan_configured"))

    def step_study_track(self):
        print("\n--- [8] 学习轨道 ---")
        nodes = self.device.dump()
        labels = self._labels(nodes)
        new_card = next((n["label"] for n in nodes
                         if n["clickable"] and n["label"].endswith("新词")), None)
        flow_visible = "答对" in labels and "答错" in labels and "汉译英" in labels
        if not flow_visible:
            header = self.device.wait_by_text_any(["学习轨道"], timeout=3)
            if header:
                self.device.tap_node(header)
                time.sleep(0.5)
                nodes = self.device.dump()
                labels = self._labels(nodes)
                flow_visible = "答对" in labels and "答错" in labels

        collapse = self.device.wait_by_text_any(["收起轨道"], timeout=3)
        if flow_visible and collapse:
            self.device.tap_node(collapse)
            time.sleep(0.5)
            collapsed = "答对" not in self._labels(self.device.dump())
            header = self.device.wait_by_text_any(["学习轨道"], timeout=3)
            reopened = False
            if header:
                self.device.tap_node(header)
                time.sleep(0.5)
                reopened = "答对" in self._labels(self.device.dump())
            ok = collapsed and reopened
            self.expect("学习轨道配置与切换", ok,
                        f"主页轨道呈现 {new_card or '新词'} 卡片及环节流程，收起后环节消失、再展开又回来"
                        if ok else "学习轨道收起/展开后环节流程没有跟着切换",
                        self.capture("study_track"))
            return

        self.expect("学习轨道配置与切换", False,
                    "主页既没有轨道环节流程，也没有「收起轨道」",
                    self.capture("study_track_missing"))

    # ---------- 学习主循环 ----------

    def _enter_study(self):
        """从任何状态进到答题卡片：可能已经在卡片上、可能停在主页、也可能停在别的页签。"""
        for _ in range(3):
            nodes = self.device.dump()
            if self._has(nodes, ID_STUDY_DONT_KNOW):
                self._dismiss_voice_guide(nodes)
                return
            start = self._node(nodes, ID_HOME_START) or self._node(nodes, ID_HOME_EXTRA)
            if start is None:
                self.device.tap_id(ID_NAV_STUDY)
                time.sleep(0.5)
                continue
            self.device.tap_node(start)
            confirm = self.device.wait_by_text_any(["马上开始"], timeout=2)
            if confirm:
                self.device.tap_node(confirm)
            if self.device.wait(ID_STUDY_DONT_KNOW, timeout=8):
                self._dismiss_voice_guide()
                return
        raise CaseFailure("进不到单词答题卡片")

    def _dismiss_voice_guide(self, nodes=None):
        """新手语音引导蒙层「你说，我来听」会盖住答题卡片，先点掉它。"""
        nodes = nodes if nodes is not None else self.device.dump()
        if not any("你说，我来听" in n["label"] for n in nodes):
            return
        btn = self.device.find_by_text("开始学习", nodes)
        if btn is None:
            raise CaseFailure("语音引导蒙层上没有可点的按钮")
        self.device.tap_node(btn)
        time.sleep(0.4)

    def step_study(self):
        print("\n--- [9] 学完当日计划 ---")
        self.device.tap_id(ID_NAV_STUDY)
        time.sleep(0.4)
        self._enter_study()
        self._switch_to_choice_mode()

        nodes = self.device.dump()
        header = self._header(nodes)
        self.expect("进入单词测评卡片", bool(header),
                    f"已呈现单词卡片：{header}", self.capture("study_card"))

        # 反向用例：拿掉录音权限，切到「说释义」必须不崩且给出权限提示
        self._permission_case()

        # 准备释义真值：先停进程拉一份快照，避免边学边读造成撕裂
        self._prepare_meanings()

        self._run_study_loop(self.plan_words)

        # 完成页可能盖着勋章弹窗
        badge = self.device.find_by_id(ID_BADGE_CLAIM)
        if badge:
            self.device.tap_node(badge)
            time.sleep(0.5)
        reached = self.device.wait(ID_FINISH_PAGE, timeout=5) is not None
        self.expect("当日计划学完进入打卡页", reached,
                    "学完当日计划并自动进入完成打卡页" if reached else "没有进入完成打卡页",
                    self.capture("finish_page"))

    def _switch_to_choice_mode(self, attempts: int = 3):
        """把作答方式切到「选择题」，题目才有可判定的选项，也不会一直开着麦克风。"""
        for _ in range(attempts):
            nodes = self.device.dump()
            if self._options(nodes):
                return
            self.device.tap_id(ID_STUDY_MODE_SWITCH, nodes)
            time.sleep(0.7)
        if not self._options(self.device.dump()):
            raise CaseFailure("切不到选择题，看不到任何选项")

    def _permission_case(self):
        print("[*] 反向用例：没有录音权限时切到「说释义」")
        # 撤销权限会被系统直接杀掉进程，所以必须先撤销再启动，才能看到「没权限时会不会崩」
        self.device.stop_app()
        self.device.set_permission("android.permission.RECORD_AUDIO", False)
        self.device.launch_app(grant=False)
        self._enter_study()
        self._switch_to_choice_mode()
        pid_before = self._pid()

        self.device.tap_id(ID_STUDY_MODE_SWITCH)   # 选择题 → 说释义（要麦克风）
        time.sleep(1.5)
        nodes = self.device.dump()
        labels = self._labels(nodes)
        explained = "麦克风权限" in labels or "暂不授权" in labels
        denied = False
        if explained:
            deny = self.device.find_by_text("暂不授权", nodes) or self.device.find_by_text("去授权", nodes)
            if deny:
                self.device.tap_node(deny)
                denied = True
                time.sleep(0.5)

        system_dialog = [n for n in nodes
                         if n["package"] and n["package"] != "com.nn.nnbdc.android"
                         and any(k in n["label"] for k in ("允许", "禁止", "使用"))]
        if system_dialog:
            deny_btn = next((n for n in system_dialog
                             if "禁止" in n["label"] or "不允许" in n["label"]), None)
            if deny_btn:
                self.device.tap_node(deny_btn)
            else:
                self.device.press_key(4)
            denied = True
            time.sleep(0.5)

        pid_after = self._pid()
        alive = bool(pid_after) and pid_after == pid_before
        self.device.set_permission("android.permission.RECORD_AUDIO", True)
        ok = alive and (explained or bool(system_dialog))
        if explained:
            detail = ("没有录音权限时切到语音作答，App 弹出「麦克风权限」说明并给"
                      f"{'了「暂不授权」出口，拒绝后进程没有重启' if denied else '出授权入口'}")
        elif system_dialog:
            detail = "没有录音权限时切到语音作答，系统弹出权限申请，App 进程没有重启"
        else:
            detail = "没有录音权限时切到语音作答，既没有权限说明也没有系统授权弹窗"
        if not alive:
            detail = "没有录音权限时切到语音作答，App 进程直接消失了"
        self.expect("拒绝录音权限不崩溃", ok, detail, self.capture("permission_denied"))

    def _pid(self):
        res = self.device._run_adb(["shell", "pidof", "com.nn.nnbdc.android"], check=False)
        return res.stdout.strip()

    def _prepare_meanings(self):
        print("[*] 停进程拉取本地快照，读今日计划的单词释义（答对/答错的真值来源）")
        self.device.stop_app()
        self.auditor = LocalDbAuditor(self.serial)
        self.auditor.pull_snapshot()
        self.device.launch_app()
        self._enter_study()
        self._switch_to_choice_mode()
        self.meanings = self.auditor.meanings_by_spell()
        print(f"[*] 本地可判定的单词释义 {len(self.meanings)} 个")

    def _run_study_loop(self, expected_words: int):
        wrong_tested = False
        correct_tested = False
        mastered_tested = False
        kill_tested = False
        answered = 0
        last_header = ""

        debug = bool(os.environ.get("E2E_DEBUG"))
        for turn in range(1, 400):
            nodes = self.device.dump()
            if debug:
                print(f"  [turn {turn}] header={self._header(nodes)!r} "
                      f"options={len(self._options(nodes))} "
                      f"next_word={self._has(nodes, ID_STUDY_NEXT_WORD)} "
                      f"detail={self._has(nodes, ID_WORD_DETAIL)} "
                      f"finish={self._has(nodes, ID_FINISH_PAGE)}")
            if self._has(nodes, ID_FINISH_PAGE) or self._has(nodes, ID_BADGE_CLAIM):
                return
            if self._has(nodes, ID_DETAIL_NEXT_WORD):
                self.device.tap_id(ID_DETAIL_NEXT_WORD)
                continue
            if self._has(nodes, ID_STUDY_NEXT_GROUP):
                self.device.tap_id(ID_STUDY_NEXT_GROUP)
                time.sleep(0.4)
                continue
            if self._has(nodes, ID_WORD_DETAIL):
                # 详情页的「下一词」没就位时先点左上角返回
                if not self.device.go_back(nodes):
                    raise CaseFailure("单词详情页既没有「下一词」也点不到返回")
                continue
            # 已经作答、等用户点「下一词」的状态：必须优先处理，
            # 否则会一直在同一张卡上重复点选项（评分被反复改写）
            if self._has(nodes, ID_STUDY_NEXT_WORD):
                self.device.tap_id(ID_STUDY_NEXT_WORD, nodes)
                continue
            if not self._has(nodes, ID_STUDY_DONT_KNOW):
                time.sleep(0.25)
                continue

            header = self._header(nodes)
            options = self._options(nodes)

            if not options:
                # 非选择题卡片：不认识 → 看答案 → 下一词
                self.device.tap_id(ID_STUDY_DONT_KNOW)
                continue

            word = self._current_word(nodes)
            option_texts = [" ".join(self.device.texts_within(o, nodes)) for o in options]
            meanings = self.meanings.get(word) if word else None
            correct = self._pick_correct_option(option_texts, meanings) if meanings else None

            if options and correct is not None and not wrong_tested:
                wrong_index = next(i for i in range(len(options)) if i != correct)
                self.device.tap_node(options[wrong_index])
                landed = self.device.wait(ID_WORD_DETAIL, timeout=4) or self.device.find_by_id(ID_DETAIL_NEXT_WORD)
                self.expect("选择题答错必须进入单词详情", landed is not None,
                            f"故意选错「{word}」的释义，App 进入单词详情页展示正确释义"
                            if landed else "故意选错后没有进入单词详情页，答错没有任何反馈",
                            self.capture("wrong_answer_detail"))
                wrong_tested = True
                continue

            if options and correct is not None and not correct_tested:
                before = header
                self.device.tap_node(options[correct])
                advanced = False
                deadline = time.time() + 4
                while time.time() < deadline:
                    after_nodes = self.device.dump()
                    if self._has(after_nodes, ID_WORD_DETAIL):
                        break
                    if self._header(after_nodes) != before:
                        advanced = True
                        break
                    time.sleep(0.2)
                self.expect("选择题答对自动进阶下一题", advanced,
                            f"按本地释义选中「{word}」的正确释义后自动进入下一题"
                            if advanced else "选中正确释义后没有进入下一题",
                            self.capture("correct_answer_advance"))
                correct_tested = True
                continue

            if not mastered_tested and self.device.find_by_id(ID_STUDY_MASTER, nodes):
                spell = self._current_word(nodes) or "本词"
                self.device.tap_id(ID_STUDY_MASTER, nodes)
                mastered_tested = True
                time.sleep(0.6)
                self.log("学习中标记已掌握", PASSED, f"对「{spell}」点了「掌握」",
                         self.capture("marked_mastered"))
                continue

            if options:
                self.device.tap_node(options[0])
                answered += 1
                last_header = header

                if (not kill_tested and answered >= 3):
                    self._kill_case(header)
                    kill_tested = True
                continue

        raise CaseFailure(f"学习流转超过 400 步仍未结束（最后位置：{last_header}）")

    def _kill_case(self, header_before: str):
        print("[*] 反向用例：学习途中最粗暴地结束进程，看进度是否还在")
        match = re.search(r"(\d+)/(\d+)", header_before)
        pos_before = int(match.group(1)) if match else 0
        self.device.stop_app()
        time.sleep(0.5)
        self.device.launch_app()
        self._enter_study()
        self._switch_to_choice_mode()
        node = self.device.wait(ID_STUDY_DONT_KNOW, timeout=10)
        nodes = self.device.dump() if node is None else None
        header_after = self._header(self.device.dump() if nodes is None else nodes)
        match_after = re.search(r"(\d+)/(\d+)", header_after)
        pos_after = int(match_after.group(1)) if match_after else 0
        ok = node is not None and pos_after >= pos_before
        self.expect("杀进程后学习进度不丢", ok,
                    f"杀进程前在 {header_before}，重启后仍在 {header_after}"
                    if ok else f"杀进程前在 {header_before}，重启后回到 {header_after or '未知页面'}",
                    self.capture("after_kill_restart"))

    # ---------- 端云同步 ----------

    def _open_sync_page(self):
        """我 → 设置与工具 → 云同步状态。进这个页面本身就会触发一次原生同步。"""
        self._goto_me_tab()
        self._open_settings_section()
        tile = self.device.find_by_id(ID_ME_SYNC)
        if tile is None:
            self.device.swipe_up(0.8, 0.4, 300)
            tile = self.device.find_by_id(ID_ME_SYNC)
        if tile is None:
            raise CaseFailure("个人中心找不到「云同步状态」")
        self.device.tap_node(tile)
        time.sleep(1.2)

    def _force_sync(self):
        self._open_sync_page()
        time.sleep(2.0)
        if not self.device.go_back():
            raise CaseFailure("同步页退不回来（左上角没有返回按钮）")
        time.sleep(0.3)

    def step_offline_sync(self):
        print("\n--- [10] 断网 / 恢复 ---")
        self.device.set_network(False)
        if self._online():
            raise CaseFailure("无法把设备切到断网状态")

        self._open_sync_page()
        saw_failure = False
        deadline = time.time() + 15
        while time.time() < deadline:
            if "失败" in self._labels(self.device.dump()):
                saw_failure = True
                break
            time.sleep(0.8)
        self.expect("断网时同步失败可见", saw_failure,
                    "断网后同步状态明确报出失败，没有假报成已同步"
                    if saw_failure else "断网后同步页面没有任何失败提示（假报成功）",
                    self.capture("offline_sync_failed"))
        if not self.device.go_back():
            raise CaseFailure("同步页退不回来")

        self.device.set_network(True)
        deadline = time.time() + 25
        while time.time() < deadline and not self._online():
            time.sleep(1.0)
        if not self._online():
            raise CaseFailure("恢复网络失败，后续无法继续")
        self._force_sync()
        self._force_sync()

        ok = self._wait_cloud_logs(self.plan_words, timeout=40)
        self.expect("恢复网络后同步补齐", ok,
                    f"恢复网络并触发同步后，云端已有学习流水（至少 {self.plan_words} 条计划内记录）"
                    if ok else "恢复网络并触发同步后，云端仍没有学习流水",
                    self.capture("online_sync_recovered"))

    def _online(self) -> bool:
        """直接发一个 ICMP 包判定联网：dumpsys 里残留的 VALIDATED 关掉 Wi-Fi 后仍然在。"""
        res = self.device._run_adb(
            ["shell", "ping", "-c", "1", "-W", "3", "223.5.5.5"], check=False)
        return res.returncode == 0

    def _wait_cloud_logs(self, min_count: int, timeout: float = 40) -> bool:
        user = manage_e2e_account.check_user()
        if not user:
            return False
        deadline = time.time() + timeout
        while time.time() < deadline:
            cloud_logs = manage_e2e_account.get_user_learning_logs(user["id"])
            if len(cloud_logs) >= min_count:
                return True
            time.sleep(1.5)
        return False

    # ---------- 本地审计 ----------

    def step_audit(self):
        print("\n--- [11] 本地库与 FSRS 审计 ---")
        self.device.stop_app()
        self.auditor.pull_snapshot()
        audit = self.auditor.audit_local_learning_data()
        user = manage_e2e_account.check_user()
        cloud_logs = manage_e2e_account.get_user_learning_logs(user["id"]) if user else []
        cloud_words = manage_e2e_account.get_user_learning_words(user["id"]) if user else []
        aligned, detail = self.auditor.verify_local_and_cloud_alignment(cloud_logs, cloud_words)
        ok = (audit["total_logs"] > 0 and not audit["duplicate_violations"]
              and aligned)
        self.audited_logs = audit["logs"]
        self.expect("本地Db与FSRS算法审计", ok,
                    f"本地 {audit['total_logs']} 条评分全部合法、无 2000ms 重复评分，{detail}"
                    if ok else f"审计不通过：{detail}",
                    self.capture("local_db_audit"))
        self.snapshot_ready = True

    def step_cross_day(self):
        print("\n--- [12] 跨天 ---")
        changed = self.auditor.shift_one_day_back()
        if changed <= 0:
            raise CaseFailure("本地库没有可前移的打卡/学习记录，无法模拟跨天")
        self.auditor.push_snapshot()
        manage_e2e_account.time_travel_yesterday()
        self.device.launch_app()
        self._enter_study()
        if self.device.wait(ID_STUDY_DONT_KNOW, timeout=10) is None:
            raise CaseFailure("跨天后进入学习没有出现复习卡片")
        self._run_study_loop(self.plan_words)
        badge = self.device.find_by_id(ID_BADGE_CLAIM)
        if badge:
            self.device.tap_node(badge)
        self._force_sync()

        user = manage_e2e_account.check_user()
        daka_count = 0
        if user:
            deadline = time.time() + 20
            while time.time() < deadline:
                row = manage_e2e_account.run_psql(
                    f"SELECT count(*) FROM daka WHERE user_id = '{user['id']}';")
                if row and row.strip().isdigit():
                    daka_count = int(row.strip())
                    if daka_count >= 2:
                        break
                time.sleep(1.5)
        self.expect("跨天复习与连续打卡", daka_count >= 2,
                    f"把本地与云端时钟前移一天后完成复习，生产库已有连续 {daka_count} 天打卡"
                    if daka_count >= 2 else f"跨天复习完成后生产库只有 {daka_count} 天打卡",
                    self.capture("cross_day_daka"))

    def step_home_status(self):
        print("\n--- [13] 主页打卡状态 ---")
        self.device.tap_id(ID_NAV_STUDY)
        time.sleep(0.8)
        nodes = self.device.dump()
        stamp = any(k in self._labels(nodes) for k in ("今日已打卡", "目标已锁定", "再来一组"))
        self.expect("主页与个人中心打卡状态", stamp,
                    "主页仪表盘已盖印「今日已打卡」" if stamp else "主页没有任何打卡印记",
                    self.capture("home_daka"))

    def step_sync_status(self):
        print("\n--- [14] 同步健康度 ---")
        self._goto_me_tab()
        time.sleep(0.5)
        nodes = self.device.dump()
        labels = self._labels(nodes)
        bad = "同步失败" in labels or "网络异常" in labels
        self.expect("端云同步健康度校验", not bad,
                    "个人中心各卡片正常，无同步失败告警" if not bad else "个人中心出现同步失败告警",
                    self.capture("sync_status"))

    # ---------- 收尾 ----------

    def step_teardown(self):
        print("\n--- [15] 善后注销 ---")
        ok = self._phone_unregister()
        nodes = self.device.dump()
        back_to_welcome = self._has(nodes, ID_LOGIN_EMAIL_ENTRY) or "微信一键登录" in self._labels(nodes)
        self.expect("测试善后注销账号", ok and back_to_welcome,
                    "已通过真机注销回到未登录态" if ok and back_to_welcome
                    else "真机注销没有回到欢迎页",
                    self.capture("teardown"))

    # ---------- 报告 ----------

    def _status_color(self, status: str) -> str:
        return {PASSED: "#10B981", FAILED: "#EF4444", NOT_RUN: "#94A3B8"}[status]

    def generate_report(self, total_time: float, passed: int,
                        failed: int, skipped: int) -> str:
        rows = ""
        for r in self.results:
            img = (f'<a href="{r["screenshot"]}" target="_blank">'
                   f'<img src="{r["screenshot"]}" style="width:72px;border-radius:6px;" /></a>'
                   if r["screenshot"] else "-")
            rows += f"""
            <tr>
                <td class="st"><span style="background:{self._status_color(r['status'])};">{r['status']}</span></td>
                <td><strong>{r['case']}</strong></td>
                <td class="dur">{r['duration']}s</td>
                <td>{r['details']}</td>
                <td class="ts">{r['timestamp']}</td>
                <td class="shot">{img}</td>
            </tr>"""

        fsrs_html = ""
        if getattr(self, "audited_logs", None):
            body = ""
            for idx, item in enumerate(self.audited_logs, 1):
                rating = {1: "忘记", 2: "困难", 3: "良好", 4: "简单"}.get(item["rating"], item["rating"])
                body += (f"<tr><td>{idx}</td><td><strong>{item['spell'] or '-'}</strong></td>"
                         f"<td>{item['word_id']}</td><td>{rating}</td>"
                         f"<td>{item['stability']}</td><td>+{item['scheduled_days']} 天</td></tr>")
            fsrs_html = f"""
            <h3>本地 SQLite 评分流水（{len(self.audited_logs)} 条）</h3>
            <table><thead><tr><th>#</th><th>单词</th><th>单词 ID</th><th>FSRS 评分</th>
            <th>稳定性</th><th>复习间隔</th></tr></thead><tbody>{body}</tbody></table>"""

        html = f"""<!DOCTYPE html>
<html lang="zh-CN"><head><meta charset="UTF-8">
<title>泡泡单词真机端到端回归测试报告</title>
<style>
body{{font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"PingFang SC","Microsoft YaHei",sans-serif;
background:#F8FAFC;color:#1E293B;margin:0;padding:32px 24px;}}
.container{{max-width:1080px;margin:0 auto;background:#fff;border-radius:16px;padding:32px;
box-shadow:0 4px 24px rgba(0,0,0,.06);}}
h1{{margin:0 0 4px;font-size:22px;}}
.sub{{color:#64748B;font-size:13px;margin-bottom:20px;}}
.cards{{display:grid;grid-template-columns:repeat(4,1fr);gap:12px;margin:18px 0;}}
.card{{background:#F1F5F9;border-radius:12px;padding:14px;text-align:center;}}
.card .l{{font-size:12px;color:#64748B;}}
.card .v{{font-size:26px;font-weight:800;}}
table{{width:100%;border-collapse:collapse;margin-top:16px;font-size:13px;}}
th{{background:#F8FAFC;text-align:left;padding:10px;color:#475569;border-bottom:2px solid #E2E8F0;}}
td{{padding:10px;border-bottom:1px solid #E2E8F0;color:#334155;vertical-align:middle;}}
td.st span{{color:#fff;padding:3px 8px;border-radius:6px;font-size:11px;font-weight:700;}}
td.dur{{font-weight:700;white-space:nowrap;}}
td.ts{{color:#64748B;font-size:12px;white-space:nowrap;}}
td.shot{{text-align:center;}}
.footer{{margin-top:24px;text-align:center;font-size:12px;color:#94A3B8;}}
</style></head><body><div class="container">
<h1>📱 泡泡单词真机端到端回归测试报告</h1>
<div class="sub">真机自助注册 → 选词书 → 设定计划 → 选择题作答（答错进详情、答对进阶）→ 杀进程 → 打卡 → 断网/恢复 → 本地库审计 → 跨天连续打卡 → 注销
｜设备 {self.device.serial if self.device else '-'}</div>
<div class="cards">
<div class="card"><div class="l">用例总数</div><div class="v">{len(CASES)}</div></div>
<div class="card"><div class="l">通过</div><div class="v" style="color:#10B981">{passed}</div></div>
<div class="card"><div class="l">失败</div><div class="v" style="color:#EF4444">{failed}</div></div>
<div class="card"><div class="l">未执行</div><div class="v" style="color:#94A3B8">{skipped}</div></div>
</div>
<div class="sub">总耗时 {total_time}s</div>
<table><thead><tr><th style="width:86px">状态</th><th style="width:230px">用例</th>
<th style="width:64px">耗时</th><th>断言结论</th><th style="width:150px">时间</th>
<th style="width:86px">截图</th></tr></thead><tbody>{rows}</tbody></table>
{fsrs_html}
<div class="footer">Generated by Android E2E Regression | {datetime.now():%Y-%m-%d %H:%M:%S}</div>
</div></body></html>"""
        path = os.path.join(REPORT_DIR, "report.html")
        with open(path, "w", encoding="utf-8") as f:
            f.write(html)
        return path

    def send_report(self, report_path, total, passed, failed, skipped):
        print("\n--- 邮件推送 ---")
        subject = f"【泡泡单词回归】通过 {passed} / 失败 {failed} / 未执行 {skipped}（{datetime.now():%m-%d %H:%M}）"
        body = (f"<p>共 {len(CASES)} 条用例：通过 {passed}，失败 {failed}，未执行 {skipped}，"
                f"总耗时 {total}s。</p><p>完整报告见附件路径：{report_path}</p>")
        try:
            if send_report_email.send_email_report(self.target_email, subject, body):
                print(f"[*] 报告已推送到 {self.target_email}")
            else:
                print("[!] 邮件推送未成功（不影响测试结论）")
        except Exception as exc:
            print(f"[!] 邮件推送异常（不影响测试结论）: {exc}")


def acquire_lock():
    os.makedirs(REPORT_DIR, exist_ok=True)
    fd = open(os.path.join(REPORT_DIR, "regression.lock"), "a+")
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return fd
    except OSError:
        print("❌ 已有另一个回归进程正在独占真机，本次退出。")
        return None


def main():
    lock = acquire_lock()
    if not lock:
        sys.exit(1)
    parser = argparse.ArgumentParser(description="泡泡单词真机端到端回归")
    parser.add_argument("--serial", default=None)
    parser.add_argument("--email", default="mmyybb3000@icloud.com")
    parser.add_argument("--no-email", action="store_true")
    parser.add_argument("--plan", type=int, default=10,
                        help="今天要学多少词（越少越快，默认 10）")
    args = parser.parse_args()
    runner = Runner(serial=args.serial, target_email=args.email,
                    send_email=not args.no_email, plan_words=args.plan)
    sys.exit(0 if runner.run_all() else 1)


if __name__ == "__main__":
    main()
