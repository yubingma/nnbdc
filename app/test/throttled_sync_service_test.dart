import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/services/sync_progress.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';

/// 首屏加载态会 await 端云同步，这里锁死「等待必须收敛」这条契约：
/// 同步被暂停、网络不可用，都不能让调用方永远停在转圈上。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThrottledDbSyncService 等待收敛', () {
    tearDown(() {
      ThrottledDbSyncService().reset();
    });

    test('导入/大事务暂停同步期间，requestSyncAndWait 立即结束', () async {
      final service = ThrottledDbSyncService();
      service.reset();
      service.suspend();

      // 暂停期间不会安排任何同步执行，等待必须立刻结束，否则首屏永远转圈
      await service.requestSyncAndWait(immediate: true).timeout(const Duration(seconds: 2));

      service.resume();
    });

    test('网络不可用时，requestSyncAndWait 也会结束', () async {
      // 测试环境没有 connectivity 插件，NetworkUtil.isConnected() 返回 false：
      // 同步被跳过，但等待者必须被收尾。
      final service = ThrottledDbSyncService();
      service.reset();

      await service.requestSyncAndWait(immediate: true).timeout(const Duration(seconds: 2));
    });
  });

  group('SyncProgress', () {
    test('idle 表示当前没有同步在进行', () {
      const progress = SyncProgress.idle();
      expect(progress.isIdle, isTrue);
      expect(progress.hasTotal, isFalse);
    });

    test('hasTotal 反映总量是否已知', () {
      const withTotal = SyncProgress(phase: 'WRITING LOCAL DATA', done: 200, total: 8621);
      expect(withTotal.isIdle, isFalse);
      expect(withTotal.hasTotal, isTrue);

      const withoutTotal = SyncProgress(phase: 'FETCHING USER DATA');
      expect(withoutTotal.hasTotal, isFalse);
    });

    test('内容相同的快照相等，避免 ValueNotifier 触发无意义刷新', () {
      const a = SyncProgress(phase: 'WRITING LOCAL DATA', done: 200, total: 8621);
      const b = SyncProgress(phase: 'WRITING LOCAL DATA', done: 200, total: 8621);
      const c = SyncProgress(phase: 'WRITING LOCAL DATA', done: 400, total: 8621);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });
}
