#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
小红书竖屏短视频（9:16）生成的公共管道。

被各「系列」脚本复用，只放与内容形态无关的东西：
    · 画布与视觉令牌、字体加载与自动缩字
    · 单词真人发音（有道音源）与中文配音（通义 qwen3-tts-flash）
    · numpy 合成的轻量 BGM
    · 逐帧渲染动画层（Layer 文字层 / ImageLayer 图片层）与深空背景
    · ffmpeg 探测时长等小工具
"""

import hashlib
import json
import os
import subprocess
import urllib.parse
import urllib.request
import wave
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageOps

ROOT_DIR = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT_DIR / "design" / "ui" / "video"
SFX_DIR = ROOT_DIR / "app" / "assets" / "audio"

W, H = 1080, 1920
FPS = 30

# 视觉设计令牌
BG_TOP = (13, 16, 21)
BG_BOTTOM = (7, 8, 11)
INK = (242, 246, 250)
INK_DIM = (138, 148, 163)
INK_FAINT = (86, 94, 108)

FONT_EN = "/System/Library/Fonts/Avenir Next.ttc"
FONT_EN_NUM = 2  # Demi Bold
FONT_LATIN = "/System/Library/Fonts/HelveticaNeue.ttc"
FONT_LATIN_BOLD = 1
FONT_LATIN_MED = 10
FONT_CN = "/System/Library/Fonts/Hiragino Sans GB.ttc"
FONT_CN_BOLD = 2
FONT_CN_REG = 0
# 音标含 ɪ / ˈ / ɛ / ɚ 等 IPA 字符，系统中仅 Arial Unicode MS 完整覆盖
FONT_IPA = "/System/Library/Fonts/Supplemental/Arial Unicode.ttf"

_font_cache = {}


def font(path, size, index=0):
    key = (path, size, index)
    if key not in _font_cache:
        _font_cache[key] = ImageFont.truetype(path, size, index=index)
    return _font_cache[key]


def fit_font(text, path, index, size, max_w, min_size=22):
    """按最大宽度自动缩字号，防止长单词/长句溢出画布。"""
    while size > min_size:
        f = font(path, size, index)
        bbox = f.getbbox(text)
        if bbox[2] - bbox[0] <= max_w:
            return f
        size -= 2
    return font(path, min_size, index)


def hex2rgb(s):
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) for i in (0, 2, 4))


def tint(color, alpha):
    """统一的 RGBA 取色，避免各处重复写 alpha 换算。"""
    return hex2rgb(color) + (max(0, min(255, int(alpha))),)


def run(cmd, **kw):
    return subprocess.run(cmd, check=True, capture_output=True, **kw)


_dur_cache = {}


def duration_of(path):
    key = str(path)
    if key not in _dur_cache:
        out = run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                   "-of", "default=nw=1:nk=1", key]).stdout.decode().strip()
        _dur_cache[key] = float(out)
    return _dur_cache[key]


# ---------------------------------------------------------------- 素材获取

def fetch_word_audio(word, dest, accent=2):
    """有道词典真人发音（accent: 1 英音 / 2 美音）。

    词典音源首尾都带一段静音（spring 原始 1.95s，实际发声不到 0.8s），
    不裁掉会把后面的中文讲解整段往后推、挤掉节奏，所以这里统一剪掉首尾静音。
    """
    trimmed = dest.with_suffix(".trim.wav")
    if trimmed.exists() and trimmed.stat().st_size > 1000:
        return trimmed
    if not (dest.exists() and dest.stat().st_size > 1000):
        url = "https://dict.youdao.com/dictvoice?" + urllib.parse.urlencode(
            {"audio": word, "type": accent})
        with urllib.request.urlopen(url, timeout=20) as r:
            dest.write_bytes(r.read())
    silence = ("silenceremove=start_periods=1:start_duration=0:"
               "start_threshold=-50dB:detection=peak")
    run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(dest),
         "-af", f"{silence},areverse,{silence},areverse", str(trimmed)])
    return trimmed


def fetch_tts(text, dest_dir, prefix, voice="Cherry", language="Chinese",
              model="qwen3-tts-flash", instructions=None):
    """通义 TTS 合成讲解配音。

    缓存文件名把「文案 + 音色 + 模型 + 语气指令」一起算进哈希——只按文案做键的话，
    换了音色会静默复用旧音频，听起来像没生效。
    """
    sig = "|".join([text, voice, model, language, instructions or ""])
    tag = hashlib.md5(sig.encode("utf-8")).hexdigest()[:8]
    dest = dest_dir / f"{prefix}_{tag}.wav"
    if dest.exists() and dest.stat().st_size > 1000:
        return dest
    payload = {"text": text, "voice": voice, "language_type": language}
    if instructions:
        payload["instructions"] = instructions
    body = json.dumps({"model": model, "input": payload}).encode()
    req = urllib.request.Request(
        "https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation",
        data=body, headers={"Authorization": f"Bearer {dashscope_key()}",
                            "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=90) as r:
        resp = json.loads(r.read())
    with urllib.request.urlopen(resp["output"]["audio"]["url"], timeout=90) as r:
        dest.write_bytes(r.read())
    return dest


def dashscope_key():
    key = os.environ.get("dashscope_api_key")
    if key:
        return key
    profile = Path.home() / ".zprofile"
    for line in profile.read_text(encoding="utf-8", errors="ignore").splitlines():
        line = line.strip().removeprefix("export ").strip()
        if line.startswith("dashscope_api_key="):
            return line.split("=", 1)[1].strip().strip('"').strip("'")
    raise RuntimeError("未在 ~/.zprofile 找到 dashscope_api_key")


# ---------------------------------------------------------------- BGM 合成

DEFAULT_MUSIC = dict(bpm=96, scale="major", motion="cycle", weight=0.5, brightness=0.5)

# 几个现成的音乐档案，供单集脚本按核心意象挑用
MUSIC_PRESETS = {
    "burst":  dict(bpm=104, scale="major", motion="rise",  weight=0.30, brightness=0.85),  # 蓄势迸发
    "load":   dict(bpm=82,  scale="minor", motion="fall",  weight=0.80, brightness=0.28),  # 装载压入
    "spin":   dict(bpm=96,  scale="major", motion="cycle", weight=0.45, brightness=0.55),  # 旋转往复
    "cut":    dict(bpm=100, scale="minor", motion="fall",  weight=0.60, brightness=0.40),  # 切断分离
    "soar":   dict(bpm=110, scale="major", motion="rise",  weight=0.25, brightness=0.90),  # 上升腾起
    "press":  dict(bpm=76,  scale="minor", motion="cycle", weight=0.85, brightness=0.25),  # 持续施压
}

_NOTE = {"C": 261.63, "D": 293.66, "E": 329.63, "F": 349.23,
         "G": 392.00, "A": 440.00, "B": 493.88}

# 16 小节的和弦进行 —— 这是治"重复感"的关键：循环长度必须长过整条片子。
# 按 96 BPM 算，一小节 2.5 秒，16 小节 = 40 秒，30~37 秒的成片基本听不到重复。
_PROGRESSIONS = {
    "major": [("C", "maj"), ("A", "min"), ("F", "maj"), ("G", "maj"),
              ("A", "min"), ("F", "maj"), ("C", "maj"), ("G", "maj"),
              ("F", "maj"), ("G", "maj"), ("E", "min"), ("A", "min"),
              ("D", "min"), ("G", "maj"), ("C", "maj"), ("C", "maj")],
    "minor": [("A", "min"), ("F", "maj"), ("C", "maj"), ("G", "maj"),
              ("F", "maj"), ("C", "maj"), ("G", "maj"), ("A", "min"),
              ("D", "min"), ("F", "maj"), ("E", "maj"), ("A", "min"),
              ("F", "maj"), ("G", "maj"), ("A", "min"), ("A", "min")],
}

# 织体分四层，每层 4 小节推进一次：垫底 → 加低音 → 加琶音与沙锤 → 加花
_LAYERS_PER_STAGE = 4


def resolve_music(spec):
    """单集脚本里的 music 可以是预设名，也可以直接给参数字典。"""
    if not spec:
        return dict(DEFAULT_MUSIC)
    if isinstance(spec, str):
        return {**DEFAULT_MUSIC, **MUSIC_PRESETS.get(spec, {})}
    return {**DEFAULT_MUSIC, **spec}


def synth_bgm(dest, seconds, profile=None):
    """按「核心意象」合成背景垫乐。

    防重复的四条规矩（都是踩过"听着心烦"之后定的）：
      1. 和弦**每小节换一次**，不是每拍换一次；
      2. 和弦进行有 **16 小节**，循环长度长过整条成片；
      3. 和弦垫是**持续音**（慢起慢落），不是拨一下就衰减的短音；
      4. **织体分层推进**：垫底 → 低音 → 琶音沙锤 → 加花，越到后面越满。

    与意象对应的抓手：音高走向（上行=迸发/下行=压入/往复=旋转）、
    明暗（大调/小调）、速度、重量（低频与底鼓）、亮度（泛音与沙锤）。
    """
    m = resolve_music(profile)
    sr, n = 44100, int(44100 * seconds)
    out = np.zeros(n)
    beat = 60.0 / m["bpm"]
    bar = beat * 4
    prog = _PROGRESSIONS[m["scale"]]
    rng = np.random.default_rng(11)
    n_bars = int(seconds / bar) + 2

    for b in range(n_bars):
        i0 = int(b * bar * sr)
        if i0 >= n:
            break
        i1 = min(n, i0 + int(bar * sr))
        tt = np.arange(i1 - i0) / sr
        name, quality = prog[b % len(prog)]
        base = _NOTE[name] / 2
        ivs = (0, 4, 7) if quality == "maj" else (0, 3, 7)

        stage = b // _LAYERS_PER_STAGE

        # 拨奏式和弦：快起快落，每小节两记（第 1 拍与第 3 拍）。
        # 用户明确要"敲击声"、不要"嗡嗡声"——而嗡鸣不来自音高高低，来自**持续不断的纯音**：
        # 三条正弦一直挂着，哪怕音高有 110Hz 以上，听感仍是风琴式的嗡鸣。
        # 改成拨奏后，整条垫乐归入打击乐家族，和底鼓、沙锤是同一个语汇。
        voice = 0.26 * np.sin(2 * np.pi * base * tt)
        if stage >= 1:
            voice += 0.18 * np.sin(2 * np.pi * base * 2 ** (ivs[1] / 12) * tt)
        if stage >= 2:
            voice += 0.14 * np.sin(2 * np.pi * base * 2 ** (ivs[2] / 12) * tt)
        if stage >= 3:
            voice += m["brightness"] * 0.06 * np.sin(2 * np.pi * base * 4 * tt)
        for hit, gain in ((0.0, 1.0), (beat * 2, 0.55)):      # 第 3 拍再来一记轻的
            h0 = i0 + int(hit * sr)
            if h0 >= n:
                continue
            h1 = min(n, h0 + len(tt))
            th = np.arange(h1 - h0) / sr
            env = np.minimum(th / 0.010, 1.0) * np.exp(-th * 3.8)
            out[h0:h1] += voice[:h1 - h0] * env * gain

        # 第 3 层起：八分音符琶音，走向由 motion 决定
        if stage >= 2:
            order = ivs if m["motion"] == "rise" else (
                ivs[::-1] if m["motion"] == "fall" else ivs + ivs[::-1])
            for j in range(8):
                j0 = i0 + int(j * beat / 2 * sr)
                if j0 >= n:
                    break
                j1 = min(n, j0 + int(0.5 * sr))
                tj = np.arange(j1 - j0) / sr
                note = base * 2 * 2 ** (order[j % len(order)] / 12)
                out[j0:j1] += 0.12 * np.sin(2 * np.pi * note * tj) * np.exp(-tj * 7)

    # 底鼓：第 2 层才进（第一层只有垫音，靠"空"给后面的进入让出对比）；
    # 重量越大越沉、越响，轻的曲子隔拍踩，重的每拍都踩
    kick_gain = 0.20 + 0.50 * m["weight"]
    kick_from = int(_LAYERS_PER_STAGE * bar * sr)
    for b in range(int(seconds / beat) + 1):
        if int(b * beat * sr) < kick_from:
            continue
        if m["weight"] < 0.5 and b % 2:
            continue
        i0 = int(b * beat * sr)
        ln = int(0.22 * sr)
        if i0 + ln >= n:
            break
        tt = np.arange(ln) / sr
        f0 = 105 - 45 * m["weight"]
        out[i0:i0 + ln] += kick_gain * np.sin(2 * np.pi * (f0 - 55 * tt / 0.22) * tt) * np.exp(-tt * 20)

    # 沙锤：第 3 层起才进，亮度越低越轻
    if seconds > 3 * _LAYERS_PER_STAGE * bar:
        for b in range(int(seconds / (beat / 2)) + 1):
            if b % 2 == 0:
                continue
            i0 = int(b * (beat / 2) * sr)
            if i0 < int(2 * _LAYERS_PER_STAGE * bar * sr):     # 前两层不出现
                continue
            ln = int(0.05 * sr)
            if i0 + ln >= n:
                break
            noise = np.diff(rng.normal(0, 1, ln), prepend=0.0)
            tt = np.arange(ln) / sr
            out[i0:i0 + ln] += (0.02 + 0.06 * m["brightness"]) * noise * np.exp(-tt * 90)

    # 第 4 层起：每 4 小节末尾加一记过门，打破方整感
    if seconds > 3 * _LAYERS_PER_STAGE * bar:
        for b in range(3, n_bars, 4):
            i0 = int((b * bar + 3.5 * beat) * sr)
            ln = int(0.10 * sr)
            if i0 + ln >= n:
                break
            tt = np.arange(ln) / sr
            out[i0:i0 + ln] += 0.28 * np.sin(2 * np.pi * 300 * tt) * np.exp(-tt * 45)

    # 极慢的整体呼吸（周期 13 秒），避免整条一样响
    breath = 1.0 + 0.10 * np.sin(2 * np.pi * np.arange(n) / sr / 13.0)
    out *= breath

    out = np.convolve(out, np.ones(48) / 48, mode="same")
    fade = int(sr * 0.8)
    out[:fade] *= np.linspace(0, 1, fade)
    out[-fade:] *= np.linspace(1, 0, fade)
    peak = np.max(np.abs(out)) or 1.0
    out = out / peak * 0.5

    with wave.open(str(dest), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(sr)
        f.writeframes((out * 32767).astype("<i2").tobytes())
    return dest


# ---------------------------------------------------------------- 画面资产

def load_line_art(path, box, floor=34, gain=1.7):
    """把白底黑线的词核心图转成「透明底 + 白色线条」的 RGBA，并裁掉白边。

    用亮度当 alpha：线越黑，反相后越亮，最终越不透明。这样它可以直接叠在深色画布上。
    """
    gray = Image.open(path).convert("L")
    mask = ImageOps.invert(gray).point(           # 黑线 → 白线
        lambda p: 0 if p < floor else min(255, int((p - floor) * gain)))
    bbox = mask.getbbox()
    if bbox:
        mask = mask.crop(bbox)
    mask.thumbnail((box, box), Image.LANCZOS)
    art = Image.new("RGBA", mask.size, (255, 255, 255, 0))
    art.putalpha(mask)
    return art


class Layer:
    """带入场动画的文字层：淡入 + 上浮。"""

    def __init__(self, draw_fn, start, dur=0.5, rise=34):
        self.draw_fn = draw_fn
        self.start = start
        self.dur = dur
        self.rise = rise

    def render(self, base, t):
        p = (t - self.start) / self.dur
        if p <= 0:
            return
        p = min(1.0, p)
        e = 1 - (1 - p) ** 3
        layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
        self.draw_fn(ImageDraw.Draw(layer), e, (1 - e) * self.rise)
        base.alpha_composite(layer)


class TimedLayer:
    """与 Layer 相同（淡入 + 上浮），但把当前时间也交给绘制函数。

    逐字高亮这类效果必须知道"现在念到第几个字了"，只靠入场进度 e 是不够的。
    """

    def __init__(self, draw_fn, start, dur=0.5, rise=34):
        self.draw_fn = draw_fn
        self.start = start
        self.dur = dur
        self.rise = rise

    def render(self, base, t):
        p = (t - self.start) / self.dur
        if p <= 0:
            return
        p = min(1.0, p)
        e = 1 - (1 - p) ** 3
        layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
        self.draw_fn(ImageDraw.Draw(layer), e, (1 - e) * self.rise, t)
        base.alpha_composite(layer)


class ImageLayer:
    """带入场动画的图片层：淡入 + 上浮 + 可选的从 scale_from 放大到 1。"""

    def __init__(self, art, center, start, dur=0.6, rise=0, scale_from=1.0, glow=None,
                 fade_in=True):
        self.art = art
        self.center = center
        self.start = start
        self.dur = dur
        self.rise = rise
        self.scale_from = scale_from
        self.glow = glow
        # fade_in=False：第 0 帧就是全不透明，只在 dur 内做缓慢缩放。
        # 小红书封面取第一帧，凡是"必须出现在封面上"的元素都得用这个模式。
        self.fade_in = fade_in

    def render(self, base, t):
        p = (t - self.start) / self.dur
        if p <= 0:
            if self.fade_in:
                return
            p = 0.0
        p = min(1.0, p)
        e = 1 - (1 - p) ** 3
        art = self.art
        scale = self.scale_from + (1 - self.scale_from) * e
        if abs(scale - 1.0) > 0.005:
            size = (max(1, int(art.width * scale)), max(1, int(art.height * scale)))
            art = art.resize(size, Image.LANCZOS)
        if self.fade_in and e < 1.0:
            alpha = art.getchannel("A").point(lambda v: int(v * e))
            art = art.copy()
            art.putalpha(alpha)
        x = int(self.center[0] - art.width / 2)
        y = int(self.center[1] - art.height / 2 + (1 - e) * self.rise)
        if self.glow:
            base.alpha_composite(self._glow(art, self.glow), (x, y))
        base.alpha_composite(art, (x, y))

    @staticmethod
    def _glow(art, color):
        halo = Image.new("RGBA", art.size, tuple(color[:3]) + (0,))
        halo.putalpha(art.getchannel("A").filter(ImageFilter.GaussianBlur(26))
                      .point(lambda v: int(v * color[3] / 255)))
        return halo


def make_background(accent):
    """深空底色 + 顶部品牌光晕 + 细腻噪点，整集静态复用。"""
    yy = np.linspace(0, 1, H)[:, None]
    bg = np.zeros((H, W, 3), dtype=np.float64)
    for c in range(3):
        bg[:, :, c] = (BG_TOP[c] * (1 - yy) + BG_BOTTOM[c] * yy)

    yy2 = np.arange(H)[:, None]
    xx2 = np.arange(W)[None, :]
    dist = np.sqrt((xx2 - W * 0.5) ** 2 + (yy2 - H * 0.22) ** 2)
    glow = np.clip(1 - dist / (W * 1.05), 0, 1) ** 2.2
    for c in range(3):
        bg[:, :, c] += glow * accent[c] * 0.16

    dist2 = np.sqrt((xx2 - W * 0.5) ** 2 + (yy2 - H * 1.02) ** 2)
    glow2 = np.clip(1 - dist2 / (W * 0.95), 0, 1) ** 2.5
    for c in range(3):
        bg[:, :, c] += glow2 * accent[c] * 0.05

    rng = np.random.default_rng(11)
    bg += rng.normal(0, 2.2, bg.shape)
    return Image.fromarray(np.clip(bg, 0, 255).astype(np.uint8)).convert("RGBA")


def teaser_chip(d, cx, y, text, fnt, alpha):
    """胶囊标签：片头承诺与片尾下集预告共用。"""
    if not text:
        return
    bbox = d.textbbox((0, 0), text, font=fnt)
    hw = (bbox[2] - bbox[0]) / 2 + 56
    d.rounded_rectangle([cx - hw, y - 48, cx + hw, y + 48], radius=48,
                        fill=(255, 255, 255, int(16 * alpha)),
                        outline=INK_FAINT + (int(150 * alpha),), width=2)
    d.text((cx, y), text, font=fnt, fill=INK + (int(230 * alpha),), anchor="mm")


def encode_video(frames, total_frames, total_seconds, audio, out_path,
                 bgm_path=None, bgm_gain=0.30, quiet=False):
    """把逐帧 RGB 字节流与音轨交给 ffmpeg 合成 mp4。frames 是可迭代的 bytes。"""
    cmd = ["ffmpeg", "-y", "-loglevel", "error",
           "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-"]
    for a in audio:
        cmd += ["-i", str(a["path"])]
    if bgm_path:
        cmd += ["-i", str(bgm_path)]

    filt, mix = [], []
    for i, a in enumerate(audio):
        filt.append(f"[{i + 1}:a]volume={a.get('gain', 1.0)},adelay={int(a['at'] * 1000)}:all=1,"
                    f"aformat=sample_fmts=fltp:sample_rates=44100:channel_layouts=stereo[a{i}]")
        mix.append(f"[a{i}]")
    if bgm_path:
        filt.append(f"[{len(audio) + 1}:a]volume={bgm_gain},"
                    f"aformat=sample_fmts=fltp:sample_rates=44100:channel_layouts=stereo[abgm]")
        mix.append("[abgm]")
    filt.append("".join(mix) + f"amix=inputs={len(mix)}:duration=longest:normalize=0[aout]")

    cmd += ["-filter_complex", ";".join(filt), "-map", "0:v", "-map", "[aout]",
            "-c:v", "libx264", "-preset", "medium", "-crf", "19", "-pix_fmt", "yuv420p",
            "-r", str(FPS), "-t", f"{total_seconds:.3f}",
            "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", str(out_path)]

    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        for i, buf in enumerate(frames):
            try:
                proc.stdin.write(buf)
            except BrokenPipeError:
                break
            if not quiet and i % 150 == 0:
                print(f"  渲染 {i}/{total_frames} 帧", flush=True)
    finally:
        try:
            proc.stdin.close()
        except BrokenPipeError:
            pass
        err = proc.stderr.read().decode()
        code = proc.wait()
    if code != 0:
        raise SystemExit(f"ffmpeg 合成失败，退出码 {code}\n{err[-4000:]}")
    return out_path


# ---------------------------------------------------------------- 交付

PHOTO_ALBUM = "小红书 · 词核心图"


def _applescript_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def photos_script(paths, album=PHOTO_ALBUM):
    """生成把成片导入 macOS「照片」的 AppleScript。"""
    files = ", ".join(f"POSIX file {_applescript_str(str(Path(p).resolve()))}" for p in paths)
    return f"""tell application "Photos"
    if not (exists album {_applescript_str(album)}) then
        make new album named {_applescript_str(album)}
    end if
    set theItems to import {{{files}}} into album {_applescript_str(album)}
    return (count of theItems)
end tell
"""


def import_to_photos(paths, album=PHOTO_ALBUM):
    """把成片导进 macOS「照片」的指定专辑。

    开 iCloud 照片的话，视频会自动同步到手机相册，直接就能发小红书，不用再导来导去。
    注意：重复导入同一个文件会产生重复项，Photos 不做去重。
    """
    paths = [Path(p) for p in paths]
    for p in paths:
        if not p.exists():
            raise SystemExit(f"要导入的文件不存在：{p}")
    r = subprocess.run(["osascript", "-e", photos_script(paths, album)],
                       capture_output=True)
    if r.returncode != 0:
        raise SystemExit(f"导入「照片」失败：{r.stderr.decode().strip()}")
    return int(r.stdout.decode().strip() or 0)
