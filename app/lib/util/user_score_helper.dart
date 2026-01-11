import 'package:nnbdc/db/db.dart';

/// 用户积分帮助类
class UserScoreHelper {
  /// 根据用户的游戏积分和打卡积分计算总积分
  static int calculateTotalScore(int? gameScore, int? dakaScore) {
    return (gameScore ?? 0) + (dakaScore ?? 0);
  }

  /// 从User对象获取总积分
  static int getTotalScoreFromUser(User user) {
    return calculateTotalScore(user.gameScore, user.dakaScore);
  }

  /// 从User对象获取游戏积分
  static int getGameScoreFromUser(User user) {
    return user.gameScore;
  }

  /// 从User对象获取打卡积分
  static int getDakaScoreFromUser(User user) {
    return user.dakaScore;
  }
}