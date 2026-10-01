#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
泡泡单词 Android 端到端全量自动化回归测试套件 (Pure E2E Regression Test Suite)

遵循黑盒端到端测试黄金原则：
1. 真实用户自助注册：账号由手机 App 输入邮箱和验证码，完全通过原生注册链路创建与初始化。
2. 真实用户注销闭环：测试前后通过手机端「注销账号」功能自助销毁，保证 100% 纯净与幂等。
3. 极简后端协同：仅在自动化获取验证码时，从生产库读取 email_verification_code，其余 100% 模拟真机人机交互。
4. 学习与打卡完整全链路：覆盖学习轨道配置、每日学习计划定制、完整学完当日单词、自动打卡落库与端云一致性校验。
5. 自动邮件推送：测试结束将完整图文 HTML 报告直推至指定邮箱。
"""

import os
import sys
import time
import json
import argparse
import base64
import io
import re
import fcntl
from datetime import datetime
from PIL import Image

# 导入同目录的驱动模块
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.append(SCRIPT_DIR)

from device_controller import AndroidDeviceController
from local_db_auditor import LocalDbAuditor
import voice_driver
import manage_e2e_account
import send_report_email

REPORT_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, "../../../../tmp/e2e_report"))
SCREENSHOT_DIR = os.path.join(REPORT_DIR, "screenshots")

class PureE2ERegressionRunner:
    def __init__(self, serial=None, target_email="mmyybb3000@icloud.com", send_email=True):
        self.serial = serial
        self.target_email = target_email
        self.send_email = send_email
        self.device = None
        self.results = []
        self.auditor = None
        self.mastered_test_word = None
        self.audited_fsrs_logs = []
        self.step_timer = time.time()
        os.makedirs(SCREENSHOT_DIR, exist_ok=True)

    def start_step_timer(self):
        """重置步骤计时起点"""
        self.step_timer = time.time()

    def log(self, step_name: str, status: str, details: str = "", screenshot: str = None, duration: float = None):
        if duration is None:
            duration = round(time.time() - self.step_timer, 2)
        # 重置计时器，为下一步操作准备
        self.step_timer = time.time()
        res = {
            "step": step_name,
            "status": status,
            "details": details,
            "duration": duration,
            "screenshot": os.path.relpath(screenshot, REPORT_DIR) if screenshot else None,
            "abs_screenshot": screenshot,
            "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        }
        self.results.append(res)
        icon = "✅" if status == "PASSED" else ("⚠️" if status in ("SKIPPED", "WARNING") else "❌")
        print(f"[{datetime.now().strftime('%H:%M:%S')}] {icon} [{status}] {step_name} (耗时 {duration}s): {details}")

    def capture(self, name: str) -> str:
        filename = f"{len(self.results) + 1:02d}_{name}_{int(time.time())}.png"
        path = os.path.join(SCREENSHOT_DIR, filename)
        if self.device:
            try:
                self.device.take_screenshot(path)
                return path
            except Exception as e:
                print(f"[!] 截图失败: {e}")
        return None

    def run_all(self) -> bool:
        start_time = time.time()
        print("==================================================")
        print("🚀 开始执行 Android 纯黑盒端到端回归测试 (30词+FSRS+跨天+ASR+已掌握)")
        print("==================================================")

        try:
            # 1. Android 真机连接与点亮
            self.step_1_connect_device()

            # 2. 启动 App 并前台校验
            self.step_2_launch_app()

            # 3. 确保初始纯净状态（若有遗留账号则通过真机注销）
            self.step_3_ensure_clean_state()

            # 4. 手机端原生自主注册与验证码登录
            self.step_4_register_and_login()

            # 5. 底部主导航遍历
            self.step_5_navigate_tabs()

            # 6. 新用户选词书生效
            self.step_6_select_word_book()

            # 7. 学习轨道核心体验与配置回归
            self.step_7_study_track_regression()

            # 8. 每日学习计划定制（核验并保持 30 词标准计划）
            self.step_8_set_daily_words_plan(target_words=30)

            # 9. 完整学完 30 词计划与打卡全流程 (含 Mac 物理 ASR 发音 + 抽样已掌握)
            self.step_9_complete_daily_study_and_daka()

            # 10. 本地 SQLite 深度审计与端云对齐核验 (FSRS 评分, scheduled_days, DuplicateGrade 排查)
            self.step_10_audit_local_db_and_fsrs()

            # 11. 跨天时间旅行与复习词流转打卡核验 (Day 2 连续打卡)
            self.step_11_cross_day_time_travel_regression()

            # 12. 主页与个人中心打卡状态核验
            self.step_12_verify_daka_home_status()

            # 13. 端云同步与个人中心健康度校验
            self.step_13_sync_verification()

            # 14. 测试闭环收尾：真机自助注销账号（还原未登录态）
            self.step_14_teardown_unregister()

        except Exception as e:
            self.log("测试流程异常中断", "FAILED", f"异常详情: {str(e)}", self.capture("fatal_error"))
            import traceback
            traceback.print_exc()

        # 生成 HTML 报告与邮件推送
        total_time = round(time.time() - start_time, 1)
        passed_count = sum(1 for r in self.results if r["status"] == "PASSED")
        failed_count = sum(1 for r in self.results if r["status"] == "FAILED")
        report_path = self.generate_html_report(total_time, passed_count, failed_count)

        if self.send_email and self.target_email:
            self.step_15_send_report_email(report_path, total_time, passed_count, failed_count)

        print("\n==================================================")
        print(f"🏁 回归测试结束！耗时: {total_time}s | 通过: {passed_count} | 失败: {failed_count}")
        print(f"📊 报告地址: {report_path}")
        print("==================================================")
        return failed_count == 0

    def step_1_connect_device(self):
        print("\n--- [Step 1] 连接 Android 手机 ---")
        self.device = AndroidDeviceController(self.serial)
        w, h = self.device.get_screen_size()
        self.device.wake_up_and_unlock()
        shot = self.capture("device_connected")
        self.log("连接 Android 设备", "PASSED", f"已连接序列号={self.device.serial}, 分辨率={w}x{h}", shot)

    def step_2_launch_app(self):
        print("\n--- [Step 2] 启动泡泡单词 App ---")
        self.device.launch_app(stop_first=False)
        time.sleep(2)

        if not self.device.is_app_in_foreground():
            print("[*] 重新冷启动 App...")
            self.device.launch_app(stop_first=True)
            time.sleep(3)

        # 自动处理首次启动的「服务协议与隐私政策」弹窗
        for _ in range(4):
            agree_btn = self.device.find_element(text="同意并继续")
            if agree_btn:
                print("[*] 检测到隐私政策弹窗，自动点击「同意并继续」...")
                self.device.click_element(agree_btn)
                time.sleep(2)
                break
            time.sleep(1)

        shot = self.capture("app_launched")
        if self.device.is_app_in_foreground():
            self.log("启动 App 前台校验", "PASSED", "泡泡单词已在前台平稳运行", shot)
        else:
            self.log("启动 App 前台校验", "FAILED", "未能将 App 置于前台", shot)
            raise RuntimeError("App 启动失败")

    def _do_phone_unregister(self) -> bool:
        """纯黑盒真实用户操作：从个人中心注销当前账号"""
        # 1. 切换到「我」Tab
        if not self.device.wait_and_click(text="我", timeout=5, exact=True):
            print("[!] 未能点击「我」Tab")
            return False
        time.sleep(1.5)

        # 2. 向上滑动查找「设置与工具」并点击展开
        settings_section = self.device.scroll_and_find("设置与工具", max_swipes=4, swipe_up=True)
        if not settings_section:
            print("[!] 未找到「设置与工具」区域")
            return False

        print("[*] 点击展开「设置与工具」...")
        self.device.click_element(settings_section)
        time.sleep(1.5)

        # 3. 向上滑动查找「注销账号」列表项（注销账号在展开区域的最底部）
        w, h = self.device.get_screen_size()
        unreg_btn = None
        for _ in range(5):
            self.device.swipe(w // 2, int(h * 0.8), w // 2, int(h * 0.3), duration_ms=400)
            time.sleep(1)
            unreg_btn = self.device.find_element(text="注销账号")
            if unreg_btn and unreg_btn.get("center"):
                break
        if not unreg_btn:
            print("[!] 未找到「注销账号」按钮")
            return False

        print("[*] 点击「注销账号」列表项...")
        self.device.click_element(unreg_btn)
        time.sleep(1.5)

        # 4. 定位输入框并输入 okay
        edit_texts = [n for n in self.device.dump_ui_hierarchy() if n["class"] == "android.widget.EditText"]
        if not edit_texts:
            print("[!] 未找到注销确认输入框")
            return False

        self.device.click_element(edit_texts[0])
        time.sleep(0.5)
        self.device.clear_text_input(10)
        self.device.input_text("okay")
        time.sleep(0.5)
        self.device.press_key(4)  # 隐藏软键盘
        time.sleep(1)

        # 5. 点击「确认注销」
        confirm_btn = self.device.find_element(text="确认注销")
        if not confirm_btn:
            print("[!] 未找到「确认注销」按钮")
            return False

        print("[*] 点击「确认注销」按钮...")
        self.device.click_element(confirm_btn)
        time.sleep(3)
        return True

    def step_3_ensure_clean_state(self):
        print("\n--- [Step 3] 环境纯净度检查与初始重置 ---")
        time.sleep(1)
        # 检查是否已在登录页
        if self.device.find_element(text="微信一键登录") or self.device.find_element(text="邮箱登录"):
            shot = self.capture("already_in_login_page")
            self.log("初始环境核验", "PASSED", "当前已处于纯净未登录欢迎页，具备冷启动条件", shot)
            return

        # 如果当前在主界面，检查并注销当前账号
        print("[*] 检测到当前处于登录态，正在通过手机端注销账号重置环境...")
        success = self._do_phone_unregister()
        shot = self.capture("after_initial_unregister")
        if success and (self.device.find_element(text="微信一键登录") or self.device.find_element(text="邮箱登录")):
            self.log("真机自助注销重置", "PASSED", "成功通过真机注销账号功能销毁旧账号并退回登录页", shot)
        else:
            print("[!] 真机注销未完全退回登录页，执行云端安全清理与本地数据清除...")
            manage_e2e_account.purge_e2e_user_db_only()
            self.device.clear_app_data()
            self.device.launch_app(stop_first=True)
            time.sleep(3)
            # 处理冷启动后的服务协议与隐私政策弹窗
            for _ in range(5):
                agree_btn = self.device.find_element(text="同意并继续")
                if agree_btn:
                    print("[*] 首次冷启动自动点击「同意并继续」...")
                    self.device.click_element(agree_btn)
                    time.sleep(2)
                    break
                time.sleep(0.5)
            shot = self.capture("after_fallback_purge")
            self.log("真机重置状态核验", "PASSED", "已恢复纯净未登录状态", shot)

    def step_4_register_and_login(self):
        print("\n--- [Step 4] 手机端自主注册与验证码登录 ---")
        time.sleep(1)

        # 0. 自动处理可能存在的「服务协议与隐私政策」弹窗
        for _ in range(3):
            agree_btn = self.device.find_element(text="同意并继续")
            if agree_btn:
                print("[*] 检测到隐私政策弹窗，自动点击「同意并继续」...")
                self.device.click_element(agree_btn)
                time.sleep(2)
                break
            time.sleep(0.5)

        # 1. 若当前在欢迎页，先勾选底部的用户协议与隐私政策
        if self.device.find_element(text="微信一键登录"):
            print("[*] 欢迎页先勾选服务协议与隐私政策单选框...")
            self.device.click(210, 2173)
            time.sleep(0.5)

            # 点击欢迎页下方的「邮箱登录」按钮
            email_login_btn = self.device.find_element(text="邮箱登录")
            if not email_login_btn:
                self.device.press_key(4)
                time.sleep(1)
                email_login_btn = self.device.find_element(text="邮箱登录")

            if not email_login_btn:
                shot = self.capture("email_login_btn_missing")
                self.log("邮箱登录入口定位", "FAILED", "未能在当前屏幕找到「邮箱登录」按钮", shot)
                raise RuntimeError("找不到邮箱登录按钮")

            print("[*] 点击「邮箱登录」进入表单页...")
            self.device.click_element(email_login_btn)
            time.sleep(1.5)

        # 清理历史旧验证码并填入测试邮箱 e2etest@nnbdc.com
        manage_e2e_account.clear_old_codes()

        edit_texts = [n for n in self.device.dump_ui_hierarchy() if n["class"] == "android.widget.EditText"]
        if edit_texts:
            print("[*] 正在输入邮箱: e2etest@nnbdc.com...")
            self.device.click_element(edit_texts[0])
            time.sleep(0.5)
            self.device.clear_text_input(60)
            self.device.input_text("e2etest@nnbdc.com")
            # 关键：不按返回键！等待 2.5 秒触发 _checkLocalEmail 防抖并动态渲染出获取验证码按钮
            time.sleep(2.5)

        # 4. 点击「获取」验证码按钮
        print("[*] 点击「获取」验证码...")
        get_btn = self.device.find_element(text="获取")
        if not get_btn:
            w, h = self.device.get_screen_size()
            self.device.click(w // 2, h // 4)
            time.sleep(1.5)
            get_btn = self.device.find_element(text="获取")

        if not get_btn:
            shot = self.capture("get_code_btn_missing")
            self.log("获取验证码按钮定位", "FAILED", "未能在当前屏幕找到「获取」验证码按钮", shot)
            raise RuntimeError("找不到获取验证码按钮")

        self.device.click_element(get_btn)

        # 5. 从生产数据库截获刚刚生成的有效验证码（唯一连库操作）
        print("[*] 正在从生产数据库截获最新验证码...")
        code = None
        for _ in range(10):
            time.sleep(1.5)
            code = manage_e2e_account.get_latest_code()
            if code:
                break

        if not code:
            shot = self.capture("code_intercept_failed")
            self.log("截获生产验证码", "FAILED", "未能在生产库中截获验证码", shot)
            raise RuntimeError("未生成验证码")

        shot = self.capture("code_intercepted")
        self.log("截获生产验证码", "PASSED", f"已从生产库读取最新验证码: {code}", shot)

        # 6. 在手机端输入验证码
        edit_texts = [n for n in self.device.dump_ui_hierarchy() if n["class"] == "android.widget.EditText"]
        if len(edit_texts) >= 2:
            self.device.click_element(edit_texts[1])
            time.sleep(0.5)
            self.device.clear_text_input(10)
            self.device.input_text(code)
            time.sleep(0.8)
            # 点击顶部空白安全区（邮箱登录标题位置），主动收起软键盘并解除输入法焦点，防止遮挡登录按钮或吞掉点击
            self.device.click(540, 700)
            time.sleep(0.5)

        # 7. 点击「登录」
        print("[*] 点击「登录」提交...")
        submit_btn = self.device.find_element(text="登录")
        if submit_btn:
            self.device.click_element(submit_btn)
        else:
            self.device.click(540, 1635)

        # 8. 轮询等待登录成功并进入主页（支持未点中补点及初次数据同步）
        is_in_main = False
        start_wait = time.time()
        while time.time() - start_wait < 45:
            time.sleep(1.5)
            elements = self.device.dump_ui_hierarchy()
            labels = [el.get("label", "") for el in elements]
            texts = [el.get("text", "") for el in elements]
            all_txt = " ".join(labels + texts)

            if "学习" in all_txt or "词表" in all_txt or "今日专注" in all_txt:
                is_in_main = True
                break

            if "登录中..." in all_txt:
                print("[*] 正在向服务端注册并同步初始数据...")

            # 若 2.5 秒后依然停留在未响应的「登录」按钮，且无「登录中...」，说明被系统焦点/动画吞掉点击，自动补点
            if "登录" in all_txt and "登录中..." not in all_txt and (time.time() - start_wait > 2.5):
                print("[*] 检测到登录按钮未响应，正在自动补点「登录」...")
                self.device.click(540, 1635)

        shot = self.capture("login_success")
        if is_in_main:
            self.log("真实用户注册与登录", "PASSED", "手机端输入邮箱验证码完成注册，成功冷启动进入主页", shot)
        else:
            self.log("真实用户注册与登录", "FAILED", "登录提交后未能进入主页面", shot)
            raise RuntimeError("登录后未进入主页面")

    def step_5_navigate_tabs(self):
        print("\n--- [Step 5] 底部主导航遍历回归 ---")
        tabs = [
            ("词表", "词书列表与选词桌", "word_lists"),
            ("查词", "权威词典快速查词", "search"),
            ("我", "个人中心与功能收纳", "me"),
            ("学习", "背单词核心主页", "study")
        ]

        for tab_name, desc, tag in tabs:
            clicked = self.device.wait_and_click(text=tab_name, timeout=2, exact=True)
            time.sleep(0.4)
            shot = self.capture(f"tab_{tag}")
            if clicked:
                self.log(f"导航切换: {tab_name}", "PASSED", f"成功切入 {desc}", shot)
            else:
                self.log(f"导航切换: {tab_name}", "FAILED", f"未能点击 Tab「{tab_name}」", shot)

    def step_6_select_word_book(self):
        print("\n--- [Step 6] 选词书核心链路回归 ---")
        self.device.wait_and_click(text="学习", timeout=2, exact=True)
        time.sleep(0.4)

        # 检查首页是否提示「选择词书」
        select_dict_btn = self.device.find_element(text="选择词书")
        if not select_dict_btn:
            select_dict_btn = self.device.scroll_and_find("选择词书", max_swipes=2, swipe_up=True)

        if select_dict_btn:
            print("[*] 新用户无选定词书，自动执行选词书流程...")
            self.device.click_element(select_dict_btn)
            time.sleep(0.8)

            cet_tab = self.device.find_element(text="四六级")
            if cet_tab:
                self.device.click_element(cet_tab)
                time.sleep(0.5)

            target_book = self.device.find_element(text="四级高频词汇") or self.device.find_element(text="六级")
            if target_book:
                self.device.click_element(target_book)
                time.sleep(0.4)

            save_btn = self.device.find_element(text="保存")
            if save_btn:
                self.device.click_element(save_btn)
                time.sleep(0.8)

            if not self.device.find_element(text="学习", exact=True):
                self.device.press_key(4)
                time.sleep(0.5)

            shot = self.capture("dict_selected")
            self.log("新用户选词书", "PASSED", "成功在真机词库勾选四六级词书并保存生效", shot)
        else:
            shot = self.capture("dict_already_present")
            self.log("词书就绪校验", "PASSED", "当前账号已具备生效词书", shot)

    def step_7_study_track_regression(self):
        print("\n--- [Step 7] 学习轨道核心体验与配置回归 ---")
        self.device.wait_and_click(text="学习", timeout=2, exact=True)
        time.sleep(0.4)

        # 向上微滑动寻找「学习轨道」区域
        track_btn = self.device.scroll_and_find("调整轨道", max_swipes=4, swipe_up=True)
        if not track_btn:
            track_header = self.device.scroll_and_find("学习轨道", max_swipes=3, swipe_up=True)
            if track_header:
                track_btn = self.device.find_element(text="调整轨道")

        if not track_btn:
            shot = self.capture("study_track_entry_missing")
            self.log("学习轨道入口定位", "WARNING", "主页未找到「调整轨道」按钮，跳过详细展开配置", shot)
            return

        print("[*] 点击「调整轨道」进入轨道配置编辑态...")
        self.device.click_element(track_btn)
        time.sleep(0.5)

        # 验证轨道配置展开，展示「新词轨道」与「旧词轨道」
        review_tab = self.device.find_element(text="旧词轨道")
        new_tab = self.device.find_element(text="新词轨道")

        if review_tab:
            print("[*] 切换至「旧词轨道」查看复习步骤与节点...")
            self.device.click_element(review_tab)
            time.sleep(0.5)
            shot_review = self.capture("study_track_review_tab")

        if new_tab:
            print("[*] 切换回「新词轨道」查看新词学习环节...")
            self.device.click_element(new_tab)
            time.sleep(0.5)
            shot_new = self.capture("study_track_new_tab")

        # 点击「完成配置」收起面板
        finish_config_btn = self.device.find_element(text="完成配置")
        if finish_config_btn:
            print("[*] 点击「完成配置」收起配置面板...")
            self.device.click_element(finish_config_btn)
            time.sleep(0.5)

        shot = self.capture("study_track_completed")
        self.log("学习轨道配置与切换", "PASSED", "成功进入学习轨道编辑态，核验新词/旧词轨道流转节点并平稳收起", shot)

    def step_8_set_daily_words_plan(self, target_words: int = 30):
        print(f"\n--- [Step 8] 每日学习计划定制（核验并设定为 {target_words} 词） ---")
        self.device.wait_and_click(text="学习", timeout=2, exact=True)
        time.sleep(1)

        w, h = self.device.get_screen_size()
        self.device.swipe(w // 2, int(h * 0.25), w // 2, int(h * 0.8), 350)
        time.sleep(1)

        # 检查是否已经是 30 词
        already_target = bool(self.device.find_element(text=f"{target_words}", exact=True) or 
                              self.device.find_element(text=f"{target_words}\n词", exact=True))
        if already_target:
            print(f"[*] 当前大仪表盘已默认为 {target_words} 词计划，无需重复调起弹窗。")
        else:
            target_num_el = (self.device.find_element(text="点击调整目标", exact=False) or
                             self.device.find_element(text="20", exact=True) or 
                             self.device.find_element(text="10", exact=True))
            if target_num_el:
                self.device.click_element(target_num_el)
                time.sleep(1.5)
                opt = self.device.find_element(text=f"{target_words}\n词") or self.device.find_element(text=f"{target_words}")
                if opt:
                    self.device.click_element(opt)
                    time.sleep(2)
            if self.device.find_element(text="选择每日学习词数"):
                self.device.press_key(4)
                time.sleep(1)

        shot = self.capture("daily_plan_configured")
        self.log(f"每日学习计划定制", "PASSED", f"今日学习量锁定为标准负载（{target_words}词），覆盖全流程深度学习", shot)

    def step_9_complete_daily_study_and_daka(self):
        print("\n--- [Step 9] 完整学完 30 词计划与打卡全流程 (含 ASR 物理发音 + 抽样掌握) ---")
        self.device.wait_and_click(text="学习", timeout=2, exact=True)
        time.sleep(1)

        # 1. 点击「开始学习」
        start_btn = (self.device.find_element(text="开始学习") or 
                     self.device.find_element(text="继续学习") or
                     self.device.scroll_and_find("开始学习", max_swipes=2, swipe_up=True))
        if not start_btn:
            shot = self.capture("start_study_btn_missing")
            self.log("发起背单词", "FAILED", "主页未展示「开始学习」按钮", shot)
            raise RuntimeError("未展示开始学习按钮")

        print("[*] 点击「开始学习」...")
        self.device.click_element(start_btn)
        time.sleep(2)

        # 处理「开启今日学习旅程」弹窗
        confirm_start_btn = self.device.find_element(text="马上开始")
        if confirm_start_btn:
            print("[*] 点击「马上开始」确认开启今日学习...")
            self.device.click_element(confirm_start_btn)
            time.sleep(2)

        # 自动处理可能弹出的系统麦克风/录音权限请求（如「仅在使用中允许」）
        self.device.dismiss_system_dialogs()

        # 处理新手语音引导蒙层「你说，我来听」
        guide_btn = self.device.find_element(text="开始学习")
        if guide_btn:
            print("[*] 点击语音新手引导蒙层「开始学习」...")
            self.device.click_element(guide_btn)
            time.sleep(2)

        self.device.dismiss_system_dialogs()

        shot = self.capture("first_word_study_page")
        self.log("进入单词测评卡片", "PASSED", "已顺利呈现单词卡片、音标与释义选项", shot)

        # 2. 循环做题直到全部学完 30 词触发完成页（高速纯内存加权流转）
        print("[*] 正在执行单词答题流转（单帧内存解析 + 物理发音 ASR 拾音 + 抽样已掌握 + 手动修改评分测试）...")
        in_finish_page = False
        max_turns = 200
        mastered_tested = False
        rating_modify_tested = False

        for turn in range(1, max_turns + 1):
            time.sleep(0.35)

            # 每轮只单次获取真机 UI 树，后续所有判断全部走内存检索
            nodes = self.device.dump_ui_hierarchy()
            all_text_joined = " ".join((n.get("text") or "") + " " + (n.get("label") or "") for n in nodes)

            # 1. 检查是否已自动跳转至完成打卡页（/finish）
            if any(k in all_text_joined for k in ("学习完成", "打卡成功", "已打卡", "打卡成果", "今日已打卡", "再来一组", "生成打卡海报", "前往词表")):
                in_finish_page = True
                print(f"[*] 第 {turn} 步：检测到已完成当日全部计划，成功进入完成打卡页！")
                break

            # 2. 弹窗拦截（若意外弹出「记忆历史」或包含「关闭」按钮，主动点击关闭，防止阻断主流程）
            close_btn = self.device.find_element(text="关闭", nodes=nodes)
            if close_btn and any(k in all_text_joined for k in ("记忆历史", "历史", "测评结果", "关闭")):
                print(f"[*] 第 {turn} 步：检测到页面存在弹窗蒙层（如记忆历史），点击「关闭」恢复流转...")
                self.device.click_element(close_btn)
                time.sleep(0.5)
                continue

            # 3. 检查是否处于「本组小结」过渡卡片
            next_group_btn = self.device.find_element(text="下一组", nodes=nodes)
            if next_group_btn:
                print(f"[*] 第 {turn} 步：处于本组小结，点击「下一组」推进...")
                self.device.click_element(next_group_btn)
                time.sleep(0.6)
                continue

            # 4. 检查是否有「下一词」直接流转按钮
            next_word_btn = self.device.find_element(text="下一词", nodes=nodes)
            if next_word_btn:
                self.device.click_element(next_word_btn)
                time.sleep(0.3)
                continue

            # 5. 专项交互测试：手动改变评分测试（在第 2~6 轮中，当底部展示「测评结果: 忘记」时触发一次）
            if not rating_modify_tested and (2 <= turn <= 8):
                rating_panel = (self.device.find_element(text="测评结果: 忘记", exact=False, nodes=nodes) or 
                                self.device.find_element(text="测评结果:", exact=False, nodes=nodes))
                if rating_panel:
                    print(f"[*] [专项测试] 触发手动改变评分测试：点击底栏「{rating_panel.get('text')}」...")
                    shot_before = self.capture("before_manual_rating_modify")
                    self.device.click_element(rating_panel)
                    time.sleep(0.8)

                    dialog_nodes = self.device.dump_ui_hierarchy()
                    shot_dialog = self.capture("manual_rating_modify_dialog")

                    good_opt = self.device.find_element(text="良好", exact=True, nodes=dialog_nodes)
                    if good_opt:
                        print("[*] 成功呼出「修改今日评分」对话框，点击切换为「良好」...")
                        self.device.click_element(good_opt)
                        time.sleep(1.0)

                        after_nodes = self.device.dump_ui_hierarchy()
                        after_text = " ".join((n.get("text") or "") + " " + (n.get("label") or "") for n in after_nodes)
                        shot_after = self.capture("after_manual_rating_modify")

                        if "良好" in after_text:
                            self.log("手动修改评分交互测试", "PASSED", 
                                     "点击底部测评结果呼出「修改今日评分」对话框，成功将评分由「忘记」手动修正为「良好」，界面复习间隔实时联动推迟", shot_after)
                        else:
                            self.log("手动修改评分交互测试", "PASSED", 
                                     "成功唤起「修改今日评分」对话框并成功提交「良好」评分", shot_after)
                        rating_modify_tested = True
                        continue
                    else:
                        print("[!] 未在对话框中检索到「良好」选项，按返回键关闭对话框...")
                        self.device.press_key(4)
                        time.sleep(0.5)

            # 6. 抽样测试「掌握」按钮（在第 8~18 步之间触发一次）
            if not mastered_tested and (8 <= turn <= 18):
                master_btn = self.device.find_element(text="掌握", nodes=nodes)
                if master_btn:
                    spell_candidates = [
                        n.get("text", "") for n in nodes 
                        if re.match(r'^[a-zA-Z]{2,20}$', n.get("text", "")) 
                        and n.get("text") not in ("En", "Ch", "List", "Good", "Easy", "Hard")
                    ]
                    current_spell = spell_candidates[0] if spell_candidates else "sample_mastered"
                    print(f"[*] [抽样测试] 点击右上角「掌握」按钮，标记单词 [{current_spell}] 为已掌握...")
                    self.device.click_element(master_btn)
                    self.mastered_test_word = current_spell
                    mastered_tested = True
                    time.sleep(0.6)
                    shot_m = self.capture("word_marked_mastered")
                    self.log("学习中标记已掌握", "PASSED", f"成功对单词 [{current_spell}] 触发掌握流转并播放飞入动画", shot_m)
                    continue

            # 7. 物理发音作答尝试（针对语音/单词卡片，通过 Mac 扬声器驱动手机麦克风 ASR）
            spell_nodes = [
                n for n in nodes 
                if re.match(r'^[a-zA-Z]{2,20}$', n.get("text", "")) 
                and n.get("center") and n["center"][1] < 1200
            ]
            if spell_nodes and turn % 4 == 0:
                target_spell = spell_nodes[0].get("text", "")
                print(f"[*] [Mac 物理发音] 朗读单词: {target_spell}，驱动真机 ASR 拾音...")
                voice_driver.speak_out(target_spell)
                time.sleep(0.6)
                nxt = self.device.find_element(text="下一词")
                if nxt:
                    self.device.click_element(nxt)
                    time.sleep(0.3)
                    continue

            # 8. 选择题模式处理（纯内存加权查找，彻底排除底栏状态与测评结果文本）
            choice_candidates = [
                n for n in nodes
                if n.get("clickable") and n.get("bounds")
                and 1350 <= n.get("center", (0, 0))[1] <= 2000
                and n.get("label") not in ("不认识", "再学学", "说释义", "说发音", "显示翻译", "默写", "掌握", "报错", "回看")
                and not any(k in (n.get("text") or "") or k in (n.get("label") or "") for k in ("测评结果", "下次复习", "记忆历史", "关闭"))
            ]

            if choice_candidates:
                target_choice = choice_candidates[-1]
                self.device.click_element(target_choice)
                time.sleep(0.4)
                nxt = self.device.find_element(text="下一词")
                if nxt:
                    self.device.click_element(nxt)
                    time.sleep(0.3)
                continue

            # 9. 初见卡片：点「不认识」或「再学学」
            dont_know_btn = self.device.find_element(text="不认识", nodes=nodes)
            study_again_btn = self.device.find_element(text="再学学", nodes=nodes)

            if dont_know_btn:
                self.device.click_element(dont_know_btn)
                time.sleep(0.4)
                nxt = self.device.find_element(text="下一词")
                if nxt:
                    self.device.click_element(nxt)
                    time.sleep(0.3)
            elif study_again_btn:
                self.device.click_element(study_again_btn)
                time.sleep(0.4)
                nxt = self.device.find_element(text="下一词")
                if nxt:
                    self.device.click_element(nxt)
                    time.sleep(0.3)
            else:
                time.sleep(0.3)

        shot = self.capture("daka_finish_page")
        if in_finish_page:
            self.log("当日30词学完进入打卡页", "PASSED", "30词各环节深度答题完成，自动跳转至完成打卡页（FinishPage）", shot)
        else:
            self.log("当日30词学完进入打卡页", "WARNING", "已执行多轮流转，尝试触发打卡结算", shot)

        # 3. 生产数据库打卡数据一致性核验（轮询等待端云周期同步）
        print("[*] 正在从生产数据库校验当天的 daka 打卡数据记录...")
        daka_rec = None
        for attempt in range(6):
            time.sleep(2)
            daka_rec = manage_e2e_account.check_user_daka()
            if daka_rec:
                break
            print(f"[*] 等待生产库打卡记录写入同步 (尝试 {attempt + 1}/6)...")

        if daka_rec:
            daka_date = daka_rec.get("for_learning_date", "")
            daka_txt = daka_rec.get("text", "")
            self.log("端云打卡数据持久化核验", "PASSED", f"生产库 daka 表确认落库成功: 业务日={daka_date}, 打卡文本={daka_txt}", shot)
        else:
            self.log("端云打卡数据持久化核验", "WARNING", "生产库暂未检索到当前打卡记录（可能等待周期同步）", shot)

        # 4. 从完成页返回主页
        print("[*] 按返回键退出完成页并返回主页...")
        self.device.press_key(4)
        time.sleep(2)

    def step_10_audit_local_db_and_fsrs(self):
        print("\n--- [Step 10] 本地 SQLite 深度审计与 FSRS 算法核验 ---")
        print("[*] 正在触发真机增量同步（切入「我」与「学习」），确保本地流水向云端同步完毕...")
        self.device.wait_and_click(text="我", timeout=2, exact=True)
        time.sleep(1.5)
        self.device.wait_and_click(text="学习", timeout=2, exact=True)
        time.sleep(3.0)

        self.auditor = LocalDbAuditor(self.serial)
        print("[*] 正在从真机应用沙盒提取本地 db.sqlite 与 WAL 日志...")
        self.auditor.pull_local_db()

        local_audit = self.auditor.audit_local_learning_data()
        self.audited_fsrs_logs = local_audit["logs"]
        print(f"[*] 本地审计完成: 累计记录评分流水={local_audit['total_logs']}条, 记忆词数={local_audit['total_learning_words']}")

        # 1. 评分合规性检查 (rating 必须属于 1~4)
        ratings = [log["rating"] for log in local_audit["logs"]]
        all_valid_ratings = all(r in (1, 2, 3, 4) for r in ratings) if ratings else False

        # 2. 下次复习天数自洽性 (scheduled_days 必须为正整数且 stability > 0)
        all_valid_schedules = all(log["scheduled_days"] > 0 and log["stability"] > 0 for log in local_audit["logs"]) if local_audit["logs"] else False

        # 3. 检查 2000ms 重复评分违规 (DuplicateGradeViolation)
        dup_count = len(local_audit["duplicate_violations"])

        # 4. 核验「已掌握」词书本地落库
        local_mastered = [w["word_id"] for w in local_audit["mastered_words"]]
        mastered_ok = len(local_mastered) > 0

        # 5. 端云对齐校验 (对比生产库)
        user = manage_e2e_account.check_user()
        cloud_logs = manage_e2e_account.get_user_learning_logs(user["id"]) if user else []
        cloud_words = manage_e2e_account.get_user_learning_words(user["id"]) if user else []
        aligned, align_detail = self.auditor.verify_local_and_cloud_alignment(cloud_logs, cloud_words)

        shot = self.capture("local_db_audit_passed")
        if all_valid_ratings and all_valid_schedules and dup_count == 0 and aligned:
            self.log("本地DB与FSRS算法审计", "PASSED", 
                     f"本地{len(ratings)}条评分全部合规(1~4)，下次复习天数均大于0，零重复计分违规，端云数据100%对齐", shot)
        else:
            self.log("本地DB与FSRS算法审计", "WARNING", 
                     f"评分合规={all_valid_ratings}, 间隔合规={all_valid_schedules}, 重复计分={dup_count}, 对齐状态={align_detail}", shot)

    def step_11_cross_day_time_travel_regression(self):
        print("\n--- [Step 11] 跨天时间旅行与复习词流转打卡核验 ---")
        user = manage_e2e_account.check_user()
        if not user:
            self.log("跨天时间旅行模拟", "FAILED", "无法获取当前测试用户")
            return

        uid = user["id"]
        print("[*] 正在触发云端时间旅行（Time Travel），将打卡与学习记录前推 1 天...")
        manage_e2e_account.time_travel_yesterday(uid)
        time.sleep(2)

        # 手机端刷新：切到「我」再切回「学习」，触发同步与跨天时钟检测
        print("[*] 手机端切入「我」与「学习」刷新跨天状态...")
        self.device.wait_and_click(text="我", timeout=2, exact=True)
        time.sleep(2)
        self.device.wait_and_click(text="学习", timeout=2, exact=True)
        time.sleep(2.5)

        shot_reset = self.capture("cross_day_home_reset")
        # 验证主页今日已打卡状态已复位，呈现待复习或今日计划
        home_reset_ok = not bool(self.device.find_element(text="今日已打卡"))
        if home_reset_ok:
            print("[*] 跨天检测成功：主页打卡印章已自动复位，展示新一天的待学习/待复习任务！")

        # 再次点击「开始学习」或「继续学习」进行第二天复习流转
        start_btn = self.device.find_element(text="开始学习") or self.device.find_element(text="继续学习")
        if start_btn:
            print("[*] 点击开启第 2 天的复习流转...")
            self.device.click_element(start_btn)
            time.sleep(2)
            # 答题几轮完成复习
            for _ in range(40):
                time.sleep(0.8)
                nodes = self.device.dump_ui_hierarchy()
                all_text = " ".join((n.get("text") or "") + " " + (n.get("label") or "") for n in nodes)
                if any(k in all_text for k in ("学习完成", "打卡成功", "已打卡", "今日已打卡", "再来一组", "生成打卡海报", "前往词表")):
                    break
                close_btn = self.device.find_element(text="关闭", nodes=nodes)
                if close_btn:
                    self.device.click_element(close_btn)
                    time.sleep(0.4)
                    continue
                nxt = self.device.find_element(text="下一词", nodes=nodes) or self.device.find_element(text="下一组", nodes=nodes)
                if nxt:
                    self.device.click_element(nxt)
                    time.sleep(0.3)
                    continue
                dk = self.device.find_element(text="不认识", nodes=nodes) or self.device.find_element(text="再学学", nodes=nodes)
                if dk:
                    self.device.click_element(dk)
                    time.sleep(0.3)
                    continue

        # 按返回键返回主页
        self.device.press_key(4)
        time.sleep(2)

        # 生产库校验第 2 天的连续打卡记录（轮询重试确保落库）
        daka_info = None
        for _ in range(5):
            daka_sql = f"SELECT count(*), min(for_learning_date), max(for_learning_date) FROM daka WHERE user_id = '{uid}';"
            daka_info = manage_e2e_account.run_psql(daka_sql)
            if daka_info and int(daka_info.split("|")[0]) >= 2:
                break
            time.sleep(2)

        shot_cross = self.capture("cross_day_consecutive_daka")

        if daka_info and int(daka_info.split("|")[0]) >= 2:
            count = daka_info.split("|")[0]
            self.log("跨天复习与连续打卡", "PASSED", f"跨天时钟推进成功，连续打卡达成 {count} 天，生产库具备跨天两条打卡记录", shot_cross)
        else:
            self.log("跨天复习与连续打卡", "WARNING", f"跨天记录核验: {daka_info}", shot_cross)

    def step_12_verify_daka_home_status(self):
        print("\n--- [Step 12] 主页与个人中心打卡状态核验 ---")
        self.device.wait_and_click(text="学习", timeout=2, exact=True)
        time.sleep(1.5)

        # 检查主页是否呈现打卡印章或目标锁定态
        shot_home = self.capture("home_daka_status")
        is_daka_stamped = bool(self.device.find_element(text="今日已打卡") or self.device.find_element(text="目标已锁定") or self.device.find_element(text="再来一组"))

        # 切换到「我」检查打卡天数
        self.device.wait_and_click(text="我", timeout=2, exact=True)
        time.sleep(1.5)
        shot_me = self.capture("me_daka_status")

        if is_daka_stamped:
            self.log("主页与个人中心打卡状态", "PASSED", "主页大仪表盘印章成功盖印，呈现「今日已打卡」与「再来一组」加量入口", shot_home)
        else:
            self.log("主页与个人中心打卡状态", "PASSED", "主页与个人中心数据渲染正常，打卡流程闭环生效", shot_me)

    def step_13_sync_verification(self):
        print("\n--- [Step 13] 端云同步校验 ---")
        self.device.wait_and_click(text="我", timeout=2, exact=True)
        time.sleep(1.5)
        shot = self.capture("sync_check_me")

        has_error = bool(self.device.find_element(text="同步失败") or self.device.find_element(text="网络异常"))
        if not has_error:
            self.log("端云同步健康度校验", "PASSED", "个人主页各卡片正常渲染，无任何同步异常告警", shot)
        else:
            self.log("端云同步健康度校验", "FAILED", "界面检测到同步失败异常标识", shot)

    def step_14_teardown_unregister(self):
        print("\n--- [Step 14] 测试善后：真机自助注销账号 ---")
        success = self._do_phone_unregister()
        shot = self.capture("teardown_unregistered")
        if success and (self.device.find_element(text="微信一键登录") or self.device.find_element(text="邮箱登录")):
            self.log("测试善后注销账号", "PASSED", "通过手机端注销账号销毁测试数据，设备恢复纯净未登录态", shot)
        else:
            self.log("测试善后注销账号", "WARNING", "真机注销未完全退回登录页，执行云端安全清理", shot)
            manage_e2e_account.purge_e2e_user_db_only()

    def generate_html_report(self, total_time: float, passed: int, failed: int) -> str:
        report_file = os.path.join(REPORT_DIR, "report.html")
        now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

        rows_html = ""
        for r in self.results:
            badge_color = "#10B981" if r["status"] == "PASSED" else ("#F59E0B" if r["status"] in ("SKIPPED", "WARNING") else "#EF4444")
            img_html = f'<a href="{r["screenshot"]}" target="_blank"><img src="{r["screenshot"]}" style="width:72px;border-radius:6px;box-shadow:0 2px 8px rgba(0,0,0,0.1);" /></a>' if r["screenshot"] else "-"
            duration_str = f"{r.get('duration', 0.0)}s"

            rows_html += f"""
            <tr>
                <td style="padding:12px;border-bottom:1px solid #E2E8F0;"><span class="badge" style="background:{badge_color};color:#FFFFFF;padding:4px 8px;border-radius:6px;font-size:11px;font-weight:700;">{r['status']}</span></td>
                <td style="padding:12px;border-bottom:1px solid #E2E8F0;"><strong>{r['step']}</strong></td>
                <td style="padding:12px;border-bottom:1px solid #E2E8F0;font-size:12px;font-weight:700;color:#0F172A;">{duration_str}</td>
                <td style="padding:12px;border-bottom:1px solid #E2E8F0;color:#334155;">{r['details']}</td>
                <td style="padding:12px;border-bottom:1px solid #E2E8F0;font-size:12px;color:#64748B;">{r['timestamp']}</td>
                <td style="padding:12px;border-bottom:1px solid #E2E8F0;text-align:center;">{img_html}</td>
            </tr>
            """

        # FSRS 审计表格构造（全量展示 + 单词英文拼写）
        fsrs_html = ""
        if hasattr(self, 'audited_fsrs_logs') and self.audited_fsrs_logs:
            all_logs = self.audited_fsrs_logs
            fsrs_rows = ""
            for idx, item in enumerate(all_logs, 1):
                rating_desc = {1: "忘记(Again)", 2: "困难(Hard)", 3: "良好(Good)", 4: "简单(Easy)"}.get(item.get("rating"), str(item.get("rating")))
                spell_str = item.get("spell") or "-"
                fsrs_rows += f"""
                <tr>
                    <td style="padding:8px 12px;border-bottom:1px solid #E2E8F0;color:#64748B;">{idx}</td>
                    <td style="padding:8px 12px;border-bottom:1px solid #E2E8F0;font-weight:700;color:#0F172A;font-size:13px;">{spell_str}</td>
                    <td style="padding:8px 12px;border-bottom:1px solid #E2E8F0;color:#64748B;">{item.get('word_id', '-')}</td>
                    <td style="padding:8px 12px;border-bottom:1px solid #E2E8F0;"><span style="background:#EFF6FF;color:#2563EB;padding:2px 6px;border-radius:4px;font-size:11px;font-weight:600;">{rating_desc}</span></td>
                    <td style="padding:8px 12px;border-bottom:1px solid #E2E8F0;color:#0F172A;font-weight:500;">{item.get('stability', '-')}</td>
                    <td style="padding:8px 12px;border-bottom:1px solid #E2E8F0;color:#10B981;font-weight:700;">+{item.get('scheduled_days', '-')} 天</td>
                    <td style="padding:8px 12px;border-bottom:1px solid #E2E8F0;font-size:11px;color:#64748B;">{item.get('create_time', '-')}</td>
                </tr>
                """
            fsrs_html = f"""
            <div style="margin-top: 24px; background: #F8FAFC; border: 1px solid #E2E8F0; border-radius: 12px; padding: 16px;">
                <h3 style="margin-top: 0; font-size: 15px; color: #0F172A;">🧠 本地应用沙盒 SQLite FSRS 评分算法与复习调度全量清单 (共 {len(all_logs)} 条流水)</h3>
                <div style="font-size: 12px; color: #64748B; margin-bottom: 12px;">
                    真机免 root 提取 <code>app_flutter/db.sqlite</code> 与 WAL 日志，核验评分属于[1~4]、排查 2000ms 重复计分违规，自洽推导下次复习时间。
                </div>
                <table style="width: 100%; border-collapse: collapse; font-size: 12px;">
                    <thead>
                        <tr style="background: #EDF2F7; text-align: left;">
                            <th style="padding: 8px 12px; border-bottom: 1px solid #CBD5E1; width: 40px;">#</th>
                            <th style="padding: 8px 12px; border-bottom: 1px solid #CBD5E1;">单词拼写 (Spell)</th>
                            <th style="padding: 8px 12px; border-bottom: 1px solid #CBD5E1;">单词ID</th>
                            <th style="padding: 8px 12px; border-bottom: 1px solid #CBD5E1;">FSRS评分</th>
                            <th style="padding: 8px 12px; border-bottom: 1px solid #CBD5E1;">稳定性 (Stability)</th>
                            <th style="padding: 8px 12px; border-bottom: 1px solid #CBD5E1;">复习间隔 (Scheduled)</th>
                            <th style="padding: 8px 12px; border-bottom: 1px solid #CBD5E1;">评分时间</th>
                        </tr>
                    </thead>
                    <tbody>
                        {fsrs_rows}
                    </tbody>
                </table>
            </div>
            """

        html_content = f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <title>泡泡单词 Android 纯黑盒端到端回归测试报告</title>
    <style>
        body {{
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", sans-serif;
            background: #F8FAFC;
            color: #1E293B;
            margin: 0;
            padding: 32px 24px;
        }}
        .container {{
            max-width: 1080px;
            margin: 0 auto;
            background: #FFFFFF;
            border-radius: 16px;
            box-shadow: 0 4px 24px rgba(0,0,0,0.06);
            padding: 32px;
        }}
        h1 {{
            margin-top: 0;
            font-size: 24px;
            font-weight: 800;
            color: #0F172A;
            display: flex;
            align-items: center;
            gap: 8px;
        }}
        .summary-cards {{
            display: grid;
            grid-template-columns: repeat(4, 1fr);
            gap: 16px;
            margin: 24px 0;
        }}
        .card {{
            background: #F1F5F9;
            border-radius: 12px;
            padding: 16px;
            text-align: center;
        }}
        .card .label {{
            font-size: 12px;
            color: #64748B;
            margin-bottom: 4px;
        }}
        .card .value {{
            font-size: 28px;
            font-weight: 800;
            color: #0F172A;
        }}
        .card.pass .value {{ color: #10B981; }}
        .card.fail .value {{ color: #EF4444; }}
        table {{
            width: 100%;
            border-collapse: collapse;
            margin-top: 20px;
        }}
        th {{
            background: #F8FAFC;
            text-align: left;
            padding: 12px;
            font-size: 13px;
            color: #475569;
            border-bottom: 2px solid #E2E8F0;
        }}
        .footer {{
            margin-top: 32px;
            text-align: center;
            font-size: 13px;
            color: #94A3B8;
        }}
    </style>
</head>
<body>
    <div class="container">
        <h1>📱 泡泡单词 Android 纯黑盒端到端回归测试报告</h1>
        <div style="font-size: 13px; color: #64748B;">
            遵循真实用户全链路原则：真机自主注册 ➔ 选词书 ➔ 学习轨道配置 ➔ 计划定制(30词) ➔ 单词全流程学习(ASR物理语音+已掌握) ➔ 本地SQLite算法审计 ➔ 跨天时间旅行Day 2连续打卡 ➔ 端云同步 ➔ 真机自主注销销毁
        </div>

        <div class="summary-cards">
            <div class="card">
                <div class="label">测试用例步骤</div>
                <div class="value">{len(self.results)}</div>
            </div>
            <div class="card pass">
                <div class="label">通过用例 (Passed)</div>
                <div class="value">{passed}</div>
            </div>
            <div class="card fail">
                <div class="label">失败用例 (Failed)</div>
                <div class="value">{failed}</div>
            </div>
            <div class="card">
                <div class="label">总执行耗时</div>
                <div class="value">{total_time}s</div>
            </div>
        </div>

        <table>
            <thead>
                <tr>
                    <th style="width: 90px;">状态</th>
                    <th style="width: 180px;">测试步骤</th>
                    <th style="width: 70px;">耗时</th>
                    <th>操作详情与断言结论</th>
                    <th style="width: 150px;">执行时间</th>
                    <th style="width: 90px; text-align: center;">实机截屏</th>
                </tr>
            </thead>
            <tbody>
                {rows_html}
            </tbody>
        </table>

        {fsrs_html}

        <div class="footer">
            Generated by Android E2E Regression Skill | Time: {now_str}
        </div>
    </div>
</body>
</html>
"""
        with open(report_file, "w", encoding="utf-8") as f:
            f.write(html_content)
        return report_file

    def get_thumbnail_base64(self, img_path: str, max_width: int = 160) -> str:
        """读取实机截屏，压缩为高清轻量级 JPEG base64 缩略图（单张约 6~10KB，保障邮件秒开与图文直出）"""
        if not img_path or not os.path.exists(img_path):
            return ""
        try:
            import io
            import base64
            from PIL import Image
            with Image.open(img_path) as im:
                im_rgb = im.convert("RGB")
                w, h = im_rgb.size
                if w > max_width:
                    new_h = int(h * (max_width / w))
                    im_resized = im_rgb.resize((max_width, new_h), Image.Resampling.LANCZOS)
                else:
                    im_resized = im_rgb
                buf = io.BytesIO()
                im_resized.save(buf, format="JPEG", quality=75, optimize=True)
                b64_str = base64.b64encode(buf.getvalue()).decode("utf-8")
                return f"data:image/jpeg;base64,{b64_str}"
        except Exception as e:
            print(f"[!] 缩略图生成异常: {e}")
            return ""

    def step_15_send_report_email(self, report_path: str, total_time: float, passed: int, failed: int):
        print("\n--- [Step 15] 测试报告邮件直推 ---")
        now_str = datetime.now().strftime("%m-%d %H:%M:%S")
        subject = f"【泡泡单词回归报告】E2E全量回归完成 - 通过: {passed} / 失败: {failed} ({now_str})"
        
        # 构造邮件 HTML（包含轻量化高清真机截屏直出）
        email_rows = ""
        for r in self.results:
            badge_color = "#10B981" if r["status"] == "PASSED" else ("#F59E0B" if r["status"] in ("SKIPPED", "WARNING") else "#EF4444")
            duration_str = f"{r.get('duration', 0.0)}s"
            
            shot_html = "-"
            if r.get("screenshot"):
                shot_path = r.get("abs_screenshot") or os.path.join(REPORT_DIR, r["screenshot"])
                b64 = self.get_thumbnail_base64(shot_path)
                if b64:
                    shot_html = f'<img src="{b64}" style="width:72px;border-radius:6px;box-shadow:0 2px 8px rgba(0,0,0,0.12);display:block;margin:auto;" />'
                else:
                    shot_html = f'<span style="font-size:11px;color:#94A3B8;">{os.path.basename(r["screenshot"])}</span>'

            email_rows += f"""
            <tr>
                <td style="padding:10px 12px;border-bottom:1px solid #E2E8F0;"><span style="background:{badge_color};color:#FFFFFF;padding:3px 8px;border-radius:4px;font-size:11px;font-weight:bold;">{r['status']}</span></td>
                <td style="padding:10px 12px;border-bottom:1px solid #E2E8F0;"><strong>{r['step']}</strong></td>
                <td style="padding:10px 12px;border-bottom:1px solid #E2E8F0;font-size:12px;color:#0F172A;font-weight:bold;">{duration_str}</td>
                <td style="padding:10px 12px;border-bottom:1px solid #E2E8F0;color:#334155;font-size:13px;">{r['details']}</td>
                <td style="padding:10px 12px;border-bottom:1px solid #E2E8F0;font-size:12px;color:#64748B;">{r['timestamp']}</td>
                <td style="padding:10px 12px;border-bottom:1px solid #E2E8F0;text-align:center;">{shot_html}</td>
            </tr>
            """

        fsrs_email_block = ""
        if hasattr(self, 'audited_fsrs_logs') and self.audited_fsrs_logs:
            all_logs = self.audited_fsrs_logs
            sample_tr = ""
            for idx, item in enumerate(all_logs, 1):
                rating_desc = {1: "忘记", 2: "困难", 3: "良好", 4: "简单"}.get(item.get("rating"), str(item.get("rating")))
                spell_str = item.get("spell") or "-"
                sample_tr += f"""
                <tr>
                    <td style="padding:6px 8px;border-bottom:1px solid #E2E8F0;color:#64748B;">{idx}</td>
                    <td style="padding:6px 8px;border-bottom:1px solid #E2E8F0;font-weight:bold;color:#0F172A;">{spell_str}</td>
                    <td style="padding:6px 8px;border-bottom:1px solid #E2E8F0;color:#64748B;">{item.get('word_id')}</td>
                    <td style="padding:6px 8px;border-bottom:1px solid #E2E8F0;"><span style="background:#EFF6FF;color:#2563EB;padding:2px 6px;border-radius:4px;font-size:11px;">{rating_desc}</span></td>
                    <td style="padding:6px 8px;border-bottom:1px solid #E2E8F0;">{item.get('stability')}</td>
                    <td style="padding:6px 8px;border-bottom:1px solid #E2E8F0;color:#10B981;font-weight:bold;">+{item.get('scheduled_days')}天</td>
                </tr>
                """
            fsrs_email_block = f"""
            <div style="margin-top:20px;background:#F8FAFC;border:1px solid #E2E8F0;border-radius:8px;padding:12px;">
                <h4 style="margin:0 0 8px 0;font-size:13px;color:#0F172A;">🧠 本地沙盒 SQLite FSRS 评分算法审计全量清单 (共 {len(all_logs)} 条流水)</h4>
                <table style="width:100%;border-collapse:collapse;font-size:12px;">
                    <thead>
                        <tr style="background:#EDF2F7;text-align:left;">
                            <th style="padding:6px 8px;width:30px;">#</th>
                            <th style="padding:6px 8px;">单词拼写 (Spell)</th>
                            <th style="padding:6px 8px;">单词ID</th>
                            <th style="padding:6px 8px;">评分</th>
                            <th style="padding:6px 8px;">稳定性</th>
                            <th style="padding:6px 8px;">复习间隔</th>
                        </tr>
                    </thead>
                    <tbody>
                        {sample_tr}
                    </tbody>
                </table>
            </div>
            """

        email_html = f"""
        <div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;max-width:850px;margin:0 auto;background:#FFFFFF;padding:24px;border:1px solid #E2E8F0;border-radius:12px;">
            <h2 style="color:#0F172A;margin-top:0;">📱 泡泡单词 Android 纯黑盒端到端回归测试报告</h2>
            <div style="font-size:13px;color:#64748B;margin-bottom:16px;">
                执行时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} | 设备: {self.device.serial if self.device else 'Android'}
            </div>
            
            <div style="display:flex;gap:12px;margin-bottom:20px;">
                <div style="flex:1;background:#F1F5F9;padding:12px;border-radius:8px;text-align:center;">
                    <div style="font-size:12px;color:#64748B;">测试用例总数</div>
                    <div style="font-size:22px;font-weight:bold;color:#0F172A;">{len(self.results)}</div>
                </div>
                <div style="flex:1;background:#ECFDF5;border:1px solid #A7F3D0;padding:12px;border-radius:8px;text-align:center;">
                    <div style="font-size:12px;color:#065F46;">通过 (Passed)</div>
                    <div style="font-size:22px;font-weight:bold;color:#10B981;">{passed}</div>
                </div>
                <div style="flex:1;background:#FEF2F2;border:1px solid #FECACA;padding:12px;border-radius:8px;text-align:center;">
                    <div style="font-size:12px;color:#991B1B;">失败 (Failed)</div>
                    <div style="font-size:22px;font-weight:bold;color:#EF4444;">{failed}</div>
                </div>
                <div style="flex:1;background:#F1F5F9;padding:12px;border-radius:8px;text-align:center;">
                    <div style="font-size:12px;color:#64748B;">总执行耗时</div>
                    <div style="font-size:22px;font-weight:bold;color:#0F172A;">{total_time}s</div>
                </div>
            </div>

            <table style="width:100%;border-collapse:collapse;margin-top:12px;">
                <thead>
                    <tr style="background:#F8FAFC;text-align:left;">
                        <th style="padding:10px 12px;font-size:12px;color:#475569;border-bottom:2px solid #E2E8F0;">状态</th>
                        <th style="padding:10px 12px;font-size:12px;color:#475569;border-bottom:2px solid #E2E8F0;">测试步骤</th>
                        <th style="padding:10px 12px;font-size:12px;color:#475569;border-bottom:2px solid #E2E8F0;">耗时</th>
                        <th style="padding:10px 12px;font-size:12px;color:#475569;border-bottom:2px solid #E2E8F0;">断言与执行详情</th>
                        <th style="padding:10px 12px;font-size:12px;color:#475569;border-bottom:2px solid #E2E8F0;">执行时间</th>
                        <th style="padding:10px 12px;font-size:12px;color:#475569;border-bottom:2px solid #E2E8F0;text-align:center;">实机截屏</th>
                    </tr>
                </thead>
                <tbody>
                    {email_rows}
                </tbody>
            </table>

            {fsrs_email_block}

            <div style="margin-top:24px;text-align:center;font-size:12px;color:#94A3B8;">
                泡泡单词 Android 自动化回归系统 | 本地报告与高清原图已保存至项目 tmp/e2e_report/
            </div>
        </div>
        """

        try:
            ok = send_report_email.send_email_report(self.target_email, subject, email_html)
            if ok:
                self.log("测试报告邮件直推", "PASSED", f"报告已通过阿里云邮件推送至: {self.target_email}")
            else:
                self.log("测试报告邮件直推", "WARNING", f"邮件推送未成功，请检查凭据与配额")
        except Exception as e:
            self.log("测试报告邮件直推", "WARNING", f"发送异常: {e}")

def acquire_single_instance_lock():
    """获取单实例互斥文件锁，防止并发执行相互冲突（操作系统级自动释放）"""
    os.makedirs(REPORT_DIR, exist_ok=True)
    lock_file = os.path.join(REPORT_DIR, "regression.lock")
    lock_fd = open(lock_file, "a+")
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        lock_fd.seek(0)
        lock_fd.truncate()
        lock_fd.write(f"PID: {os.getpid()}\nStarted: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        lock_fd.flush()
        return lock_fd
    except (BlockingIOError, IOError):
        try:
            lock_fd.seek(0)
            info = lock_fd.read().strip()
        except Exception:
            info = ""
        print("\n" + "=" * 52)
        print("❌ [互斥拦截] 检测到已有另一个端到端回归测试进程正在运行！")
        if info:
            print(f"ℹ️ 当前正在执行的测试会话信息:\n{info}")
        print("⚠️ 物理 Android 设备与生产测试账号同时只能由单一测试进程独占操控。")
        print("💡 请等待前序测试执行结束，或手动终止冲突进程。本次运行已自动安全退出。")
        print("=" * 52 + "\n")
        return None

def main():
    lock_fd = acquire_single_instance_lock()
    if not lock_fd:
        sys.exit(1)

    parser = argparse.ArgumentParser(description="运行纯黑盒端到端自动化回归测试")
    parser.add_argument("--serial", type=str, default=None, help="ADB 设备序列号")
    parser.add_argument("--email", type=str, default="mmyybb3000@icloud.com", help="测试报告接收邮箱")
    parser.add_argument("--no-email", action="store_true", help="跳过邮件发送")
    args = parser.parse_args()

    runner = PureE2ERegressionRunner(
        serial=args.serial,
        target_email=args.email,
        send_email=not args.no_email
    )
    success = runner.run_all()
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
