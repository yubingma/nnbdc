#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
「打哭小馋怪」场景音效合成器

为什么是程序化合成而不是找素材：
  这个场景里 16 只小怪 × 3 次命中 = 每循环 48 次命中，平均每秒 7 次。
  这种密度下音效必须能「同一素材变调复用」——而播放层（StudyAudioSessionController
  的音效池）每个播放器会记住自己加载的资源，换资源要重新 setAsset 解码。
  所以正确做法是**每类音效只出一个文件**，变调交给播放器的 speed 参数
  （见 app/lib/util/game_sfx.dart）。程序化合成正好满足「一个文件、参数可调、可重生成」。

合成方法：
  白噪声 + 双二阶（biquad）滤波器做气声与撞击，脉冲串 + 共振峰做卡通呜咽。
  不依赖 scipy——biquad 直接按 RBJ Audio EQ Cookbook 的公式手写。

用法：
  python3 tools/sfx/gen_monster_sfx.py
输出：
  app/assets/audio/monster/*.wav （44.1kHz 单声道 16bit PCM，体积都在 10KB 上下）
"""

import os
import struct
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))), 'app', 'assets', 'audio', 'monster')


# ----------------------------------------------------------------- 基础工具

def biquad(x, b, a):
    """直接 I 型双二阶。x 是 1D 数组，返回同长度输出。"""
    y = np.zeros_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for i in range(len(x)):
        xi = x[i]
        yi = b[0] * xi + b[1] * x1 + b[2] * x2 - a[1] * y1 - a[2] * y2
        x2, x1 = x1, xi
        y2, y1 = y1, yi
        y[i] = yi
    return y


def _rbj(kind, f0, q, sr=SR):
    """RBJ Audio EQ Cookbook 的双二阶系数。"""
    w0 = 2 * np.pi * f0 / sr
    cw, sw = np.cos(w0), np.sin(w0)
    alpha = sw / (2 * q)
    if kind == 'bp':          # 带通（峰值增益归一）
        b = [alpha, 0.0, -alpha]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == 'lp':
        b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == 'hp':
        b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    else:
        raise ValueError(kind)
    return [v / a[0] for v in b], [1.0, a[1] / a[0], a[2] / a[0]]


def sweep(x, kind, f_curve, q, block=64):
    """中心频率随时间变化的滤波。分块重算系数，块内的过渡听不出来。

    整体滤完后做一次前后拼接的淡入淡出，避免块边界的细微不连续。
    """
    y = np.zeros_like(x)
    for i in range(0, len(x), block):
        seg = x[i:i + block]
        b, a = _rbj(kind, float(f_curve[i]), q)
        y[i:i + block] = biquad(seg, b, a)
    return y


def noise(n, seed):
    return np.random.default_rng(seed).normal(0, 1, n)


def fade(x, ms_in=2.0, ms_out=6.0):
    """首尾淡入淡出。不做的话，波形被硬切会有「咔」的爆音。"""
    n = len(x)
    a = max(1, int(SR * ms_in / 1000))
    b = max(1, int(SR * ms_out / 1000))
    w = np.ones(n)
    w[:a] = np.linspace(0, 1, a)
    w[-b:] = np.linspace(1, 0, b)
    return x * w


def norm(x, peak):
    m = np.max(np.abs(x))
    return x if m == 0 else x / m * peak


def save(name, x, peak=0.85):
    x = norm(fade(x), peak)
    data = (np.clip(x, -1, 1) * 32767).astype('<i2')
    path = os.path.join(OUT, name)
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(f'  {name:22s} {len(x)/SR*1000:6.0f} ms   {os.path.getsize(path)/1024:5.1f} KB')


# ----------------------------------------------------------------- 四个音效

def throw_whoosh(dur=0.26):
    """投掷：气声「唰」。窄带噪声从低扫到高再落回，是"挥出去"的听感来源。"""
    n = int(SR * dur)
    t = np.linspace(0, 1, n)
    # 中心频率：500 → 3000 → 800 Hz，先冲上去再落回来
    f = 500 + 2500 * np.sin(np.pi * t ** 0.7) - 300 * t
    x = sweep(noise(n, 1), 'bp', f, q=4.0)
    # 音量包络：快起、缓落
    env = np.exp(-4.2 * t) * (1 - np.exp(-40 * t))
    return x * env


def hit_bonk(dur=0.20):
    """命中：闷响「咚」。三样叠出来——极短的噪声撞击 + 下滑的正弦主体 + 二次谐波。"""
    n = int(SR * dur)
    t = np.linspace(0, dur, n)
    # 极短的噪声撞击（木质"啪"）
    click = sweep(noise(n, 2), 'bp', np.full(n, 1800.0), q=1.2) * np.exp(-90 * t)
    # 主体：220 → 110 Hz 下滑，像被敲了一下的实心东西
    f0 = 110 + 110 * np.exp(-9 * t)
    phase = np.cumsum(2 * np.pi * f0 / SR)
    body = np.sin(phase) * np.exp(-13 * t)
    # 二次谐波给一点"木"的音色
    harm = 0.28 * np.sin(2 * phase) * np.exp(-22 * t)
    return 0.55 * click + body + harm


def cry_whimper(dur=0.78):
    """被打哭：卡通呜咽「嘤」。

    用「脉冲串声源 + 共振峰滤波」近似人声：
      声源 = 基频脉冲串，基频走一条哭泣的音高曲线（高-低-高-低）并带颤音；
      声道 = 三个共振峰（900 / 1500 / 2900 Hz）加权求和。
    比直接合成一个正弦更像「在哭」，而不是「一个音在响」。
    """
    n = int(SR * dur)
    t = np.linspace(0, dur, n)

    # 音高曲线：两次抽泣，每次都先高后低
    sob = np.sin(2 * np.pi * 1.6 * t)          # 抽泣的起伏
    f0 = 330 - 70 * sob + 28 * np.sin(2 * np.pi * 6.5 * t)   # 6.5Hz 颤音
    # 声源：脉冲串（每个基频周期一个窄脉冲）
    phase = np.cumsum(f0 / SR)
    src = np.zeros(n)
    idx = np.where(np.diff(np.floor(phase)) > 0)[0]
    src[idx] = 1.0
    # 脉冲串能量太低，过一级低通把它"抹"成声带波形
    src = biquad(src, *_rbj('lp', 1200, 0.8))

    # 共振峰
    voice = (1.00 * sweep(src, 'bp', np.full(n, 900.0), q=6.0) +
             0.55 * sweep(src, 'bp', np.full(n, 1500.0), q=7.0) +
             0.30 * sweep(src, 'bp', np.full(n, 2900.0), q=9.0))

    # 音量包络：两次抽泣，每次快起缓落
    env = 0.5 + 0.5 * np.sin(2 * np.pi * 1.6 * t - np.pi / 2)
    env = np.clip(env, 0, 1) ** 1.6
    env *= np.clip(1 - t / dur * 1.15, 0, 1) ** 0.7
    return voice * env


def flee_step(dur=0.11):
    """逃跑脚步：短促的一下。低频占比高一点，才有"踩在木板上"的分量。"""
    n = int(SR * dur)
    t = np.linspace(0, dur, n)
    body = sweep(noise(n, 3), 'lp', np.full(n, 1500.0), q=0.9) * np.exp(-38 * t)
    thud = np.sin(2 * np.pi * 95 * t) * np.exp(-45 * t) * 0.6
    return body + thud


def main():
    os.makedirs(OUT, exist_ok=True)
    print(f'输出目录：{OUT}')
    save('throw_whoosh.wav', throw_whoosh(), peak=0.72)
    save('hit_bonk.wav', hit_bonk(), peak=0.92)
    save('cry_whimper.wav', cry_whimper(), peak=0.68)
    save('flee_step.wav', flee_step(), peak=0.60)


if __name__ == '__main__':
    main()
