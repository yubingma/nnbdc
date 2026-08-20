import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/study_track.dart';

/// 三组学习规则（check=测评 / correct=答对后 / wrong=答错后）
typedef ThreeGroupSteps = ({String check, List<String> correct, List<String> wrong});

/// 用户学习步骤服务：单表三组结构（scope='new' 新词 / 'review' 旧词），
/// 新词与旧词的学习规则同构，仅默认值与 FSRS 评分语义不同。
class StudyStepsService {
  /// 注意：不要缓存 `MyDatabase.instance`。
  MyDatabase get _db => MyDatabase.instance;

  /// 读取指定 scope 的三组规则；表空（未配置）时返回默认值（不落库）。
  Future<ThreeGroupSteps> getThreeGroupConfig(String scope) async {
    final user = Global.getLoggedInUser();
    final steps = user == null
        ? <UserStudyStep>[]
        : await _db.userStudyStepsDao.getStepsOfScope(user.id, scope);
    String? check;
    final correct = <String>[];
    final wrong = <String>[];
    for (final s in steps) {
      if (s.state != 'Active') continue;
      switch (s.group) {
        case 'check':
          check = s.studyStep;
          break;
        case 'correct':
          correct.add(s.studyStep);
          break;
        case 'wrong':
          wrong.add(s.studyStep);
          break;
      }
    }
    if (check != null) {
      return (check: check, correct: correct, wrong: wrong);
    }
    // 未配置：默认三组
    if (scope == 'new') {
      const defaultSteps = ['Ch2En'];
      return (check: 'En2Ch', correct: defaultSteps, wrong: defaultSteps);
    }
    // review 默认：check=新词 check、correct=[]、wrong=[反向互补]
    final newCfg = await getThreeGroupConfig('new');
    return (
      check: newCfg.check,
      correct: const <String>[],
      wrong: [StudyTrack.oppositeWordStep(newCfg.check)],
    );
  }

  /// diff 保存指定 scope 的三组规则（删除与插入的主键互不重叠，同步顺序无关）
  Future<void> saveThreeGroupConfig({
    required String scope,
    required String check,
    required List<String> correct,
    required List<String> wrong,
  }) async {
    final user = Global.getLoggedInUser();
    if (user == null) throw Exception('用户未登录');
    final now = AppClock.now();

    final targets = <String, Map<String, int>>{
      'check': {check: 0},
      'correct': {for (int i = 0; i < correct.length; i++) correct[i]: i},
      'wrong': {for (int i = 0; i < wrong.length; i++) wrong[i]: i},
    };

    final existing = await _db.userStudyStepsDao.getStepsOfScope(user.id, scope);
    final existingByGroup = <String, Map<String, UserStudyStep>>{};
    for (final e in existing) {
      existingByGroup.putIfAbsent(e.group, () => {})[e.studyStep] = e;
    }

    final pendingSaves = <UserStudyStep>[];
    for (final group in ['check', 'correct', 'wrong']) {
      final target = targets[group]!;
      final cur = existingByGroup[group] ?? <String, UserStudyStep>{};
      // 删除：现有中存在但目标中已移除的环节
      for (final step in cur.keys) {
        if (!target.containsKey(step)) {
          await _db.userStudyStepsDao
              .deleteUserStudyStep(user.id, scope, group, step, true);
        }
      }
      // 插入/更新：目标中的环节
      target.forEach((step, seq) {
        final old = cur[step];
        pendingSaves.add(UserStudyStep(
          userId: user.id,
          scope: scope,
          group: group,
          studyStep: step,
          seq: seq,
          state: 'Active',
          createTime: old?.createTime ?? now,
          updateTime: now,
        ));
      });
    }
    for (final e in pendingSaves) {
      await _db.userStudyStepsDao.saveUserStudyStep(e, true);
    }
  }
}
