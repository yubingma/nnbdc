import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/models/sync_log.dart';
import 'package:nnbdc/services/sync_log_service.dart';
import 'package:nnbdc/util/app_clock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SyncLog & SyncStatus 状态机与防误判测试', () {
    test('SyncLog 刚创建时处于进行中状态 (isInProgress)', () {
      final now = AppClock.now();
      final log = SyncLog.start(
        id: 'test-1',
        startTime: now,
        userId: 'user-1',
      );

      expect(log.isInProgress, isTrue);
      expect(log.isFinished, isFalse);
      expect(log.endTime, isNull);
    });

    test('SyncLog 完成后处于已完成状态 (isFinished)', () {
      final now = AppClock.now();
      final log = SyncLog.start(
        id: 'test-2',
        startTime: now,
        userId: 'user-1',
      );

      final completedLog = log.complete(
        endTime: now.add(const Duration(milliseconds: 300)),
        uploadCount: 5,
        downloadCount: 2,
      );

      expect(completedLog.isInProgress, isFalse);
      expect(completedLog.isFinished, isTrue);
      expect(completedLog.success, isTrue);
      expect(completedLog.durationMs, 300);
    });

    test('SyncLog 失败后处于已完成状态且标记失败', () {
      final now = AppClock.now();
      final log = SyncLog.start(
        id: 'test-3',
        startTime: now,
        userId: 'user-1',
      );

      final failedLog = log.fail(
        endTime: now.add(const Duration(milliseconds: 500)),
        errorMessage: '网络连接超时',
      );

      expect(failedLog.isInProgress, isFalse);
      expect(failedLog.isFinished, isTrue);
      expect(failedLog.success, isFalse);
      expect(failedLog.errorMessage, '网络连接超时');
    });

    test('进行中的同步不应被判定为同步失败', () {
      // 场景模拟：最新一条日志是刚开始、正在同步中的日志（endTime == null）
      // 倒数第二条是之前成功完成的日志
      final now = AppClock.now();
      final inProgressLog = SyncLog.start(
        id: 'log-in-progress',
        startTime: now,
      );

      final previousFinishedSuccessLog = SyncLog(
        id: 'log-previous',
        startTime: now.subtract(const Duration(minutes: 5)),
        endTime: now.subtract(const Duration(minutes: 4, seconds: 58)),
        success: true,
      );

      final logs = [inProgressLog, previousFinishedSuccessLog];
      logs.sort((a, b) => b.startTime.compareTo(a.startTime));

      // 寻找最近一条已完成的日志
      SyncLog? lastFinished;
      for (final l in logs) {
        if (l.isFinished) {
          lastFinished = l;
          break;
        }
      }

      expect(lastFinished, isNotNull);
      expect(lastFinished!.id, 'log-previous');
      expect(lastFinished.success, isTrue);
      // 正在进行中绝非失败
      expect(inProgressLog.isInProgress, isTrue);
    });

    test('SyncStatusNotifier 能正确发布状态联动', () {
      final service = SyncLogService();
      expect(service.currentStatus, SyncStatus.idle);

      service.syncStatusNotifier.value = SyncStatus.syncing;
      expect(service.isSyncing, isTrue);

      service.syncStatusNotifier.value = SyncStatus.idle;
      expect(service.isSyncing, isFalse);

      service.syncStatusNotifier.value = SyncStatus.failed;
      expect(service.currentStatus, SyncStatus.failed);

      // 恢复 idle
      service.syncStatusNotifier.value = SyncStatus.idle;
    });
  });
}
