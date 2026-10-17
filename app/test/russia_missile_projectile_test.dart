import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/page/russia.dart';
import 'dart:io';

void main() {
  group('海底对战 导弹系统与点错反噬惩罚逻辑', () {
    test('GameProjectile 实体支持导弹攻击与惩罚反噬导弹', () {
      final attackMissile = GameProjectile.mine(
        startX: 300,
        startY: 700,
        targetX: 280,
        targetY: 80,
      );
      expect(attackMissile.type, equals(ProjectileType.mine));
      expect(attackMissile.startX, equals(300));
      expect(attackMissile.targetX, equals(280));

      final penaltyMissile = GameProjectile.penaltyMissile(
        startX: 150,
        startY: 400,
        targetX: 100,
        targetY: 80,
        reason: '答错 -1 HP!',
      );
      expect(penaltyMissile.type, equals(ProjectileType.penaltyMissile));
      expect(penaltyMissile.startX, equals(150));
      expect(penaltyMissile.startY, equals(400));
      expect(penaltyMissile.targetX, equals(100));
      expect(penaltyMissile.targetY, equals(80));
      expect(penaltyMissile.reason, equals('答错 -1 HP!'));
    });

    test('源码静态断言：点错泡泡必须发射惩罚导弹飞向我方血条，并在命中后扣血', () {
      final source = File('lib/page/russia.dart').readAsStringSync();

      // 1. 点错干扰词泡泡时不再直接原地扣血，而是生成 penaltyMissile
      expect(source, contains('GameProjectile.penaltyMissile('));
      expect(source, contains('targetX: size.width * 0.28'));

      // 2. 惩罚导弹飞行结束命中后才调用 _applyDamage
      expect(source, contains("if (isPenalty)"));
      expect(source, contains("_applyDamage(1, reason: p.reason.isNotEmpty ? p.reason : '答错 -1 HP!', fromOpponent: true);"));

      // 3. 道具栏图标与发射动效已改为导弹
      expect(source, contains('Icons.rocket_launch_rounded'));
      expect(source, contains('连对3次可得导弹!'));
      expect(source, contains('🚀 导弹轰击 对手 -1 HP!'));

      // 4. 包含流线型动态导弹绘制函数
      expect(source, contains('void _drawMissile(Canvas canvas, GameProjectile p)'));
    });
  });
}
