import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/page/russia.dart';

void main() {
  group('Russia 开局开场动画', () {
    test('双人对战播「开始对战」，单人练习播「练习开始」', () {
      expect(RussiaPageState.introTitle(false), '开始对战');
      expect(RussiaPageState.introTitle(true), '练习开始');
    });

    test('不透明度曲线：淡入 → 稳定 → 淡出，首尾归零', () {
      expect(RussiaPageState.introOpacity(0.0), 0.0);
      expect(RussiaPageState.introOpacity(0.09), closeTo(0.5, 0.01));
      expect(RussiaPageState.introOpacity(0.4), 1.0);
      expect(RussiaPageState.introOpacity(1.0), 0.0);

      for (double t = 0.0; t <= 1.0; t += 0.02) {
        final double v = RussiaPageState.introOpacity(t);
        expect(v, inInclusiveRange(0.0, 1.0));
      }
    });

    test('缩放曲线：入场从 0.7 弹起，停留为 1.0，退场放大冲出去', () {
      expect(RussiaPageState.introScale(0.0), 0.7);
      expect(RussiaPageState.introScale(0.4), 1.0);
      expect(RussiaPageState.introScale(0.99), closeTo(1.18, 0.01));
      // 入场段必须把画面从缩小状态撑大，绝不出现越播越小
      expect(RussiaPageState.introScale(0.09),
          greaterThan(RussiaPageState.introScale(0.02)));
    });
  });

  group('受击 / 治愈的屏幕边缘光晕', () {
    test('光晕强度有界，衰减到 0 时归零', () {
      expect(RussiaPageState.edgeGlowStrength(0.0), 0.0);

      for (double decay = 0.0; decay <= 1.0; decay += 0.02) {
        final double v = RussiaPageState.edgeGlowStrength(decay);
        expect(v, inInclusiveRange(0.0, 1.0));
        // 衰减越靠后光晕越弱，绝不会反过来越闪越亮
        expect(v, lessThanOrEqualTo(decay + 1e-9));
      }
    });
  });
}
