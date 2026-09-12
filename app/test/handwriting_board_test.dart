import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/widget/handwriting_board.dart';
import 'package:provider/provider.dart';

/// 中文默写（分格手写）与「提交」判据的回归测试。
///
/// 覆盖三件事：
/// 1. [HandwritingBoardState.hasInk]：上层用它决定「提交/回退」是走手写还是作用于输入框，
///    因此"落笔 → true、清空 → false"必须准确；
/// 2. 提交后不能清空已识别序列：续写必须是追加，否则已写对的内容会从答案里消失；
/// 3. "打字 → 手写"切换时，输入框已有文本作为答案前缀并入，键盘内容不丢且不重复。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const MethodChannel channel = MethodChannel('nnbdc/ocr');
  // 手写识别结果：每个格子都识别成同一个字，便于断言"前缀累积"
  const String recognizedChar = '剧';
  late List<String> recognized;
  late List<String> previews;

  setUp(() {
    recognized = <String>[];
    previews = <String>[];
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
    bool Function()? onUndoRequest,
    VoidCallback? onUndo,
    String Function()? onReadCurrentText,
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
              onRecognizedPreview: previews.add,
              onCancel: () {},
              onSubmit: onSubmit,
              onUndoRequest: onUndoRequest,
              onUndo: onUndo,
              onReadCurrentText: onReadCurrentText,
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
    // 与生产代码的 onSubmit 分发同构：键盘在用或没有笔迹 → 判输入框；否则交回手写板
    await pumpBoard(tester, key, onSubmit: () {
      if (key.currentState!.hasInk) return false;
      judgedByKeyboard++;
      return true;
    });

    await tapSubmit(tester);

    expect(judgedByKeyboard, 1, reason: '没有笔迹时应判输入框文本');
    expect(recognized, isEmpty, reason: '没有笔迹时不应走手写识别');
  });

  testWidgets('回退：无笔迹时由上层删输入框字符，不触发手写板回退', (tester) async {
    final key = GlobalKey<HandwritingBoardState>();
    var undoneByKeyboard = 0;
    var undoneByBoard = 0;
    await pumpBoard(
      tester,
      key,
      onUndoRequest: () {
        if (key.currentState!.hasInk) return false;
        undoneByKeyboard++;
        return true;
      },
      onUndo: () => undoneByBoard++,
    );

    // 无笔迹 → 由上层处理（删输入框最后一个字符）
    await tester.tap(find.text('回退'));
    await tester.pump();
    expect(undoneByKeyboard, 1);
    expect(undoneByBoard, 0, reason: '没有笔迹时不应走手写板的回退逻辑');

    // 有笔迹 → 交回手写板处理
    await drawStroke(tester);
    await tester.tap(find.text('回退'));
    await tester.pump();
    expect(undoneByKeyboard, 1, reason: '有笔迹时不应再删输入框字符');
    expect(undoneByBoard, 1, reason: '有笔迹时应交回手写板回退');

    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('键盘接管输入框时擦掉画布残留笔迹（避免旧笔迹在提交时覆盖键盘内容）', (tester) async {
    final key = GlobalKey<HandwritingBoardState>();
    await pumpBoard(tester, key);

    await drawStroke(tester);
    expect(key.currentState!.hasInk, true);

    // 模拟键盘编辑输入框（父层在 TextField.onChanged 里调此方法）
    key.currentState!.clearHandwritingPreview();
    await tester.pump();
    expect(key.currentState!.hasInk, false, reason: '键盘接管后画布不应再残留旧笔迹');
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

  testWidgets('打字 → 手写：输入框已有文本作为答案前缀并入回显与判题', (tester) async {
    final key = GlobalKey<HandwritingBoardState>();
    // 模拟输入框里键盘已打好"悲"
    String boxText = '悲';
    await pumpBoard(tester, key, onReadCurrentText: () => boxText);

    await drawStroke(tester);
    await tester.pump(const Duration(milliseconds: 600)); // 停笔预览识别
    expect(previews.last, '悲$recognizedChar', reason: '回显应带上前缀，键盘内容不丢');

    await tapSubmit(tester);
    expect(recognized.last, '悲$recognizedChar', reason: '判题文本应带上前缀');

    // 提交后继续写：前缀不会重复叠加
    await drawStroke(tester);
    await tapSubmit(tester);
    expect(recognized.last, '悲$recognizedChar$recognizedChar',
        reason: '前缀只捕获一次，续写只在手写部分累积');
  });

  testWidgets('键盘接管输入框后前缀失效：下次落笔重新捕获输入框文本', (tester) async {
    final key = GlobalKey<HandwritingBoardState>();
    String boxText = '悲';
    await pumpBoard(tester, key, onReadCurrentText: () => boxText);

    await drawStroke(tester);
    await tapSubmit(tester);
    expect(recognized.last, '悲$recognizedChar');

    // 键盘接管：清掉手写状态，输入框此时是"悲剧"再补打字 → "悲剧难"
    key.currentState!.clearHandwritingPreview();
    boxText = '悲$recognizedChar难';
    await tester.pump();

    await drawStroke(tester);
    await tapSubmit(tester);
    expect(recognized.last, '悲$recognizedChar难$recognizedChar',
        reason: '重新捕获输入框文本作前缀，既不丢键盘内容也不重复旧前缀');
  });
}
