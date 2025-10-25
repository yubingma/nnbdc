import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/util/utils.dart';

void main() {
  group('表名转换测试', () {
    test('本地表名到远程表名', () {
      expect(Util.localTableNameToRemote('dakas'), equals('daka'));
      expect(Util.localTableNameToRemote('learningDicts'), equals('learning_dict'));
      expect(Util.localTableNameToRemote('userStudySteps'), equals('user_study_step'));
      expect(Util.localTableNameToRemote('userOpers'), equals('user_oper'));
      expect(Util.localTableNameToRemote('dictWords'), equals('dict_word'));
    });

    test('远程表名到本地表名', () {
      expect(Util.remoteTableNameToLocal('daka'), equals('dakas'));
      expect(Util.remoteTableNameToLocal('learning_dict'), equals('learningDicts'));
      expect(Util.remoteTableNameToLocal('user_study_step'), equals('userStudySteps'));
      expect(Util.remoteTableNameToLocal('user_oper'), equals('userOpers'));
      expect(Util.remoteTableNameToLocal('dict_word'), equals('dictWords'));
    });
  });
} 