import 'package:nnbdc/util/fsrs.dart';
import 'package:nnbdc/api/enum.dart';

void main() {
  testRating(FsrsRating.easy, "Easy");
  print("----------------------------------");
  testRating(FsrsRating.good, "Good");
  print("----------------------------------");
  testRating(FsrsRating.hard, "Hard");
}

void testRating(FsrsRating rating, String label) {
  print("==== Testing $label ====");
  var fsrs = FSRS();
  var currentFsrs = fsrs.init(rating);
  int totalDays = 0;
  int learningTimes = 1;

  print("第 ${learningTimes} 次学习 (Day 0), stability: ${currentFsrs.stability.toStringAsFixed(2)}, 下次规划天数: ${currentFsrs.scheduledDays}");

  while (currentFsrs.stability < 180.0 && learningTimes < 20) {
    learningTimes++;
    int elapsedDays = currentFsrs.scheduledDays > 0 ? currentFsrs.scheduledDays : 1;
    totalDays += elapsedDays;
    currentFsrs = fsrs.next(currentFsrs, rating, elapsedDays);
    print("第 ${learningTimes} 次复习 (间隔 ${elapsedDays} 天 | 总计第 ${totalDays} 天), stability: ${currentFsrs.stability.toStringAsFixed(2)}, 下次规划天数: ${currentFsrs.scheduledDays}");
  }

  if (currentFsrs.stability >= 180.0) {
    print("🎓 [$label] 顺利毕业! 耗时: ${totalDays} 天, 复习次数: ${learningTimes} 次");
  } else {
    print("❌ [$label] 未能毕业, stability: ${currentFsrs.stability.toStringAsFixed(2)}");
  }
}
