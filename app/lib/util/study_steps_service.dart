import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/db/dao.dart';
import 'package:nnbdc/util/app_clock.dart';

/// 用户学习步骤服务，提供本地数据库操作实现
class StudyStepsService {
  final _db = MyDatabase.instance;

  /// 获取当前用户的所有学习步骤
  Future<List<UserStudyStepVo>> getUserStudySteps() async {
    // 获取当前登录用户
    final user = Global.getLoggedInUser();
    if (user == null) {
      return [];
    }

    // 初始化学习步骤（如果需要）
    final clientType = await _getClientType();
    await _db.userStudyStepsDao.initUserStudySteps(clientType, user.id, true);

    // 查询学习步骤
    final steps = await _db.userStudyStepsDao.getUserStudySteps(user.id);

    // 转换为VO对象
    return steps.map(_convertToVo).toList();
  }

  /// 获取当前用户的激活状态的学习步骤
  Future<List<UserStudyStepVo>> getActiveUserStudySteps() async {
    // 获取当前登录用户
    final user = Global.getLoggedInUser();
    if (user == null) {
      return [];
    }

    // 查询激活的学习步骤
    final steps = await _db.userStudyStepsDao.getActiveUserStudySteps(user.id);

    // 转换为VO对象
    return steps.map(_convertToVo).toList();
  }

  /// 保存用户学习步骤
  Future<void> saveUserStudySteps(List<UserStudyStepVo> steps) async {
    final user = Global.getLoggedInUser();
    if (user == null) {
      throw Exception('用户未登录');
    }

    final dao = UserStudyStepsDao(_db);
    try {
      // 转换为实体对象
      final entities = steps
          .map((vo) => UserStudyStep(
                userId: user.id,
                studyStep: vo.studyStep,
                seq: vo.seq,
                state: vo.state,
                createTime: AppClock.now(),
              ))
          .toList();

      await dao.saveUserStudySteps(entities, user.id, true);
    } catch (e) {
      Global.logger.d('保存学习步骤到本地数据库失败: $e');
      rethrow;
    }
  }

  /// 获取客户端类型
  Future<String> _getClientType() async {
    // 根据实际情况返回客户端类型，这里简单返回Flutter
    return 'Flutter';
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
      case 'Word':
        return StudyStep.word;
      case 'Meaning':
        return StudyStep.meaning;
      default:
        return StudyStep.word;
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
