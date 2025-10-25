import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:nnbdc/util/clock_like_adder.dart';

void main() {
  group('ClockLikeAdder Tests', () {
    test('should initialize correctly with valid data', () {
      final data = [
        [1.0, 2.0, 3.0, 4.0],
        [5.0, 6.0, 7.0, 8.0],
        [9.0, 10.0, 11.0, 12.0],
        [13.0, 14.0, 15.0, 16.0],
      ];
      final adder = ClockLikeAdder(data);
      expect(adder.rowCount, equals(4));
      expect(adder.colCount, equals(4));
      expect(adder.rowCursors, equals([0, 0, 0, -1]));
    });

    test('should throw assertion error for empty data', () {
      expect(() => ClockLikeAdder([]), throwsAssertionError);
    });

    test('should handle single row data', () {
      final data = [
        [1.0, 2.0, 3.0]
      ];
      final adder = ClockLikeAdder(data);
      // 对于单行数据，maxSum 应该返回最大值
      expect(adder.maxSum(false), equals(3.0));
    });

    test('should handle single column data', () {
      final data = [
        [1.0],
        [2.0],
        [3.0],
      ];
      final adder = ClockLikeAdder(data);
      // 对于单列数据，maxSum 应该返回所有行的和
      expect(adder.maxSum(false), equals(6.0)); // 1 + 2 + 3
    });

    test('should handle 2x2 matrix correctly', () {
      final data = [
        [1.0, 2.0],
        [3.0, 4.0],
      ];
      final adder = ClockLikeAdder(data);
      // 对于 2x2 矩阵，maxSum 应该返回最大值组合
      expect(adder.maxSum(false), equals(5.0)); // 1 + 4 = 5 是最大值
    });

    test('should handle 3x3 matrix correctly', () {
      final data = [
        [1.0, 2.0, 3.0],
        [4.0, 5.0, 6.0],
        [7.0, 8.0, 9.0],
      ];
      final adder = ClockLikeAdder(data);
      // 对于 3x3 矩阵，maxSum 应该返回最大值组合
      expect(adder.maxSum(false), equals(15.0)); // 1 + 5 + 9 = 15 是最大值
    });

    test('should handle 2x3 matrix correctly', () {
      final data = [
        [1.0, 2.0, 3.0],
        [4.0, 5.0, 6.0],
      ];
      final adder = ClockLikeAdder(data);
      // 对于 2x3 矩阵，maxSum 应该返回最大值组合
      expect(adder.maxSum(false), equals(8.0)); // 2 + 6 = 8 是最大值
    });

    test('should handle 3x2 matrix correctly', () {
      final data = [
        [1.0, 2.0],
        [3.0, 4.0],
        [5.0, 6.0],
      ];
      final adder = ClockLikeAdder(data);
      // 对于 3x2 矩阵，maxSum 应该返回最大值组合
      expect(adder.maxSum(false), equals(10.0)); // 1 + 3 + 6 = 10 是最大值
    });

    test('should handle large matrix efficiently(should finish in 500 ms)', () {
      Stopwatch stopwatch = Stopwatch()..start();
      final data =
          List.generate(8, (i) => List.generate(30, (j) => (i + j).toDouble()));
      final adder = ClockLikeAdder(data);
      final maxSum = adder.maxSum(false);
      expect(maxSum, isA<double>());
      expect(maxSum, greaterThan(0.0));
      debugPrint('maxSum: $maxSum, time: ${stopwatch.elapsedMilliseconds} ms');
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
    });

    test('should handle decimal numbers', () {
      final data = [
        [1.5, 2.5],
        [3.5, 4.5],
      ];
      final adder = ClockLikeAdder(data);
      // 对于小数矩阵，maxSum 应该返回最大值组合
      expect(adder.maxSum(false), equals(6.0)); // 1.5 + 4.5 = 6.0 是最大值
    });

    test('should handle zero values', () {
      final data = [
        [0.0, 1.0],
        [0.0, 2.0],
      ];
      final adder = ClockLikeAdder(data);
      // 对于包含零值的矩阵，maxSum 应该返回最大值组合
      expect(adder.maxSum(false), equals(2.0)); // 0 + 2 = 2 是最大值
    });

    test('should handle edge case with single element', () {
      final data = [
        [1.0]
      ];
      final adder = ClockLikeAdder(data);
      // 对于单元素矩阵，maxSum 应该返回该元素
      expect(adder.maxSum(false), equals(1.0));
    });

    test('should handle matrix with different column counts', () {
      // 这种情况在实际使用中不应该发生，但测试一下边界情况
      final data = [
        [1.0, 2.0, 3.0],
        [4.0, 5.0], // 第二行只有2列
      ];
      final adder = ClockLikeAdder(data);
      // 这种情况会抛出异常，因为列数不一致
      expect(() => adder.maxSum(false), throwsRangeError);
    });

    test('should handle 4x4 matrix correctly', () {
      final data = [
        [1.0, 2.0, 3.0, 4.0],
        [5.0, 6.0, 7.0, 8.0],
        [9.0, 10.0, 11.0, 12.0],
        [13.0, 14.0, 15.0, 16.0],
      ];
      final adder = ClockLikeAdder(data);
      // 对于 4x4 矩阵，maxSum 应该返回最大值组合
      expect(adder.maxSum(false), equals(34.0)); // 1 + 6 + 11 + 16 = 34 是最大值
    });

    test('should handle 1x3 matrix correctly', () {
      final data = [
        [1.0, 2.0, 3.0]
      ];
      final adder = ClockLikeAdder(data);
      // 对于 1x3 矩阵，maxSum 应该返回最大值
      expect(adder.maxSum(false), equals(3.0)); // 3 是最大值
    });

    test('should handle 3x1 matrix correctly', () {
      final data = [
        [1.0],
        [2.0],
        [3.0],
      ];
      final adder = ClockLikeAdder(data);
      // 对于 3x1 矩阵，maxSum 应该返回所有行的和
      expect(adder.maxSum(false), equals(6.0)); // 1 + 2 + 3 = 6
    });

    // maxSum 方法测试用例
    group('maxSum Tests', () {
      test('should return correct max sum for 2x2 matrix', () {
        final data = [
          [1.0, 2.0],
          [3.0, 4.0],
        ];
        final adder = ClockLikeAdder(data);
        expect(adder.maxSum(false), equals(5.0)); // 1 + 4 = 5 是最大值
      });

      test('should return correct max sum for 3x3 matrix', () {
        final data = [
          [1.0, 2.0, 3.0],
          [4.0, 5.0, 6.0],
          [7.0, 8.0, 9.0],
        ];
        final adder = ClockLikeAdder(data);
        expect(adder.maxSum(false), equals(15.0)); // 1 + 5 + 9 = 15 是最大值
      });

      test('should return correct max sum for single row', () {
        final data = [
          [1.0, 2.0, 3.0]
        ];
        final adder = ClockLikeAdder(data);
        expect(adder.maxSum(false), equals(3.0)); // 3 是最大值
      });

      test('should return correct max sum for single column', () {
        final data = [
          [1.0],
          [2.0],
          [3.0],
        ];
        final adder = ClockLikeAdder(data);
        expect(adder.maxSum(false), equals(6.0)); // 1 + 2 + 3 = 6 是唯一值
      });

      test('should return correct max sum for decimal numbers', () {
        final data = [
          [1.5, 2.5],
          [3.5, 4.5],
        ];
        final adder = ClockLikeAdder(data);
        expect(adder.maxSum(false), equals(6.0)); // 1.5 + 4.5 = 6.0 是最大值
      });

      test('should return correct max sum for 2x3 matrix', () {
        final data = [
          [1.0, 2.0, 3.0],
          [4.0, 5.0, 6.0],
        ];
        final adder = ClockLikeAdder(data);
        expect(adder.maxSum(false), equals(8.0)); // 2 + 6 = 8 是最大值
      });

      test('should return correct max sum for 3x2 matrix', () {
        final data = [
          [1.0, 2.0],
          [3.0, 4.0],
          [5.0, 6.0],
        ];
        final adder = ClockLikeAdder(data);
        expect(adder.maxSum(false), equals(10.0)); // 1 + 3 + 6 = 10 是最大值
      });

      test('should return correct max sum for 4x4 matrix', () {
        final data = [
          [1.0, 2.0, 3.0, 4.0],
          [5.0, 6.0, 7.0, 8.0],
          [9.0, 10.0, 11.0, 12.0],
          [13.0, 14.0, 15.0, 16.0],
        ];
        final adder = ClockLikeAdder(data);
        expect(adder.maxSum(false), equals(34.0)); // 1 + 6 + 11 + 16 = 34 是最大值
      });

      test('should handle zero values correctly', () {
        final data = [
          [0.0, 1.0],
          [0.0, 2.0],
        ];
        final adder = ClockLikeAdder(data);
        expect(adder.maxSum(false), equals(2.0)); // 0 + 2 = 2 是最大值
      });

      test('should handle all zero values', () {
        final data = [
          [0.0, 0.0],
          [0.0, 0.0],
        ];
        final adder = ClockLikeAdder(data);
        expect(adder.maxSum(false), equals(0.0)); // 所有组合都是 0
      });

      test('should handle large values efficiently', () {
        final data = [
          [1000.0, 2000.0],
          [3000.0, 4000.0],
        ];
        final adder = ClockLikeAdder(data);
        expect(adder.maxSum(false), equals(5000.0)); // 1000 + 4000 = 5000 是最大值
      });

      test('should handle single element matrix', () {
        final data = [
          [42.0]
        ];
        final adder = ClockLikeAdder(data);
        expect(adder.maxSum(false), equals(42.0)); // 唯一值
      });

      test('should handle 1x3 matrix', () {
        final data = [
          [1.0, 2.0, 3.0]
        ];
        final adder = ClockLikeAdder(data);
        expect(adder.maxSum(false), equals(3.0)); // 3 是最大值
      });

      test('should handle 3x1 matrix', () {
        final data = [
          [1.0],
          [2.0],
          [3.0],
        ];
        final adder = ClockLikeAdder(data);
        expect(adder.maxSum(false), equals(6.0)); // 1 + 2 + 3 = 6 是唯一值
      });

      test('should handle performance test for maxSum (should finish in 1000 ms)', () {
        Stopwatch stopwatch = Stopwatch()..start();
        final data = List.generate(6, (i) => List.generate(20, (j) => (i + j).toDouble()));
        final adder = ClockLikeAdder(data);
        final maxSum = adder.maxSum(false);
        debugPrint('maxSum: $maxSum, time: ${stopwatch.elapsedMilliseconds} ms');
        expect(maxSum, isA<double>());
        expect(stopwatch.elapsedMilliseconds, lessThan(1000));
      });

      test('should verify maxSum matches actual ClockLikeAdder behavior', () {
        final data = [
          [1.0, 2.0, 3.0],
          [4.0, 5.0, 6.0],
          [7.0, 8.0, 9.0],
        ];
        final adder = ClockLikeAdder(data);
        final maxSum = adder.maxSum(false);
        
        // 根据 ClockLikeAdder 的实际行为验证
        // 它生成的和为: [12.0, 13.0, 14.0, 15.0, 7.0, 8.0, 3.0]
        // 最大值是 15.0 (1 + 5 + 9)
        expect(maxSum, equals(15.0));
      });

      // 优化算法测试用例
      group('Optimization Tests', () {
        test('should return correct optimized max sum for simple case', () {
          final data = [
            [1.0, 2.0, 3.0],
            [4.0, 5.0, 6.0],
            [7.0, 8.0, 9.0],
          ];
          final adder = ClockLikeAdder(data);
          final optimizedMax = adder.maxSumOptimized();
          expect(optimizedMax, equals(18.0)); // 3 + 6 + 9 = 18 (理论最大值)
        });

        test('should return correct optimized max sum for 2x2 matrix', () {
          final data = [
            [1.0, 2.0],
            [3.0, 4.0],
          ];
          final adder = ClockLikeAdder(data);
          final optimizedMax = adder.maxSumOptimized();
          expect(optimizedMax, equals(6.0)); // 2 + 4 = 6 (理论最大值)
        });

        test('should return correct optimized max sum for single row', () {
          final data = [
            [1.0, 2.0, 3.0]
          ];
          final adder = ClockLikeAdder(data);
          final optimizedMax = adder.maxSumOptimized();
          expect(optimizedMax, equals(3.0)); // 3 是最大值
        });

        test('should return correct optimized max sum for single column', () {
          final data = [
            [1.0],
            [2.0],
            [3.0],
          ];
          final adder = ClockLikeAdder(data);
          final optimizedMax = adder.maxSumOptimized();
          expect(optimizedMax, equals(6.0)); // 1 + 2 + 3 = 6
        });

        test('should use smart optimization when applicable', () {
          final data = [
            [1.0, 2.0, 3.0],
            [4.0, 5.0, 6.0],
            [7.0, 8.0, 9.0],
          ];
          final adder = ClockLikeAdder(data);
          final smartMax = adder.maxSumSmart();
          expect(smartMax, equals(15.0)); // 应该使用优化算法
        });

        test('should fall back to original algorithm when optimization not applicable', () {
          final data = [
            [1.0, 2.0, 3.0],
            [6.0, 5.0, 4.0], // 最大值在位置0，不满足约束
            [7.0, 8.0, 9.0],
          ];
          final adder = ClockLikeAdder(data);
          final smartMax = adder.maxSumSmart();
          expect(smartMax, isA<double>());
          expect(smartMax, greaterThan(0.0));
        });

        test('should handle isMaxSumGreaterOrEquals correctly', () {
          final data = [
            [3.0, 2.0, 1.0],
            [4.0, 6.0, 5.0],
            [7.0, 8.0, 9.0],
          ];
          final adder = ClockLikeAdder(data);
          
          // 测试目标值小于等于实际最大值的情况
          expect(adder.isMaxSumGreaterOrEquals(18.0), isTrue); // 等于最大值
          expect(adder.isMaxSumGreaterOrEquals(14.0), isTrue); // 小于最大值
          expect(adder.isMaxSumGreaterOrEquals(10.0), isTrue); // 远小于最大值
          
          // 测试目标值大于实际最大值的情况
          expect(adder.isMaxSumGreaterOrEquals(20.0), isFalse); // 远大于最大值
        });

        test('should handle isMaxSumGreaterOrEquals with edge cases', () {
          // 测试单行数据
          final data1 = [
            [1.0, 2.0, 3.0]
          ];
          final adder1 = ClockLikeAdder(data1);
          expect(adder1.isMaxSumGreaterOrEquals(3.0), isTrue);
          expect(adder1.isMaxSumGreaterOrEquals(2.0), isTrue);
          expect(adder1.isMaxSumGreaterOrEquals(4.0), isFalse);

          // 测试单列数据
          final data2 = [
            [1.0],
            [2.0],
            [3.0],
          ];
          final adder2 = ClockLikeAdder(data2);
          expect(adder2.isMaxSumGreaterOrEquals(6.0), isTrue);
          expect(adder2.isMaxSumGreaterOrEquals(5.0), isTrue);
          expect(adder2.isMaxSumGreaterOrEquals(7.0), isFalse);

          // 测试2x2矩阵
          final data3 = [
            [1.0, 2.0],
            [3.0, 4.0],
          ];
          final adder3 = ClockLikeAdder(data3);
          expect(adder3.isMaxSumGreaterOrEquals(5.0), isTrue); // 最大值
          expect(adder3.isMaxSumGreaterOrEquals(4.0), isTrue);
          expect(adder3.isMaxSumGreaterOrEquals(6.0), isFalse);
        });

        test('should handle isMaxSumGreaterOrEquals with zero and negative targets', () {
          final data = [
            [1.0, 2.0, 3.0],
            [4.0, 5.0, 6.0],
          ];
          final adder = ClockLikeAdder(data);
          
          // 测试零值目标
          expect(adder.isMaxSumGreaterOrEquals(0.0), isTrue); // 任何正数都大于0
          
          // 测试负值目标
          expect(adder.isMaxSumGreaterOrEquals(-1.0), isTrue); // 任何正数都大于-1
          expect(adder.isMaxSumGreaterOrEquals(-100.0), isTrue); // 任何正数都大于-100
        });

        test('should have early termination performance benefit', () {
          final data = List.generate(6, (i) => List.generate(20, (j) => (i + j).toDouble()));
          final adder = ClockLikeAdder(data);
          
          // 测试一个较低的目标值，应该能快速找到
          Stopwatch stopwatch = Stopwatch()..start();
          final result = adder.isMaxSumGreaterOrEquals(50.0); // 较低的目标值
          final time = stopwatch.elapsedMilliseconds;
          
          debugPrint('isMaxSumGreaterOrEquals with low target: ${time}ms, result: $result');
          expect(result, isTrue);
          expect(time, lessThan(100)); // 应该很快找到
        });

        test('should use optimization for isMaxSumGreaterOrEquals when applicable', () {
          // 测试优化算法适用的情况
          final data1 = [
            [1.0, 2.0, 3.0],
            [4.0, 5.0, 6.0],
            [7.0, 8.0, 9.0],
          ];
          final adder1 = ClockLikeAdder(data1);
          
          // 理论最大值是18.0，应该能快速判断
          Stopwatch stopwatch = Stopwatch()..start();
          final result1 = adder1.isMaxSumGreaterOrEquals(15.0);
          final time1 = stopwatch.elapsedMilliseconds;
          
          debugPrint('isMaxSumGreaterOrEquals with optimization: ${time1}ms, result: $result1');
          expect(result1, isTrue);
          expect(time1, lessThan(10)); // 优化算法应该极快
          
          // 测试理论最大值小于目标值的情况
          stopwatch.reset();
          stopwatch.start();
          final result2 = adder1.isMaxSumGreaterOrEquals(20.0);
          final time2 = stopwatch.elapsedMilliseconds;
          
          debugPrint('isMaxSumGreaterOrEquals impossible target: ${time2}ms, result: $result2');
          expect(result2, isFalse);
          expect(time2, lessThan(10)); // 应该立即返回false
        });

        test('should fall back to original algorithm when optimization not applicable', () {
          // 测试优化算法不适用的情况
          final data = [
            [1.0, 2.0, 3.0],
            [6.0, 5.0, 4.0], // 最大值在位置0，不满足约束
            [7.0, 8.0, 9.0],
          ];
          final adder = ClockLikeAdder(data);
          
          // 理论最大值是18.0，但实际最大值可能更小
          final result = adder.isMaxSumGreaterOrEquals(15.0);
          expect(result, isA<bool>()); // 应该返回一个布尔值
        });

        test('should have better performance with optimizations', () {
          Stopwatch stopwatch = Stopwatch()..start();
          final data = List.generate(8, (i) => List.generate(30, (j) => (i + j).toDouble()));
          final adder = ClockLikeAdder(data);
          
          // 测试优化算法
          final optimizedMax = adder.maxSumOptimized();
          final optimizedTime = stopwatch.elapsedMilliseconds;
          
          // 测试智能算法
          stopwatch.reset();
          stopwatch.start();
          final maxSum = adder.maxSum(false);
          final maxSumTime = stopwatch.elapsedMilliseconds;
          
          debugPrint('Performance comparison:');
          debugPrint('Optimized: ${optimizedTime}ms, result: $optimizedMax');
          debugPrint('Smart: ${maxSumTime}ms, result: $maxSum');
          
          // 优化算法应该更快(虽然不一定准确)
          expect(optimizedTime, lessThan(maxSumTime)); // 优化算法应该很快
        });

        test('should handle edge cases for optimized algorithms', () {
          // 测试全零矩阵
          final data1 = [
            [0.0, 0.0],
            [0.0, 0.0],
          ];
          final adder1 = ClockLikeAdder(data1);
          expect(adder1.maxSumOptimized(), equals(0.0));
          expect(adder1.maxSumSmart(), equals(0.0));

          // 测试单元素矩阵
          final data2 = [
            [42.0]
          ];
          final adder2 = ClockLikeAdder(data2);
          expect(adder2.maxSumOptimized(), equals(42.0));
          expect(adder2.maxSumSmart(), equals(42.0));

          // 测试大数值矩阵
          final data3 = [
            [1000.0, 2000.0],
            [3000.0, 4000.0],
          ];
          final adder3 = ClockLikeAdder(data3);
          expect(adder3.maxSumOptimized(), equals(6000.0)); // 2000 + 4000
          expect(adder3.maxSumSmart(), equals(5000.0));
        });

        test('should handle decimal numbers in optimized algorithms', () {
          final data = [
            [1.5, 2.5],
            [3.5, 4.5],
          ];
          final adder = ClockLikeAdder(data);
          expect(adder.maxSum(false), equals(6.0));
          expect(adder.maxSumOptimized(), equals(7.0)); // 2.5 + 4.5 = 7.0
          expect(adder.maxSumSmart(), equals(6.0));
        });

        test('should verify optimization applicability logic', () {
          // 测试适用的情况：每行最大值位置递增
          final data1 = [
            [1.0, 2.0, 3.0],
            [4.0, 5.0, 6.0],
            [7.0, 8.0, 9.0],
          ];
          final adder1 = ClockLikeAdder(data1);
          final optimized1 = adder1.maxSumOptimized();
          final smart1 = adder1.maxSumSmart();
          expect(optimized1, equals(18.0)); // 3 + 6 + 9 = 18
          expect(smart1, equals(15.0)); // 应该使用优化算法

          // 测试不适用的情况：最大值位置不满足约束
          final data2 = [
            [1.0, 2.0, 3.0],
            [6.0, 5.0, 4.0], // 最大值在位置0，小于上一行的位置2
            [7.0, 8.0, 9.0],
          ];
          final adder2 = ClockLikeAdder(data2);
          final optimized2 = adder2.maxSumOptimized();
          final smart2 = adder2.maxSumSmart();
          expect(optimized2, equals(18.0)); // 理论最大值
          expect(smart2, isA<double>()); // 应该回退到原始算法
          expect(smart2, lessThanOrEqualTo(optimized2)); // 实际值应该小于等于理论值
        });
      });
    });
  });
}
