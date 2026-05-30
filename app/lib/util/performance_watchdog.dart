import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart'; // 引入 kReleaseMode
import 'package:flutter/scheduler.dart';
import 'package:nnbdc/global.dart';

/// 性能哨兵系统 - 全版本就绪（支持双击唤醒 FPS 诊断与静默运维监控）
class PerformanceWatchdog {
  /// 全局流畅度/卡顿热度值 (0.0 代表极度流畅，1.0 代表严重阻塞)
  static final ValueNotifier<double> jankHeat = ValueNotifier<double>(0.0);
  
  /// 全局开关：是否展示 FPS Overlay 帧率层
  static final ValueNotifier<bool> showFpsOverlay = ValueNotifier<bool>(false);

  /// 实时滑动平滑 FPS 值 (支持 60Hz 到 120Hz 高刷屏检测)
  static final ValueNotifier<double> currentFps = ValueNotifier<double>(60.0);

  static Timer? _decayTimer;

  /// 初始化哨兵
  static void init() {
    _initFrameWatchdog();
    _startHeartbeatChecker();
    _startHeatDecay();
    
    if (!kReleaseMode) {
      Global.logger.i('🚀 性能哨兵系统已成功启动 (支持双击进度条激活 FPS 诊断图层)');
    }
  }

  /// 切换 FPS 诊断气泡状态
  static void toggleFpsOverlay() {
    showFpsOverlay.value = !showFpsOverlay.value;
    if (!kReleaseMode) {
      Global.logger.i('FPS 诊断彩蛋显示状态切换为: ${showFpsOverlay.value}');
    }
  }

  /// 累加卡顿热度
  static void reportJank(double intensity) {
    jankHeat.value = (jankHeat.value + intensity).clamp(0.0, 1.0);
  }

  /// 1. 监测每一帧的 UI 线程与 Raster 渲染线程耗时，并估算滑动 FPS
  static void _initFrameWatchdog() {
    SchedulerBinding.instance.addTimingsCallback((List<FrameTiming> timings) {
      for (final timing in timings) {
        final uiTimeMs = timing.buildDuration.inMilliseconds;
        final rasterTimeMs = timing.rasterDuration.inMilliseconds;
        final totalFrameTime = timing.totalSpan.inMilliseconds.toDouble();

        // 1. 基于 EMA (指数移动平均) 滤波器滑动计算当前帧率 (避免除零，假设对于60Hz一帧16.6ms)
        final double rawFps = 1000.0 / (totalFrameTime > 0 ? totalFrameTime : 16.6);
        // 限制在合理频率区间，支持最大 120Hz 高刷
        final clampedFps = rawFps.clamp(1.0, 120.0);
        // 使用 0.95 滑动系数确保 FPS 显示丝滑平滑，不闪烁
        currentFps.value = double.parse(
          (0.95 * currentFps.value + 0.05 * clampedFps).toStringAsFixed(1)
        );

        // 2. 卡顿卡秒检查 (一帧预算 > 16.6ms 判定为掉帧)
        if (uiTimeMs > 16) {
          // Release 模式下静默监控，绝不执行控制台 logging 以免产生字符串分配与 I/O 耗时
          if (!kReleaseMode) {
            Global.logger.w(
              '⚠️ [Performance] 帧率警告：UI 线程卡顿！耗时: ${uiTimeMs}ms (阈值 16ms)。'
            );
          }
          // 卡顿程度正相关地累加到热度值中 (最大 0.5)
          reportJank(((uiTimeMs - 16) / 32).clamp(0.0, 0.5));
        }

        if (rasterTimeMs > 16) {
          if (!kReleaseMode) {
            Global.logger.w(
              '⚠️ [Performance] 帧率警告：GPU 渲染卡顿！耗时: ${rasterTimeMs}ms (阈值 16ms)。'
            );
          }
          reportJank(((rasterTimeMs - 16) / 32).clamp(0.0, 0.5));
        }
      }
    });
  }

  /// 2. 心跳监测主 Isolate 事件循环，捕获引起 ANR 的同步阻塞任务
  static void _startHeartbeatChecker() {
    Timer.periodic(const Duration(milliseconds: 50), (timer) {
      final start = DateTime.now().millisecondsSinceEpoch;
      
      // 插入一个高优先级微任务
      Future.microtask(() {
        final elapsed = DateTime.now().millisecondsSinceEpoch - start;
        
        // 同步阻塞超过 80ms (连续掉 5 帧) 时发出严重警告
        if (elapsed > 80) {
          if (!kReleaseMode) {
            Global.logger.e(
              '🚨 [UI Thread Blocked] 主线程同步阻塞警告！耗时: ${elapsed}ms。'
            );
          }
          // 在卡死的时候，FPS 也强制拉低
          currentFps.value = max(1.0, 1000.0 / elapsed);
          reportJank(((elapsed - 80) / 120).clamp(0.4, 1.0));
        }
      });
    });
  }

  /// 3. 热度自平滑衰减机制 (每 100ms 衰减 10%，约 1 秒内无卡顿自动恢复)
  static void _startHeatDecay() {
    _decayTimer?.cancel();
    _decayTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (jankHeat.value > 0.0) {
        jankHeat.value = (jankHeat.value - 0.1).clamp(0.0, 1.0);
      }
    });
  }
}
