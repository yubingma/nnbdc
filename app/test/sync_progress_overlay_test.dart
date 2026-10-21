import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/services/sync_progress.dart';
import 'package:nnbdc/widget/sync_progress_overlay.dart';

void main() {
  setUp(() {
    syncProgress.value = const SyncProgress.idle();
    resetSyncReceivedBytes();
  });

  tearDown(() {
    syncProgress.value = const SyncProgress.idle();
    resetSyncReceivedBytes();
  });

  Widget host({required bool syncing}) {
    return MaterialApp(
      home: Scaffold(
        body: SyncProgressOverlay(
          isDarkMode: false,
          accentColor: const Color(0xFF0B7C9E),
          syncing: syncing,
        ),
      ),
    );
  }

  testWidgets('同步中同时显示已接收字节数与已处理记录数', (tester) async {
    syncProgress.value = const SyncProgress(
      phase: 'WRITING LOCAL DATA',
      done: 12400,
      total: 86321,
    );
    addSyncReceivedBytes(19327352); // 18.4 MB

    await tester.pumpWidget(host(syncing: true));
    await tester.pump();

    expect(find.text('正在同步云端数据'), findsOneWidget);
    expect(find.text('本次已下载'), findsOneWidget);
    expect(find.text('18.4 MB'), findsOneWidget);
    expect(find.text('已处理记录'), findsOneWidget);
    expect(find.text('12,400 / 86,321'), findsOneWidget);
    expect(find.text('正在把云端记录写入本机'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
  });

  testWidgets('下载阶段记录总数未知时，仍显示已接收字节数', (tester) async {
    syncProgress.value = const SyncProgress(phase: 'FETCHING USER DATA');
    addSyncReceivedBytes(5 * 1024 * 1024);

    await tester.pumpWidget(host(syncing: true));
    await tester.pump();

    expect(find.text('5.00 MB'), findsOneWidget);
    expect(find.text('已处理记录'), findsNothing);
    expect(find.text('正在下载你的云端数据'), findsOneWidget);
  });

  testWidgets('同步结束但计划仍未就绪时，显示准备今日计划', (tester) async {
    await tester.pumpWidget(host(syncing: false));
    await tester.pump();

    expect(find.text('正在准备今日计划'), findsOneWidget);
    expect(find.text('正在同步云端数据'), findsNothing);
  });

  test('本轮已接收字节数只增不减', () {
    addSyncReceivedBytes(1024);
    addSyncReceivedBytes(2048);
    expect(syncReceivedBytes.value, 3072);

    // 非法负数不得把数字拉回去
    addSyncReceivedBytes(-100);
    expect(syncReceivedBytes.value, 3072);

    resetSyncReceivedBytes();
    expect(syncReceivedBytes.value, 0);
  });
}
