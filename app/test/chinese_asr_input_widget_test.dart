import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:nnbdc/page/bdc/widgets/chinese_asr_input_widget.dart';
import 'package:nnbdc/page/bdc/widgets/english_asr_input_widget.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/util/asr.dart';

Widget _buildTestApp(Widget child) {
  return ChangeNotifierProvider(
    create: (_) => DarkMode(),
    child: MaterialApp(
      home: Scaffold(
        body: child,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChineseAsrInputWidget 状态文字测试', () {
    testWidgets('未答题初始状态下显示"请说中文释义"', (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();

      await tester.pumpWidget(
        _buildTestApp(
          ChineseAsrInputWidget(
            controller: controller,
            asrState: AsrState.stopped,
            onStartAsr: (_) {},
            isKeyboardVisible: false,
            focusNode: focusNode,
            score: null,
            isScorePassed: false,
          ),
        ),
      );

      expect(find.text('请说中文释义'), findsOneWidget);
      expect(find.text('回答正确'), findsNothing);
    });

    testWidgets('英译汉模式答完题（isScorePassed=true）后应显示"回答正确"，不再显示"请说中文释义"', (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();

      await tester.pumpWidget(
        _buildTestApp(
          ChineseAsrInputWidget(
            controller: controller,
            asrState: AsrState.stopped,
            onStartAsr: (_) {},
            isKeyboardVisible: false,
            focusNode: focusNode,
            score: null,
            isScorePassed: true,
          ),
        ),
      );

      expect(find.text('回答正确'), findsOneWidget);
      expect(find.text('请说中文释义'), findsNothing);

      final textWidget = tester.widget<Text>(find.text('回答正确'));
      expect(textWidget.style?.color, Colors.green);
    });

    testWidgets('例句英译汉模式答完题后也应显示"回答正确"', (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();

      await tester.pumpWidget(
        _buildTestApp(
          ChineseAsrInputWidget(
            controller: controller,
            asrState: AsrState.stopped,
            onStartAsr: (_) {},
            isKeyboardVisible: false,
            focusNode: focusNode,
            score: 90,
            isSentenceStep: true,
            isScorePassed: true,
          ),
        ),
      );

      expect(find.text('回答正确'), findsOneWidget);
      expect(find.text('请说例句中文'), findsNothing);
    });
  });

  group('EnglishAsrInputWidget 状态文字测试', () {
    testWidgets('汉译英模式下非语音（无发音打分）答对后应显示"回答正确"，不再显示"请说单词发音"', (tester) async {
      final controller = TextEditingController();
      final focusNode = FocusNode();

      await tester.pumpWidget(
        _buildTestApp(
          EnglishAsrInputWidget(
            controller: controller,
            asrState: AsrState.stopped,
            onStartAsr: (_) {},
            isKeyboardVisible: false,
            focusNode: focusNode,
            score: null,
            isScorePassed: true,
          ),
        ),
      );

      expect(find.text('回答正确'), findsOneWidget);
      expect(find.text('请说单词发音'), findsNothing);

      final textWidget = tester.widget<Text>(find.text('回答正确'));
      expect(textWidget.style?.color, Colors.green);
    });
  });
}
