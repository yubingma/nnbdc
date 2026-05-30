import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart'; // 引入 kReleaseMode
import 'package:flutter/scheduler.dart';
import 'package:nnbdc/global.dart';

/// 性能哨兵系统 - 全版本就绪（支持双击唤醒 FPS 诊断与工业级峰值保持运维监控）
class PerformanceWatchdog {
  /// 全局流畅度/卡顿热度值 (0.0 代表极度流畅，1.0 代表严重阻塞)
  static final ValueNotifier<double> jankHeat = ValueNotifier<double>(0.0);
  
  /// 全局开关：是否展示 FPS Overlay 帧率层
  static final ValueNotifier<bool> showFpsOverlay = ValueNotifier<bool>(false);

  /// 实时滑动平滑 FPS 值 (支持 60Hz 到 120Hz 高刷屏检测)
  static final ValueNotifier<double> currentFps = ValueNotifier<double>(60.0);

  /// 最后一次检测到卡顿/阻塞的时间戳 (用于工业级 Peak Hold 峰值锁定)
  static int _lastJankTime = 0;

  static Timer? _decayTimer;

  /// 初始化哨兵
  static void init() {
    _initFrameWatchdog();
    _startHeartbeatChecker();
    _startHeatDecay();
    
    if (!kReleaseMode) {
      Global.logger.i('🚀 性能哨兵系统已成功启动 (已实装工业级峰值保持机制)');
    }
  }

  /// 切换 FPS 诊断气泡状态
  static void toggleFpsOverlay() {
    showFpsOverlay.value = !showFpsOverlay.value;
    if (!kReleaseMode) {
      Global.logger.i('FPS 诊断彩蛋显示状态切换为: ${showFpsOverlay.value}');
    }
  }

  /// 累加卡顿热度，并记录卡顿时点以锁定峰值
  static void reportJank(double intensity) {
    jankHeat.value = (jankHeat.value + intensity).clamp(0.0, 1.0);
    _lastJankTime = DateTime.now().millisecondsSinceEpoch;
  }

  /// 1. 监测每一帧的 UI 线程与 Raster 渲染线程耗时，并估算滑动 FPS
  static void _initFrameWatchdog() {
    SchedulerBinding.instance.addTimingsCallback((List<FrameTiming> timings) {
      for (final timing in timings) {
        final uiTimeMs = timing.buildDuration.inMilliseconds;
        final rasterTimeMs = timing.rasterDuration.inMilliseconds;
        final totalFrameTime = timing.totalSpan.inMilliseconds.toDouble();

        // 1. 基于 EMA 滤波器滑动计算当前帧率 (最大 120Hz 高刷)
        final double rawFps = 1000.0 / (totalFrameTime > 0 ? totalFrameTime : 16.6);
        final clampedFps = rawFps.clamp(1.0, 120.0);
        currentFps.value = double.parse(
          (0.95 * currentFps.value + 0.05 * clampedFps).toStringAsFixed(1)
        );

        // 2. 卡顿检测 (掉帧判定)
        if (uiTimeMs > 16) {
          if (!kReleaseMode) {
            Global.logger.w('⚠️ [Performance] 帧率警告：UI 线程卡顿！耗时: ${uiTimeMs}ms');
          }
          reportJank(((uiTimeMs - 16) / 32).clamp(0.0, 0.5));
        }

        if (rasterTimeMs > 24) {
          if (!kReleaseMode) {
            Global.logger.w('⚠️ [Performance] 帧率警告：GPU 渲染卡顿！耗时: ${rasterTimeMs}ms');
          }
          reportJank(((rasterTimeMs - 24) / 32).clamp(0.0, 0.5));
        }
      }
    });
  }

  /// 2. 心跳监测主 Isolate 事件循环，捕获引起 ANR 的同步阻塞任务
  static void _startHeartbeatChecker() {
    Timer.periodic(const Duration(milliseconds: 50), (timer) {
      final start = DateTime.now().millisecondsSinceEpoch;
      
      Future.microtask(() {
        final elapsed = DateTime.now().millisecondsSinceEpoch - start;
        
        if (elapsed > 80) {
          if (!kReleaseMode) {
            Global.logger.e('🚨 [UI Thread Blocked] 主线程同步阻塞警告！耗时: ${elapsed}ms。');
          }
          currentFps.value = max(1.0, 1000.0 / elapsed);
          reportJank(((elapsed - 80) / 120).clamp(0.4, 1.0));
        }
      });
    });
  }

  /// 3. 热度慢速自平滑衰减机制 (实装 1.5 秒 Peak Hold 峰值锁定，锁定后指数淡出)
  static void _startHeatDecay() {
    _decayTimer?.cancel();
    _decayTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (jankHeat.value > 0.0) {
        final now = DateTime.now().millisecondsSinceEpoch;
        
        // 峰值保持 (Peak Hold)：距离最后一次卡顿小于 1.5 秒时，锁死红色，拒绝衰减！
        if (now - _lastJankTime < 1500) {
          return;
        }

        // 锁定超时后，开启极其丝滑的渐变指数衰减
        final next = jankHeat.value * 0.85 - 0.01;
        jankHeat.value = next.clamp(0.0, 1.0);
      }
    });
  }
}
