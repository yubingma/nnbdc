#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
词根系列竖屏短视频生成器（小红书 9:16）

用法：
    python3 tools/xhs_video_pipeline/root_series.py tools/xhs_video_pipeline/episodes/ep01_spect.json

流程：读取单集脚本 JSON → 取发音与中文配音 → 合成 BGM → PIL 逐帧渲染 → ffmpeg 合成。
中间产物落在 tmp/xhs_root_series/<集号>/，成片输出到 design/ui/video/。
"""

import argparse
import json
from pathlib import Path

from PIL import ImageDraw

from xhs_common import (
    FONT_CN, FONT_CN_BOLD, FONT_CN_REG, FONT_EN, FONT_EN_NUM, FONT_IPA,
    FONT_LATIN, FONT_LATIN_MED, FPS, H, INK, INK_DIM, INK_FAINT, OUT_DIR,
    SFX_DIR, W, Layer, duration_of, encode_video, fetch_tts, fetch_word_audio,
    fit_font, font, hex2rgb, synth_bgm, teaser_chip, make_background,
)

ROOT_DIR = Path(__file__).resolve().parents[2]
TMP_DIR = ROOT_DIR / "tmp" / "xhs_root_series"


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

    def frames():
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
            yield img.convert("RGB").tobytes()

    encode_video(frames(), n_frames, total, audio, out_path, bgm_path, quiet=quiet)
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
