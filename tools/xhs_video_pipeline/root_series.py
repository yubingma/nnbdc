#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
词根系列竖屏短视频生成器（小红书 9:16）

用法：
    python3 tools/xhs_video_pipeline/root_series.py tools/xhs_video_pipeline/episodes/ep01_spect.json

流程：
    1. 读取单集脚本 JSON（词根人格、词条、讲解文案、时间轴）
    2. 下载单词真实发音（有道词典音源）与中文讲解配音（通义 qwen3-tts-flash）
    3. numpy 合成轻量 BGM（--no-bgm 可关闭）
    4. PIL 逐帧渲染 1080x1920 画面，rawvideo 管道喂给 ffmpeg
    5. 输出成片到 design/ui/video/

中间产物（音频、临时帧）统一落在 tmp/xhs_root_series/<集号>/。
"""

import argparse
import json
import math
import subprocess
import sys
import urllib.parse
import urllib.request
import wave
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT_DIR = Path(__file__).resolve().parents[2]
TMP_DIR = ROOT_DIR / "tmp" / "xhs_root_series"
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
    """有道词典真人发音（accent: 1 英音 / 2 美音）。"""
    if dest.exists() and dest.stat().st_size > 1000:
        return dest
    url = "https://dict.youdao.com/dictvoice?" + urllib.parse.urlencode(
        {"audio": word, "type": accent})
    with urllib.request.urlopen(url, timeout=20) as r:
        dest.write_bytes(r.read())
    return dest


def fetch_tts(text, dest_dir, prefix, voice="Cherry", language="Chinese"):
    """通义 qwen3-tts-flash 合成讲解配音。文件名带文案哈希，改文案自动重新合成。"""
    import hashlib
    tag = hashlib.md5(text.encode("utf-8")).hexdigest()[:8]
    dest = dest_dir / f"{prefix}_{tag}.wav"
    if dest.exists() and dest.stat().st_size > 1000:
        return dest
    key = _dashscope_key()
    body = json.dumps({"model": "qwen3-tts-flash",
                       "input": {"text": text, "voice": voice, "language_type": language}}).encode()
    req = urllib.request.Request(
        "https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation",
        data=body, headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        resp = json.loads(r.read())
    url = resp["output"]["audio"]["url"]
    with urllib.request.urlopen(url, timeout=60) as r:
        dest.write_bytes(r.read())
    return dest


def _dashscope_key():
    import os
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
    t = np.arange(n) / sr
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
    k = np.ones(48) / 48
    out = np.convolve(out, k, mode="same")
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


# ---------------------------------------------------------------- 画面渲染

class Layer:
    """带入场动画的画面元素：淡入 + 上浮。"""

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
        d = ImageDraw.Draw(layer)
        self.draw_fn(d, e, (1 - e) * self.rise)
        base.alpha_composite(layer)


def make_background(accent):
    """深空底色 + 顶部品牌光晕 + 细腻噪点，整集静态复用。"""
    yy = np.linspace(0, 1, H)[:, None]
    bg = np.zeros((H, W, 3), dtype=np.float64)
    for c in range(3):
        bg[:, :, c] = (BG_TOP[c] * (1 - yy) + BG_BOTTOM[c] * yy)

    yy2 = np.arange(H)[:, None]
    xx2 = np.arange(W)[None, :]
    cx, cy, rad = W * 0.5, H * 0.22, W * 1.05
    dist = np.sqrt((xx2 - cx) ** 2 + (yy2 - cy) ** 2)
    glow = np.clip(1 - dist / rad, 0, 1) ** 2.2
    for c in range(3):
        bg[:, :, c] += glow * accent[c] * 0.16

    # 底部再来一层极淡的暖色补光
    dist2 = np.sqrt((xx2 - W * 0.5) ** 2 + (yy2 - H * 1.02) ** 2)
    glow2 = np.clip(1 - dist2 / (W * 0.95), 0, 1) ** 2.5
    for c in range(3):
        bg[:, :, c] += glow2 * accent[c] * 0.05

    rng = np.random.default_rng(11)
    bg += rng.normal(0, 2.2, bg.shape)
    return Image.fromarray(np.clip(bg, 0, 255).astype(np.uint8)).convert("RGBA")


def teaser_chip(d, cx, y, text, fnt, alpha):
    """胶囊标签：片头承诺（3 个考研词）与片尾下集预告共用。"""
    if not text:
        return
    bbox = d.textbbox((0, 0), text, font=fnt)
    tw = bbox[2] - bbox[0]
    hw = tw / 2 + 56
    d.rounded_rectangle([cx - hw, y - 48, cx + hw, y + 48], radius=48,
                        fill=(255, 255, 255, int(16 * alpha)),
                        outline=INK_FAINT + (int(150 * alpha),), width=2)
    d.text((cx, y), text, font=fnt, fill=INK + (int(230 * alpha),), anchor="mm")


def chips_row(d, cx, y, chips, alpha, max_w=W - 160):
    """词根拆解 chips 行：[in-] 往里  +  [spect] 看"""
    f_cn = font(FONT_CN, 34, FONT_CN_REG)
    f_op = font(FONT_LATIN, 52, FONT_LATIN_MED)
    op_w = 70

    # 按最长词条自动缩字号，直到整行宽度落在画布安全区内
    size = 62
    while size > 34:
        f_en = font(FONT_EN, size, FONT_EN_NUM)
        widths = []
        for c in chips:
            tw = f_en.getbbox(c["text"])[2] - f_en.getbbox(c["text"])[0]
            cw = f_cn.getbbox(c.get("cn", ""))[2] - f_cn.getbbox(c.get("cn", ""))[0]
            widths.append(max(tw, cw) + 64)
        if sum(widths) + op_w * (len(chips) - 1) <= max_w:
            break
        size -= 4
    f_en = font(FONT_EN, size, FONT_EN_NUM)

    total = sum(widths) + op_w * (len(chips) - 1)
    x = cx - total / 2
    for i, (c, bw) in enumerate(zip(chips, widths)):
        col = hex2rgb(c["color"]) + (int(255 * alpha),)
        d.rounded_rectangle([x, y - 62, x + bw, y + 62], radius=26,
                            fill=hex2rgb(c["color"]) + (int(28 * alpha),),
                            outline=col, width=3)
        d.text((x + bw / 2, y - 16), c["text"], font=f_en, fill=col, anchor="mm")
        if c.get("cn"):
            d.text((x + bw / 2, y + 34), c["cn"], font=f_cn,
                   fill=INK_DIM + (int(255 * alpha),), anchor="mm")
        x += bw
        if i < len(chips) - 1:
            d.text((x + op_w / 2, y - 16), "+", font=f_op,
                   fill=INK_FAINT + (int(255 * alpha),), anchor="mm")
            x += op_w


def render_episode(cfg, audio, out_path, bgm_path, quiet=False):
    accent = hex2rgb(cfg.get("accent", "#F5A524"))
    bg = make_background(accent)
    segments = cfg["segments"]
    seg_starts, acc = [], 0.0
    for s in segments:
        seg_starts.append(acc)
        acc += s["dur"]
    total = acc

    f_series = font(FONT_CN, 34, FONT_CN_REG)
    f_hook = font(FONT_CN, 50, FONT_CN_REG)
    f_root = font(FONT_EN, 230, FONT_EN_NUM)
    f_root_cn = font(FONT_CN, 92, FONT_CN_BOLD)
    f_small = font(FONT_CN, 36, FONT_CN_REG)
    f_idx = font(FONT_LATIN, 40, FONT_LATIN_MED)

    def wf(s):
        return fit_font(s["word"], FONT_EN, FONT_EN_NUM, 168, W - 150)

    def cf(s):
        return fit_font(s["cn"], FONT_CN, FONT_CN_BOLD, 118, W - 190)

    def hf(s):
        return fit_font(s["hook"], FONT_CN, FONT_CN_REG, 50, W - 190)

    def lf(text, size=104):
        return fit_font(text, FONT_CN, FONT_CN_BOLD, size, W - 170)

    def sf(text, size=50):
        return fit_font(text, FONT_CN, FONT_CN_REG, size, W - 170)

    layers_by_seg = []
    for idx, s in enumerate(segments):
        L = []
        kind = s["type"]
        dur = s["dur"]
        if kind == "hook":
            L.append(Layer(lambda d, e, dy, s=s: d.text(
                (W / 2, 640 + dy), cfg["root"], font=f_root,
                fill=accent + (int(255 * e),), anchor="mm"), 0.25))
            L.append(Layer(lambda d, e, dy, s=s: d.text(
                (W / 2, 860 + dy), f"= {cfg['root_cn']}", font=f_root_cn,
                fill=INK + (int(255 * e),), anchor="mm"), 0.55))
            L.append(Layer(lambda d, e, dy, s=s: d.text(
                (W / 2, 1080 + dy), s["line"], font=sf(s["line"]),
                fill=INK + (int(235 * e),), anchor="mm"), dur * 0.30, dur=0.6))
            L.append(Layer(lambda d, e, dy, s=s: teaser_chip(
                d, W / 2, 1280 + dy, cfg.get("hook_chip", ""), f_small, e),
                dur * 0.46, dur=0.6))
        elif kind == "word":
            L.append(Layer(lambda d, e, dy, s=s: d.text(
                (W / 2, 520 + dy), s["word"], font=wf(s),
                fill=INK + (int(255 * e),), anchor="mm"), 0.05, dur=0.45, rise=44))
            L.append(Layer(lambda d, e, dy, s=s: d.text(
                (W / 2, 700 + dy), s["phonetic"], font=font(FONT_IPA, 54),
                fill=(150, 200, 235) + (int(235 * e),), anchor="mm"), 0.30, rise=24))
            L.append(Layer(lambda d, e, dy, s=s: chips_row(
                d, W / 2, 940 + dy, s["chips"], e), dur * 0.25, dur=0.5, rise=30))
            L.append(Layer(lambda d, e, dy, s=s: d.text(
                (W / 2, 1200 + dy), s["cn"], font=cf(s),
                fill=accent + (int(255 * e),), anchor="mm"), dur * 0.45, dur=0.5, rise=36))
            L.append(Layer(lambda d, e, dy, s=s: d.text(
                (W / 2, 1400 + dy), s["hook"], font=hf(s),
                fill=INK_DIM + (int(255 * e),), anchor="mm"), dur * 0.62, dur=0.6))
        elif kind == "outro":
            L.append(Layer(lambda d, e, dy, s=s: d.text(
                (W / 2, 760 + dy), s["line"], font=lf(s["line"], 104),
                fill=accent + (int(255 * e),), anchor="mm"), 0.10, dur=0.6))
            L.append(Layer(lambda d, e, dy, s=s: d.text(
                (W / 2, 960 + dy), s["sub"], font=sf(s["sub"]),
                fill=INK + (int(240 * e),), anchor="mm"), dur * 0.16, dur=0.6))
            L.append(Layer(lambda d, e, dy, s=s: teaser_chip(
                d, W / 2, 1150 + dy, s["next"], f_small, e), dur * 0.28, dur=0.6))
            L.append(Layer(lambda d, e, dy, s=s: d.text(
                (W / 2, 1370 + dy), s["cta"], font=f_hook,
                fill=INK_DIM + (int(255 * e),), anchor="mm"), dur * 0.40, dur=0.6))
        layers_by_seg.append(L)

    # 顶部栏与底部进度条贯穿全集
    def draw_chrome(img, t):
        d = ImageDraw.Draw(img)
        d.text((86, 150), f"{cfg['series']} · {cfg['episode']}", font=f_series,
               fill=INK_FAINT, anchor="lm")
        d.text((W - 86, 150), cfg.get("position", ""), font=f_idx,
               fill=INK_FAINT, anchor="rm")
        prog = min(1.0, t / total)
        d.rounded_rectangle([86, H - 120, W - 86, H - 112], radius=4,
                            fill=(255, 255, 255, 22))
        d.rounded_rectangle([86, H - 120, 86 + (W - 172) * prog, H - 112], radius=4,
                            fill=accent + (230,))
        d.text((W / 2, H - 175), cfg["slogan"], font=f_small,
               fill=INK_FAINT, anchor="mm")

    n_frames = int(round(total * FPS))
    cmd = ["ffmpeg", "-y", "-loglevel", "error",
           "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-"]
    for a in audio:
        cmd += ["-i", str(a["path"])]
    if bgm_path:
        cmd += ["-i", str(bgm_path)]

    filt = []
    mix_labels = []
    for i, a in enumerate(audio):
        ms = int(a["at"] * 1000)
        gain = a.get("gain", 1.0)
        filt.append(f"[{i + 1}:a]volume={gain},adelay={ms}:all=1,"
                    f"aformat=sample_fmts=fltp:sample_rates=44100:channel_layouts=stereo[a{i}]")
        mix_labels.append(f"[a{i}]")
    if bgm_path:
        bi = len(audio) + 1
        filt.append(f"[{bi}:a]volume=0.30,aformat=sample_fmts=fltp:sample_rates=44100:channel_layouts=stereo[abgm]")
        mix_labels.append("[abgm]")
    filt.append("".join(mix_labels) + f"amix=inputs={len(mix_labels)}:duration=longest:normalize=0[aout]")

    cmd += ["-filter_complex", ";".join(filt), "-map", "0:v", "-map", "[aout]",
            "-c:v", "libx264", "-preset", "medium", "-crf", "19",
            "-pix_fmt", "yuv420p", "-r", str(FPS), "-t", f"{total:.3f}",
            "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart", str(out_path)]

    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        for f in range(n_frames):
            t = f / FPS
            seg = 0
            for i, st in enumerate(seg_starts):
                if t >= st:
                    seg = i
            st = seg_starts[seg]
            img = bg.copy()
            for lay in layers_by_seg[seg]:
                lay.render(img, t - st)
            draw_chrome(img, t)
            try:
                proc.stdin.write(img.convert("RGB").tobytes())
            except BrokenPipeError:
                break
            if not quiet and f % 150 == 0:
                print(f"  渲染 {f}/{n_frames} 帧", flush=True)
    finally:
        try:
            proc.stdin.close()
        except BrokenPipeError:
            pass
        err = proc.stderr.read().decode()
        code = proc.wait()
    if code != 0:
        print(err[-4000:], file=sys.stderr)
        raise SystemExit(f"ffmpeg 合成失败，退出码 {code}")
    return total


# ---------------------------------------------------------------- 主流程

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("episode_json")
    ap.add_argument("--out", default=None)
    ap.add_argument("--no-bgm", action="store_true")
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    cfg = json.loads(Path(args.episode_json).read_text(encoding="utf-8"))
    ep = cfg["episode"]
    work = TMP_DIR / ep
    (work / "audio").mkdir(parents=True, exist_ok=True)

    print(f"· 生成 {ep} 《{cfg['series']}》 词根 {cfg['root']} = {cfg['root_cn']}")

    # 1. 逐段准备音频。时间轴以语音为准：先让单词发音读完，中文讲解再进来。
    seg_starts, acc = [], 0.0
    for s in cfg["segments"]:
        seg_starts.append(acc)
        acc += s["dur"]
    total = acc

    audio = []
    sfx_map = {"hook": "magic.mp3", "word": "bubble-pop.wav", "outro": "stamp.mp3"}
    for si, s in enumerate(cfg["segments"]):
        t0 = seg_starts[si]
        seg_end = t0 + s["dur"]
        kind = s["type"]
        clips = []
        if kind == "word":
            p = fetch_word_audio(s["word"], work / "audio" / f"{s['word']}.mp3")
            clips.append({"path": p, "at": t0 + 0.30, "gain": 1.0})
            tts_at = max(1.85, 0.30 + duration_of(p) + 0.20)
        else:
            tts_at = 0.35
        tts = fetch_tts(s["say"], work / "audio", f"{ep}_{si}_{kind}")
        clips.append({"path": tts, "at": t0 + tts_at, "gain": 1.0})
        sfx = SFX_DIR / sfx_map[kind]
        if sfx.exists():
            clips.append({"path": sfx, "at": t0 + 0.05, "gain": 0.30})

        # 失败即暴露：任何音频超出本段（或全集）时长都直接报错，不静默截断
        for c in clips:
            end = c["at"] + duration_of(c["path"])
            if end > min(seg_end, total) + 0.02:
                raise SystemExit(
                    f"第 {si + 1} 段（{kind}）音频超时：{c['path'].name} 于 "
                    f"{c['at']:.2f}s 起播、{end:.2f}s 结束，超出段落结束 {seg_end:.2f}s。"
                    f"请缩短文案或增大该段 dur。")
        audio.extend(clips)

    # 2. BGM
    bgm = None
    if not args.no_bgm:
        bgm = synth_bgm(work / "bgm.wav", total + 0.5)
        print(f"· BGM 合成完成 {duration_of(bgm):.1f}s")

    # 3. 渲染合成
    out = Path(args.out) if args.out else OUT_DIR / f"{ep}_{cfg['root']}.mp4"
    out.parent.mkdir(parents=True, exist_ok=True)
    dur = render_episode(cfg, audio, out, bgm, quiet=args.quiet)
    print(f"✅ 成片 {out}  时长 {dur:.1f}s  大小 {out.stat().st_size/1024/1024:.1f}MB")


if __name__ == "__main__":
    main()
