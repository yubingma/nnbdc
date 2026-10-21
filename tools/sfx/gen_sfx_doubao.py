#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
用「豆包音频生成模型 1.0」生成「打哭小馋怪」的音效

为什么换成大模型：
  原先用双二阶滤波 + 共振峰自己合成，撞击与气声那类"物理声"还凑合，
  但**哭声**要的是"可爱"这种带情绪的音色，合成器做出来是一段电子哨音。
  豆包音频生成模型支持纯文本模式——text_prompt 直接描述想生成的音频，
  官方用途里明确列了 sound effects。

接口（对齐官方文档 https://www.volcengine.com/docs/6561/2550782）：
  POST https://openspeech.bytedance.com/api/v3/tts/create
  Header: X-Api-Key: <API Key>            ← 唯一的鉴权要素
          X-Api-App-Id: <App ID>          ← 应用标识，不是鉴权要素，可省
  Body:   {"model":"seed-audio-1.0", "text_prompt":"…",
           "audio_config":{"format":"wav","sample_rate":44100, ...}}

凭据（放在 ~/.zprofile）：
  DOUBAO_AUDIO_API_KEY   必填，豆包语音控制台的 API Key
  DOUBAO_APP_ID          选填

用法：
  # 每类音效生成 3 个候选，落到 tmp/sfx_candidates/ 供试听挑选
  python3 tools/sfx/gen_sfx_doubao.py

  # 只生成某一类
  python3 tools/sfx/gen_sfx_doubao.py --only cry_whimper

  # 把某个候选定为正式资源（会转成 44.1kHz 单声道 16bit PCM 并裁掉静音）
  python3 tools/sfx/gen_sfx_doubao.py --adopt cry_whimper:2

设计约定：
  * 候选一律先落 tmp/，只有 --adopt 之后才进 app/assets/audio/monster/，
    避免把没挑过的半成品混进正式资源。
  * 统一转成 44.1kHz 单声道 16bit PCM——与 app/test/monster_sfx_test.dart 的约定一致，
    也是跨 iOS/Android 最稳的编码（项目里已有 correct_ios.wav 的分叉说明 iOS 对编码敏感）。
"""

import argparse
import base64
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
import wave

import numpy as np

ENDPOINT = 'https://openspeech.bytedance.com/api/v3/tts/create'
MODEL = 'seed-audio-1.0'

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CANDIDATE_DIR = os.path.join(ROOT, 'tmp', 'sfx_candidates')
ASSET_DIR = os.path.join(ROOT, 'app', 'assets', 'audio', 'monster')

# 每类音效的提示词。纯文本模式下 text_prompt 就是"描述想生成的声音"，
# 所以要写**声音本身**（音色、情绪、长度、风格），不要写成一句台词。
SOUNDS = {
    'throw_whoosh': (
        '一声轻快短促的投掷呼啸声：小东西被用力扔出去划破空气的"咻"声，'
        '音调由低快速上扬再收住，卡通动画风格，干净利落，约零点三秒，无背景音'
    ),
    'hit_bonk': (
        '一声卡通风格的闷响撞击声：软软的小怪物脑袋被坚果砸中的"咚"，'
        '带一点木质敲击的脆头，低音短促可爱，约零点二秒，无背景音'
    ),
    # 注意：哭声提示词里严禁出现任何拟声汉字（如“哇呜”“嗷呜”“咿呀”），
    # 一旦带拟声字，模型会切入语音朗读模式把汉字念出来，而不是生成非语言哭泣声。
    'cry_whimper': (
        '搞笑动画片里圆滚滚的小馋怪被坚果砸中脑袋后一声极具喜感的戏剧化瘪嘴哭泣声，'
        '先急促抽泣两下再音调夸张滑落，带着委屈不服气的滑稽哭腔抖动，'
        '圆润饱满不刺耳，纯哭泣发声不要说任何字词；'
        '总时长半秒以内，只有一声短的，不要重复，无背景音'
    ),
    'flee_step': (
        '一声轻快的卡通脚步声：小脚踩在木桥板上的一下"嗒"，'
        '干脆短促、低频有分量，约零点一秒，无背景音'
    ),
}


def load_credentials():
    key = (os.environ.get('DOUBAO_AUDIO_API_KEY') or '').strip()
    app_id = (os.environ.get('DOUBAO_APP_ID') or '').strip()
    if not key:
        sys.exit(
            '缺少 DOUBAO_AUDIO_API_KEY。\n'
            '请到火山引擎控制台 → 语音技术 → 音频生成，创建应用后拿到 API Key，\n'
            '然后执行：export DOUBAO_AUDIO_API_KEY=...\n'
            '（写在 ~/.zprofile 里更省事，与 VOLC_API_KEY 放一起）'
        )
    return key, app_id


def request_audio(prompt, api_key, app_id, fmt='wav', sample_rate=44100,
                  pitch_rate=0, speech_rate=0, timeout=180, speaker=None):
    body = {
        'model': MODEL,
        'text_prompt': prompt,
        'audio_config': {
            'format': fmt,
            'sample_rate': sample_rate,
            'pitch_rate': pitch_rate,
            'speech_rate': speech_rate,
        },
    }
    if speaker:
        # 传 speaker 就是「参考音频生成」模式：用这个真人音色的嗓子，按 text_prompt 的描述发声。
        # 童声（如 奶气萌娃 zh_male_naiqimengwa_uranus_bigtts）比让模型凭空造一个嗓子像人得多。
        body['references'] = [{'speaker': speaker}]
    headers = {'Content-Type': 'application/json', 'X-Api-Key': api_key}
    if app_id:
        headers['X-Api-App-Id'] = app_id
    req = urllib.request.Request(ENDPOINT, data=json.dumps(body).encode('utf-8'),
                                 headers=headers, method='POST')
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            payload = json.loads(resp.read().decode('utf-8'))
            log_id = resp.headers.get('X-Tt-Logid')
    except urllib.error.HTTPError as e:
        detail = e.read().decode('utf-8', 'replace')[:600]
        sys.exit(f'HTTP {e.code}：{detail}')

    code = payload.get('code')
    if code not in (0, None):
        sys.exit(f'接口返回错误 code={code} message={payload.get("message")!r} '
                 f'(log_id={payload.get("log_id") or log_id})')
    if payload.get('audio'):
        return base64.b64decode(payload['audio']), payload.get('duration')
    if payload.get('url'):
        with urllib.request.urlopen(payload['url'], timeout=timeout) as r:
            return r.read(), payload.get('duration')
    sys.exit(f'响应里既没有 audio 也没有 url：{json.dumps(payload)[:400]}')


def to_asset(src_path, dst_path, max_seconds, peak_target=0.5, pad_ms=8.0):
    """转成项目约定的 44.1kHz 单声道 16bit PCM，裁掉首尾静音并做**静态**峰值归一。

    这里刻意不用 ffmpeg 的 silenceremove + loudnorm，两个原因都是实测出来的：

    * `silenceremove` 会把**柔和的起音一起裁掉**。拿自己合成的呜咽试过：
      780ms 在 -45dB 阈值下只剩 562ms，调到 -60dB 仍有 206ms 被吃掉——
      因为哭声本来就是缓起的。裁剪必须可控可审计，所以改用 numpy 显式裁，
      并把"裁掉了多少"打出来，而不是丢给一个黑盒滤波器。
    * `loudnorm` 是**动态**归一，对不到一秒的短音效会抽气。短音效用静态峰值归一即可。

    峰值目标为什么是 0.5（-6dBFS）而不是 0.9（-1dBFS）：
      游戏里四类音效各有独立播放器，会**同时发声**，播放层的音量加起来最大到 1.5 上下，
      若素材本身贴着满刻度，混音结果就冲到 1.5 倍满刻度——必然削波失真。
      实测过：素材归一化到 0.90 时，单是「哭声 + 命中」同时响就有 1.20。
      留 -6dB 余量后，最坏情况 0.5 × 1.5 = 0.75，还有约 2.5dB 富余。
    """
    raw = subprocess.run(
        ['ffmpeg', '-y', '-loglevel', 'error', '-i', src_path,
         '-f', 's16le', '-acodec', 'pcm_s16le', '-ac', '1', '-ar', '44100', '-'],
        check=True, capture_output=True).stdout
    x = np.frombuffer(raw, dtype='<i2').astype(np.float64) / 32768.0
    if x.size == 0:
        sys.exit(f'{src_path} 解出来是空的')
    original_ms = x.size / 44100 * 1000

    # 静音判据：低于峰值的 1%（约 -40dB）且低于绝对底噪，才算静音。
    # 用「相对峰值」而不是固定 dB，是为了不被模型输出的整体音量大小影响。
    peak = float(np.max(np.abs(x)))
    gate = max(peak * 0.01, 1e-4)
    loud = np.where(np.abs(x) > gate)[0]
    if loud.size == 0:
        sys.exit(f'{src_path} 整段都低于静音阈值，等于没有声音')
    pad = int(44100 * pad_ms / 1000)
    lo = max(0, int(loud[0]) - pad)
    hi = min(x.size, int(loud[-1]) + pad + 1)
    capped = int(44100 * max_seconds)
    truncated = (hi - lo) > capped
    x = x[lo:hi][:capped]
    if truncated:
        # 被上限截断时必须淡出：模型经常无视提示词里的时长（要 0.2 秒给 2.5 秒），
        # 硬切会在结尾留下一声"咔"。15ms 淡出足够消掉它，又听不出音量变化。
        n = min(len(x), int(44100 * 0.015))
        x[-n:] *= np.linspace(1.0, 0.0, n)
    x = x * (peak_target / float(np.max(np.abs(x))))

    with wave.open(dst_path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(44100)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype('<i2').tobytes())
    tail = '，结尾已淡出（被上限截断）' if truncated else ''
    print(f'    裁静音 {original_ms:.0f} → {len(x)/44100*1000:.0f} ms'
          f'（首尾各留 {pad_ms:.0f} ms）{tail}，峰值归一到 {peak_target}')


def probe_duration(path):
    out = subprocess.run(
        ['ffprobe', '-v', 'error', '-show_entries', 'format=duration',
         '-of', 'csv=p=0', path], capture_output=True, text=True, check=True)
    return float(out.stdout.strip())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--only', help='只生成某一类音效')
    ap.add_argument('--candidates', type=int, default=3, help='每类生成几个候选')
    ap.add_argument('--adopt', help='把某个候选定为正式资源，格式 名称:序号（序号从 1 起）')
    ap.add_argument('--prompt', help='覆盖内置提示词（配合 --only 用来单独试某一版写法）')
    ap.add_argument('--tag', default='', help='候选文件名后缀，用来区分不同提示词版本')
    ap.add_argument('--speaker', help='音色 ID（豆包语音合成 2.0 的 *_uranus_bigtts），'
                                     '传入即为「参考音频生成」模式，用真人音色当嗓子')
    ap.add_argument('--max-seconds', type=float, default=1.2, help='成品最长时长')
    args = ap.parse_args()

    if args.adopt:
        name, idx = args.adopt.split(':')
        suffix = f'_{args.tag}' if args.tag else ''
        src = os.path.join(CANDIDATE_DIR, f'{name}{suffix}_{int(idx)}.wav')
        if not os.path.exists(src):
            sys.exit(f'找不到候选 {src}')
        os.makedirs(ASSET_DIR, exist_ok=True)
        dst = os.path.join(ASSET_DIR, f'{name}.wav')
        to_asset(src, dst, args.max_seconds)
        print(f'已采用 → {dst}  ({probe_duration(dst)*1000:.0f} ms, '
              f'{os.path.getsize(dst)/1024:.1f} KB)')
        return

    api_key, app_id = load_credentials()
    os.makedirs(CANDIDATE_DIR, exist_ok=True)
    names = [args.only] if args.only else list(SOUNDS)
    for name in names:
        if name not in SOUNDS:
            sys.exit(f'未知音效 {name}，可选：{", ".join(SOUNDS)}')
        prompt = args.prompt if args.prompt else SOUNDS[name]
        for i in range(1, args.candidates + 1):
            suffix = f'_{args.tag}' if args.tag else ''
            raw_path = os.path.join(CANDIDATE_DIR, f'{name}{suffix}_{i}_raw')
            out_path = os.path.join(CANDIDATE_DIR, f'{name}{suffix}_{i}.wav')
            data, duration = request_audio(prompt, api_key, app_id, speaker=args.speaker)
            with open(raw_path, 'wb') as f:
                f.write(data)
            to_asset(raw_path, out_path, args.max_seconds)
            os.remove(raw_path)
            print(f'  {os.path.basename(out_path)}  {probe_duration(out_path)*1000:5.0f} ms  '
                  f'{os.path.getsize(out_path)/1024:5.1f} KB  (接口报时长 {duration})')
    print(f'\n候选都在 {CANDIDATE_DIR}，挑好之后执行：')
    print(f'  python3 tools/sfx/gen_sfx_doubao.py --adopt <名称>:<序号>')


if __name__ == '__main__':
    main()
