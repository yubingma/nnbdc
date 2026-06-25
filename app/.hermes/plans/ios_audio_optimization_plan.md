# 背单词（BDC）单词发音爆音与断续现象分析与优化方案

## 影响范围
- Flutter: 是，修改 `app/lib/util/sound.dart` 的 `playSoundByUrl` 重置逻辑
- iOS 原生 (Swift): 是，修改 `app/ios/Runner/AppDelegate.swift` 中的 ASR 物理关麦与 TTS 发音控制逻辑
- 音频/ASR: 是

---

## Task 分解

### Task 1: 物理重置 completed 状态的播放器
- **文件**: `app/lib/util/sound.dart`
- **变更**: 
  - 在 `playSoundByUrl` 方法中，当播放器的 `processingState` 为 `completed` 时，将 `needHardStop` 判定为 `true`。
  - 调用 `player.stop()` 重置为 `idle`，并引入 30ms 的异步过渡延迟，消除硬件管线残留瞬态。
- **目的**: 彻底消除 iOS `AVPlayer` 在 completed 状态下直接调用 `replaceCurrentItem` (加载新词发音) 时产生的瞬态电流爆音。
- **验证**: flutter test test/audio_state_machine_test.dart && flutter analyze

### Task 2: 优化 iOS 原生 ASR 物理关麦逻辑
- **文件**: `app/ios/Runner/AppDelegate.swift`
- **变更**: 
  - 在 `stopMicrophone` 方法中，移除修改 `AVAudioSession` 的 Category 回 `.playback` 和调用 `setActive(false)` 的逻辑。只保留逻辑释放（`teardownAudioEngine()`、`stopSpeechRecognition()` 等）。
- **目的**: 彻底避免 ASR 物理关闭麦克风时引发的 `AVAudioSession` 双端激活竞态，消除硬件频繁“下电 -> 上电”导致的爆音。
- **验证**: 本地编译通过

### Task 3: [顺带优化] 优化 iOS 原生 TTS 发音逻辑与硬件稳定延迟
- **文件**: `app/ios/Runner/AppDelegate.swift`
- **变更**:
  - 在 `speak(text:utteranceId:language:)` 中，在真正触发播放前显式检查并配置 `AVAudioSession` 状态（如果 Category 为 `playAndRecord`，强制配置具备 `.defaultToSpeaker` 和 `.mixWithOthers` 选项并激活；如果是其他分类则设置为 `.playback` 并激活）。
  - 在激活会话后，引入 100ms 异步错峰延迟（`DispatchQueue.main.asyncAfter`），给硬件驱动留出稳定时钟后再调用 `synthesizer.speak`。
- **目的**: 顺带解决如果用户使用随身听（Walkman）播放释义时，TTS 首字被吞、切换爆音和声音偏小的问题。
- **验证**: 本地编译通过

---

## [架构审查结果]

Plan 阶段

✅ PASS:
- **状态控制收口**：将 `AVAudioSession` 的状态控制权完全收归 Flutter 端的状态机，分层清晰，杜绝双端并发修改。
- **物理状态对齐**：针对 iOS completed 状态直接加载资源的缺陷，显式进行 `stop()` 重置，符合合理性与物理直觉。
- **变更范围小且精准**：仅修改 `sound.dart` 的重置逻辑和 `AppDelegate.swift` 中的 ASR/TTS 控制逻辑，为 Surgical Changes，无过度抽象与工程臃肿。

总结: PASS
