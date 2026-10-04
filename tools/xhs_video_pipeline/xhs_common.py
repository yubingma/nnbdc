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

def synth_bgm(dest, seconds, bpm=96):
    """合成一条低音量 lo-fi 底噪节奏：柔和铺底和弦 + 轻 kick + 反向 hat。"""
    sr = 44100
    n = int(sr * seconds)
    out = np.zeros(n)

    beat = 60.0 / bpm
    # 4 小节循环：Am - F - C - G（根音 + 五度，柔和正弦）
    chords = [(220.0, 330.0), (174.6, 261.6), (261.6, 392.0), (196.0, 293.7)]
    for bar in range(int(seconds / (beat * 4)) + 1):
        for k, (f1, f2) in enumerate(chords):
            start = (bar * 4 + k) * beat
            i0, i1 = int(start * sr), int(min(n, (start + beat * 1.6) * sr))
            if i0 >= n:
                continue
            tt = np.arange(i1 - i0) / sr
            env = np.minimum(tt / 0.25, 1.0) * np.exp(-tt * 1.1)
            voice = 0.30 * np.sin(2 * np.pi * f1 * tt) + 0.20 * np.sin(2 * np.pi * f2 * tt)
            voice += 0.06 * np.sin(2 * np.pi * f1 * 2 * tt)
            out[i0:i1] += voice * env

    # 轻 kick：每小节第 1、3 拍
    rng = np.random.default_rng(7)
    for b in range(int(seconds / beat) + 1):
        if b % 2:
            continue
        i0 = int(b * beat * sr)
        ln = int(0.22 * sr)
        if i0 + ln >= n:
            break
        tt = np.arange(ln) / sr
        out[i0:i0 + ln] += 0.5 * np.sin(2 * np.pi * (95 - 55 * tt / 0.22) * tt) * np.exp(-tt * 22)

    # 反向 hat：八分音符反拍
    for b in range(int(seconds / (beat / 2)) + 1):
        if b % 2 == 0:
            continue
        i0 = int(b * (beat / 2) * sr)
        ln = int(0.05 * sr)
        if i0 + ln >= n:
            break
        noise = rng.normal(0, 1, ln)
        noise = np.diff(noise, prepend=0.0)  # 简易高通
        tt = np.arange(ln) / sr
        out[i0:i0 + ln] += 0.05 * noise * np.exp(-tt * 90)

    # 柔和低通 + 淡入淡出
    out = np.convolve(out, np.ones(48) / 48, mode="same")
    fade = int(sr * 0.8)
    out[:fade] *= np.linspace(0, 1, fade)
    out[-fade:] *= np.linspace(1, 0, fade)
    peak = np.max(np.abs(out)) or 1.0
    out = out / peak * 0.5

    data = (out * 32767).astype("<i2")
    with wave.open(str(dest), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(sr)
        f.writeframes(data.tobytes())
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
