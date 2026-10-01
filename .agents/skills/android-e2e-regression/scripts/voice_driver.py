#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Mac 原生双语语音驱动模块 (Voice Driver)
用于向空气中发声驱动物理 Android 手机麦克风进行 ASR 语音识别作答：
- 英文发音: say -v Samantha "{word}"
- 中文释义: say -v Tingting "{chinese}"
"""

import re
import subprocess
import time

def speak_out(text: str, pause_after: float = 0.5):
    """
    通过 Mac 本地扬声器发声：
    若包含中文字符，自动调用 macOS 内置普通话发音人 Tingting；
    纯英文单词/例句则调用美式发音人 Samantha。
    """
    if not text or not text.strip():
        return

    clean_text = text.strip()
    is_chinese = bool(re.search(r'[\u4e00-\u9fa5]', clean_text))
    voice = "Tingting" if is_chinese else "Samantha"

    try:
        subprocess.run(["say", "-v", voice, clean_text], check=True, timeout=10)
        if pause_after > 0:
            time.sleep(pause_after)
    except Exception as e:
        print(f"[!] Mac 语音发音异常: {e}")
