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

    // 制造「通用释义缺失」：删掉**今日学习批次**全部单词在本机的通用释义（dict_id = '0'）。
    //
    // 为什么按批次而不是按 learning_order 取前 N 个：learning_order 是每个批次内各自编号的，
    // 按它排序取到的全是历史批次的词，今日第一个词根本不在里面，异常造不出来。
    // 今日批次 = 该用户最大的 batch_id（今天刚生成的那一批）。
    final affected = await MyDatabase.instance.customUpdate(
      "DELETE FROM meaning_items WHERE dict_id = ? AND word_id IN ("
      "SELECT word_id FROM learning_words WHERE user_id = ? "
      "AND batch_id = (SELECT MAX(batch_id) FROM learning_words WHERE user_id = ?))",
      variables: [
        Variable.withString(Global.commonDictId),
        Variable.withString(_testUserId),
        Variable.withString(_testUserId),
      ],
    );
    debugPrint('【模拟器验收】已删除 $affected 条通用释义（今日学习批次的全部单词）');
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

    // === 闭环（离线可验证的部分）：引导到体检页后，体检必须真的检出这个缺失 ===
    //
    // 为什么只验证到"检出"为止：本机 App 连的是局域网开发后端（192.168.1.230），
    // 这台机器上连不通，一键修复要用的 getFallbackWordsData 拿不到数据；
    // 为了不误连生产后端触发端云同步，这里不验证修复动作本身。
    await tester.tap(find.text('修复数据（数据健康检查）'));
    await _waitFor(tester, () => find.text('正在学习单词的释义完整性').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30), label: '进入数据健康检查页');
    debugPrint('【模拟器验收】已进入数据健康检查页');

    await _waitFor(tester, () => find.text('详情').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 150), label: '体检检出不通过项');
    debugPrint('【模拟器验收】体检已检出问题（页面上出现「详情」入口）');

    // 点开「正在学习单词的释义完整性」的详情，确认它指的就是学习页上那个词
    final itemRow = find
        .ancestor(of: find.text('正在学习单词的释义完整性'), matching: find.byType(Row))
        .first;
    final detailBtn = find.descendant(of: itemRow, matching: find.text('详情'));
    expect(detailBtn, findsOneWidget, reason: '这一项必须被判为不通过，才有「详情」可点');
    await tester.tap(detailBtn);
    await tester.pump(const Duration(milliseconds: 800));
    await _waitFor(tester, () => find.textContaining('在本地查不到释义').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 20), label: '明细里出现缺释义的说明');
    debugPrint('【模拟器验收】体检明细确认了"学习中的词查不到释义"');
    await _captureFlutterSurface(tester, 'health_check_detail.png');

    // === 走完修复闭环：只修这一项，确认数据真的能补回来、学习页恢复正常 ===
    await tester.tap(find.text('立即修复此项异常'));
    await _waitFor(tester, () => find.text('确定修复').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 20), label: '出现「确认修复」对话框');
    await tester.tap(find.text('确定修复'));
    debugPrint('【模拟器验收】已确认修复「正在学习单词的释义完整性」');

    // 修复流程会连带处理其它体检项（词书数量对账等），UI 上的「修复完成」可能很久才出现；
    // 这里直接盯结果：被删掉的通用释义必须被补回来，缺释义的学习词数必须归零。
    await _waitForAsync(tester, () async {
      final row = await MyDatabase.instance.customSelect(
        "SELECT COUNT(*) AS c FROM learning_words lw WHERE NOT EXISTS ("
        "SELECT 1 FROM meaning_items mi WHERE mi.word_id = lw.word_id AND mi.dict_id = ?)",
        variables: [Variable.withString(Global.commonDictId)],
      ).getSingle();
      return row.read<int>('c') == 0;
    }, label: '缺释义的学习词被补齐', timeout: const Duration(seconds: 300));
    debugPrint('【模拟器验收】修复生效：缺释义的学习词已归零');
    await _captureFlutterSurface(tester, 'repair_in_progress.png');

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
