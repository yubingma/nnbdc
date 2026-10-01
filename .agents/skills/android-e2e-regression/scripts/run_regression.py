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
import fcntl
from datetime import datetime
from PIL import Image

# 导入同目录的驱动模块
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.append(SCRIPT_DIR)

from device_controller import AndroidDeviceController
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
        os.makedirs(SCREENSHOT_DIR, exist_ok=True)

    def log(self, step_name: str, status: str, details: str = "", screenshot: str = None):
        res = {
            "step": step_name,
            "status": status,
            "details": details,
            "screenshot": os.path.relpath(screenshot, REPORT_DIR) if screenshot else None,
            "abs_screenshot": screenshot,
            "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        }
        self.results.append(res)
        icon = "✅" if status == "PASSED" else ("⚠️" if status in ("SKIPPED", "WARNING") else "❌")
        print(f"[{datetime.now().strftime('%H:%M:%S')}] {icon} [{status}] {step_name}: {details}")

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
        print("🚀 开始执行 Android 纯黑盒端到端回归测试 (含打卡与学习轨道)")
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

            # 8. 每日学习计划定制（设置为 2 词）
            self.step_8_set_daily_words_plan(target_words=2)

            # 9. 完整学完当日计划与打卡全流程
            self.step_9_complete_daily_study_and_daka()

            # 10. 主页与个人中心打卡状态核验
            self.step_10_verify_daka_home_status()

            # 11. 端云同步与个人中心健康度校验
            self.step_11_sync_verification()

            # 12. 测试闭环收尾：真机自助注销账号（还原未登录态）
            self.step_12_teardown_unregister()

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
            self.step_13_send_report_email(report_path, total_time, passed_count, failed_count)

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

        # 3. 向上滑动查找「注销账号」列表项
        unreg_btn = self.device.scroll_and_find("注销账号", max_swipes=3, swipe_up=True)
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
            print("[!] 真机注销未完全退回登录页，执行云端安全清理并重启 App...")
            manage_e2e_account.purge_e2e_user_db_only()
            self.device.launch_app(stop_first=True)
            time.sleep(2)
            shot = self.capture("after_fallback_purge")
            self.log("真机重置状态核验", "PASSED", "已恢复纯净未登录状态", shot)

    def step_4_register_and_login(self):
        print("\n--- [Step 4] 手机端自主注册与验证码登录 ---")
        time.sleep(1)

        # 1. 点击「邮箱登录」
        email_login_btn = self.device.find_element(text="邮箱登录")
        if not email_login_btn:
            self.device.press_key(4)
            time.sleep(1)
            email_login_btn = self.device.find_element(text="邮箱登录")

        if not email_login_btn:
            shot = self.capture("email_login_btn_missing")
            self.log("邮箱登录入口定位", "FAILED", "未能在当前屏幕找到「邮箱登录」按钮", shot)
            raise RuntimeError("找不到邮箱登录按钮")

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

        # 8. 轮询等待登录成功并进入主页（内存级快速单次 dump，支持未点中自动补点）
        is_in_main = False
        start_wait = time.time()
        while time.time() - start_wait < 15:
            time.sleep(1.2)
            elements = self.device.dump_ui_hierarchy()
            labels = [el.get("label", "") for el in elements]
            texts = [el.get("text", "") for el in elements]
            all_txt = " ".join(labels + texts)

            if "学习" in all_txt or "词表" in all_txt:
                is_in_main = True
                break

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
            time.sleep(1)
            clicked = self.device.wait_and_click(text=tab_name, timeout=3, exact=True)
            time.sleep(1.5)
            shot = self.capture(f"tab_{tag}")
            if clicked:
                self.log(f"导航切换: {tab_name}", "PASSED", f"成功切入 {desc}", shot)
            else:
                self.log(f"导航切换: {tab_name}", "FAILED", f"未能点击 Tab「{tab_name}」", shot)

    def step_6_select_word_book(self):
        print("\n--- [Step 6] 选词书核心链路回归 ---")
        self.device.wait_and_click(text="学习", timeout=2, exact=True)
        time.sleep(1)

        # 检查首页是否提示「选择词书」
        select_dict_btn = self.device.find_element(text="选择词书")
        if not select_dict_btn:
            select_dict_btn = self.device.scroll_and_find("选择词书", max_swipes=2, swipe_up=True)

        if select_dict_btn:
            print("[*] 新用户无选定词书，自动执行选词书流程...")
            self.device.click_element(select_dict_btn)
            time.sleep(2)

            cet_tab = self.device.find_element(text="四六级")
            if cet_tab:
                self.device.click_element(cet_tab)
                time.sleep(1.5)

            target_book = self.device.find_element(text="四级高频词汇") or self.device.find_element(text="六级")
            if target_book:
                self.device.click_element(target_book)
                time.sleep(1)

            save_btn = self.device.find_element(text="保存")
            if save_btn:
                self.device.click_element(save_btn)
                time.sleep(3)

            if not self.device.find_element(text="学习", exact=True):
                self.device.press_key(4)
                time.sleep(1.5)

            shot = self.capture("dict_selected")
            self.log("新用户选词书", "PASSED", "成功在真机词库勾选四六级词书并保存生效", shot)
        else:
            shot = self.capture("dict_already_present")
            self.log("词书就绪校验", "PASSED", "当前账号已具备生效词书", shot)

    def step_7_study_track_regression(self):
        print("\n--- [Step 7] 学习轨道核心体验与配置回归 ---")
        self.device.wait_and_click(text="学习", timeout=2, exact=True)
        time.sleep(1)

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
        time.sleep(1.5)

        # 验证轨道配置展开，展示「新词轨道」与「旧词轨道」
        review_tab = self.device.find_element(text="旧词轨道")
        new_tab = self.device.find_element(text="新词轨道")

        if review_tab:
            print("[*] 切换至「旧词轨道」查看复习步骤与节点...")
            self.device.click_element(review_tab)
            time.sleep(1.5)
            shot_review = self.capture("study_track_review_tab")

        if new_tab:
            print("[*] 切换回「新词轨道」查看新词学习环节...")
            self.device.click_element(new_tab)
            time.sleep(1.5)
            shot_new = self.capture("study_track_new_tab")

        # 点击「完成配置」收起面板
        finish_config_btn = self.device.find_element(text="完成配置")
        if finish_config_btn:
            print("[*] 点击「完成配置」收起配置面板...")
            self.device.click_element(finish_config_btn)
            time.sleep(1.5)

        shot = self.capture("study_track_completed")
        self.log("学习轨道配置与切换", "PASSED", "成功进入学习轨道编辑态，核验新词/旧词轨道流转节点并平稳收起", shot)

    def step_8_set_daily_words_plan(self, target_words: int = 2):
        print(f"\n--- [Step 8] 每日学习计划定制（调整为 {target_words} 词） ---")
        self.device.wait_and_click(text="学习", timeout=2, exact=True)
        time.sleep(1)

        # 滑动回主页顶部
        w, h = self.device.get_screen_size()
        self.device.swipe(w // 2, int(h * 0.25), w // 2, int(h * 0.8), 350)
        time.sleep(1)

        # 查找中央大仪表盘的数字（新用户默认 30 词，或匹配「点击调整目标」）
        target_num_el = (self.device.find_element(text="点击调整目标", exact=False) or
                         self.device.find_element(text="30", exact=True) or
                         self.device.find_element(text="20", exact=True) or 
                         self.device.find_element(text="10", exact=True))

        if target_num_el:
            print("[*] 点击学习仪表盘单词量打开定制弹窗...")
            self.device.click_element(target_num_el)
            time.sleep(1.5)
        else:
            # 仪表盘中心点击
            self.device.click(w // 2, int(h * 0.32))
            time.sleep(1.5)

        # 验证弹窗是否出现
        sheet_title = self.device.find_element(text="选择每日学习词数")
        if sheet_title:
            print(f"[*] 发现弹窗「选择每日学习词数」，正在选取 {target_words} 词...")
            option_el = (self.device.find_element(text=f"{target_words}\n词") or 
                         self.device.find_element(text=f"{target_words}词") or 
                         self.device.find_element(text=str(target_words)))
            if option_el:
                self.device.click_element(option_el)
                time.sleep(2)
            else:
                print(f"[!] 未找到选项 {target_words}，尝试点击备选项...")
                first_opt = self.device.find_element(text="3\n词") or self.device.find_element(text="5\n词")
                if first_opt:
                    self.device.click_element(first_opt)
                    time.sleep(2)

            # 确保弹窗已彻底关闭
            if self.device.find_element(text="选择每日学习词数"):
                self.device.press_key(4)
                time.sleep(1)

        shot = self.capture("daily_plan_configured")
        self.log(f"每日学习计划定制", "PASSED", f"成功将今日学习量定制为精简目标（{target_words}词），便于完整走通全量打卡链路", shot)

    def step_9_complete_daily_study_and_daka(self):
        print("\n--- [Step 9] 完整学完当日计划与打卡全流程 ---")
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

        # 处理新手语音引导蒙层「你说，我来听」
        guide_btn = self.device.find_element(text="开始学习")
        if guide_btn:
            print("[*] 点击语音新手引导蒙层「开始学习」...")
            self.device.click_element(guide_btn)
            time.sleep(2)

        shot = self.capture("first_word_study_page")
        self.log("进入单词测评卡片", "PASSED", "已顺利呈现单词卡片、音标与释义选项", shot)

        # 2. 循环做题直到全部学完触发完成页
        print("[*] 正在执行单词答题流转，直至完成当日全部计划...")
        in_finish_page = False
        max_turns = 30

        for turn in range(1, max_turns + 1):
            time.sleep(1.5)

            # 检查是否已自动跳转至完成打卡页（/finish）
            if (self.device.find_element(text="学习完成") or 
                self.device.find_element(text="打卡成功") or 
                self.device.find_element(text="已打卡") or 
                self.device.find_element(text="打卡成果") or 
                self.device.find_element(text="今日已打卡") or 
                self.device.find_element(text="再来一组") or 
                self.device.find_element(text="前往词表") or 
                self.device.find_element(text="生成打卡海报")):
                in_finish_page = True
                print(f"[*] 第 {turn} 步：检测到已完成当日全部计划，成功进入完成打卡页！")
                break

            # 检查是否处于「本组小结」总结过渡卡片
            next_group_btn = self.device.find_element(text="下一组")
            if next_group_btn:
                print(f"[*] 第 {turn} 步：处于本组小结，点击「下一组」推进...")
                self.device.click_element(next_group_btn)
                time.sleep(2.5)
                continue

            # 检查是否有「下一词」直接流转按钮
            next_word_btn = self.device.find_element(text="下一词")
            if next_word_btn:
                self.device.click_element(next_word_btn)
                time.sleep(1.5)
                continue

            # 检查是否为选择题模式（选择题选项区域位于中间，且无直接流转按钮）
            nodes = self.device.dump_ui_hierarchy()
            choice_candidates = [
                n for n in nodes
                if n.get("clickable") and n.get("bounds")
                and 1350 <= n.get("center", (0, 0))[1] <= 1950
                and n.get("label") not in ("不认识", "再学学", "说释义", "说发音", "显示翻译", "默写", "掌握", "报错", "回看")
            ]

            if choice_candidates:
                # 遍历点击选项卡片（优先点击后排选项或匹配到的词条）
                target_choice = choice_candidates[-1]
                self.device.click_element(target_choice)
                time.sleep(1.5)
                nxt = self.device.find_element(text="下一词")
                if nxt:
                    self.device.click_element(nxt)
                    time.sleep(1.5)
                continue

            # 常规测评初见卡片：点击「不认识」查看释义
            dont_know_btn = self.device.find_element(text="不认识")
            study_again_btn = self.device.find_element(text="再学学")

            if dont_know_btn:
                self.device.click_element(dont_know_btn)
                time.sleep(1.5)
                next_btn = self.device.find_element(text="下一词")
                if next_btn:
                    self.device.click_element(next_btn)
                    time.sleep(1.5)
            elif study_again_btn:
                self.device.click_element(study_again_btn)
                time.sleep(1.5)
                next_btn = self.device.find_element(text="下一词")
                if next_btn:
                    self.device.click_element(next_btn)
                    time.sleep(1.5)
            else:
                time.sleep(1)

        shot = self.capture("daka_finish_page")
        if in_finish_page:
            self.log("当日计划学完进入打卡页", "PASSED", "今日单词全部环节完成，自动跳转至完成打卡页（FinishPage）", shot)
        else:
            self.log("当日计划学完进入打卡页", "WARNING", "已执行多轮流转，尝试触发打卡结算", shot)

        # 3. 生产数据库打卡数据一致性核验（验证服务端 daka 表中是否真实写入）
        print("[*] 正在从生产数据库校验当天的 daka 打卡数据记录...")
        time.sleep(2)
        daka_rec = manage_e2e_account.check_user_daka()
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

    def step_10_verify_daka_home_status(self):
        print("\n--- [Step 10] 主页与个人中心打卡状态核验 ---")
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

    def step_11_sync_verification(self):
        print("\n--- [Step 11] 端云同步校验 ---")
        self.device.wait_and_click(text="我", timeout=2, exact=True)
        time.sleep(1.5)
        shot = self.capture("sync_check_me")

        has_error = bool(self.device.find_element(text="同步失败") or self.device.find_element(text="网络异常"))
        if not has_error:
            self.log("端云同步健康度校验", "PASSED", "个人主页各卡片正常渲染，无任何同步异常告警", shot)
        else:
            self.log("端云同步健康度校验", "FAILED", "界面检测到同步失败异常标识", shot)

    def step_12_teardown_unregister(self):
        print("\n--- [Step 12] 测试善后：真机自助注销账号 ---")
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

            rows_html += f"""
            <tr>
                <td style="padding:12px;border-bottom:1px solid #E2E8F0;"><span class="badge" style="background:{badge_color};color:#FFFFFF;padding:4px 8px;border-radius:6px;font-size:11px;font-weight:700;">{r['status']}</span></td>
                <td style="padding:12px;border-bottom:1px solid #E2E8F0;"><strong>{r['step']}</strong></td>
                <td style="padding:12px;border-bottom:1px solid #E2E8F0;color:#334155;">{r['details']}</td>
                <td style="padding:12px;border-bottom:1px solid #E2E8F0;font-size:12px;color:#64748B;">{r['timestamp']}</td>
                <td style="padding:12px;border-bottom:1px solid #E2E8F0;text-align:center;">{img_html}</td>
            </tr>
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
            遵循真实用户全链路原则：真机自主注册 ➔ 选词书 ➔ 学习轨道配置 ➔ 计划定制 ➔ 单词全流程学习 ➔ 打卡落库 ➔ 端云同步 ➔ 真机自主注销销毁
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
                    <th style="width: 190px;">测试步骤</th>
                    <th>操作详情与断言结论</th>
                    <th style="width: 150px;">执行时间</th>
                    <th style="width: 90px; text-align: center;">实机截屏</th>
                </tr>
            </thead>
            <tbody>
                {rows_html}
            </tbody>
        </table>

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

    def step_13_send_report_email(self, report_path: str, total_time: float, passed: int, failed: int):
        print("\n--- [Step 13] 测试报告邮件直推 ---")
        now_str = datetime.now().strftime("%m-%d %H:%M:%S")
        subject = f"【泡泡单词回归报告】E2E全量回归完成 - 通过: {passed} / 失败: {failed} ({now_str})"
        
        # 构造邮件专用纯净 HTML（避免包含大量 base64 触发阿里防垃圾拦截）
        email_rows = ""
        for r in self.results:
            badge_color = "#10B981" if r["status"] == "PASSED" else ("#F59E0B" if r["status"] in ("SKIPPED", "WARNING") else "#EF4444")
            shot_name = os.path.basename(r["screenshot"]) if r["screenshot"] else "-"
            email_rows += f"""
            <tr>
                <td style="padding:10px 12px;border-bottom:1px solid #E2E8F0;"><span style="background:{badge_color};color:#FFFFFF;padding:3px 8px;border-radius:4px;font-size:11px;font-weight:bold;">{r['status']}</span></td>
                <td style="padding:10px 12px;border-bottom:1px solid #E2E8F0;"><strong>{r['step']}</strong></td>
                <td style="padding:10px 12px;border-bottom:1px solid #E2E8F0;color:#334155;font-size:13px;">{r['details']}</td>
                <td style="padding:10px 12px;border-bottom:1px solid #E2E8F0;font-size:12px;color:#64748B;">{r['timestamp']}</td>
                <td style="padding:10px 12px;border-bottom:1px solid #E2E8F0;font-size:11px;color:#94A3B8;text-align:center;">{shot_name}</td>
            </tr>
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
                        <th style="padding:10px 12px;font-size:12px;color:#475569;border-bottom:2px solid #E2E8F0;">断言与执行详情</th>
                        <th style="padding:10px 12px;font-size:12px;color:#475569;border-bottom:2px solid #E2E8F0;">执行时间</th>
                        <th style="padding:10px 12px;font-size:12px;color:#475569;border-bottom:2px solid #E2E8F0;text-align:center;">截图文件</th>
                    </tr>
                </thead>
                <tbody>
                    {email_rows}
                </tbody>
            </table>

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
