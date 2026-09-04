---
name: xhs-video-pipeline
description: 用通义万相 Wan3.0（图/文生视频）+ 本地 ffmpeg 包装，把 App 操作录屏或界面截图制作成小红书竖屏(9:16)营销短视频（≤15s，含花字/调色/BGM/模糊背景卡片）。当需要为 App 产出小红书营销视频、把粗略录屏美化提质感、用 UI 截图生成宣传片、批量制作竖屏种草视频时使用。
whenToUse: 用户提到"做小红书视频"、"把录屏做成营销片"、"生成的视频没质感"、"用 App 界面图出宣传片"、"调用万相/万象3.0生成视频"等情况。
---

# 小红书营销视频管线（Wan3.0 + 本地包装）

## 0. 一句话定位

> 核心是「**真实素材为主 + AI 提质感 + 本地包装**」。先用 Wan3.0 把粗糙录屏 / UI 截图渲染出高级质感画面（图生视频/参考生视频），再用本地 ffmpeg 管线做成 9:16 竖屏成片（模糊背景、居中卡片、调色、花字、BGM、卡 15s）。**不要依赖生成模型直接"重绘"整条 UI 演示**——Wan3.0 仍有文字/品牌标识漂移，核心功能展示必须人工复核或保留真实画面。

## 1. 两条链路

| 链路 | 做什么 | 是否扣费 | 何时用 |
|---|---|---|---|
| **A. 纯本地包装**（保真） | 真实录屏 / UI 截图 → `package.py` 竖屏装载+调色+花字+BGM | 否 | 信息不可丢、要可信的功能演示 |
| **B. Wan3.0 提质感**（出效果） | 一/多张 UI 图 `first_frame` 图生视频，或录屏 `reference_video` 编辑 → 一段高档竖屏镜头 | 是 | 片头/氛围/B-roll、把静态界面变动态、提质感 |

推荐组合：**B 生成氛围/片头镜头 + A 装载真实功能录屏**，再统一 `package.py` 输出。也可纯 B（纯生成）或纯 A（纯保真）。

## 2. 输入素材

- **真实录屏**：App 操作 mp4/mov，横竖皆可，≤15s（Wan3.0 参考视频总时长≤15s，且"输入参考+输出"≤30s）。
- **界面截图**：`design/ui/png/*.png`（920×1880 竖屏），或任意 PNG/JPG（单边 240–8000px、≤20MB、长宽比≤8:1、不支持透明通道）。
- **BGM**：mp3/wav，`package.py --bgm` 自动淡入淡出混合。

## 3. Wan3.0 接入（已验证）

### 3.1 前置
- API Key：`~/.zprofile` 里的 `dashscope_api_key`（本脚本自动读取，**不回显**）。
- **Wan3.0 处于邀测阶段**：本项目的 key 已具备权限（实测 `wan3.0-video` 提交被受理，返回 `task_id`）。若无权限会报"模型不存在/无权限"。
- 地域一致性：Key、Endpoint、模型须同地域。老 DashScope endpoint（默认）已验证可直接路由。

### 3.2 Endpoint
```text
老 DashScope（默认，无需 workspace id）:
  POST https://dashscope.aliyuncs.com/api/v1/services/aigc/video-generation/video-synthesis
  查询 GET  https://dashscope.aliyuncs.com/api/v1/tasks/{task_id}

官方北京（百炼, 需业务空间 id）:
  POST https://{WorkspaceId}.cn-beijing.maas.aliyuncs.com/api/v1/services/aigc/video-generation/video-synthesis
```
- 必需 Header：`Authorization: Bearer <key>`、`Content-Type: application/json`、`X-DashScope-Async: enable`（缺失会报"不支持的同步调用"）。
- 异步：先提交拿 `task_id`，再轮询 `GET /tasks/{id}`（间隔 ≥15s，RPS 默认 20）。

### 3.3 请求体（`wan3.py` 已封装）
```json
{
  "model": "wan3.0-video",
  "input": {
    "prompt": "...",
    "media": [ {"type": "first_frame", "url": "data:image/png;base64,...."} ]
  },
  "parameters": {
    "resolution": "720P",
    "ratio": "9:16",
    "duration": 10,
    "prompt_extend": true,
    "audio": true,
    "watermark": false,
    "seed": -1
  }
}
```
- **图生视频**：`type: first_frame`（严格作首帧，≤1 张）或 `first_frame+last_frame`；`ratio` 建议 `adaptive`（自动匹配首帧比例）或 `9:16`。
- **参考生视频**：`type: reference_image|reference_video|reference_audio|file|link`，可组合；prompt 里用"图1/视频1/音频1"指代素材顺序。
- **图片可 base64 直传**（`url` 填 `data:image/...;base64,...`），本地截图无需公网/OSS。
- `model`：`wan3.0-video-prime`（高速版，能力对齐标准版）。
- `duration`：无视频输入时 [2,30]，默认 5；传 `-1` 智能推荐。
- `task_id` 与成片链接均 **24h 有效**，拿到 `video_url` 必须立即下载转存。

### 3.4 计费（华北2 北京，元/秒）
| 分辨率 | 单价 | 15s | 10s |
|---|---|---|---|
| 480P | 0.30 | 4.5 | 3.0 |
| 720P | 0.60 | 9.0 | 6.0 |
| 1080P | 1.20 | 18 | 12 |

> 原型验证先用 **480P/720P + 短时长**；确认效果再上 1080P。任务成功后才计费；创建任务后若在 PENDING 可取消（RUNNING 后不可）。

### 3.5 实测结果与边界（2026-09，用本项目 UI 截图实测）

- 图生视频：用 `design/ui/png/study_preview.png`（920×1880）做 `first_frame`，`--resolution 480P --ratio adaptive --duration 10`，输出 **442×902（自适应）**、10s、h264+aac，cost≈3 元。
- 质感：生成画面自带**深色真机壳 + 暖色场景虚化 + 推近/环绕运镜**，明显优于本地 zoompan 占位；**首帧文字基本正确**。
- **文字漂移（确认存在）**：镜头推进/旋转后，UI 内英文正文出现乱码——例：首帧 "The manager gave a brief summary of the project." → 后段变 "The m ojerooct banach skarybte imeoet he we inat."。即**第 1 帧稳、运镜后不稳**。
- **应对**：核心信息/文案/品牌 logo **不要**依赖生成画面。建议——① Wan3.0 只用于氛围/首帧/B-roll，关键功能画面用真实截图或录屏；② 或在 prompt 里强调"screenshot 界面文字保持原样、不要改写"，并抽帧逐段复核；③ 对文字区域后期叠加真实截图盖住。

## 4. 本地包装脚本 `tools/xhs_video_pipeline/package.py`

### 4.1 依赖
`ffmpeg`、`ffprobe`、`PIL(Pillow)`、macOS 系统自带中文字体（本机 `Arial Unicode.ttf` / `Hiragino Sans GB.ttc`）。**本机 ffmpeg 无 drawtext**，花字用 PIL 渲染成 PNG 再 overlay。

### 4.2 用法
```bash
python3 tools/xhs_video_pipeline/package.py \
  --input /tmp/src.mp4 --out design/ui/video/xhs_demo_15s.mp4 --duration 15 \
  --title "背单词 · 每天10分钟" --subtitle "打卡坚持100天" --bgm /tmp/bgm.mp3
```
- 输出：9:16（默认 1080×1920）竖屏，模糊背景+居中卡片+顶部标题条+可选 BGM，固定 30fps、h264+aac。
- 只喂真实录屏可 `--no-title` 去掉花字。

### 4.3 常用参数
| 参数 | 默认 | 说明 |
|---|---|---|
| `--duration` | 15 | 输出时长（秒） |
| `--title` / `--subtitle` | — | 主/副标题（半透明圆角衬底） |
| `--bgm` / `--music-volume` | — / 0.9 | 背景音乐及音量 |
| `--card-h-ratio` | 0.9 | 前景卡片高/画布高 |
| `--margin-x` | 150 | 左右留白 |
| `--blur` / `--brightness` / `--saturation` | 28 / -0.10 / 1.06 | 背景模糊与调色 |
| `--width` / `--height` | 1080 / 1920 | 画布尺寸 |

- 若源不足时长，成片会短于 `--duration`（不补帧）。
- 无音频源且无 BGM 时，自动补一条静音轨（保证成片带音轨）。
- **FFmpeg 命令行注意**：所有 `-i` 输入必须放在 `-map`/编码选项**之前**，否则报"cannot be applied to input / Unknown decoder"混淆错误。

## 5. Wan3.0 生成脚本 `tools/xhs_video_pipeline/wan3.py`

```bash
python3 tools/xhs_video_pipeline/wan3.py \
  --prompt "..." --first-frame design/ui/png/study_preview.png \
  --duration 10 --resolution 720P --ratio 9:16 --out /tmp/wan3.mp4
```
- `--first-frame <本地图|URL>`：图生视频（本地图自动 base64）。
- `--media '{"type":"reference_image","url":"..."}'`：可多次，参考生视频。
- `--resolution 480P|720P|1080P`、`--duration`、`--ratio`、`--audio/--watermark/--prompt-extend/--seed`。
- 流程：提交 → 轮询(15s) → 下载，Key 从 `~/.zprofile` 读。

## 6. 完整工作流（建议）

1. **备料**：录屏（≤15s）与/或 UI 截图（`design/ui/png/`）。
2. **（可选，扣费）Wan3.0 提质感**：选 1 张最有代表性的图做 `first_frame`，`--ratio 9:16`，产出高档竖屏镜头；或把真实录屏作为 `reference_video` 做风格化（需公网/OSS URL）。
3. **（可选）拼源视频**：多张 UI 图先用 `zoompan` 各生成一段再 concat（见下方示例），作为 `package.py --input`。
4. **本地包装**：`package.py` 输出 9:16 成片到 `design/ui/video/`。
5. **人工复核**：Wan3.0 生成画面会文字错乱/品牌漂移，商用发布前必须人工核对 UI、文字、logo。

### 多图 → 源视频（zoompan + concat）
```bash
PNG=design/ui/png; mkdir -p /tmp/segs
for img in login_preview today_plan_preview study_preview; do
  ffmpeg -y -loglevel error -i "$PNG/$img.png" \
    -vf "zoompan=z='min(zoom+0.0007,1.15)':d=150:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s=720x1440:fps=30" \
    -t 5 -r 30 -pix_fmt yuv420p -c:v libx264 /tmp/segs/$img.mp4
done
printf "file '/tmp/segs/login_preview.mp4'\nfile '/tmp/segs/today_plan_preview.mp4'\nfile '/tmp/segs/study_preview.mp4'\n" >/tmp/segs/list.txt
ffmpeg -y -loglevel error -f concat -safe 0 -i /tmp/segs/list.txt -c copy /tmp/src15.mp4
```

## 7. 安全红线

- **不回显 / 不硬编码** `dashscope_api_key`（`~/.zprofile` 读取；脚本不会打印值）。
- Wan3.0 生成**会扣费**，触发前先向用户确认分辨率和时长。
- 生成视频链接 24h 失效，脚本/流程须立即下载转存到 `design/ui/video/`。
- 生成式画面可能含错误内容（文字、标识），商用发布前**人工复核**，不宜直接作为最终交付。
- 不改动生产库；本技能只产出视频素材，不触碰业务数据。

## 8. 语音 + 界面反馈 演示（"说出来 → 答对"）

> 需求：视频里加一段"模拟用户把单词/释义说出来"的语音，随后 App 给出正确答案反馈（像真实功能）。

做法（已实测跑通）：
1. **用户语音**：macOS `say`。`say -v Tingting "简短的" -o user.m4a --data-format=aac`。⚠️ 网络音色（`Flo`/`Sandy`/`Reed` 等 `zh_CN`）用 `say -o` 输出异常短（~0.14s），要用**本地音色** `Tingting`/`Meijia`（~0.75s）。
2. **待说态图**：`design/ui/png/study_preview.png`（"正在倾听 / 请说出中文释义"态）。
3. **答对态图**：本机 Chrome 无头在沙箱受限（`--headless` 报 sandbox/Crashpad 失败或挂起），**无法**用 `render_mockup_png.js` 渲染含 JS 的答对态。改用 **PIL 在待说态真机图上精准覆盖**：把"正在倾听…"改绿色"✓ 识别匹配成功！"、adj 槽填绿色"简短的"、n/v 衬提示灰字、底部"不认识"改"下一词 ➔"。另保留 `design/ui/study_correct_preview.html`（写死 `simulateSayBrief()` 结果的答对态 DOM），可在**正常 Chrome 环境**用 `node design/ui/render_mockup_png.js study_correct_preview.html --no-photos` 渲染像素级答对态图。
4. **合成**（ffmpeg）：`-loop 1 -t 2.5 -i 待说态 -loop 1 -t 4 -i 答对态 -i 语音`，`-filter_complex "[0:v]...[1:v]...[0v][1v]concat...[2:a]adelay=600,apad[aout]"`，`-t 6.5` 输出。

**关键取舍**：真实界面反馈**不能**直接叠加在 Wan3.0 生成画面上——生成画面是重绘的 UI 且文字漂移，与真实反馈不同层、不对齐。正确做法是把这条"真实功能演示"作为营销片里的**独立镜头/环节**，而不是 overlaying 到生成画面。

## 9. 已落盘文件

- `tools/xhs_video_pipeline/wan3.py` — Wan3.0 生成（提交/轮询/下载）。
- `tools/xhs_video_pipeline/package.py` — 本地竖屏包装（ffmpeg+PIL）。
- `design/ui/video/xhs_demo_15s.mp4` — 本地包装 demo（1080×1920, 15s）。
- `design/ui/video/xhs_demo_wan3_10s.mp4` — Wan3.0 生成 + 包装 demo（1080×1920, 10s）。
- `design/ui/video/speak_answer_demo.mp4` — "说出来→答对"功能演示（920×1880, 6.5s, 含语音）。
- `design/ui/video/speak_answer_demo_9x16.mp4` — 同上 9:16 统一版（1080×1920, 含标题）。
