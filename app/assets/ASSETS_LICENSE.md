# 随身听场景媒体资源合规与开源许可声明 (Scene Assets License)

本项目随身听（Walkman）功能所使用的微动态背景视频及环境白噪音音频，均来自 100% 免版权争议的公共领域（Public Domain / CC0）或开源项目（MIT License）。

---

## 1. 音频资源 (Audio)

### `assets/audio/scenes/rain.mp3`（雨声）
- **来源项目**: [Moodist](https://github.com/remvze/moodist) (Ambient sounds for focus and calm)
- **原始文件**: `rain-on-window.mp3`
- **作者/项目方**: [Remvze](https://github.com/remvze)
- **开源许可证**: [MIT License](https://github.com/remvze/moodist/blob/main/LICENSE)
- **处理方式**: 30秒无缝循环切片，并在音频首尾添加 1.5秒平滑交叉淡入淡出。

### `assets/audio/scenes/night.mp3`（夏夜虫鸣）
- **来源项目**: [Moodist](https://github.com/remvze/moodist)
- **原始文件**: `crickets.mp3`
- **作者/项目方**: [Remvze](https://github.com/remvze)
- **开源许可证**: [MIT License](https://github.com/remvze/moodist/blob/main/LICENSE)
- **处理方式**: 30秒无缝循环切片，并在音频首尾添加 1.5秒平滑交叉淡入淡出。

---

## 2. 视频资源 (Video)

### `assets/video/scenes/rain.mp4`（湖泊细雨微动态）
- **拍摄题材**: 迷失湖（Lost Lake, Oregon）细雨涟漪与平静湖畔实景
- **来源**: [Wikimedia Commons - File:Lost Lake (33497670251).webm](https://commons.wikimedia.org/wiki/File:Lost_Lake_(33497670251).webm)
- **拍摄者 / 机构**: Greg Shine, 美国土地管理局 (Bureau of Land Management, U.S. Department of the Interior)
- **许可证**: **Public Domain (公有领域)**（作为美国联邦政府雇员在职务范围内创作的作品，根据美国法典第17条第105款，属于全球公有领域，无版权限制）
- **处理方式**: 提取高质量片段并采用 1.0秒交叉淡入淡出（xfade）无缝平滑微循环，压缩为移动端轻量级 H.264 编码（~570KB），去除原始环境杂音（音轨由独立的纯净白噪音单独提供）。

### `assets/video/scenes/night.mp4`（骷髅石星空微动态）
- **拍摄题材**: 约书亚树国家公园（Joshua Tree National Park）骷髅石上方银河星空延时实景
- **来源**: [Wikimedia Commons - File:Stars over Skull Rock (30233587084).webm](https://commons.wikimedia.org/wiki/File:Stars_over_Skull_Rock_(30233587084).webm)
- **拍摄者 / 机构**: 美国国家公园管理局 (National Park Service, U.S. Department of the Interior)
- **许可证**: **Public Domain (公有领域)**（作为美国联邦政府雇员在职务范围内创作的作品，属于全球公有领域，无版权限制）
- **处理方式**: 提取高质量延时片段并采用 1.0秒交叉淡入淡出（xfade）无缝平滑微循环，压缩为移动端轻量级 H.264 编码（~670KB），去除无用音轨。
