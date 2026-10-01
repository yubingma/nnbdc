import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/phase_presentation_tracker.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「本环节已出过题」记录的行为测试。
///
/// 它只为学习页的环节进度指示服务：分子要按"已出过题"计数，
/// 而同一环节里"答错待重练"与"还没轮到"的词在 learning_word 上完全同态，
/// 只能靠这份记录区分。
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    await PhasePresentationTracker.clear();
  });

  tearDown(() async {
    await PhasePresentationTracker.clear();
    AppClock.reset();
  });

  test('记录后能被数出来，同一个词重复记录不重复计数', () async {
    AppClock.setClock(FakeClock(DateTime(2026, 10, 1, 10, 0)));

    await PhasePresentationTracker.markPresented(
        groupNo: 1, trackName: '新词测评', stepIndex: 0, wordId: 'w_1');
    await PhasePresentationTracker.markPresented(
        groupNo: 1, trackName: '新词测评', stepIndex: 0, wordId: 'w_2');
    // 同一个词再记一次（答错后回到队尾重练）：不应变成 3
    await PhasePresentationTracker.markPresented(
        groupNo: 1, trackName: '新词测评', stepIndex: 0, wordId: 'w_1');

    expect(
        PhasePresentationTracker.presentedCount(
            groupNo: 1, trackName: '新词测评', stepIndex: 0),
        2);
    expect(
        PhasePresentationTracker.presentedWordIds(
            groupNo: 1, trackName: '新词测评', stepIndex: 0),
        {'w_1', 'w_2'});
  });

  test('不同组、不同轨道、不同环节互不串味', () async {
    AppClock.setClock(FakeClock(DateTime(2026, 10, 1, 10, 0)));

    await PhasePresentationTracker.markPresented(
        groupNo: 1, trackName: '新词测评', stepIndex: 0, wordId: 'w_1');
    await PhasePresentationTracker.markPresented(
        groupNo: 1, trackName: '新词答对', stepIndex: 1, wordId: 'w_1');
    await PhasePresentationTracker.markPresented(
        groupNo: 2, trackName: '新词答对', stepIndex: 1, wordId: 'w_11');

    expect(
        PhasePresentationTracker.presentedCount(
            groupNo: 1, trackName: '新词测评', stepIndex: 0),
        1);
    expect(
        PhasePresentationTracker.presentedCount(
            groupNo: 1, trackName: '新词答对', stepIndex: 1),
        1,
        reason: '同一组的不同环节各数各的');
    expect(
        PhasePresentationTracker.presentedCount(
            groupNo: 2, trackName: '新词答对', stepIndex: 1),
        1,
        reason: '键里带组号：第 2 组的词不能被算进第 1 组');
  });

  test('跨业务日后记录自动作废', () async {
    AppClock.setClock(FakeClock(DateTime(2026, 10, 1, 10, 0)));
    await PhasePresentationTracker.markPresented(
        groupNo: 1, trackName: '新词测评', stepIndex: 0, wordId: 'w_1');
    expect(
        PhasePresentationTracker.presentedCount(
            groupNo: 1, trackName: '新词测评', stepIndex: 0),
        1);

    // 进入下一个业务日（凌晨 03:00 为界）
    AppClock.setClock(FakeClock(DateTime(2026, 10, 2, 10, 0)));
    expect(
        PhasePresentationTracker.presentedCount(
            groupNo: 1, trackName: '新词测评', stepIndex: 0),
        0,
        reason: '跨业务日后应视为空，无需依赖清理任务');
  });

  test('清空后归零（换环节 / 本组结束时调用）', () async {
    AppClock.setClock(FakeClock(DateTime(2026, 10, 1, 10, 0)));
    await PhasePresentationTracker.markPresented(
        groupNo: 1, trackName: '新词测评', stepIndex: 0, wordId: 'w_1');

    await PhasePresentationTracker.clear();

    expect(
        PhasePresentationTracker.presentedCount(
            groupNo: 1, trackName: '新词测评', stepIndex: 0),
        0);
  });
}
