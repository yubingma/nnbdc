#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Android 设备控制驱动模块
基于 ADB 和 uiautomator 实现对真实 Android 手机的连接、控制、布局抓取与智能点击。
深度适配 Flutter Semantics（自动匹配 text 与 content-desc）。
"""

import os
import re
import sys
import time
import subprocess
import xml.etree.ElementTree as ET
from typing import List, Dict, Optional, Tuple

APP_PACKAGE = "com.nn.nnbdc.android"
MAIN_ACTIVITY = "com.nn.nnbdc.android.MainActivity"

class AndroidDeviceController:
    def __init__(self, serial: Optional[str] = None):
        self.serial = serial
        self._ensure_device()

    def _run_adb(self, cmd_args: List[str], check: bool = True, timeout: int = 30) -> subprocess.CompletedProcess:
        """执行 ADB 命令"""
        full_cmd = ["adb"]
        if self.serial:
            full_cmd.extend(["-s", self.serial])
        full_cmd.extend(cmd_args)
        
        try:
            res = subprocess.run(
                full_cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=timeout
            )
            if check and res.returncode != 0:
                raise RuntimeError(f"ADB 命令执行失败 ({' '.join(full_cmd)}): {res.stderr.strip() or res.stdout.strip()}")
            return res
        except subprocess.TimeoutExpired:
            raise TimeoutError(f"ADB 命令超时: {' '.join(full_cmd)}")

    def _ensure_device(self):
        """确保设备已连接"""
        res = self._run_adb(["devices"])
        lines = [line.strip() for line in res.stdout.splitlines() if line.strip()]
        devices = []
        for line in lines[1:]: # 跳过 "List of devices attached"
            parts = line.split()
            if len(parts) >= 2 and parts[1] == "device":
                devices.append(parts[0])
        
        if not devices:
            raise ConnectionError(
                "❌ 未检测到已连接的 Android 设备！\n"
                "请检查：\n"
                "1. 手机是否已通过 USB 连接至 Mac，并开启了「开发者选项 -> USB 调试」；\n"
                "2. 手机是否弹出「允许 USB 调试」授权框并勾选允许；\n"
                "3. 若使用无线调试，请先执行 `adb connect <IP>:<PORT>`。"
            )
        
        if self.serial:
            if self.serial not in devices:
                raise ConnectionError(f"❌ 指定的设备序列号 {self.serial} 未在线！当前在线设备: {devices}")
        else:
            self.serial = devices[0]
            print(f"[*] 选定当前在线设备: {self.serial}")

    def get_screen_size(self) -> Tuple[int, int]:
        """获取屏幕分辨率 (width, height)"""
        res = self._run_adb(["shell", "wm", "size"])
        match = re.search(r"Physical size:\s*(\d+)x(\d+)", res.stdout)
        if match:
            return int(match.group(1)), int(match.group(2))
        return 1080, 2280

    def wake_up_and_unlock(self):
        """唤醒屏幕并解锁（无密码锁屏可直接滑动，并强制锁定标准竖屏）"""
        # 强制锁定系统为竖屏方向（关闭自动旋转），杜绝机身晃动或倾斜导致横屏UI变形
        self._run_adb(["shell", "settings", "put", "system", "accelerometer_rotation", "0"])
        self._run_adb(["shell", "settings", "put", "system", "user_rotation", "0"])

        res = self._run_adb(["shell", "dumpsys", "power"])
        if "mHoldingDisplaySuspendBlocker=false" in res.stdout or "Display Power: state=OFF" in res.stdout:
            self._run_adb(["shell", "input", "keyevent", "26"])
            time.sleep(0.5)
        
        w, h = self.get_screen_size()
        self.swipe(w // 2, int(h * 0.8), w // 2, int(h * 0.2), 300)
        time.sleep(0.5)

    def grant_runtime_permissions(self):
        """通过 ADB 自动为 App 预先授予所有必要运行时权限（录音/麦克风、通知等），彻底杜绝系统弹窗阻断自动化流程"""
        permissions = [
            "android.permission.RECORD_AUDIO",
            "android.permission.POST_NOTIFICATIONS",
            "android.permission.READ_PHONE_STATE",
        ]
        for perm in permissions:
            try:
                self._run_adb(["shell", "pm", "grant", APP_PACKAGE, perm])
            except Exception:
                pass

    def dismiss_system_dialogs(self) -> bool:
        """主动检测并点击系统权限弹窗（如麦克风权限请求「仅在使用中允许」「使用应用时允许」「允许」等）"""
        target_texts = [
            "仅在使用中允许", "使用应用时允许", "仅本次允许", "允许",
            "While using the app", "Only this time", "Allow"
        ]
        nodes = self.dump_ui_hierarchy()
        for n in nodes:
            txt = (n.get("text") or n.get("label") or "").strip()
            if any(t in txt for t in target_texts) and n.get("clickable"):
                print(f"[*] 检测到系统权限弹窗按钮「{txt}」，正在自动授权点击...")
                self.click_element(n)
                time.sleep(1.0)
                return True
        return False

    def launch_app(self, stop_first: bool = False):
        """启动泡泡单词 App 并预先授权必要权限"""
        if stop_first:
            self.stop_app()
            time.sleep(1)
        
        # 预先授予录音麦克风等运行时权限
        self.grant_runtime_permissions()

        print(f"[*] 启动 App: {APP_PACKAGE}...")
        self._run_adb(["shell", "monkey", "-p", APP_PACKAGE, "-c", "android.intent.category.LAUNCHER", "1"])
        time.sleep(3)

        # 尝试消除任何系统启动弹窗
        self.dismiss_system_dialogs()

    def clear_app_data(self):
        """清除 App 本地应用数据与缓存，强制还原纯净初始安装状态"""
        print(f"[*] 清除 App 本地应用数据: {APP_PACKAGE}...")
        self._run_adb(["shell", "pm", "clear", APP_PACKAGE])
        time.sleep(1)
        self.grant_runtime_permissions()

    def stop_app(self):
        """停止 App"""
        self._run_adb(["shell", "am", "force-stop", APP_PACKAGE])

    def is_app_in_foreground(self) -> bool:
        """检查泡泡单词是否在前台"""
        res = self._run_adb(["shell", "dumpsys", "window"])
        return APP_PACKAGE in res.stdout

    def take_screenshot(self, save_path: str) -> str:
        """捕获屏幕截图并保存到本地"""
        os.makedirs(os.path.dirname(os.path.abspath(save_path)), exist_ok=True)
        cmd = ["adb"]
        if self.serial:
            cmd.extend(["-s", self.serial])
        cmd.extend(["exec-out", "screencap", "-p"])
        
        with open(save_path, "wb") as f:
            res = subprocess.run(cmd, stdout=f, stderr=subprocess.PIPE)
            if res.returncode != 0:
                raise RuntimeError(f"截图失败: {res.stderr}")
        return save_path

    def dump_ui_hierarchy(self) -> List[Dict]:
        """抓取当前屏幕的 UI 节点树，统一适配 Flutter Semantics（支持多轮重试防动画瞬时阻塞）"""
        success = False
        for attempt in range(4):
            dump_cmd = self._run_adb(["shell", "uiautomator", "dump", "/sdcard/e2e_dump.xml"], check=False)
            if dump_cmd.returncode == 0:
                success = True
                break
            time.sleep(0.8 + attempt * 0.4)

        if not success:
            return []

        cat_res = self._run_adb(["shell", "cat", "/sdcard/e2e_dump.xml"])
        xml_content = cat_res.stdout.strip()
        if not xml_content.startswith("<?xml") and not xml_content.startswith("<hierarchy"):
            return []

        elements = []
        try:
            root = ET.fromstring(xml_content)
            for node in root.iter("node"):
                text = node.attrib.get("text", "").strip()
                desc = node.attrib.get("content-desc", "").strip()
                bounds_str = node.attrib.get("bounds", "") # format: [x1,y1][x2,y2]
                res_id = node.attrib.get("resource-id", "")
                clickable = node.attrib.get("clickable", "false") == "true"

                bounds_match = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", bounds_str)
                if bounds_match:
                    x1, y1, x2, y2 = map(int, bounds_match.groups())
                    center = ((x1 + x2) // 2, (y1 + y2) // 2)
                else:
                    center = None

                # 提取统一可视标签（合并 text 与 desc）
                label = text if text else desc

                elements.append({
                    "label": label,
                    "text": text,
                    "desc": desc,
                    "resource_id": res_id,
                    "clickable": clickable,
                    "bounds": bounds_str,
                    "center": center,
                    "class": node.attrib.get("class", "")
                })
        except Exception as e:
            print(f"[!] 解析 UI 节点失败: {e}")

        return elements

    def find_element(self, text: Optional[str] = None, desc: Optional[str] = None, exact: bool = False, only_clickable: bool = False, nodes: Optional[List[Dict]] = None) -> Optional[Dict]:
        """查找满足条件的元素（支持传入 nodes 进行零延迟纯内存检索，避免反复 dump_ui_hierarchy）"""
        target = text or desc
        if not target:
            return None

        elements = nodes if nodes is not None else self.dump_ui_hierarchy()
        target_clean = target.strip()

        exact_clickable = []
        exact_any = []
        contains_clickable = []
        contains_any = []

        for el in elements:
            if only_clickable and not el.get("clickable"):
                continue

            candidates = [el.get("label", ""), el.get("text", ""), el.get("desc", "")]
            is_exact = False
            is_contains = False

            for cand in candidates:
                if not cand:
                    continue
                cand_clean = cand.replace("\n", " ").strip()
                if cand_clean == target_clean or cand.strip() == target_clean:
                    is_exact = True
                    break
                elif not exact and (target_clean in cand_clean or target in cand):
                    is_contains = True

            if is_exact:
                if el.get("clickable"):
                    exact_clickable.append(el)
                else:
                    exact_any.append(el)
            elif is_contains:
                if el.get("clickable"):
                    contains_clickable.append(el)
                else:
                    contains_any.append(el)

        if exact_clickable:
            return exact_clickable[0]
        if exact_any:
            return exact_any[0]
        if not exact:
            if contains_clickable:
                return contains_clickable[0]
            if contains_any:
                return contains_any[0]

        return None

    def click(self, x: int, y: int):
        """点击指定绝对坐标"""
        self._run_adb(["shell", "input", "tap", str(x), str(y)])

    def click_element(self, el: Dict):
        """点击元素中心"""
        center = el.get("center")
        if not center:
            raise ValueError(f"元素无有效中心坐标: {el}")
        self.click(center[0], center[1])

    def wait_and_click(self, text: str, timeout: int = 10, exact: bool = False) -> bool:
        """等待某元素出现并点击"""
        start = time.time()
        while time.time() - start < timeout:
            el = self.find_element(text=text, exact=exact)
            if el and el.get("center"):
                self.click_element(el)
                return True
            time.sleep(1)
        return False

    def scroll_and_find(self, text: str, max_swipes: int = 5, swipe_up: bool = True) -> Optional[Dict]:
        """在屏幕上滑动查找元素"""
        w, h = self.get_screen_size()
        for _ in range(max_swipes):
            el = self.find_element(text=text)
            if el and el.get("center"):
                return el
            # 滑动
            if swipe_up:
                self.swipe(w // 2, int(h * 0.75), w // 2, int(h * 0.35), 350)
            else:
                self.swipe(w // 2, int(h * 0.35), w // 2, int(h * 0.75), 350)
            time.sleep(1)
        # 最后再查一次
        return self.find_element(text=text)

    def input_text(self, text: str):
        """通过 ADB 输入文本"""
        escaped = text.replace(" ", "%s").replace("&", "\\&").replace("@", "\\@")
        self._run_adb(["shell", "input", "text", escaped])

    def clear_text_input(self, delete_count: int = 40):
        """双向彻底清空输入框文本（单次批处理命令，耗时由 35s 降至 1s）"""
        # 123=MOVE_END, 67=DEL, 122=MOVE_HOME, 112=FORWARD_DEL
        keys = ["123"] + ["67"] * delete_count + ["122"] + ["112"] * delete_count
        self._run_adb(["shell", "input", "keyevent"] + keys)

    def press_key(self, keycode: int):
        """发送按键事件 (4=BACK, 66=ENTER, 3=HOME)"""
        self._run_adb(["shell", "input", "keyevent", str(keycode)])

    def swipe(self, x1: int, y1: int, x2: int, y2: int, duration_ms: int = 300):
        """滑动操作"""
        self._run_adb(["shell", "input", "swipe", str(x1), str(y1), str(x2), str(y2), str(duration_ms)])

if __name__ == "__main__":
    controller = AndroidDeviceController()
    w, h = controller.get_screen_size()
    print(f"✅ 连接成功！分辨率: {w}x{h}")
