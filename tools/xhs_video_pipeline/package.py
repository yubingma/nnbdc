#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
本地「竖屏营销视频」包装模块（纯 ffmpeg + PIL，不依赖 Wan3.0 / drawtext）。

把一段源视频包装成 9:16 竖屏成片：
  - 背景：源视频放大 + 高斯模糊 + 压暗，铺满画布
  - 前景：源视频按原比例缩放，居中悬浮于模糊背景（"卡片"感）
  - 花字：用 PIL 渲染中文主/副标题贴片 PNG，overlay 叠加（弥补 ffmpeg 无 drawtext）
  - 可选 BGM：淡入淡出后与原声混合
  - 时长：裁剪到目标秒数

依赖：ffmpeg、ffprobe、PIL(Pillow)、macOS 系统自带中文字体。

用法：
  python3 package.py --input /tmp/src.mp4 --out /tmp/out.mp4 \
      --title "背单词 · 100天计划" --subtitle "一个APP搞定" --bgm /tmp/bgm.mp3
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile

W = 1080
H = 1920
FPS = 30
CJK_FONTS = [
    "/System/Library/Fonts/Arial Unicode.ttf",
    "/System/Library/Fonts/Hiragino Sans GB.ttc",
    "/System/Library/Fonts/STHeiti Medium.ttc",
]


def which(cmd):
    p = shutil.which(cmd)
    if not p:
        raise RuntimeError(f"找不到可执行文件 {cmd}，请确认已安装 ffmpeg/ffprobe")
    return p


def run(cmd):
    proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if proc.returncode != 0:
        err = proc.stderr.decode("utf-8", "replace").strip()
        raise RuntimeError(f"ffmpeg 失败 (code {proc.returncode}):\n{err}")
    return proc


def ffprobe_meta(path):
    """返回 {dur, w, h, fps, has_audio}。"""
    out = run([which("ffprobe"), "-v", "error", "-print_format", "json",
               "-show_format", "-show_streams", path]).stdout.decode("utf-8")
    d = json.loads(out)
    streams = d.get("streams", [])
    vs = [s for s in streams if s.get("codec_type") == "video"]
    if not vs:
        raise ValueError(f"输入无视频流: {path}")
    v = vs[0]
    duration = float(d.get("format", {}).get("duration") or v.get("duration") or 0)
    fps = 0.0
    fr = v.get("avg_frame_rate") or v.get("r_frame_rate") or ""
    if "/" in fr:
        num, den = fr.split("/")
        try:
            fps = float(num) / float(den)
        except ZeroDivisionError:
            fps = 0.0
    has_audio = any(s.get("codec_type") == "audio" for s in streams)
    return {"dur": duration, "w": int(v["width"]), "h": int(v["height"]),
            "fps": fps or FPS, "has_audio": has_audio}


def pick_font(size):
    from PIL import ImageFont
    for path in CJK_FONTS:
        if os.path.exists(path):
            try:
                for index in range(3):
                    try:
                        ImageFont.truetype(path, size=size, index=index)
                        return (path, index)
                    except Exception:
                        continue
                return (path, 0)
            except Exception:
                continue
    raise RuntimeError("未找到可用中文字体")


def make_text_card(text, font_size, fill, stroke, padding=40):
    from PIL import Image, ImageDraw, ImageFont
    font_path, font_index = pick_font(font_size)
    font = ImageFont.truetype(font_path, size=font_size, index=font_index)
    probe = Image.new("RGBA", (1, 1))
    d = ImageDraw.Draw(probe)
    bbox = d.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    tw = max(tw, 40)
    th = max(th, font_size)
    img = Image.new("RGBA", (tw + padding * 2, th + padding * 2), (0, 0, 0, 0))
    dr = ImageDraw.Draw(img)
    dr.text((padding - bbox[0], padding - bbox[1]), text, font=font,
            fill=fill, stroke_width=2, stroke_fill=stroke)
    return img


def render_overlay(title, subtitle, width):
    """渲染主/副标题贴片（带半透明圆角衬底），返回 PNG 路径。None 表示无花字。

    衬底是深色半透明圆角条，让花字在任何画面上都清晰可读，不至于和界面内容混在一起。
    """
    if not title and not subtitle:
        return None
    from PIL import Image, ImageDraw
    main = make_text_card(title, 84, (255, 255, 255, 255), (0, 0, 0, 180)) if title else None
    sub = make_text_card(subtitle, 52, (255, 235, 200, 255), (0, 0, 0, 150)) if subtitle else None
    parts = [p for p in (main, sub) if p]
    if not parts:
        return None
    pad = 60
    gap = 36
    inner_w = max(p.width for p in parts)
    inner_h = sum(p.height for p in parts) + gap * (len(parts) - 1)
    w2 = min(inner_w + pad * 2, width)
    h2 = inner_h + pad * 2
    canvas = Image.new("RGBA", (w2, h2), (0, 0, 0, 0))
    dr = ImageDraw.Draw(canvas)
    dr.rounded_rectangle([0, 0, w2 - 1, h2 - 1], radius=42, fill=(0, 0, 0, 168))
    y = pad
    for p in parts:
        pw, ph = p.size
        if pw > w2 - pad * 2:
            p = p.resize((w2 - pad * 2, int(ph * (w2 - pad * 2) / pw)))
        canvas.alpha_composite(p, dest=((w2 - p.width) // 2, y))
        y += p.height + gap
    fd, path = tempfile.mkstemp(suffix=".png")
    os.close(fd)
    canvas.save(path)
    return path


def compute_layout(src_w, src_h, canvas_w, canvas_h, card_h_ratio, margin_x):
    avail_h = int(canvas_h * card_h_ratio)
    card_h = avail_h
    card_w = int(card_h * (src_w / src_h))
    if card_w > canvas_w - margin_x * 2:
        card_w = canvas_w - margin_x * 2
        card_h = int(card_w * (src_h / src_w))
    x = (canvas_w - card_w) // 2
    y = (canvas_h - card_h) // 2
    return card_w, card_h, x, y


def main(argv=None):
    ap = argparse.ArgumentParser(description="竖屏营销视频包装")
    ap.add_argument("--input", required=True, help="源视频文件")
    ap.add_argument("--out", required=True, help="输出 mp4 路径")
    ap.add_argument("--duration", type=int, default=15)
    ap.add_argument("--title", default=None)
    ap.add_argument("--subtitle", default=None)
    ap.add_argument("--bgm", default=None, help="背景音乐文件")
    ap.add_argument("--music-volume", type=float, default=0.9)
    ap.add_argument("--card-h-ratio", type=float, default=0.9)
    ap.add_argument("--margin-x", type=int, default=150)
    ap.add_argument("--blur", type=int, default=28)
    ap.add_argument("--brightness", type=float, default=-0.10)
    ap.add_argument("--saturation", type=float, default=1.06)
    ap.add_argument("--width", type=int, default=W)
    ap.add_argument("--height", type=int, default=H)
    ap.add_argument("--no-title", action="store_true")
    ap.add_argument("--fps", type=int, default=FPS)
    args = ap.parse_args(argv)

    ffmpeg = which("ffmpeg")

    src = ffprobe_meta(args.input)
    cw, ch, xoff, yoff = compute_layout(
        src["w"], src["h"], args.width, args.height, args.card_h_ratio, args.margin_x)

    # 输入列表 & 索引
    inputs = [args.input]
    idx = {"src": 0}
    title_png = None
    if not args.no_title and (args.title or args.subtitle):
        title_png = render_overlay(args.title, args.subtitle, args.width)
        inputs.append(title_png)
        idx["title"] = len(inputs) - 1
    has_bgm = bool(args.bgm)
    if has_bgm:
        inputs.append(args.bgm)
        idx["bgm"] = len(inputs) - 1

    # ---- filter_complex ----
    fc = []
    # 视频链
    fc.append(
        f"[{idx['src']}:v]split=2[bg_in][fg_in];"
        f"[bg_in]scale={args.width}:{args.height}:force_original_aspect_ratio=increase,"
        f"crop={args.width}:{args.height},gblur=sigma={args.blur},"
        f"eq=brightness={args.brightness}:saturation={args.saturation}[bg];"
        f"[fg_in]scale={cw}:{ch}:force_original_aspect_ratio=decrease[fg0];"
        f"[bg][fg0]overlay=x={xoff}:y={yoff}[vbase]"
    )
    vout = "[vbase]"
    if title_png:
        fc.append(f"[vbase][{idx['title']}:v]overlay=x=(W-w)/2:y=88[vt]")
        vout = "[vt]"

    # 音频输出决定：bgm → [aout]；源有音频 → 直接 map；否则补静音轨 anullsrc
    anull_index = None
    if has_bgm:
        fc.append(
            f"[{idx['bgm']}:a]aformat=sample_rates=44100:channel_layouts=stereo,"
            f"volume={args.music_volume},afade=t=in:d=0.8,"
            f"afade=t=out:st={args.duration - 1.0}:d=1.0[bgm_a]"
        )
        if src["has_audio"]:
            fc.append(f"[{idx['src']}:a]aformat=sample_rates=44100:channel_layouts=stereo[src_a]")
            fc.append("[src_a][bgm_a]amix=inputs=2:duration=first[aout]")
        else:
            fc.append("[bgm_a]anull[aout]")
        aout = "[aout]"
    elif src["has_audio"]:
        aout = f"{idx['src']}:a"
    else:
        anull_index = len(inputs)
        aout = f"{anull_index}:a"

    cmd = [ffmpeg, "-y"]
    for ip in inputs:
        cmd += ["-i", ip]
    if anull_index is not None:
        cmd += ["-f", "lavfi", "-i", "anullsrc=r=44100:cl=stereo"]
    cmd += ["-filter_complex", ";".join(fc)]
    cmd += ["-map", vout, "-map", aout]
    cmd += ["-t", str(args.duration), "-r", str(args.fps)]
    cmd += ["-c:v", "libx264", "-crf", "20", "-pix_fmt", "yuv420p"]
    cmd += ["-c:a", "aac", "-b:a", "192k"]
    cmd += ["-movflags", "+faststart", args.out]

    print("执行:", " ".join(cmd))
    run(cmd)
    print("完成:", args.out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
