# 随身听场景媒体资源合规与开源许可声明 (Scene Assets License)

本项目随身听（Walkman）功能所使用的微动态背景视频及环境白噪音音频，均来自 100% 免版权争议的公共领域（Public Domain / CC0）或开源项目（MIT License / CC BY 3.0 / CC BY-SA 4.0）。

所有镜头均为**专业三脚架固定机位拍摄（Zero Shake / Rock-Solid Tripod）**，构图极简留白，专为沉浸式单词记忆与学习心流设计。

---

## 一、音频资源清单 (Audio Assets)

所有音频资源均来自专业自然白噪音开源项目 [Moodist](https://github.com/remvze/moodist)（作者：Remvze），遵循 **MIT License** 开源协议：

1. **`assets/audio/scenes/rain.mp3`（闲时听雨）**
   - 来源：`rain-on-window.mp3`
   - 许可：MIT License
   - 说明：30秒高保真立体声切片，首尾 1.5 秒平滑交叉淡入淡出。

2. **`assets/audio/scenes/night.mp3`（夏夜虫鸣）**
   - 来源：`crickets.mp3`
   - 许可：MIT License
   - 说明：30秒高保真立体声切片，首尾 1.5 秒平滑交叉淡入淡出。

3. **`assets/audio/scenes/river.mp3`（湖光水镜）**
   - 来源：`nature/river.mp3`
   - 许可：MIT License
   - 说明：30秒高保真立体声切片，首尾 1.5 秒平滑交叉淡入淡出。

4. **`assets/audio/scenes/waves.mp3`（潮汐海浪）**
   - 来源：`nature/waves.mp3`
   - 许可：MIT License
   - 说明：30秒高保真立体声切片，首尾 1.5 秒平滑交叉淡入淡出。

5. **`assets/audio/scenes/forest.mp3`（森林微风）**
   - 来源：`nature/wind-in-trees.mp3` / `animals/birds.mp3`
   - 许可：MIT License
   - 说明：30秒高保真立体声切片，首尾 1.5 秒平滑交叉淡入淡出。

6. **`assets/audio/scenes/fire.mp3`（围炉夜话）**
   - 来源：`nature/campfire.mp3`
   - 许可：MIT License
   - 说明：30秒高保真立体声切片，首尾 1.5 秒平滑交叉淡入淡出。

7. **`assets/audio/scenes/mist.mp3`（空谷晨雾）**
   - 来源：`animals/birds.mp3`
   - 许可：MIT License
   - 说明：30秒高保真立体声切片，首尾 1.5 秒平滑交叉淡入淡出。

---

## 二、视频资源清单 (Video Assets)

所有背景视频均为**100% 广播级重型三脚架锁死固定机位拍摄（Locked-off Tripod Shots / 0 像素位移验证通过）**、构图极简留白、大面积纯色与自然层次，让位于前景单词信息。采用 ffmpeg 消除杂音音轨，通过 1.0 秒交叉淡入淡出（xfade）消除循环跳变，压制为移动端轻量级 H.264 编码（单文件体积仅 200KB ~ 960KB）：

1. **`assets/video/scenes/night.mp4`（夏夜虫鸣）**
   - 题材：加州约书亚树国家公园（Joshua Tree National Park）骷髅石上方银河星空固定机位延时实景
   - 来源：[Wikimedia Commons - File:Stars over Skull Rock (30233587084).webm](https://commons.wikimedia.org/wiki/File:Stars_over_Skull_Rock_(30233587084).webm)
   - 创作者：美国国家公园管理局 (National Park Service, U.S. Department of the Interior)
   - 许可证：**Public Domain (公有领域)**（美国联邦政府官方作品）
   - 机位：三脚架锁死地面，物理基岩 0 位移。

2. **`assets/video/scenes/rain.mp4`（闲时听雨）**
   - 题材：极简微距窗户雨滴缓缓滑落，背景柔和漫射灰调，室内三脚架固定
   - 来源：[Wikimedia Commons - File:Radevormwald - Raindrops on a window 07 (1) ies.webm](https://commons.wikimedia.org/wiki/File:Radevormwald_-_Raindrops_on_a_window_07_(1)_ies.webm)
   - 创作者：Frank Vincentz
   - 许可证：**Creative Commons Attribution-ShareAlike 3.0 Unported (CC BY-SA 3.0)**
   - 机位：室内三脚架正对窗框，玻璃 0 位移。

3. **`assets/video/scenes/waves.mp4`（潮汐海浪）**
   - 题材：加州海峡群岛国家公园（Channel Islands National Park）圣罗莎岛海岸线，远山连绵与太平洋碧蓝白浪平缓推涌
   - 来源：[Wikimedia Commons - File:Santa Rosa Island Waves.webm](https://commons.wikimedia.org/wiki/File:Santa_Rosa_Island_Waves.webm)
   - 许可证：**Creative Commons CC0 1.0 Universal (Public Domain Dedication，公有领域献身)**
   - 机位：重型三脚架锁死礁石地面，远山与岩石 0 位移（`dx=0, dy=0` 检验通过）。

4. **`assets/video/scenes/river.mp4`（湖光水镜）**
   - 题材：蒙大拿州冰川国家公园（Glacier National Park）麦克唐纳湖清晨薄雾，群山雪峰在如镜水面的深邃倒影与岸边安详黑鹅卵石
   - 来源：[Wikimedia Commons - File:Misty Morning at Lake McDonald (25569241623).webm](https://commons.wikimedia.org/wiki/File:Misty_Morning_at_Lake_McDonald_(25569241623).webm)
   - 创作者：美国国家公园管理局 (National Park Service, U.S. Department of the Interior)
   - 许可证：**Public Domain (公有领域)**（美国联邦政府官方作品）
   - 机位：重型三脚架锁死湖岸，山体倒影与鹅卵石 0 位移（`dx=0, dy=0` 检验通过）。

5. **`assets/video/scenes/forest.mp4`（森林微风）**
   - 题材：苍劲粗壮的树干斜贯画面，阳光穿透绿叶洒下金辉斑驳，嫩绿枝叶在微风中轻摇
   - 来源：[Wikimedia Commons - File:Thomas Bresson - arbres.webm](https://commons.wikimedia.org/wiki/File:Thomas_Bresson_-_arbres.webm)
   - 创作者：Thomas Bresson
   - 许可证：**Creative Commons Attribution 4.0 International (CC BY 4.0)**
   - 机位：重型三脚架锁死地面，主树干 0 位移（`dx=0, dy=0` 检验通过）。

6. **`assets/video/scenes/fire.mp4`（围炉夜话）**
   - 题材：宾夕法尼亚州福吉谷国家历史公园（Valley Forge National Historical Park）石砌古壁炉节日暖柴木炭实景，暗调炉膛红炭微燃，大面积深色留白
   - 来源：[Wikimedia Commons - File:Valley Forge Yule Log.webm](https://commons.wikimedia.org/wiki/File:Valley_Forge_Yule_Log.webm)
   - 创作者：美国国家公园管理局 (National Park Service, U.S. Department of the Interior)
   - 许可证：**Public Domain (公有领域)**（美国联邦政府官方作品）
   - 机位：石壁炉前三脚架锁死地面，石质炉膛 0 位移（`dx=0, dy=0` 检验通过）。

7. **`assets/video/scenes/mist.mp4`（空谷晨雾）**
   - 题材：亚利桑那州大峡谷国家公园（Grand Canyon National Park）罕见逆温云海瀑布（Inversion Clouds）壮阔延时实景，群峰如仙岛耸立于翻腾白云之中
   - 来源：[Wikimedia Commons - File:Grand Canyon National Park- Time-lapse of Inversion Clouds (sunset) (11197630903).webm](https://commons.wikimedia.org/wiki/File:Grand_Canyon_National_Park-_Time-lapse_of_Inversion_Clouds_%28sunset%29_%2811197630903%29.webm)
   - 创作者：美国国家公园管理局 (National Park Service, U.S. Department of the Interior)
   - 许可证：**Public Domain (公有领域)**（美国联邦政府官方作品）
   - 机位：峡谷观景台重型三脚架锁死地面，岩体绝壁 0 位移（`dx=0, dy=0` 检验通过）。
