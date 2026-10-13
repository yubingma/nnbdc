import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/page/russia.dart';

/// 离开确认弹窗的文案口径。
///
/// 用户反馈：练习模式下点离开，按钮写着"判负离开"，看着像要扣分——而练习其实
/// 从来不计分、也不判负（服务端练习跑在 WaitState 里，压根走不到判负那条路）。
/// 这里把三种处境的文案钉住，避免再把代价说错。
void main() {
  group('离开确认文案', () {
    test('正式对战：说清判负代价', () {
      final text = RussiaPageState.leaveGameConfirmText(
          isBattle: true, inPrivateRoom: false, opponentPresent: false, quitBattle: true);

      expect(text.body, contains('判为战败'));
      expect(text.confirmLabel, '判负离开');
    });

    test('练习离开，任何一处都不许出现"判负"字样', () {
      for (final inPrivateRoom in [true, false]) {
        for (final opponentPresent in [true, false]) {
          for (final quitBattle in [true, false]) {
            final text = RussiaPageState.leaveGameConfirmText(
              isBattle: false,
              inPrivateRoom: inPrivateRoom,
              opponentPresent: opponentPresent,
              quitBattle: quitBattle,
            );

            expect(text.title, isNot(contains('判负')));
            expect(text.body, isNot(contains('判负')));
            expect(text.confirmLabel, isNot(contains('判负')));
            // 每一条练习文案都要明确"不计分、不扣魔法泡泡"
            expect(text.body, contains('不计分'));
            expect(text.body, contains('魔法泡泡'));
          }
        }
      }
    });

    test('私房里只剩我一个人时离开：交代房间会散、房号作废', () {
      final text = RussiaPageState.leaveGameConfirmText(
          isBattle: false, inPrivateRoom: true, opponentPresent: false, quitBattle: true);

      expect(text.title, contains('解散'));
      expect(text.body, contains('房号作废'));
      expect(text.confirmLabel, '解散并离开');
    });

    test('私房里还有同伴时离开：交代房间和房号都还在', () {
      final text = RussiaPageState.leaveGameConfirmText(
          isBattle: false, inPrivateRoom: true, opponentPresent: true, quitBattle: true);

      expect(text.body, contains('房间和房号都还在'));
      expect(text.confirmLabel, '退出房间');
      expect(text.body, isNot(contains('房号作废')));
    });

    test('匹配练习离开：说清只是退出匹配', () {
      final text = RussiaPageState.leaveGameConfirmText(
          isBattle: false, inPrivateRoom: false, opponentPresent: false, quitBattle: true);

      expect(text.body, contains('退出匹配'));
      expect(text.confirmLabel, '结束练习');
    });
  });
}
