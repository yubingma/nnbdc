import 'dart:io' as io;
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/util/utils.dart';
import 'package:nnbdc/util/platform_util.dart';
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
      expect(Util.localTableNameToRemote('users'), equals('user'));
    });

    test('远程表名到本地表名', () {
      expect(Util.remoteTableNameToLocal('daka'), equals('dakas'));
      expect(Util.remoteTableNameToLocal('learning_dict'), equals('learningDicts'));
      expect(Util.remoteTableNameToLocal('user_study_step'), equals('userStudySteps'));
      expect(Util.remoteTableNameToLocal('user_oper'), equals('userOpers'));
      expect(Util.remoteTableNameToLocal('dict_word'), equals('dictWords'));
      expect(Util.remoteTableNameToLocal('user_badge'), equals('userBadges'));
      expect(Util.remoteTableNameToLocal('user'), equals('users'));
      expect(Util.remoteTableNameToLocal('users'), equals('users'));
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

  group('PlatformUtils 卓易通检测测试', () {
    tearDown(() {
      PlatformUtils.zhuoyiTongOverride = null;
    });

    test('zhuoyiTongOverride 覆盖检测', () {
      PlatformUtils.zhuoyiTongOverride = true;
      expect(PlatformUtils.isZhuoyiTong, isTrue);

      PlatformUtils.zhuoyiTongOverride = false;
      expect(PlatformUtils.isZhuoyiTong, isFalse);
    });
  });

  group('pubspec.yaml changes 解析测试', () {
    test('正常解析带双引号和单引号以及无引号的更新说明', () {
      const sampleYaml = '''
name: nnbdc
version: 26.08.29+26082901

# 版本更新说明
changes:
  - "添加新词表-易混淆单词"
  - '修复bug'
  - 优化登录页面性能

environment:
  sdk: ^3.4.0
''';
      final changes = Util.parseChangesFromPubspec(sampleYaml);
      expect(changes, equals([
        '添加新词表-易混淆单词',
        '修复bug',
        '优化登录页面性能',
      ]));
    });

    test('解析当前实际 pubspec.yaml 中的 changes', () {
      final file = io.File('pubspec.yaml');
      expect(file.existsSync(), isTrue);
      final content = file.readAsStringSync();
      final changes = Util.parseChangesFromPubspec(content);
      expect(changes, isNotEmpty);
      expect(changes.every((item) => item.trim().isNotEmpty), isTrue);
    });
  });
} 