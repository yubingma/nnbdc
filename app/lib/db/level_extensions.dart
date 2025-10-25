import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/api/vo.dart';

/// Level类的扩展方法
extension LevelExtensions on Level {
  /// 将Level转换为LevelVo
  LevelVo toLevelVo() {
    final levelVo = LevelVo(id);
    levelVo.level = level;
    levelVo.name = name;
    levelVo.figure = figure;
    levelVo.minScore = minScore;
    levelVo.maxScore = maxScore;
    levelVo.style = style;
    return levelVo;
  }
} 