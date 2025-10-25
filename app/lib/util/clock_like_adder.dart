import 'package:nnbdc/global.dart';

/// 一个模仿时钟工作方式的加法器。
/// 输入为一个二维数组，假设这个数组有m行，n列
/// 需要在每行取一个值，然后对这m个值求和，返回和。
/// 本加法器有状态，每次求和返回的是"下一个"和。
/// 可以把数组的一行想象成时钟的一个指针，第一行是时钟，第二行分针，第三行秒针。。。
/// 每一次求和，首先把最下面的行向右步进一格，上面各行的当前格位置不变，对每行的当前格求和。
/// 如果某行及下面的各行当前格都走到了最右端，则上面的行向右步进一格，并把本行的当前格置为上一行再向右一格（这个细节和时钟不一样，时钟是把本行的当前格设为最左端）
/// 当所有行都走到了最右端，则取完了所有的和，再取返回null.
class ClockLikeAdder {
  final List<List<double>> data;

  /// 数组每一行的当前位置
  late List<int> rowCursors;

  late int rowCount;
  late int colCount;
  late int maxColIndex; // 缓存 colCount - 1

  ClockLikeAdder(this.data) {
    assert(data.isNotEmpty);
    rowCount = data.length;
    colCount = data[0].length;
    maxColIndex = colCount - 1;
    rowCursors = List.filled(rowCount, 0);
    rowCursors[rowCount - 1] = -1; //最下面一行当前格移到最左端的左边，上面各行当前格默认在最左端
  }

  bool _isFinished() {
    return rowCursors[0] > maxColIndex;
  }

  /// 使指定行的当前格向右步进一格
  ///
  /// @param row
  void _stepRight(int row) {
    if (_isFinished()) {
      return;
    }

    rowCursors[row]++;
    if (rowCursors[row] > maxColIndex) {
      // 本行到达超出最右端，使上一行向右步进
      if (row == 0) {
        return;
      }
      _stepRight(row - 1);
    } else {
      // 本行成功步进, 重置下面各行的当前格（每一行比上一行右移一格）
      // 优化：只重置必要的行
      int nextRow = row + 1;
      if (nextRow < rowCount) {
        int basePos = rowCursors[row] + 1;
        for (int i = nextRow; i < rowCount; i++) {
          rowCursors[i] = basePos + (i - nextRow);
        }
      }
    }
  }

  double? _nextSum() {
    if (_isFinished()) {
      return null;
    }

    _stepRight(rowCount - 1);
    if (_isFinished()) {
      return null;
    }

    // 优化：直接计算和，避免重复的边界检查
    double sum = 0.0;
    for (int i = 0; i < rowCount; i++) {
      int pos = rowCursors[i];
      if (pos <= maxColIndex) {
        sum += data[i][pos];
      }
    }
    return sum;
  }

  /// 获取所有nextSum返回值的最大值
  /// enforceOrder: 是否强制顺序约束。当为true时，只考虑列索引递增的组合
  /// 注意：当某一行（字符）无法匹配到任何列（识别字符）时，其游标可能大于最大列索引。
  /// 这种未匹配行不应参与“顺序约束”的比较，否则会错误地阻止后续行与更早的列匹配。
  /// 因此顺序校验时仅对“有效列索引（<= maxColIndex）”进行严格递增检查。
  double maxSum(bool enforceOrder) {
    double max = 0.0;
    double? sum;
    // ignore: unused_local_variable
    int count = 0;

    // 重置状态
    rowCursors = List.filled(rowCount, 0);
    rowCursors[rowCount - 1] = -1;

    while ((sum = _nextSum()) != null) {
      // 如果启用了顺序约束，检查列索引是否递增
      if (enforceOrder) {
        bool validOrder = true;
        int lastPos = -1;
        for (int i = 0; i < rowCount; i++) {
          final pos = rowCursors[i];
          if (pos > maxColIndex) {
            // 未匹配行：忽略于顺序校验
            continue;
          }
          if (pos <= lastPos) {
            validOrder = false;
            break;
          }
          lastPos = pos;
        }
        // 如果有效列索引不是严格递增，跳过这个组合
        if (!validOrder) {
          count++;
          continue;
        }
      }

      max = max > sum! ? max : sum;
      count++;
    }

    return max;
  }

  /// 优化的最大和计算方法（贪心算法）
  /// 直接计算每行的最大值之和，这是理论上的最大可能值
  double maxSumOptimized() {
    double maxSum = 0.0;
    for (int i = 0; i < rowCount; i++) {
      double rowMax = data[i].reduce((a, b) => a > b ? a : b);
      maxSum += rowMax;
    }
    return maxSum;
  }

  /// 检查优化算法是否适用于当前数据
  /// 如果每行的最大值位置满足时钟式约束，则优化算法结果正确
  bool _isOptimizationApplicable() {
    List<int> maxPositions = [];
    for (int i = 0; i < rowCount; i++) {
      double maxVal = data[i][0];
      int maxPos = 0;
      for (int j = 1; j < colCount; j++) {
        if (data[i][j] > maxVal) {
          maxVal = data[i][j];
          maxPos = j;
        }
      }
      maxPositions.add(maxPos);
    }

    // 检查最大值位置是否满足时钟式约束
    for (int i = 1; i < rowCount; i++) {
      if (maxPositions[i] <= maxPositions[i - 1]) {
        return false;
      }
    }
    return true;
  }

  /// 智能最大和计算
  /// 如果优化算法适用，使用优化算法；否则使用原始算法
  double maxSumSmart() {
    if (_isOptimizationApplicable()) {
      return maxSumOptimized();
    } else {
      return maxSum(false);
    }
  }

  /// 检查是否存在和大于等于指定值的组合
  /// 如果找到大于等于指定值的组合，返回true；否则返回false
  bool isMaxSumGreaterOrEquals(double targetValue) {
    // 首先检查理论最大值是否小于目标值
    double theoreticalMax = maxSumOptimized();
    if (theoreticalMax < targetValue) {
      Global.logger.d('isMaxSumGreaterOrEquals: theoretical max ($theoreticalMax) < target ($targetValue), impossible to reach');
      return false;
    }

    // 如果理论最大值大于等于目标值，且优化算法适用，直接返回true
    if (_isOptimizationApplicable()) {
      Global.logger.d('isMaxSumGreaterOrEquals: optimization applicable, theoretical max ($theoreticalMax) >= target ($targetValue)');
      return true;
    }

    // 否则使用原始算法进行搜索
    double max = 0.0;
    double? sum;
    int count = 0;

    // 重置状态
    rowCursors = List.filled(rowCount, 0);
    rowCursors[rowCount - 1] = -1;

    while ((sum = _nextSum()) != null) {
      max = max > sum! ? max : sum;
      count++;

      // 早期终止：如果找到大于等于目标值的组合，可以提前结束
      if (max >= targetValue) {
        Global.logger.d('isMaxSumGreaterOrEquals early termination: found value >= $targetValue at iteration $count');
        return true;
      }

      // 性能监控：每10000次迭代打印一次进度
      if (count % 10000 == 0) {
        Global.logger.d(
            'isMaxSumGreaterOrEquals progress: $count iterations, current max: ${max.toStringAsFixed(2)}, target: ${targetValue.toStringAsFixed(2)}');
      }
    }

    Global.logger.d('isMaxSumGreaterOrEquals completed: $count total iterations, final max: ${max.toStringAsFixed(2)}');
    return false;
  }
}

void main() {
  List<List<double>> data = [
    [1, 2, 3, 4],
    [1, 2, 3, 4],
    [1, 2, 3, 4],
    [1, 2, 3, 4],
    [1, 2, 3, 4]
  ];
  ClockLikeAdder adder = ClockLikeAdder(data);
  double? sum;
  while ((sum = adder._nextSum()) != null) {
    Global.logger.d(sum.toString());
  }
}
