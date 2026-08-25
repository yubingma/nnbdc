import 'package:flutter/material.dart';

/// 最小复现工程：验证 Flutter 3.44 "Build scheduled during frame" 断言来自框架自身，
/// 而非业务代码问题。
///
/// 设备复现步骤：
/// 1. `flutter run`（必须是 debug 构建，断言只在 debug 生效）
/// 2. 开启设备无障碍服务（TalkBack / 旁白 / 自动化测试工具如 Appium）。
///    语义树启用后，每帧都会执行 updateSemantics，输入法消息更容易在帧内被
///    引擎重入派发（这正是业务应用日志里 updateEditingValue 嵌套在 drawFrame 内的原因）。
/// 3. 在输入框里连续输入，若控制台出现
///    "Build scheduled during frame." 以及
///    "while dispatching notifications for TextEditingController"
///    即复现成功（与业务应用中的报错完全一致）。
///
/// 对照实验：关闭无障碍后再快速输入，该错误将很难复现 —— 印证触发条件在设备环境，
/// 与业务代码无关。
void main() => runApp(const ReproApp());

class ReproApp extends StatelessWidget {
  const ReproApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TextField 断言复现',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const ReproHome(),
    );
  }
}

class ReproHome extends StatefulWidget {
  const ReproHome({super.key});

  @override
  State<ReproHome> createState() => _ReproHomeState();
}

class _ReproHomeState extends State<ReproHome>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();

  // 持续运行的帧动画：模拟真实应用"打字期间仍有帧在产出"的常态，
  // 提高输入法消息在帧内被重入派发的概率（仅用于放大竞态窗口，非复现必需）。
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TextField "Build scheduled during frame" 复现')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '在此快速输入',
                helperText: '开启无障碍(TalkBack)后快速连续输入，观察控制台断言',
                border: OutlineInputBorder(),
                floatingLabelBehavior: FloatingLabelBehavior.always,
              ),
            ),
            const SizedBox(height: 24),
            FadeTransition(
              opacity: _pulse,
              child: const Text('●'),
            ),
          ],
        ),
      ),
    );
  }
}
