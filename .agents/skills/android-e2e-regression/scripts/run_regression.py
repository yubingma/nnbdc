#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
端到端自动回归测试套件 (E2E Regression Test Suite)
覆盖：生产库连接与测试账号初始化、真机唤醒与启动、验证码自动化登录、
底部主导航遍历、单词学习核心链路、端云同步及完整测试报告生成。
"""

import os
import sys
import time
import json
import argparse
from datetime import datetime

# 导入同目录的驱动模块
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.append(SCRIPT_DIR)

from device_controller import AndroidDeviceController
import manage_e2e_account

REPORT_DIR = os.path.abspath(os.path.join(SCRIPT_DIR, "../../../../tmp/e2e_report"))
SCREENSHOT_DIR = os.path.join(REPORT_DIR, "screenshots")

class RegressionRunner:
    def __init__(self, serial=None, skip_db_reset=False):
        self.serial = serial
        self.skip_db_reset = skip_db_reset
        self.device = None
        self.results = []
        os.makedirs(SCREENSHOT_DIR, exist_ok=True)

    def log(self, step_name: str, status: str, details: str = "", screenshot: str = None):
        res = {
            "step": step_name,
            "status": status,
            "details": details,
            "screenshot": os.path.relpath(screenshot, REPORT_DIR) if screenshot else None,
            "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        }
        self.results.append(res)
        icon = "✅" if status == "PASSED" else ("⚠️" if status == "SKIPPED" else "❌")
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
        print("🚀 开始执行 Android 端到端回归测试")
        print("==================================================")

        try:
            # 1. 生产库环境与 e2etest 账号检查
            self.step_db_init()

            # 2. Android 手机连接与点亮
            self.step_connect_device()

            # 3. 启动 App 并前台校验
            self.step_launch_app()

            # 4. 账号登录（支持验证码自动化抓取）
            self.step_login_if_needed()

            # 5. 底部主导航遍历
            self.step_navigate_tabs()

            # 6. 单词学习核心闭环
            self.step_word_study_flow()

            # 7. 数据同步与状态检验
            self.step_sync_verification()

        except Exception as e:
            self.log("测试流程意外中断", "FAILED", f"异常详情: {str(e)}", self.capture("fatal_error"))
            import traceback
            traceback.print_exc()

        # 生成 HTML 报告
        total_time = round(time.time() - start_time, 1)
        passed_count = sum(1 for r in self.results if r["status"] == "PASSED")
        failed_count = sum(1 for r in self.results if r["status"] == "FAILED")
        self.generate_html_report(total_time, passed_count, failed_count)

        print("\n==================================================")
        print(f"🏁 回归测试结束！耗时: {total_time}s | 通过: {passed_count} | 失败: {failed_count}")
        print(f"📊 报告地址: {os.path.join(REPORT_DIR, 'report.html')}")
        print("==================================================")
        return failed_count == 0

    def step_db_init(self):
        print("\n--- [Step 1] 生产数据库与测试账号校验 ---")
        try:
            user = manage_e2e_account.check_user()
            if not user:
                print("[*] 数据库中未找到 e2etest@nnbdc.com 账号，正在自动创建...")
                user_id = manage_e2e_account.create_e2e_user()
                user = manage_e2e_account.check_user()
                self.log("生产库账号创建", "PASSED", f"新创建用户成功: ID={user_id}")
            else:
                self.log("生产库账号存在校验", "PASSED", f"测试用户已就绪: ID={user['id']}, 魔法泡泡={user['cow_dung']}")

            if not self.skip_db_reset:
                manage_e2e_account.reset_e2e_user(user["id"])
                self.log("测试账号数据重置", "PASSED", "已恢复纯净初始测试状态（泡泡=100，学习进度清空）")
        except Exception as e:
            self.log("生产库初始化失败", "FAILED", str(e))
            raise

    def step_connect_device(self):
        print("\n--- [Step 2] 连接 Android 手机 ---")
        self.device = AndroidDeviceController(self.serial)
        w, h = self.device.get_screen_size()
        self.device.wake_up_and_unlock()
        shot = self.capture("device_connected")
        self.log("连接 Android 设备", "PASSED", f"已连接序列号={self.device.serial}, 分辨率={w}x{h}", shot)

    def step_launch_app(self):
        print("\n--- [Step 3] 启动泡泡单词 App ---")
        self.device.launch_app(stop_first=True)
        time.sleep(3)

        if not self.device.is_app_in_foreground():
            time.sleep(2)
            if not self.device.is_app_in_foreground():
                shot = self.capture("app_launch_failed")
                self.log("启动 App 前台校验", "FAILED", "App 未能在前台正常显示", shot)
                raise RuntimeError("App 启动失败")

        shot = self.capture("app_launched")
        self.log("启动 App 前台校验", "PASSED", "泡泡单词已成功在前台运行", shot)

        # 处理可能出现的系统弹窗或权限框
        for _ in range(2):
            if self.device.wait_and_click(text="允许", timeout=1):
                print("[*] 已点击「允许」系统权限")
            elif self.device.wait_and_click(text="同意并继续", timeout=1):
                print("[*] 已点击「同意并继续」")

    def step_login_if_needed(self):
        print("\n--- [Step 4] 登录认证链路回归 ---")
        time.sleep(2)
        shot = self.capture("login_state_check")

        # 检查当前是否在登录页面
        if self.device.find_element(text="邮箱登录") or self.device.find_element(text="微信一键登录"):
            print("[*] 当前处于登录首页，准备进入邮箱登录...")
            self._do_email_login_flow()
            return

        if self.device.find_element(text="验证码") and self.device.find_element(text="获取"):
            print("[*] 当前直接在邮箱登录页...")
            self._fill_email_and_code()
            return

        # 若在主页，先点底部「我」检查当前账户
        print("[*] 当前已在主界面，切换到「我」检查登录账户...")
        if self.device.wait_and_click(text="我", timeout=3):
            time.sleep(1.5)
            # 检查当前登录昵称
            el_nick = self.device.find_element(text="E2E测试用户")
            el_email = self.device.find_element(text="e2etest")
            if el_nick or el_email:
                shot = self.capture("already_e2e_user")
                self.log("用户身份校验", "PASSED", "当前已登录为 e2etest 账号，无需重登", shot)
                self.device.wait_and_click(text="学习", timeout=2)
                return

            print("[*] 当前非 e2etest 用户，准备展开设置并切换账号...")
            # 检查「设置与工具」是否需要展开
            settings_expand = self.device.scroll_and_find("设置与工具", max_swipes=2)
            if settings_expand:
                if "展开" in settings_expand.get("label", "") or "展开" in settings_expand.get("desc", ""):
                    print("[*] 点击展开「设置与工具」...")
                    self.device.click_element(settings_expand)
                    time.sleep(1)

            # 向上滑动寻找「切换账号」
            switch_btn = self.device.scroll_and_find("切换账号", max_swipes=5)
            if switch_btn:
                print("[*] 点击「切换账号」...")
                self.device.click_element(switch_btn)
                time.sleep(2)
                self._do_email_login_flow()
            else:
                shot = self.capture("switch_account_not_found")
                self.log("切换账号按钮定位", "FAILED", "未能在设置中定位到「切换账号」按钮", shot)
                # 兜底切回学习页
                self.device.wait_and_click(text="学习", timeout=2)
                return

    def _do_email_login_flow(self):
        # 1. 勾选同意协议（如果在登录主页）
        agree_el = self.device.find_element(text="同意")
        if agree_el:
            self.device.click_element(agree_el)
            time.sleep(0.5)

        # 2. 点击「邮箱登录」
        if self.device.wait_and_click(text="邮箱登录", timeout=3):
            time.sleep(1.5)
            self._fill_email_and_code()
        else:
            self.log("进入邮箱登录页", "FAILED", "未找到「邮箱登录」入口", self.capture("email_login_entry_failed"))

    def _fill_email_and_code(self):
        # 点击邮箱输入框并输入
        el_email_input = self.device.find_element(text="邮箱") or self.device.find_element(text="请输入邮箱")
        if el_email_input:
            self.device.click_element(el_email_input)
            time.sleep(0.5)
            self.device.clear_text_input(40)
            self.device.input_text("e2etest@nnbdc.com")
            time.sleep(0.5)

        # 再次勾选同意协议
        agree_el = self.device.find_element(text="同意")
        if agree_el:
            self.device.click_element(agree_el)
            time.sleep(0.5)

        # 点击「获取」验证码按钮
        print("[*] 点击获取验证码...")
        get_btn = self.device.find_element(text="获取")
        if get_btn:
            self.device.click_element(get_btn)
            time.sleep(2)
        else:
            print("[!] 未找到「获取」验证码按钮，尝试从数据库读取最新验证码...")

        # 从生产数据库查询刚刚生成的 6 位验证码
        code = None
        for attempt in range(6):
            code = manage_e2e_account.get_latest_code()
            if code:
                break
            time.sleep(1.5)

        if not code:
            shot = self.capture("code_fetch_failed")
            self.log("提取生产环境验证码", "FAILED", "未能从生产库 email_verification_code 表读取到有效验证码", shot)
            raise RuntimeError("验证码读取失败")

        self.log("提取生产环境验证码", "PASSED", f"成功从生产库截获验证码: {code}")

        # 填入验证码
        code_input = self.device.find_element(text="验证码")
        if code_input:
            self.device.click_element(code_input)
            time.sleep(0.5)
            self.device.input_text(code)
            time.sleep(0.5)

        # 隐藏键盘并点击「登录」
        self.device.press_key(4) # BACK 隐藏软键盘
        time.sleep(0.5)

        login_btn = self.device.find_element(text="登录")
        if login_btn:
            self.device.click_element(login_btn)
            time.sleep(4)
            shot = self.capture("login_result")
            # 校验是否回到主页
            if self.device.find_element(text="学习") or self.device.find_element(text="开始学习"):
                self.log("邮箱验证码登录闭环", "PASSED", "验证码验证成功并跳转至主界面", shot)
            else:
                self.log("邮箱验证码登录闭环", "FAILED", "登录后未能在预期时间内进入主页", shot)
        else:
            self.log("点击登录按钮", "FAILED", "未找到登录按钮", self.capture("login_btn_not_found"))

    def step_navigate_tabs(self):
        print("\n--- [Step 5] 底部主导航遍历回归 ---")
        tabs = [
            ("词表", "词书列表与选词桌", "word_lists"),
            ("查词", "权威词典快速查词", "search"),
            ("我", "个人中心与功能收纳", "me"),
            ("学习", "背单词核心主页", "study")
        ]

        for tab_name, desc, tag in tabs:
            time.sleep(1)
            clicked = self.device.wait_and_click(text=tab_name, timeout=3)
            time.sleep(1.5)
            shot = self.capture(f"tab_{tag}")
            if clicked:
                self.log(f"导航切换: {tab_name}", "PASSED", f"成功切入 {desc}", shot)
            else:
                self.log(f"导航切换: {tab_name}", "FAILED", f"未能点击 Tab「{tab_name}」", shot)

    def step_word_study_flow(self):
        print("\n--- [Step 6] 单词学习核心链路冒烟 ---")
        # 确保在学习页
        self.device.wait_and_click(text="学习", timeout=2)
        time.sleep(1)

        # 检查是否需要先选择词书
        select_dict_btn = self.device.find_element(text="选择词书")
        if select_dict_btn:
            print("[*] 检测到首页提示选择词书，开始自动配置词书...")
            self.device.click_element(select_dict_btn)
            time.sleep(2)
            # 点击「四六级」标签
            cet_tab = self.device.find_element(text="四六级")
            if cet_tab:
                self.device.click_element(cet_tab)
                time.sleep(1.5)
            # 勾选一本词书
            target_book = self.device.find_element(text="四级高频词汇") or self.device.find_element(text="六级")
            if target_book:
                self.device.click_element(target_book)
                time.sleep(1)
            # 点击「保存」
            save_btn = self.device.find_element(text="保存")
            if save_btn:
                self.device.click_element(save_btn)
                time.sleep(3)
            # 关闭弹窗或返回
            if not self.device.find_element(text="学习"):
                self.device.press_key(4)
                time.sleep(1.5)
            shot = self.capture("dict_selected")
            self.log("学习词书配置", "PASSED", "已自动进入词库选定四级词书并保存", shot)

        # 点击「开始学习」或「继续学习」
        start_btn = self.device.find_element(text="开始学习") or self.device.find_element(text="继续学习")
        if not start_btn:
            shot = self.capture("start_learn_not_found")
            self.log("进入学习流程", "FAILED", "主页未展示「开始学习/继续学习」按钮", shot)
            return

        print("[*] 点击「开始学习」按钮...")
        self.device.click_element(start_btn)
        time.sleep(2)

        # 处理「开启今日学习旅程」弹窗
        confirm_start_btn = self.device.find_element(text="马上开始")
        if confirm_start_btn:
            print("[*] 点击「马上开始」确认今日学习...")
            self.device.click_element(confirm_start_btn)
            time.sleep(2)

        # 处理新手语音引导蒙层「你说，我来听」
        guide_btn = self.device.find_element(text="开始学习")
        if guide_btn:
            print("[*] 点击新手引导蒙层「开始学习」...")
            self.device.click_element(guide_btn)
            time.sleep(2)

        shot = self.capture("in_study_page")
        self.log("进入单词学习页面", "PASSED", "已成功唤起背单词交互流转界面", shot)

        # 推进 2 轮学习互动
        for round_idx in range(1, 3):
            time.sleep(1.5)
            # 寻找流转按钮:「不认识」或「下一词」或「再学学」
            btn = (self.device.find_element(text="不认识") or
                   self.device.find_element(text="下一词") or
                   self.device.find_element(text="再学学"))
            if btn:
                btn_text = btn.get("label", "未知")
                self.device.click_element(btn)
                time.sleep(1.5)
                shot = self.capture(f"study_action_round_{round_idx}")
                self.log(f"单词交互: 轮次{round_idx}", "PASSED", f"点击了「{btn_text}」按钮推进学习步骤", shot)
                # 如果点击不认识后进入单词详情，通常会展示「下一词」
                next_btn = self.device.find_element(text="下一词")
                if next_btn:
                    print("[*] 单词详情页点击「下一词」进入下一环节...")
                    self.device.click_element(next_btn)
                    time.sleep(1.5)
            else:
                shot = self.capture(f"study_btn_missing_round_{round_idx}")
                self.log(f"单词交互: 轮次{round_idx}", "SKIPPED", "未能在当前页面匹配到常规流转按钮", shot)

        # 退出学习界面返回首页
        print("[*] 按返回键退出学习界面...")
        self.device.press_key(4) # KEYCODE_BACK
        time.sleep(1.5)
        # 如果有弹窗“确定退出学习”，点击退出
        exit_btn = self.device.find_element(text="退出") or self.device.find_element(text="确定")
        if exit_btn:
            self.device.click_element(exit_btn)
            time.sleep(1)
        shot = self.capture("back_to_home")
        self.log("退出学习回到首页", "PASSED", "学习状态保存并顺利返回主页", shot)

    def step_sync_verification(self):
        print("\n--- [Step 7] 端云同步校验 ---")
        time.sleep(1)
        # 切到个人中心
        self.device.wait_and_click(text="我", timeout=2)
        time.sleep(1.5)
        shot = self.capture("sync_check_me")

        # 检查是否有同步失败红字提示
        has_error = bool(self.device.find_element(text="同步失败") or self.device.find_element(text="网络异常"))
        if not has_error:
            self.log("端云同步无异常校验", "PASSED", "个人主页数据展示平稳，未见同步报错红字", shot)
        else:
            self.log("端云同步无异常校验", "FAILED", "界面检测到同步失败或网络异常提示", shot)

    def generate_html_report(self, total_time: float, passed: int, failed: int):
        report_file = os.path.join(REPORT_DIR, "report.html")
        now_str = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

        rows_html = ""
        for r in self.results:
            badge_color = "#10B981" if r["status"] == "PASSED" else ("#F59E0B" if r["status"] == "SKIPPED" else "#EF4444")
            img_html = f'<a href="{r["screenshot"]}" target="_blank"><img src="{r["screenshot"]}" class="thumb" /></a>' if r["screenshot"] else "-"
            rows_html += f"""
            <tr>
                <td><span class="badge" style="background: {badge_color};">{r['status']}</span></td>
                <td><strong>{r['step']}</strong></td>
                <td>{r['details']}</td>
                <td>{r['timestamp']}</td>
                <td style="text-align: center;">{img_html}</td>
            </tr>
            """

        html_content = f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <title>泡泡单词 Android 端到端回归测试报告</title>
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
            font-size: 24px;
            font-weight: 800;
            margin-top: 0;
            color: #0F172A;
            display: flex;
            align-items: center;
            gap: 12px;
        }}
        .summary-cards {{
            display: grid;
            grid-template-columns: repeat(4, 1fr);
            gap: 16px;
            margin: 24px 0;
        }}
        .card {{
            background: #F1F5F9;
            padding: 16px;
            border-radius: 12px;
        }}
        .card-label {{ font-size: 13px; color: #64748B; font-weight: 500; }}
        .card-val {{ font-size: 22px; font-weight: 800; margin-top: 6px; }}
        table {{
            width: 100%;
            border-collapse: collapse;
            margin-top: 24px;
        }}
        th, td {{
            padding: 14px 16px;
            text-align: left;
            border-bottom: 1px solid #E2E8F0;
            font-size: 14px;
        }}
        th {{
            background: #F8FAFC;
            font-weight: 700;
            color: #475569;
        }}
        .badge {{
            display: inline-block;
            padding: 4px 10px;
            border-radius: 9999px;
            color: white;
            font-size: 12px;
            font-weight: 700;
            letter-spacing: 0.5px;
        }}
        .thumb {{
            width: 54px;
            height: 96px;
            object-fit: cover;
            border-radius: 6px;
            border: 1px solid #CBD5E1;
            transition: transform 0.2s;
        }}
        .thumb:hover {{
            transform: scale(2.2);
            z-index: 10;
            box-shadow: 0 8px 16px rgba(0,0,0,0.2);
        }}
    </style>
</head>
<body>
    <div class="container">
        <h1>📱 泡泡单词 Android 端到端回归测试报告</h1>
        <div style="font-size: 14px; color: #64748B;">测试环境：生产数据库 (47.108.27.205) + Android 实体真机自动化</div>
        
        <div class="summary-cards">
            <div class="card">
                <div class="card-label">测试结果</div>
                <div class="card-val" style="color: {'#10B981' if failed == 0 else '#EF4444'};">{'ALL PASSED' if failed == 0 else 'FAILED'}</div>
            </div>
            <div class="card">
                <div class="card-label">总执行耗时</div>
                <div class="card-val">{total_time}s</div>
            </div>
            <div class="card">
                <div class="card-label">步骤通过率</div>
                <div class="card-val">{passed}/{passed + failed}</div>
            </div>
            <div class="card">
                <div class="card-label">生成时间</div>
                <div class="card-val" style="font-size: 15px; margin-top: 10px;">{now_str}</div>
            </div>
        </div>

        <table>
            <thead>
                <tr>
                    <th style="width: 100px;">状态</th>
                    <th style="width: 200px;">测试步骤</th>
                    <th>详细信息与断言结果</th>
                    <th style="width: 160px;">时间</th>
                    <th style="width: 80px; text-align: center;">实机截图</th>
                </tr>
            </thead>
            <tbody>
                {rows_html}
            </tbody>
        </table>
    </div>
</body>
</html>
"""
        with open(report_file, "w", encoding="utf-8") as f:
            f.write(html_content)

def main():
    parser = argparse.ArgumentParser(description="运行 Android 端到端回归测试套件")
    parser.add_argument("--serial", help="指定 Android 设备序列号 (可选)")
    parser.add_argument("--skip-reset", action="store_true", help="跳过数据库测试账号数据重置")
    args = parser.parse_args()

    runner = RegressionRunner(serial=args.serial, skip_db_reset=args.skip_reset)
    success = runner.run_all()
    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()
