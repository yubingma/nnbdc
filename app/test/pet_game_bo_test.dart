import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/bo/pet_game_bo.dart';

void main() {
  group('守护兽进化规则', () {
    test('阈值边界：刚好达到阈值即升阶', () {
      expect(PetGameBo.stageIndexOf(0), 0, reason: '未投喂时是泡芽');
      expect(PetGameBo.stageIndexOf(7), 0);
      expect(PetGameBo.stageIndexOf(8), 1, reason: '第 8 次投喂应进入幼兽');
      expect(PetGameBo.stageIndexOf(29), 1);
      expect(PetGameBo.stageIndexOf(30), 2);
      expect(PetGameBo.stageIndexOf(70), 3);
      expect(PetGameBo.stageIndexOf(140), 4, reason: '第 140 次投喂应到达最终形态');
    });

    test('超过最终阈值仍停在最终形态，不越界', () {
      expect(PetGameBo.stageIndexOf(9999), PetGameBo.stages.length - 1);
    });

    test('阶段下标始终落在 stages 合法区间内', () {
      for (var feedings = 0; feedings <= 200; feedings++) {
        final index = PetGameBo.stageIndexOf(feedings);
        expect(index, inInclusiveRange(0, PetGameBo.stages.length - 1));
      }
    });

    test('距离下次进化：满阶返回 null，其余返回正数且随投喂递减', () {
      expect(PetGameBo.feedingsToNextStage(0), 8);
      expect(PetGameBo.feedingsToNextStage(7), 1);
      expect(PetGameBo.feedingsToNextStage(8), 22);
      expect(PetGameBo.feedingsToNextStage(139), 1);
      expect(PetGameBo.feedingsToNextStage(140), isNull, reason: '满阶后没有下一次进化');
      expect(PetGameBo.feedingsToNextStage(200), isNull);
    });

    test('每个阶段的阈值严格递增，且首阶段从 0 开始', () {
      expect(PetGameBo.stages.first.threshold, 0);
      for (var i = 1; i < PetGameBo.stages.length; i++) {
        expect(
          PetGameBo.stages[i].threshold,
          greaterThan(PetGameBo.stages[i - 1].threshold),
          reason: '阶段阈值必须递增，否则进化会被后面的阶段吞掉',
        );
      }
    });
  });
}
