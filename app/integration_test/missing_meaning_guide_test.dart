import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/main.dart' as app;
import 'package:nnbdc/page/bdc/bdc.dart';
import 'package:nnbdc/page/bdc/providers/bdc_notifier.dart';
import 'package:nnbdc/page/bdc/providers/bdc_state.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 在 iOS 模拟器里跑**真实 App**：先在库里制造「通用释义缺失」，再走正常路径进入学习页，
/// 验证界面给出的是「修复数据 / 清空本地数据重新同步」两条出路，而不是一个必然再次失败的重试。
///
/// 制造缺失的方式是直接删本地 `meaning_items` 里的通用释义行（绕过 DAO、不写同步日志），
/// 所以不会有任何上行数据打到云端；测试结束后用备份恢复模拟器数据库即可。
/// 宿主机预先灌进模拟器数据库的登录用户
const String _testUserId = 'a7cb3e88c84545bf8febef1ec62418f2';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('通用释义缺失时，学习页展示引导面板', (tester) async {
    // 模拟器上的 App 是全新安装：先把「已同意隐私协议 + 已登录用户」写进本地偏好，
    // 让它直接进入首页（登录用户行由宿主机预先灌入的数据库提供）。
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('accepted_privacy_version', 20260310);
    await prefs.setString('currentUserId', _testUserId);

    app.main();

    // 兜底：万一隐私框还是弹出来，点「同意并继续」
    await _waitFor(tester, () {
      return find.textContaining('开始学习').evaluate().isNotEmpty;
    }, timeout: const Duration(seconds: 150), label: '首页出现「开始学习」', tapWhenFound: '同意并继续');
    debugPrint('【模拟器验收】已进入首页（今日计划）');

    // 等云端把「正在学习的词」同步回来（模拟器可能是全新安装、本地为空），再制造缺失
    await _waitForAsync(tester, () async {
      final row = await MyDatabase.instance
          .customSelect('SELECT COUNT(*) AS c FROM learning_words')
          .getSingle();
      return row.read<int>('c') > 0;
    }, label: '云端同步回正在学习的词', timeout: const Duration(seconds: 180));
    await _sleep(tester, const Duration(seconds: 5));

    // 制造「通用释义缺失」：删掉今天计划里前 50 个词在本机的通用释义（dict_id = '0'）。
    // 只取前 50 个是刻意的：第一个必是学习页会先取到的词，而范围小能让随后的
    // 「一键修复」请求保持在可观察的规模。
    final affected = await MyDatabase.instance.customUpdate(
      "DELETE FROM meaning_items WHERE dict_id = ? AND word_id IN ("
      "SELECT word_id FROM learning_words WHERE user_id = ? AND batch_id IS NOT NULL "
      "ORDER BY learning_order LIMIT 50)",
      variables: [Variable.withString(Global.commonDictId), Variable.withString(_testUserId)],
    );
    debugPrint('【模拟器验收】已删除 $affected 条通用释义（今日计划前 50 个词）');
    expect(affected, greaterThan(0), reason: '模拟器库里应有正在学习的词，否则造不出这个场景');

    // 走真实用户路径：点「开始学习」进入学习页。
    // 今天首次开始学习会先弹「开启今日学习旅程」确认框，需要点「马上开始」。
    await tester.tap(find.textContaining('开始学习').first);
    debugPrint('【模拟器验收】已点击「开始学习」');

    final entryDeadline = DateTime.now().add(const Duration(seconds: 45));
    while (DateTime.now().isBefore(entryDeadline)) {
      await tester.pump(const Duration(milliseconds: 120));
      final confirm = find.textContaining('马上开始');
      if (confirm.evaluate().isNotEmpty) {
        await tester.tap(confirm.first);
        debugPrint('【模拟器验收】已点击「马上开始」确认今日学习');
        continue;
      }
      if (find.byType(BdcPage).evaluate().isNotEmpty) break;
    }
    debugPrint('【模拟器验收】已进入学习页（或已离开首页入口）');

    await _waitFor(tester, () => find.text('本机缺少这个词的释义').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 90), label: '学习页出现缺释义引导面板');

    // 三条出路必须都在
    expect(find.text('本机缺少这个词的释义'), findsOneWidget);
    expect(find.text('修复数据（数据健康检查）'), findsOneWidget);
    expect(find.text('清空本地数据重新同步'), findsOneWidget);

    // 确认走的是引导面板，而不是原来的普通错误页：面板认得出这是「通用释义缺失」
    final state = _bdcState(tester);
    expect(state?.loadErrorCause, isNotNull, reason: '错误对象必须带到界面，界面才能分辨错误种类');
    debugPrint('【模拟器验收】loadError=${state?.loadError}');
    debugPrint('【模拟器验收】loadErrorCause=${state?.loadErrorCause.runtimeType}');
    debugPrint('【模拟器验收】引导面板已出现，学习页不再只是一个必然失败的重试');

    // 取证：把 Flutter 自己渲染的画面写成 PNG 存进 App 沙盒（绕开系统级弹框），
    // 再由宿主机从模拟器容器里取出，作为界面证据。
    await _captureFlutterSurface(tester, 'missing_meaning_guide.png');

    // === 闭环：真的走一次「修复数据」这条出路，确认数据能补回来 ===
    await tester.tap(find.text('修复数据（数据健康检查）'));
    await _waitFor(tester, () => find.byTooltip('一键自动修复').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30), label: '进入数据健康检查页');
    debugPrint('【模拟器验收】已进入数据健康检查页，等体检自动跑完');
    await _sleep(tester, const Duration(seconds: 25));

    await tester.tap(find.byTooltip('一键自动修复'));
    await _waitFor(tester, () => find.text('确定修复').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 20), label: '出现「确认修复」对话框');
    await tester.tap(find.text('确定修复'));
    debugPrint('【模拟器验收】已确认「一键自动修复」');

    await _waitFor(tester, () => find.text('修复完成').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 240), label: '修复完成');
    await tester.tap(find.text('确定'));
    debugPrint('【模拟器验收】修复完成');

    // 回学习页，原样点「重试」
    await tester.tap(find.byTooltip('返回'));
    await _sleep(tester, const Duration(seconds: 3));
    await tester.tap(find.text('重试'));
    await _waitFor(tester, () {
      final s = _bdcState(tester);
      return s != null && s.loadError == null && s.word != null;
    }, timeout: const Duration(seconds: 90), label: '修复后学习页正常出词');
    debugPrint('【模拟器验收】修复后学习页正常出词：${_bdcState(tester)?.word?.spell}');
    await _captureFlutterSurface(tester, 'fixed_after_repair.png');

    // 停住画面一会儿，方便外部用 simctl 截图
    await _sleep(tester, const Duration(seconds: 15));
  });
}

BdcState? _bdcState(WidgetTester tester) {
  final pages = find.byType(BdcPage).evaluate();
  if (pages.isEmpty) return null;
  return ProviderScope.containerOf(pages.first, listen: false).read(bdcNotifierProvider);
}

Future<void> _waitForAsync(
  WidgetTester tester,
  Future<bool> Function() ready, {
  required String label,
  Duration timeout = const Duration(seconds: 60),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 300));
    if (await ready()) return;
  }
  fail('等待超时：$label');
}

Future<void> _waitFor(
  WidgetTester tester,
  bool Function() ready, {
  required String label,
  Duration timeout = const Duration(seconds: 60),
  String? tapWhenFound,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 120));
    if (tapWhenFound != null) {
      final dialogButton = find.text(tapWhenFound);
      if (dialogButton.evaluate().isNotEmpty) {
        await tester.tap(dialogButton.first);
        debugPrint('【模拟器验收】已点击「$tapWhenFound」');
        await tester.pump(const Duration(milliseconds: 300));
      }
    }
    if (ready()) return;
  }
  fail('等待超时：$label');
}

/// 边等边推帧：测试期间界面要持续刷新，外部才截得到当前画面
Future<void> _sleep(WidgetTester tester, Duration duration) async {
  final deadline = DateTime.now().add(duration);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

/// 截图当前 Flutter 渲染画面，写到 App 的 Documents 目录
Future<void> _captureFlutterSurface(WidgetTester tester, String fileName) async {
  final boundary =
      tester.firstRenderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
  final image = await boundary.toImage(pixelRatio: 2.0);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  debugPrint('【模拟器验收】界面截图已写入 ${file.path}');
}
