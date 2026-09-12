import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/widget/handwriting_board.dart';
import 'package:provider/provider.dart';

/// 中文默写（分格手写）与「提交」判据的回归测试。
///
/// 覆盖两件事：
/// 1. [HandwritingBoardState.hasInk]：上层用它决定「提交」是走手写识别还是判输入框文本，
///    因此"落笔 → true、清空 → false"必须准确；
/// 2. 提交后不能清空已识别序列：续写必须是追加，否则已写对的内容会从答案里消失。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('nnbdc/ocr');
  // 手写识别结果：每个格子都识别成同一个字，便于断言"前缀累积"
  const String recognizedChar = '剧';
  late List<String> recognized;

  setUp(() {
    recognized = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'recognizeHandwriting':
          return recognizedChar;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> pumpBoard(
    WidgetTester tester,
    GlobalKey<HandwritingBoardState> key, {
    bool Function()? onSubmit,
  }) async {
    await tester.pumpWidget(ChangeNotifierProvider<DarkMode>.value(
      value: DarkMode(),
      child: MaterialApp(
        theme: AppTheme.getThemeData(AppThemeStyle.emerald),
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 600,
            child: HandwritingBoard(
              key: key,
              language: 'zh-Hani',
              cellCount: 2,
              manualSubmit: true,
              onRecognized: recognized.add,
              onCancel: () {},
              onSubmit: onSubmit,
            ),
          ),
        ),
      ),
    ));
  }

  /// 在画布中央画一笔（真实按下-移动-抬起，让 _lines 记录笔迹）
  Future<void> drawStroke(WidgetTester tester) async {
    final gesture =
        await tester.startGesture(tester.getCenter(find.byType(HandwritingBoard)));
    await gesture.moveBy(const Offset(40, 30));
    await gesture.moveBy(const Offset(20, 20));
    await gesture.up();
    await tester.pump();
  }

  /// 点底部「提交」按钮，并让手写识别（mock 通道）与判题回调落地
  Future<void> tapSubmit(WidgetTester tester) async {
    await tester.tap(find.text('提交'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 20));
  }

  testWidgets('hasInk：无笔迹为 false，落笔后为 true', (tester) async {
    final key = GlobalKey<HandwritingBoardState>();
    await pumpBoard(tester, key);
    expect(key.currentState!.hasInk, false);

    await drawStroke(tester);
    expect(key.currentState!.hasInk, true);

    // 让停笔识别的防抖定时器落地，避免测试结束时残留 timer
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('提交：无笔迹时由上层判输入框文本，不触发手写识别', (tester) async {
    final key = GlobalKey<HandwritingBoardState>();
    var judgedByKeyboard = 0;
    // 与生产代码的 onSubmit 分发同构：有笔迹 → 交回手写板；无笔迹 → 判输入框
    await pumpBoard(tester, key, onSubmit: () {
      if (key.currentState?.hasInk ?? false) return false;
      judgedByKeyboard++;
      return true;
    });

    await tapSubmit(tester);

    expect(judgedByKeyboard, 1, reason: '没有笔迹时应判输入框文本');
    expect(recognized, isEmpty, reason: '没有笔迹时不应走手写识别');
  });

  testWidgets('提交：有笔迹时走手写识别，提交后已识别内容保留（续写=追加）', (tester) async {
    final key = GlobalKey<HandwritingBoardState>();
    await pumpBoard(tester, key);

    await drawStroke(tester);
    await tapSubmit(tester);
    expect(recognized, [recognizedChar], reason: '有笔迹时应把手写识别结果交给上层判题');
    expect(key.currentState!.hasInk, true, reason: '提交后已识别内容应保留，便于直接续写');

    // 再写一笔再提交：答案应是"累积前缀"，而不是只剩新写的那个字
    await drawStroke(tester);
    await tapSubmit(tester);
    expect(recognized.length, 2);
    expect(recognized.last, recognizedChar * 2,
        reason: '提交后再次提交应累积此前的识别结果，不能从头开始');
  });
}
