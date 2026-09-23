#!/usr/bin/env python3
"""炭炭背单词 UI 自动化辅助：dump 层级 / 点击 / 滑动 / 返回。"""
import re
import subprocess
import time

PKG = "com.maimemo.momolist.android"
NODE = re.compile(r'<node[^>]*?>')


def _adb(*args, **kw):
    return subprocess.run(["adb", *args], capture_output=True, text=True, **kw)


def dump(retries=3):
    """返回当前界面的节点列表 [{text, desc, cls, x1,y1,x2,y2, cx,cy}]。"""
    for _ in range(retries):
        _adb("shell", "uiautomator", "dump", "/sdcard/ui.xml")
        xml = _adb("shell", "cat", "/sdcard/ui.xml").stdout
        if "<hierarchy" in xml:
            break
        time.sleep(0.6)
    else:
        raise RuntimeError("uiautomator dump 失败")
    out = []
    for tag in NODE.findall(xml):
        def attr(name):
            m = re.search(rf'{name}="([^"]*)"', tag)
            return m.group(1) if m else ""
        b = re.search(r'bounds="\[(\d+),(\d+)\]\[(\d+),(\d+)\]"', tag)
        if not b:
            continue
        x1, y1, x2, y2 = map(int, b.groups())
        out.append({
            "text": attr("text"), "desc": attr("content-desc"),
            "cls": attr("class"), "clickable": attr("clickable") == "true",
            "x1": x1, "y1": y1, "x2": x2, "y2": y2,
            "cx": (x1 + x2) // 2, "cy": (y1 + y2) // 2,
        })
    return out


def texts(nodes=None, min_y=0, max_y=99999):
    nodes = nodes if nodes is not None else dump()
    return [n["text"] for n in nodes if n["text"].strip()
            and min_y <= n["cy"] <= max_y]


def show(nodes=None):
    nodes = nodes if nodes is not None else dump()
    for n in nodes:
        if n["text"].strip() or n["desc"].strip():
            label = n["text"] or f'[{n["desc"]}]'
            print(f'{label[:60]!r:64} ({n["cx"]},{n["cy"]})')


def tap(x, y, wait=1.5):
    _adb("shell", "input", "tap", str(x), str(y))
    time.sleep(wait)


def tap_text(text, wait=1.5, exact=True):
    for n in dump():
        t = n["text"] or n["desc"]
        if (t == text) if exact else (text in t):
            tap(n["cx"], n["cy"], wait)
            return n
    raise LookupError(f"未找到可点击文本: {text!r}")


def swipe(x1, y1, x2, y2, ms=300, wait=1.0):
    _adb("shell", "input", "swipe", str(x1), str(y1), str(x2), str(y2), str(ms))
    time.sleep(wait)


def back(wait=1.5):
    _adb("shell", "input", "keyevent", "4")
    time.sleep(wait)


def shot(path):
    with open(path, "wb") as f:
        f.write(subprocess.run(["adb", "exec-out", "screencap", "-p"],
                               capture_output=True).stdout)
