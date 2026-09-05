import 'dart:io' as io;
import 'package:flutter/material.dart';
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

  group('Util.getInitial 测试', () {
    test('英文字符正常转大写', () {
      expect(Util.getInitial('alice'), equals('A'));
      expect(Util.getInitial('Bob'), equals('B'));
    });

    test('中文字符正常获取首字', () {
      expect(Util.getInitial('张三'), equals('张'));
      expect(Util.getInitial(' 泡泡 '), equals('泡'));
    });

    test('Emoji字符完整获取不截断UTF-16代理项', () {
      expect(Util.getInitial('😊开心'), equals('😊'));
      expect(Util.getInitial('🌟星空'), equals('🌟'));
      expect(Util.getInitial('👨‍👩‍👧家庭'), equals('👨‍👩‍👧'));
      expect(Util.getInitial('🌙'), equals('🌙'));
      expect(Util.getInitial('🍊'), equals('🍊'));
      expect(Util.getInitial('🎀'), equals('🎀'));
      
      // 验证原生 TextSpan 布局完全正常，无 UTF-16 代理项断裂异常
      for (final emoji in ['🌙', '🍊', '🎀', '😊', '🌟']) {
        final initial = Util.getInitial(emoji);
        expect(initial, equals(emoji));
        expect(initial.codeUnits.length, greaterThanOrEqualTo(2));
        
        final tp = TextPainter(
          text: TextSpan(text: initial),
          textDirection: TextDirection.ltr,
        );
        tp.layout();
        expect(tp.width, greaterThan(0));
      }
    });

    test('特殊符号与书名号正常跳过并获取首个有效文字', () {
      expect(Util.getInitial('《考研英语核心词汇》'), equals('考'));
      expect(Util.getInitial('[六级]高频词汇'), equals('六'));
      expect(Util.getInitial('(四级)必备'), equals('四'));
      expect(Util.getInitial('“新概念英语”'), equals('新'));
      expect(Util.getInitial('【专八】词汇'), equals('专'));
      expect(Util.getInitial('99天搞定GRE'), equals('9'));
      expect(Util.getInitial('《TOEFL听力》'), equals('T'));
    });

    test('空值与异常值使用 fallback', () {
      expect(Util.getInitial(null), equals('U'));
      expect(Util.getInitial(''), equals('U'));
      expect(Util.getInitial('   ', fallback: '?'), equals('?'));
    });
  });
} 