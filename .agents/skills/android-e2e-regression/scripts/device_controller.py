#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Android 设备控制驱动模块

只做三件事：抓当前界面节点树、按「稳定标识 / 文案」找节点、按节点坐标点它。

定位约定：
- 测试要点的控件，一律按 `Semantics(identifier: ...)` 写进无障碍树的 `resource-id` 找，
  文案改字、换分辨率都不影响；`resource-id` 找不到就是用例失败，绝不退回按文案猜。
- 只有两类东西允许按文案找：断言要读的展示内容（如「第 1 组 · 新词测评 1/10」），
  以及 App 内置的系统输入控件（android.widget.EditText）。
- 不写任何绝对坐标。
"""

import re
import subprocess
import time
import xml.etree.ElementTree as ET
from typing import Dict, List, Optional, Tuple

APP_PACKAGE = "com.nn.nnbdc.android"

_BOUNDS_RE = re.compile(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]")


class AndroidDeviceController:
    def __init__(self, serial: Optional[str] = None):
        self.serial = serial
        self._screen_size: Optional[Tuple[int, int]] = None
        self.dump_calls = 0
        self.dump_failures = 0
        self._ensure_device()

    # ---------- ADB 基础 ----------

    def _run_adb(self, cmd_args: List[str], check: bool = True, timeout: int = 30) -> subprocess.CompletedProcess:
        full_cmd = ["adb"]
        if self.serial:
            full_cmd.extend(["-s", self.serial])
        full_cmd.extend(cmd_args)
        try:
            res = subprocess.run(
                full_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, timeout=timeout,
            )
            stderr = (res.stderr or "").strip()
            # 设备掉线不是「重试一下就好」的临时错误：继续跑只会拿空界面骗自己
            if res.returncode != 0 and any(
                    k in stderr for k in ("device not found", "device offline", "no devices")):
                raise ConnectionError(f"真机已断开连接: {stderr}")
            if check and res.returncode != 0:
                raise RuntimeError(
                    f"ADB 命令执行失败 ({' '.join(full_cmd)}): "
                    f"{stderr or res.stdout.strip()}"
                )
            return res
        except subprocess.TimeoutExpired:
            raise TimeoutError(f"ADB 命令超时: {' '.join(full_cmd)}")

    def _ensure_device(self):
        res = self._run_adb(["devices"])
        devices = []
        for line in res.stdout.splitlines()[1:]:
            parts = line.split()
            if len(parts) >= 2 and parts[1] == "device":
                devices.append(parts[0])
        if not devices:
            raise ConnectionError(
                "❌ 未检测到已连接的 Android 设备！请检查 USB 调试授权，"
                "或先执行 `adb connect <IP>:<PORT>`。"
            )
        if self.serial:
            if self.serial not in devices:
                raise ConnectionError(
                    f"❌ 指定的设备序列号 {self.serial} 未在线！当前在线设备: {devices}"
                )
        else:
            self.serial = devices[0]
            print(f"[*] 选定当前在线设备: {self.serial}")

    def get_screen_size(self) -> Tuple[int, int]:
        """屏幕分辨率，进程内只查一次（分辨率不会在一次回归中途改变）。"""
        if self._screen_size is None:
            res = self._run_adb(["shell", "wm", "size"])
            match = re.search(r"Physical size:\s*(\d+)x(\d+)", res.stdout)
            self._screen_size = (int(match.group(1)), int(match.group(2))) if match else (1080, 2280)
        return self._screen_size

    # ---------- 设备与环境 ----------

    def wake_up_and_unlock(self):
        # 熄屏会让 Flutter 视图变成 0×0，uiautomator 抓到空树 —— 长跑必须常亮
        self._run_adb(["shell", "svc", "power", "stayon", "true"], check=False)
        self._run_adb(["shell", "settings", "put", "system", "accelerometer_rotation", "0"])
        self._run_adb(["shell", "settings", "put", "system", "user_rotation", "0"])
        res = self._run_adb(["shell", "dumpsys", "power"])
        if "mHoldingDisplaySuspendBlocker=false" in res.stdout or "Display Power: state=OFF" in res.stdout:
            self._run_adb(["shell", "input", "keyevent", "26"])
            time.sleep(0.3)
        w, h = self.get_screen_size()
        self.swipe(w // 2, int(h * 0.8), w // 2, int(h * 0.2), 300)

    def grant_runtime_permissions(self):
        for perm in ("android.permission.RECORD_AUDIO", "android.permission.POST_NOTIFICATIONS"):
            self._run_adb(["shell", "pm", "grant", APP_PACKAGE, perm], check=False)

    def set_permission(self, permission: str, granted: bool):
        action = "grant" if granted else "revoke"
        self._run_adb(["shell", "pm", action, APP_PACKAGE, permission])

    def set_network(self, enabled: bool):
        """开关 Wi-Fi 与移动数据，用于断网反向用例。"""
        state = "enable" if enabled else "disable"
        self._run_adb(["shell", "svc", "wifi", state], check=False)
        self._run_adb(["shell", "svc", "data", state], check=False)
        time.sleep(1.0)

    def launch_app(self, stop_first: bool = False, grant: bool = True):
        if stop_first:
            self.stop_app()
        if grant:
            self.grant_runtime_permissions()
        self._run_adb([
            "shell", "monkey", "-p", APP_PACKAGE,
            "-c", "android.intent.category.LAUNCHER", "1",
        ], check=False)
        self.wait_foreground(timeout=15)

    def stop_app(self):
        self._run_adb(["shell", "am", "force-stop", APP_PACKAGE])

    def is_app_in_foreground(self) -> bool:
        res = self._run_adb(["shell", "dumpsys", "window"], check=False)
        for line in res.stdout.splitlines():
            if "mCurrentFocus" in line:
                return APP_PACKAGE in line
        return False

    def wait_foreground(self, timeout: float = 10) -> bool:
        deadline = time.time() + timeout
        while time.time() < deadline:
            if self.is_app_in_foreground():
                return True
            time.sleep(0.25)
        return False

    def ensure_app_foreground(self):
        if not self.is_app_in_foreground():
            print("[*] App 不在前台，重新拉起...")
            self.launch_app()

    # ---------- 界面节点树 ----------

    def dump(self) -> List[Dict]:
        """一次性抓取当前界面节点树。

        用 `exec-out uiautomator dump /dev/tty` 把 XML 直接读回 stdout，
        比「dump 到文件再 cat」少一次 ADB 往返。刚启动时 uiautomator 偶发
        `null root node`，这里重试几次直到拿到 `<hierarchy`。
        """
        for attempt in range(4):
            self.dump_calls += 1
            res = self._run_adb(
                ["exec-out", "uiautomator", "dump", "/dev/tty"], check=False, timeout=40
            )
            out = res.stdout or ""
            start, end = out.find("<?xml"), out.rfind("</hierarchy>")
            if start >= 0 and end > start:
                return self._parse(out[start:end + len("</hierarchy>")])
            self.dump_failures += 1
            time.sleep(0.25 + attempt * 0.2)
        return []

    @staticmethod
    def _parse(xml_text: str) -> List[Dict]:
        nodes: List[Dict] = []
        root = ET.fromstring(xml_text)
        for node in root.iter("node"):
            bounds = node.attrib.get("bounds", "")
            match = _BOUNDS_RE.match(bounds)
            center = None
            if match:
                x1, y1, x2, y2 = map(int, match.groups())
                center = ((x1 + x2) // 2, (y1 + y2) // 2)
            text = node.attrib.get("text", "").strip()
            desc = node.attrib.get("content-desc", "").strip()
            nodes.append({
                "text": text,
                "desc": desc,
                "label": text or desc,
                "rid": node.attrib.get("resource-id", ""),
                "package": node.attrib.get("package", ""),
                "clickable": node.attrib.get("clickable", "false") == "true",
                "enabled": node.attrib.get("enabled", "true") == "true",
                "bounds": bounds,
                "center": center,
                "class": node.attrib.get("class", ""),
            })
        return nodes

    # ---------- 查找 ----------

    def find_by_id(self, identifier: str, nodes: Optional[List[Dict]] = None) -> Optional[Dict]:
        for el in (nodes if nodes is not None else self.dump()):
            if el["rid"] == identifier:
                return el
        return None

    def find_all_by_id_prefix(self, prefix: str, nodes: Optional[List[Dict]] = None) -> List[Dict]:
        return [el for el in (nodes if nodes is not None else self.dump())
                if el["rid"].startswith(prefix)]

    def find_by_text(self, text: str,
                     nodes: Optional[List[Dict]] = None,
                     exact: bool = False) -> Optional[Dict]:
        """只在读「展示内容」时用：优先整串相等，其次包含。"""
        target = text.replace("\n", " ")
        best = None
        for el in (nodes if nodes is not None else self.dump()):
            for cand in (el["text"], el["desc"]):
                if not cand:
                    continue
                cand_clean = cand.replace("\n", " ")
                if cand_clean == target:
                    return el
                if not exact and target in cand_clean and best is None:
                    best = el
        return best

    @staticmethod
    def texts_within(node: Dict, nodes: List[Dict]) -> List[str]:
        """取完全落在 node 边界内的所有文案，用于读一个选项/卡片里到底写了什么。"""
        match = _BOUNDS_RE.match(node.get("bounds") or "")
        if not match:
            return []
        x1, y1, x2, y2 = map(int, match.groups())
        texts: List[str] = []
        for el in nodes:
            m = _BOUNDS_RE.match(el.get("bounds") or "")
            if not m:
                continue
            ex1, ey1, ex2, ey2 = map(int, m.groups())
            if ex1 >= x1 and ey1 >= y1 and ex2 <= x2 and ey2 <= y2:
                value = el["label"]
                if value:
                    texts.append(value)
        return texts

    def wait(self, identifier: Optional[str] = None,
             text: Optional[str] = None,
             timeout: float = 4.0,
             interval: float = 0.2,
             enabled_only: bool = False) -> Optional[Dict]:
        """等某个标识/文案出现。命中即返回节点，超时返回 None。

        这是替换 `time.sleep(2)` 的主要手段：界面稳定就立刻往下走。
        """
        deadline = time.time() + timeout
        while True:
            nodes = self.dump()
            el = self.find_by_id(identifier, nodes) if identifier else self.find_by_text(text, nodes)
            if el and (not enabled_only or el["enabled"]):
                return el
            if time.time() >= deadline:
                return None
            time.sleep(interval)

    def wait_by_text_any(self, texts, timeout: float = 3.0,
                         interval: float = 0.2) -> Optional[Dict]:
        deadline = time.time() + timeout
        while True:
            nodes = self.dump()
            for text in texts:
                el = self.find_by_text(text, nodes)
                if el:
                    return el
            if time.time() >= deadline:
                return None
            time.sleep(interval)

    def wait_gone(self, identifier: str, timeout: float = 30.0, interval: float = 0.3) -> bool:
        deadline = time.time() + timeout
        while True:
            if not self.find_by_id(identifier):
                return True
            if time.time() >= deadline:
                return False
            time.sleep(interval)

    # ---------- 操作 ----------

    def tap_node(self, node: Dict):
        center = node.get("center")
        if not center:
            raise ValueError(f"节点没有有效坐标: {node}")
        self._run_adb(["shell", "input", "tap", str(center[0]), str(center[1])])

    def tap_id(self, identifier: str, nodes: Optional[List[Dict]] = None) -> bool:
        node = self.find_by_id(identifier, nodes)
        if not node:
            return False
        self.tap_node(node)
        return True

    def tap_text(self, text: str, nodes: Optional[List[Dict]] = None) -> bool:
        node = self.find_by_text(text, nodes)
        if not node:
            return False
        self.tap_node(node)
        return True

    def top_left_back_button(self, nodes: Optional[List[Dict]] = None) -> Optional[Dict]:
        """左上角返回按钮：按位置与可点性找，不写死坐标、不按文案。"""
        w, _ = self.get_screen_size()
        for el in (nodes if nodes is not None else self.dump()):
            center = el.get("center")
            if not center or not el.get("clickable"):
                continue
            if center[0] < w * 0.2 and center[1] < 200:
                return el
        return None

    def go_back(self, nodes: Optional[List[Dict]] = None) -> bool:
        """点左上角返回按钮。找不到就报错，不按返回键兜底（返回键可能直接退出 App）。"""
        btn = self.top_left_back_button(nodes)
        if not btn:
            return False
        self.tap_node(btn)
        return True

    def press_key(self, keycode: int):
        self._run_adb(["shell", "input", "keyevent", str(keycode)])

    def input_text(self, text: str):
        escaped = text.replace(" ", "%s").replace("&", "\\&").replace("@", "\\@")
        self._run_adb(["shell", "input", "text", escaped])

    def clear_text_input(self, delete_count: int = 40):
        keys = ["123"] + ["67"] * delete_count + ["122"] + ["112"] * delete_count
        self._run_adb(["shell", "input", "keyevent"] + keys)

    def swipe(self, x1: int, y1: int, x2: int, y2: int, duration_ms: int = 300):
        self._run_adb(["shell", "input", "swipe",
                       str(x1), str(y1), str(x2), str(y2), str(duration_ms)])

    def swipe_up(self, ratio_from: float = 0.75, ratio_to: float = 0.35, duration_ms: int = 300):
        w, h = self.get_screen_size()
        self.swipe(w // 2, int(h * ratio_from), w // 2, int(h * ratio_to), duration_ms)

    def take_screenshot(self, save_path: str) -> str:
        cmd = ["adb"]
        if self.serial:
            cmd.extend(["-s", self.serial])
        cmd.extend(["exec-out", "screencap", "-p"])
        with open(save_path, "wb") as f:
            res = subprocess.run(cmd, stdout=f, stderr=subprocess.PIPE)
            if res.returncode != 0:
                raise RuntimeError(f"截图失败: {res.stderr}")
        return save_path


if __name__ == "__main__":
    controller = AndroidDeviceController()
    width, height = controller.get_screen_size()
    print(f"✅ 连接成功！分辨率: {width}x{height}")
