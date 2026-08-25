# TextField "Build scheduled during frame" 最小复现工程

## 结论先行

业务应用日志里的 **"Build scheduled during frame."** 与 **"The following assertion
was thrown while dispatching notifications for TextEditingController"** 两条异常，
是 **Flutter 框架自身的竞态**（仅 debug 构建生效），**不是业务代码问题**，无需也不应
在业务代码里做 workaround。

## 根因

1. Flutter 框架的 `TextField` 内部自带两个监听 controller 的 `AnimatedBuilder`：
   - `packages/flutter/lib/src/material/text_field.dart:1804`
     `AnimatedBuilder(animation: controller, ...)`（向语义树同步字符数）；
   - `text_field.dart:1765`
     `AnimatedBuilder(animation: Listenable.merge([focusNode, controller]), ...)`（InputDecorator）。
2. 用户输入时，输入法消息（`TextInput.updateEditingValue`）被引擎在 `drawFrame` 的
   `flushSemantics → updateSemantics`（同步 FFI 调用）期间**重入派发**回 Dart
   （堆栈可见 `_dispatchPlatformMessage` 嵌套在 `__updateSemantics$Method$FfiNative` 内）。
   `updateSemantics` 只在**语义树启用**时执行 —— 即设备开启了无障碍服务
   （TalkBack / 旁白 / 自动化测试工具）。
3. controller 通知 → 框架内部 `AnimatedBuilder._handleChange` → `setState`，
   此时 `debugBuildingDirtyElements == true` → 断言抛出。

堆栈中的 `_AnimatedState._handleChange (transitions.dart:133)` 就是框架内部
AnimatedBuilder 的回调，与业务代码无关（已逐一核对业务侧所有
`AnimatedBuilder`/`ListenableBuilder`/`AnimatedWidget`，均只监听
`AnimationController`/`FocusNode`，无一监听 TextEditingController）。

## 目录

- `lib/main.dart` —— 真机/模拟器复现入口（单个 TextField + 持续帧动画放大竞态窗口）
- `test/build_scheduled_repro_test.dart` —— **确定性** widget 测试，本地即可稳定复现断言
- `analysis_options.yaml` / `pubspec.yaml`

## 运行

### 1. 确定性复现（widget 测试，无需设备）

```bash
cd app/scratch/textfield_build_scheduled_repro
flutter pub get
flutter test
```

预期：测试通过，控制台打印捕获到的框架错误，内容包含
`Build scheduled during frame.` 与
`while dispatching notifications for TextEditingController`。

### 2. 真机/模拟器复现（复现原始场景）

```bash
cd app/scratch/textfield_build_scheduled_repro
flutter run          # 必须是 debug 构建
```

步骤：
1. 设备开启无障碍服务（TalkBack / 旁白 / Appium 等自动化工具）；
2. 在输入框快速连续输入；
3. 控制台出现上述断言即复现成功。

对照实验：关闭无障碍后再快速输入，错误将很难复现 —— 印证触发条件在设备环境。

## 影响与处理

- **仅 debug 构建出现**。断言在 `assert(() {...}())` 内，release 构建被剥离，
  至多造成一帧延迟，无崩溃、无功能影响。
- 业务侧 `FlutterError.onError` 会把这类错误上报 Umeng `flutter_error`，
  debug 包 + 无障碍环境下会产生噪声数据，分析线上错误时建议过滤。
- 处理路径：升级到最新 stable Flutter（当前 3.44.0 已有 3.44.4 hotfix，但
  changelog 未覆盖此问题）；可携带本工程向 [flutter/flutter](https://github.com/flutter/flutter/issues)
  提交 issue。
