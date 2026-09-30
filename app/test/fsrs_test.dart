import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/util/fsrs.dart';

/// 黄金向量由官方 py-fsrs 4.1.2（FSRS-5）生成：
/// `Scheduler(enable_fuzzing=False).review_card(...)`，生成脚本 tmp/fsrs_ref/gen_vectors.py。
/// 容差 1e-9 吸收两种实现的浮点末位差异。
void main() {
  const double eps = 1e-9;
  late FSRS fsrs;

  FSRSItem item(double stability, double difficulty) => FSRSItem(
        stability: stability,
        difficulty: difficulty,
        elapsedDays: 0,
        scheduledDays: 0,
        reps: 0,
        lapses: 0,
        state: FsrsState.review,
      );

  setUp(() => fsrs = FSRS());

  group('FSRS-5 首次评分', () {
    // (rating, 稳定性 S0, 难度 D0)
    const cases = <(FsrsRating, double, double)>[
      (FsrsRating.again, 0.40255, 7.1949),
      (FsrsRating.hard, 1.18385, 6.488305268471453),
      (FsrsRating.good, 3.173, 5.282434422319005),
      (FsrsRating.easy, 15.69105, 3.2245015893713678),
    ];

    for (final (rating, stability, difficulty) in cases) {
      test('init(${rating.name})', () {
        final result = fsrs.init(rating);
        expect(result.stability, closeTo(stability, eps));
        expect(result.difficulty, closeTo(difficulty, eps));
        expect(result.elapsedDays, 0);
        expect(result.reps, 1);
        expect(result.lapses, rating == FsrsRating.again ? 1 : 0);
        expect(result.state, FsrsState.learning);
      });
    }
  });

  group('FSRS-5 跨天复习（长期记忆）', () {
    // (S_in, D_in, elapsedDays, rating, S_out, D_out, 间隔天数)
    // 再次评分的间隔由"重学步骤"决定而非 FSRS 间隔，故以 -1 标记不断言
    const cases = <(double, double, int, FsrsRating, double, double, int)>[
      (2.4, 5.0, 1, FsrsRating.again, 0.7867215109141141, 6.607035107311108, -1),
      (2.4, 5.0, 1, FsrsRating.hard, 3.069639430664681, 5.7994339073111085, 3),
      (2.4, 5.0, 1, FsrsRating.good, 5.292610931596894, 4.991832707311108, 5),
      (2.4, 5.0, 1, FsrsRating.easy, 11.04832816328839, 4.184231507311108, 11),
      (2.4, 5.0, 5, FsrsRating.again, 1.0684441333549506, 6.607035107311108, -1),
      (2.4, 5.0, 5, FsrsRating.hard, 5.244295168262089, 5.7994339073111085, 5),
      (2.4, 5.0, 5, FsrsRating.good, 14.686372217114858, 4.991832707311108, 15),
      (2.4, 5.0, 5, FsrsRating.easy, 39.13379565473, 4.184231507311108, 39),
      (2.4, 5.0, 30, FsrsRating.again, 1.7048224703525037, 6.607035107311108, -1),
      (2.4, 5.0, 30, FsrsRating.hard, 11.662443995295032, 5.7994339073111085, 12),
      (2.4, 5.0, 30, FsrsRating.good, 42.410557215097334, 4.991832707311108, 42),
      (2.4, 5.0, 30, FsrsRating.easy, 122.023563961698, 4.184231507311108, 122),
      (10.0, 5.0, 1, FsrsRating.again, 1.724224315938114, 6.607035107311108, -1),
      (10.0, 5.0, 1, FsrsRating.hard, 10.585229671972748, 5.7994339073111085, 11),
      (10.0, 5.0, 1, FsrsRating.good, 12.52798994372677, 4.991832707311108, 13),
      (10.0, 5.0, 1, FsrsRating.easy, 17.55818433375429, 4.184231507311108, 18),
      (10.0, 5.0, 5, FsrsRating.again, 1.8984747875650796, 6.607035107311108, -1),
      (10.0, 5.0, 5, FsrsRating.hard, 12.799019990005638, 5.7994339073111085, 13),
      (10.0, 5.0, 5, FsrsRating.good, 22.090799092896923, 4.991832707311108, 22),
      (10.0, 5.0, 5, FsrsRating.easy, 46.14907112794323, 4.184231507311108, 46),
      (10.0, 5.0, 30, FsrsRating.again, 2.856084594172231, 6.607035107311108, -1),
      (10.0, 5.0, 30, FsrsRating.hard, 23.330790223394693, 5.7994339073111085, 23),
      (10.0, 5.0, 30, FsrsRating.good, 67.58440701250409, 4.991832707311108, 68),
      (10.0, 5.0, 30, FsrsRating.easy, 182.1658600859847, 4.184231507311108, 182),
      (50.0, 8.0, 1, FsrsRating.again, 3.416833327202288, 8.624113667311107, -1),
      (50.0, 8.0, 1, FsrsRating.hard, 50.24376855122227, 8.301073187311108, 50),
      (50.0, 8.0, 1, FsrsRating.good, 51.05299590160804, 7.978032707311108, 51),
      (50.0, 8.0, 1, FsrsRating.easy, 53.148247146627746, 7.654992227311109, 53),
      (50.0, 8.0, 5, FsrsRating.again, 3.488843758572642, 8.624113667311107, -1),
      (50.0, 8.0, 5, FsrsRating.hard, 51.207672345529446, 8.301073187311108, 51),
      (50.0, 8.0, 5, FsrsRating.good, 55.21672719451165, 7.978032707311108, 55),
      (50.0, 8.0, 5, FsrsRating.easy, 65.59697096615092, 7.654992227311109, 66),
      (50.0, 8.0, 30, FsrsRating.again, 3.9276311552869356, 8.624113667311107, -1),
      (50.0, 8.0, 30, FsrsRating.hard, 56.85740370835789, 8.301073187311108, 57),
      (50.0, 8.0, 30, FsrsRating.good, 79.6216142909628, 7.978032707311108, 80),
      (50.0, 8.0, 30, FsrsRating.easy, 138.56270240712055, 7.654992227311109, 139),
    ];

    for (final (s, d, elapsed, rating, outS, outD, interval) in cases) {
      test('S=$s D=$d elapsed=$elapsed ${rating.name}', () {
        final result = fsrs.next(item(s, d), rating, elapsed);
        expect(result.stability, closeTo(outS, eps));
        expect(result.difficulty, closeTo(outD, eps));
        expect(result.elapsedDays, elapsed);
        if (interval >= 0) expect(result.scheduledDays, interval);
      });
    }
  });

  group('FSRS-5 遗忘分支的短期上限', () {
    // 官方 py-fsrs 4.1.2 的 `_next_forget_stability` 会取小：
    //   min(长期值, S / e^(w17·w18))，w17=0.51655、w18=0.6621 ⇒ S / e^(0.342008…) = S / 1.4078…
    // 既有黄金向量里 (S=2.4, D=5.0, elapsed=30, again) 的 1.7048224703525037 就是被这个上限截出来的，
    // 但那条用例只断言数值，看不出走的是哪条分支。这里用一条官方向量把它钉死。
    test('遗忘的短期上限真的会取小：S 被封顶到 S/e^(w17·w18)，小于未封顶的长期值', () {
      // 与官方对照用例同一入口：init(again) 给出 S0=0.40255、D0=7.1949
      final initAgain = fsrs.init(FsrsRating.again);
      expect(initAgain.stability, closeTo(0.40255, eps));
      expect(initAgain.difficulty, closeTo(7.1949, eps));

      final result = fsrs.next(initAgain, FsrsRating.again, 30);

      // 官方 py-fsrs 4.1.2：取小后的 stability = 0.2859484522668335、difficulty = 8.082797017759107
      expect(result.stability, closeTo(0.2859484522668335, eps));
      expect(result.difficulty, closeTo(8.082797017759107, eps));
      // 官方同一分支里"未取小"的长期公式值 = 0.9385616153751637（是上限 0.2859… 的 3.28 倍）
      expect(
        result.stability,
        lessThan(0.9385616153751637),
        reason: '若 min(长期值, S/e^(w17·w18)) 的取小分支被删掉，这里会拿到未封顶的 0.9385…',
      );
    });
  });

  group('FSRS-5 当天重复评分（短期记忆）', () {
    // (S_in, D_in, rating, S_out, D_out, 间隔天数)
    const cases = <(double, double, FsrsRating, double, double, int)>[
      (2.4, 5.0, FsrsRating.again, 1.2024684580644198, 6.607035107311108, -1),
      (2.4, 5.0, FsrsRating.hard, 2.0156192985142365, 5.7994339073111085, 2),
      (2.4, 5.0, FsrsRating.good, 3.3786509153700988, 4.991832707311108, 3),
      (2.4, 5.0, FsrsRating.easy, 5.66341174464131, 4.184231507311108, 6),
      (10.0, 5.0, FsrsRating.again, 5.010285241935083, 6.607035107311108, -1),
      (10.0, 5.0, FsrsRating.hard, 8.398413743809318, 5.7994339073111085, 8),
      (10.0, 5.0, FsrsRating.good, 14.077712147375411, 4.991832707311108, 14),
      (10.0, 5.0, FsrsRating.easy, 23.59754893600546, 4.184231507311108, 24),
      (100.0, 3.0, FsrsRating.again, 50.10285241935083, 5.262316067311109, -1),
      (100.0, 3.0, FsrsRating.hard, 83.98413743809319, 4.131674387311109, 84),
      (100.0, 3.0, FsrsRating.good, 140.7771214737541, 3.001032707311108, 141),
      (100.0, 3.0, FsrsRating.easy, 235.9754893600546, 1.8703910273111084, 236),
    ];

    for (final (s, d, rating, outS, outD, interval) in cases) {
      test('S=$s D=$d ${rating.name}', () {
        final result = fsrs.next(item(s, d), rating, 0);
        expect(result.stability, closeTo(outS, eps));
        expect(result.difficulty, closeTo(outD, eps));
        expect(result.elapsedDays, 0);
        if (interval >= 0) expect(result.scheduledDays, interval);
      });
    }

    test('答对提升稳定性、答错降低稳定性（不再重设回初始值）', () {
      final afterAgain = fsrs.next(item(2.4, 5.0), FsrsRating.again, 0);
      expect(afterAgain.stability, lessThan(2.4));
      final recovered = fsrs.next(afterAgain, FsrsRating.good, 0);
      expect(recovered.stability, greaterThan(afterAgain.stability));
    });
  });

  group('FSRS 行为约束', () {
    test('cross-day rating ordering: hard < good < easy', () {
      final base = fsrs.init(FsrsRating.good);

      final hardItem = fsrs.next(base, FsrsRating.hard, 1);
      final goodItem = fsrs.next(base, FsrsRating.good, 1);
      final easyItem = fsrs.next(base, FsrsRating.easy, 1);

      expect(hardItem.stability, lessThan(goodItem.stability));
      expect(goodItem.stability, lessThan(easyItem.stability));

      expect(hardItem.difficulty, greaterThan(goodItem.difficulty));
      expect(goodItem.difficulty, greaterThan(easyItem.difficulty));
    });

    test('reps/lapses 累计，state 缺省按评分推断', () {
      final base = item(10.0, 5.0);
      final again = fsrs.next(base, FsrsRating.again, 1);
      expect(again.reps, 1);
      expect(again.lapses, 1);
      expect(again.state, FsrsState.relearning);

      final good = fsrs.next(again, FsrsRating.good, 1);
      expect(good.reps, 2);
      expect(good.lapses, 1);
      expect(good.state, FsrsState.review);
    });

    test('nextState 覆盖：学习步骤未走完时保持 learning', () {
      expect(
        fsrs.next(item(2.4, 5.0), FsrsRating.good, 0, nextState: FsrsState.learning).state,
        FsrsState.learning,
      );
      expect(
        fsrs.next(item(2.4, 5.0), FsrsRating.again, 0, nextState: FsrsState.relearning).state,
        FsrsState.relearning,
      );
      expect(
        fsrs.next(item(2.4, 5.0), FsrsRating.good, 1, nextState: FsrsState.review).state,
        FsrsState.review,
      );
    });

    test('difficulty 恒在 [1.0, 10.0]', () {
      var result = fsrs.init(FsrsRating.again);
      for (var i = 0; i < 10; i++) {
        result = fsrs.next(result, FsrsRating.again, 1);
      }
      expect(result.difficulty, lessThanOrEqualTo(10.0));

      result = fsrs.init(FsrsRating.easy);
      for (var i = 0; i < 10; i++) {
        result = fsrs.next(result, FsrsRating.easy, 5);
      }
      expect(result.difficulty, greaterThanOrEqualTo(1.0));
    });

    test('stability 下限为 0.1', () {
      var result = fsrs.init(FsrsRating.good);
      for (var i = 0; i < 10; i++) {
        result = fsrs.next(result, FsrsRating.again, 1);
      }
      expect(result.stability, greaterThanOrEqualTo(0.1));
    });

    test('init 难度钳制（自定义权重）', () {
      final customFsrs = FSRS(w: [
        0.4, 0.6, 2.4, 5.8,
        0.5, // w4：初始难度基准
        5.0, // w5：难度指数系数
        0.86, 0.01, 1.49, 0.14, 0.94, 2.18, 0.05, 0.34, 1.26, 0.29, 2.61, 0.51, 0.66
      ]);

      // D0(easy) = 0.5 - e^(5*3) + 1 < 1 -> 钳制到 1.0
      expect(customFsrs.init(FsrsRating.easy).difficulty, 1.0);
    });

    test('间隔随目标保留率提高而缩短', () {
      final normal = FSRS(requestRetention: 0.9).init(FsrsRating.good);
      final strict = FSRS(requestRetention: 0.95).init(FsrsRating.good);
      expect(strict.scheduledDays, lessThan(normal.scheduledDays));
    });
  });

  group('FSRS-5 稳定度下限（本地自加口径，非官方行为）', () {
    // app/lib/util/fsrs.dart:22 的 _minStability = 0.1 是本项目自己加的：
    // 官方 py-fsrs 4.1.2 的 `_next_stability` 与 `_short_term_stability` 都没有这个下限，
    // 因此下面这些输入本地值会严格大于官方值。此处断言的是"当前本地口径"，并记录官方数值便于日后核对。
    test('同日 again：官方 0.050102852419350835，本地抬到 0.1', () {
      final result = fsrs.next(item(0.1, 5.0), FsrsRating.again, 0);
      expect(result.stability, 0.1,
          reason: '官方 py-fsrs 4.1.2 同输入给 0.050102852419350835；本地下限把它抬到 0.1');
    });

    test('跨天 1 天 again：官方 0.07103426959802099，本地抬到 0.1', () {
      final result = fsrs.next(item(0.1, 5.0), FsrsRating.again, 1);
      expect(result.stability, 0.1,
          reason: '官方 py-fsrs 4.1.2 同输入给 0.07103426959802099（遗忘短期上限 min(长期值, S/1.4078)）；本地抬到 0.1');
    });

    test('init 也吃这个下限：官方 w0=0.05 会给出 0.05，本地抬到 0.1', () {
      final customFsrs = FSRS(w: [
        0.05, // w0：again 档初始稳定度，官方会用 0.05
        1.18385, 3.173, 15.69105, 7.1949, 0.5345, 1.4604, 0.0046, 1.54575,
        0.1192, 1.01925, 1.9395, 0.11, 0.29605, 2.2698, 0.2315, 2.9898, 0.51655, 0.6621
      ]);
      expect(customFsrs.init(FsrsRating.again).stability, 0.1,
          reason: '官方 py-fsrs 4.1.2 无下限，同权重会给 0.05；本地取下限 0.1');
    });
  });

  group('下次复习间隔反解（_calculateInterval）', () {
    // 官方 py-fsrs 4.1.2 `Scheduler._next_interval`：
    //   round(S / FACTOR * (desired_retention^(1/DECAY) - 1))，再 max(1)、min(maximum_interval)
    // 目标保留率 = 0.9 时 (0.9^-2 - 1) / FACTOR = 1，间隔恰好等于稳定度。
    test('目标保留率 0.9：间隔等于稳定度（官方同值）', () {
      expect(FSRS(requestRetention: 0.9).init(FsrsRating.good).scheduledDays, 3); // S=3.173
    });

    test('目标保留率 ≠ 0.9：0.8 → 8 天、0.95 → 1 天（官方 _next_interval 对照）', () {
      expect(FSRS(requestRetention: 0.8).init(FsrsRating.good).scheduledDays, 8,
          reason: '官方 py-fsrs 4.1.2 同输入为 8 天');
      expect(FSRS(requestRetention: 0.95).init(FsrsRating.good).scheduledDays, 1,
          reason: '官方 py-fsrs 4.1.2 同输入为 1 天（严格档位把间隔压到最短）');
    });
  });

  group('退化输入与守卫断言', () {
    test('stability 为 0 / 负数 / 非有限值时立即暴露', () {
      for (final bad in [0.0, -1.0, double.nan, double.infinity]) {
        expect(() => fsrs.next(item(bad, 5.0), FsrsRating.good, 1),
            throwsA(isA<AssertionError>()),
            reason: 'stability=$bad 必须在守卫处报错，而不是算出脏的记忆参数');
      }
    });

    test('difficulty 越界（<1 或 >10）或非有限值时立即暴露', () {
      for (final bad in [0.999, 10.001, double.nan]) {
        expect(() => fsrs.next(item(2.4, bad), FsrsRating.good, 1),
            throwsA(isA<AssertionError>()), reason: 'difficulty=$bad 必须在守卫处报错');
      }
    });

    test('elapsedDays 为负时立即暴露', () {
      expect(() => fsrs.next(item(2.4, 5.0), FsrsRating.good, -1),
          throwsA(isA<AssertionError>()));
    });

    test('目标保留率越界或权重不足 19 个时立即暴露', () {
      expect(() => FSRS(requestRetention: 1.0).init(FsrsRating.good),
          throwsA(isA<AssertionError>()));
      expect(() => FSRS(requestRetention: 0.0).init(FsrsRating.good),
          throwsA(isA<AssertionError>()));
      expect(() => FSRS(w: List<double>.filled(18, 0.1)),
          throwsA(isA<AssertionError>()));
    });
  });
}
