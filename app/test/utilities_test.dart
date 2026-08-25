import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/util/utils.dart';
import 'package:nnbdc/page/bdc/providers/bdc_notifier.dart';

void main() {
  group('表名转换测试', () {
    test('本地表名到远程表名', () {
      expect(Util.localTableNameToRemote('dakas'), equals('daka'));
      expect(Util.localTableNameToRemote('learningDicts'), equals('learning_dict'));
      expect(Util.localTableNameToRemote('userStudySteps'), equals('user_study_step'));
      expect(Util.localTableNameToRemote('userOpers'), equals('user_oper'));
      expect(Util.localTableNameToRemote('dictWords'), equals('dict_word'));
      expect(Util.localTableNameToRemote('userBadges'), equals('user_badge'));
    });

    test('远程表名到本地表名', () {
      expect(Util.remoteTableNameToLocal('daka'), equals('dakas'));
      expect(Util.remoteTableNameToLocal('learning_dict'), equals('learningDicts'));
      expect(Util.remoteTableNameToLocal('user_study_step'), equals('userStudySteps'));
      expect(Util.remoteTableNameToLocal('user_oper'), equals('userOpers'));
      expect(Util.remoteTableNameToLocal('dict_word'), equals('dictWords'));
      expect(Util.remoteTableNameToLocal('user_badge'), equals('userBadges'));
    });
  });

  group('ASR文本智能拼接测试 (stitchTexts)', () {
    test('中文无标点正常重叠', () {
      final res = BdcNotifier.stitchTexts("我爱苹果", "苹果很好吃", isEnglish: false);
      expect(res, equals("我爱苹果很好吃"));
    });

    test('中文带不同标点重叠', () {
      final res = BdcNotifier.stitchTexts("我爱苹果。", "苹果，很好吃。", isEnglish: false);
      expect(res, equals("我爱苹果。很好吃。"));
    });

    test('英文带不同标点重叠', () {
      final res = BdcNotifier.stitchTexts("I love apple.", "Apple, it is good.", isEnglish: true);
      expect(res, equals("I love apple. it is good."));
    });

    test('完全重叠包含关系', () {
      final res = BdcNotifier.stitchTexts("我爱苹果", "苹果", isEnglish: false);
      expect(res, equals("我爱苹果"));
    });

    test('完全没有重叠', () {
      final res = BdcNotifier.stitchTexts("我爱苹果", "香蕉很好吃", isEnglish: false);
      // 无重叠的阶段性结果用空格分隔，避免多个阶段识别文本黏连（与 bdc_notifier_test 断言一致）
      expect(res, equals("我爱苹果 香蕉很好吃"));
    });
  });
} 