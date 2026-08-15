---
name: audio-specialist
description: ppdc 项目音频专项审查。涉及 TTS、ASR、单词发音播放、音频会话管理的变更，在团队工作流阶段 3 需由音频专家按本 skill 审查。
whenToUse: 变更涉及音频（TTS/ASR/播放/音频会话/延迟/爆音等）时。
---

# ppdc 音频专家审查

ppdc 是背单词应用，音频是核心体验路径：单词/例句发音播放、ASR 跟读评测、TTS 释义播放。

## 音频相关代码地图

- 播放：`app/lib/util/sound.dart`（playSoundByUrl）
- TTS：`app/lib/util/tts.dart`
- ASR：`app/lib/util/asr.dart`、`app/lib/util/asr_util.dart`
- 会话管理：`app/lib/util/study_audio_session_controller.dart`
- iOS 原生：`app/ios/Runner/AppDelegate.swift`（AVAudioSession、ASR 物理关麦、TTS 发声）
- 状态机测试：`app/test/audio_state_machine_test.dart`

## 审查要点

1. **状态机一致性**：播放/ASR/TTS 的状态转换是否与音频状态机一致；新增状态是否同步更新 `audio_state_machine_test.dart`
2. **AVAudioSession 竞争**：iOS 会话 Category/激活必须单端收口（Flutter 状态机侧），避免双端并发修改导致爆音
3. **播放器复用**：completed 状态的播放器直接 replaceCurrentItem 会产生瞬态爆音，必须先 stop() 重置（必要时加短暂过渡延迟）
4. **延迟与错峰**：会话切换与发声之间是否留出硬件稳定延迟，避免 TTS 首字被吞、切换爆音
5. **生命周期**：暂停/切页/后台/来电打断时音频资源是否正确释放与恢复（物理关麦、engine teardown）
6. **多语言**：TTS/ASR 的语言参数是否与词条语言一致（en/zh 等）
7. **性能**：音频资源的缓存与释放策略是否合理，避免解码资源或内存泄漏

## 输出格式

同架构审查：逐条 ✅ PASS / ❌ FAIL 及理由，最后给出结论（PASS，或修改后重审）。
