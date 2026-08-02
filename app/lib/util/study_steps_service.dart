import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/app_clock.dart';

/// 用户学习步骤服务，提供本地数据库操作实现
class StudyStepsService {
  /// 注意：不要缓存 `MyDatabase.instance`。
  /// 数据库在 `wipeAllTables()` / `closeDatabase()` 后会重建实例，
  /// 若缓存旧实例会导致 "Can't re-open a database after closing it"。
  MyDatabase get _db => MyDatabase.instance;

  /// 获取当前用户的所有学习步骤
  Future<List<UserStudyStepVo>> getUserStudySteps() async {
    // 获取当前登录用户
    final user = Global.getLoggedInUser();
    if (user == null) {
      return [];
    }

    // 查询学习步骤
    final steps = await _db.userStudyStepsDao.getUserStudySteps(user.id);


    // 转换为VO对象
    var voSteps = steps.map(_convertToVo).toList();
    
    // 过滤掉所有不认识的未知步骤（防崩兜底）
    voSteps.removeWhere((s) => s.studyStep == 'Unknown');

    // 检查并补全缺失的标准学习步骤 (如 EnSentence2Ch、ChSentence2En)
    bool needsPersist = false;
    final requiredSteps = ['En2Ch', 'Ch2En', 'EnSentence2Ch', 'ChSentence2En'];
    for (final stepName in requiredSteps) {
      if (!voSteps.any((s) => s.studyStep == stepName)) {
        // 例句新模式默认不要选中 (Inactive)
        final isSentenceStep = stepName == 'EnSentence2Ch' || stepName == 'ChSentence2En';
        final defaultState = isSentenceStep ? StudyStepState.inactive.json : StudyStepState.active.json;
        voSteps.add(UserStudyStepVo(stepName, voSteps.length, defaultState));
        needsPersist = true;
      }
    }

    // 强制“单词列表”阶段排在最后且必须激活
    var listStepIndex = voSteps.indexWhere((s) => s.studyStep == 'List');
    UserStudyStepVo? listStep;

    if (listStepIndex != -1) {
      listStep = voSteps.removeAt(listStepIndex);
    } else {
      // 单词列表(List)是内置的、必须拥有的核心步骤。如果丢失，无论是否是游客，都应在内存中予以补齐，
      // 以便答题流程正常运转，稍后若有保存操作或启动时数据健康检查，它就会被持久化及同步到云端。
      listStep = UserStudyStepVo('List', voSteps.length, StudyStepState.active.json);
      needsPersist = true;
    }

    listStep.state = StudyStepState.active.json;
    voSteps.add(listStep);

    // 重新校正所有的seq，确保有序且List排在最后
    for (var i = 0; i < voSteps.length; i++) {
      voSteps[i].seq = i;
    }

    if (needsPersist) {
      // 补全缺失步骤时必须静默保存 (genLog: false)，严禁产生本地 db_log，防止上报服务端触发同步报错
      try {
        final now = AppClock.now();
        final entities = voSteps
            .map((vo) => UserStudyStep(
                  userId: user.id,
                  studyStep: vo.studyStep,
                  seq: vo.seq,
                  state: vo.state,
                  createTime: now,
                  updateTime: now,
                ))
            .toList();
        await _db.userStudyStepsDao.saveUserStudySteps(entities, user.id, false);
      } catch (e) {
        Global.logger.w('静默补全缺失学习步骤到本地数据库失败: $e');
      }
    }

    return voSteps;
  }

  /// 获取当前用户的激活状态的学习步骤
  Future<List<UserStudyStepVo>> getActiveUserStudySteps() async {
    // 直接复用 getUserStudySteps 以确保规则一致（List必然存在且在最后）
    final allSteps = await getUserStudySteps();

    // 转换为VO对象
    return allSteps.where((s) => s.state == StudyStepState.active.json).toList();
  }

  /// 保存用户学习步骤
  Future<void> saveUserStudySteps(List<UserStudyStepVo> steps) async {
    final user = Global.getLoggedInUser();
    if (user == null) {
      throw Exception('用户未登录');
    }

    try {
      // 转换为VO对象以便于处理
      var voSteps = List<UserStudyStepVo>.from(steps);

      // 确保标准例句步骤不会因前端保存丢失
      final requiredSteps = ['En2Ch', 'Ch2En', 'EnSentence2Ch', 'ChSentence2En'];
      for (final stepName in requiredSteps) {
        if (!voSteps.any((s) => s.studyStep == stepName)) {
          // 如果用户提交的设置中没有此步骤，以 Inactive 状态追加补全
          voSteps.add(UserStudyStepVo(stepName, voSteps.length, StudyStepState.inactive.json));
        }
      }

      // 强制“单词列表”阶段排在最后且必须激活
      var listStepIndex = voSteps.indexWhere((s) => s.studyStep == 'List');
      UserStudyStepVo? listStep;

      if (listStepIndex != -1) {
        listStep = voSteps.removeAt(listStepIndex);
      } else {
        // 单词列表(List)是内置的、必须拥有的核心步骤。保存时如果传入的步骤列表（通常来自
        // 首页今日计划，该页面会过滤掉List步骤不显示）中没有List步骤，我们也应该无条件补齐它。
        listStep = UserStudyStepVo('List', voSteps.length, StudyStepState.active.json);
      }

      listStep.state = StudyStepState.active.json;
      voSteps.add(listStep);

      // 重新校正顺序
      for (var i = 0; i < voSteps.length; i++) {
        voSteps[i].seq = i;
      }

      // 转换为实体对象
      final now = AppClock.now();
      final entities = voSteps
          .map((vo) => UserStudyStep(
                userId: user.id,
                studyStep: vo.studyStep,
                seq: vo.seq,
                state: vo.state,
                createTime: now,
                updateTime: now,
              ))
          .toList();

      await _db.userStudyStepsDao.saveUserStudySteps(entities, user.id, true);
    } catch (e) {
      Global.logger.d('保存学习步骤到本地数据库失败: $e');
      rethrow;
    }
  }


  /// 将数据库实体转换为VO对象
  UserStudyStepVo _convertToVo(UserStudyStep step) {
    final studyStep = _getStudyStepFromString(step.studyStep);
    final state = _getStudyStepStateFromString(step.state);

    return UserStudyStepVo(studyStep.json, step.seq, state.json);
  }

  /// 从字符串获取StudyStep枚举
  StudyStep _getStudyStepFromString(String stepStr) {
    switch (stepStr) {
      case 'En2Ch':
        return StudyStep.en2Ch;
      case 'Ch2En':
        return StudyStep.ch2En;
      case 'EnSentence2Ch':
        return StudyStep.enSentence2Ch;
      case 'ChSentence2En':
        return StudyStep.chSentence2En;
      case 'List':
        return StudyStep.list;
      default:
        return StudyStep.unknown;
    }
  }

  /// 从字符串获取StudyStepState枚举
  StudyStepState _getStudyStepStateFromString(String stateStr) {
    switch (stateStr) {
      case 'Active':
        return StudyStepState.active;
      case 'Inactive':
        return StudyStepState.inactive;
      default:
        return StudyStepState.inactive;
    }
  }
}
