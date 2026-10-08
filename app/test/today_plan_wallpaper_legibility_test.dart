import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/page/today_plan.dart';
import 'package:nnbdc/services/study_cache_manager.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 壁纸底「玻璃保持原样、只把文字调清」的回归测试。
///
/// 背景：卡片只是一层半透明玻璃（白 22% / 深色 #6018202F，跟着 App 主题，**不随照片改**），
/// 照片明暗完全不受控。字色若只按 App 主题取，浅色主题配宝蓝底的「石韵」就是深色字压在宝石蓝玻璃上，看不清。
/// 所以：
/// - 每张壁纸在 [planWallpapers] 里登记明暗档，只用来挑**字色**（中心岛/右上图标）；
/// - 屏幕最底部永远被暗角光幕压深，底部双任务卡与主按钮一律白字。
/// 这里既守「玻璃不变、字色跟着照片走」，也用**真实照片像素**算一遍对比度守住底线：
/// 实测中心岛 3.2~8.9、任务卡 4.9~10.0、主按钮 11.6~19.6、右上图标 3.2~16.2，
/// 其中湖光/旷野两档照片中段偏亮，是通透玻璃下最弱的两张（想再高只能动玻璃或加深光幕）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MyDatabase db;
  final now = AppClock.now();

  // 与 today_plan.dart 的 _buildBackground 一致：照片上那层黑色暗角光幕
  const List<double> scrimStops = [0.0, 0.32, 0.68, 1.0];
  const List<double> scrimAlphas = [0.45, 0.06, 0.42, 0.78];

  setUpAll(() {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => '.',
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('nnbdc/ocr'),
      (MethodCall methodCall) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      (MethodCall methodCall) async => <String>[],
    );
  });

  setUp(() async {
    db = MyDatabase(NativeDatabase.memory());
    MyDatabase.setInstanceForTesting(db);
    StudyCacheManager().clear();
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    Global.commonDictId = 'mock_dict_1';
  });

  tearDown(() async {
    await db.close();
    Global.currentUserId = null;
    Global.commonDictId = '0';
  });

  /// 一个"今天还没开始学、今日计划 5 个词"的账号：中心岛会渲染成「今日目标」。
  Future<void> seedTodayPlan() async {
    const String userId = 'test_user_id';
    final user = User(
      id: userId,
      userName: 'mock_user',
      password: '',
      nickName: 'Tester',
      email: '',
      gameScore: 0,
      dakaScore: 0,
      learnedDays: 1,
      learningFinished: false,
      inviteAwardTaken: false,
      isSuperAdmin: false,
      isAdmin: false,
      isInputor: false,
      cowDung: 0,
      throwDiceChance: 0,
      wordsPerDay: 5,
      dakaDayCount: 0,
      masteredWordsCount: 0,
      maxContinuousDakaDayCount: 0,
      continuousDakaDayCount: 0,
      todayStudyStarted: false,
      lastLearningDate: now,
      totalLearningSeconds: 0,
      todayLearningSeconds: 0,
      createTime: now,
      updateTime: now,
    );
    await db.usersDao.saveUser(user, false);
    Global.currentUserId = userId;
    Global.updateUserCache(user);
    await Prefs.write('currentUserId', userId);

    const dictId = 'mock_dict_1';
    await db.into(db.dicts).insert(Dict(
          id: dictId,
          name: '四级核心词汇',
          wordCount: 10,
          isShared: false,
          isReady: true,
          ownerId: 'sys',
          visible: true,
          editable: false,
          deletable: false,
          createTime: now,
          updateTime: now,
        ));
    await db.into(db.learningDicts).insert(LearningDict(
          userId: userId,
          dictId: dictId,
          isPrivileged: false,
          fetchMastered: false,
          sortAlg: 'ORIGINAL',
          createTime: now,
          updateTime: now,
        ));
    for (int i = 1; i <= 10; i++) {
      final wordId = 'word_$i';
      await db.into(db.words).insert(Word(
            id: wordId,
            spell: 'apple_$i',
            popularity: 100,
            createTime: now,
            updateTime: now,
          ));
      await db.into(db.dictWords).insert(DictWord(
            dictId: dictId,
            wordId: wordId,
            seq: i,
            unit: 0,
            createTime: now,
            updateTime: now,
          ));
    }
    for (int i = 1; i <= 5; i++) {
      await db.into(db.learningWords).insert(LearningWord(
            userId: userId,
            wordId: 'word_$i',
            addTime: now,
            addDay: 1,
            batchId: 1,
            stability: 0.0,
            isTodayNewWord: true,
            learnedTimes: 0,
            todayLearnedTimes: 0,
            lastLearningDate: now,
            learningOrder: i,
            createTime: now,
            updateTime: now,
            isExtra: false,
          ));
    }
  }

  /// 用指定壁纸 + 指定 App 主题渲染今日计划页，并给出 393x852 的真机视口。
  Future<void> pumpTodayPlan(
    WidgetTester tester, {
    required String wallpaper,
    required bool darkTheme,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(393, 852);
    tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
    addTearDown(tester.view.reset);

    await Prefs.write('today_plan_wallpaper', wallpaper);

    final darkMode = DarkMode();
    darkMode.setThemeStyle(darkTheme ? AppThemeStyle.midnight : AppThemeStyle.emerald);

    await tester.pumpWidget(
      ChangeNotifierProvider<DarkMode>.value(
        value: darkMode,
        child: const MaterialApp(home: TodayPlanPage()),
      ),
    );
    await tester.pump();
    await tester.pump(Duration.zero);
    for (int i = 0; i < 200 && find.text('今日目标').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// 取中心岛/任务卡的玻璃底色与实际字色（全部从渲染出来的组件里读，避免测试和实现各写一份调色板）。
  ({
    Color islandGlass,
    Color cardGlass,
    Color islandInk,
    Color islandMutedInk,
    Color cardInk,
    Color actionInk,
    Color headerInk,
  }) renderedPalette(WidgetTester tester) {
    Color decorationColor(Finder textFinder) {
      final container = tester.widget<Container>(
        find.ancestor(of: textFinder, matching: find.byType(Container)).first,
      );
      return (container.decoration! as BoxDecoration).color!;
    }

    final today = AppClock.today();
    final dateLabel = '${today.year}.${today.month.toString().padLeft(2, '0')}'
        '.${today.day.toString().padLeft(2, '0')}';
    return (
      islandGlass: decorationColor(find.text('今日目标')),
      cardGlass: decorationColor(find.text('新词')),
      islandInk: tester.widget<Text>(find.text('今日目标')).style!.color!,
      islandMutedInk: tester.widget<Text>(find.text(dateLabel)).style!.color!,
      cardInk: tester.widget<Text>(find.text('新词')).style!.color!,
      actionInk: tester.widget<Text>(find.text('开始学习')).style!.color!,
      headerInk: tester.widget<Icon>(find.byIcon(Icons.tune_rounded)).color!,
    );
  }

  Future<ui.Image> decodedImage(String assetPath) async {
    final bytes = await rootBundle.load(assetPath);
    final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
    return (await codec.getNextFrame()).image;
  }

  /// 屏幕坐标 → 照片像素的平均色（壁纸按 BoxFit.cover 铺满，必须按裁切关系换算）。
  Future<List<double>> photoAverage(ui.Image image, Rect screenRect, Size viewport) async {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final data = bytes!.buffer.asUint8List();
    final scale = (viewport.width / image.width) > (viewport.height / image.height)
        ? viewport.width / image.width
        : viewport.height / image.height;
    final drawnWidth = image.width * scale;
    final drawnHeight = image.height * scale;
    final offsetX = (viewport.width - drawnWidth) / 2;
    final offsetY = (viewport.height - drawnHeight) / 2;

    final imageRect = Rect.fromLTRB(
      ((screenRect.left - offsetX) / scale).clamp(0.0, image.width.toDouble()),
      ((screenRect.top - offsetY) / scale).clamp(0.0, image.height.toDouble()),
      ((screenRect.right - offsetX) / scale).clamp(0.0, image.width.toDouble()),
      ((screenRect.bottom - offsetY) / scale).clamp(0.0, image.height.toDouble()),
    );

    double r = 0, g = 0, b = 0;
    int count = 0;
    for (int y = imageRect.top.round(); y < imageRect.bottom.round(); y++) {
      for (int x = imageRect.left.round(); x < imageRect.right.round(); x++) {
        final i = (y * image.width + x) * 4;
        r += data[i];
        g += data[i + 1];
        b += data[i + 2];
        count++;
      }
    }
    return [r / count, g / count, b / count];
  }

  /// sRGB 单通道 → 线性光强（WCAG 相对亮度用的口径）
  double linearChannel(double channel) {
    final c = channel / 255.0;
    return c <= 0.04045 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  double relativeLuminance(List<double> rgb) =>
      0.2126 * linearChannel(rgb[0]) + 0.7152 * linearChannel(rgb[1]) + 0.0722 * linearChannel(rgb[2]);

  double contrastRatio(double a, double b) {
    final hi = a > b ? a : b;
    final lo = a > b ? b : a;
    return (hi + 0.05) / (lo + 0.05);
  }

  double scrimAlphaAt(double t) {
    for (int i = 0; i < scrimStops.length - 1; i++) {
      final t0 = scrimStops[i];
      final t1 = scrimStops[i + 1];
      if (t <= t0) return scrimAlphas[i];
      if (t <= t1) {
        final k = (t - t0) / (t1 - t0);
        return scrimAlphas[i] * (1 - k) + scrimAlphas[i + 1] * k;
      }
    }
    return scrimAlphas.last;
  }

  /// 直接压在照片上的字（按钮/顶栏图标）：只有暗角光幕，没有玻璃托底。
  double photoContrast({
    required List<double> photo,
    required double screenYRatio,
    required Color ink,
  }) {
    final scrim = scrimAlphaAt(screenYRatio);
    final bg = photo.map((c) => c * (1 - scrim)).toList();
    final inked = List<double>.generate(
      3,
      (i) => bg[i] * (1 - ink.a) + [ink.r * 255, ink.g * 255, ink.b * 255][i] * ink.a,
    );
    return contrastRatio(relativeLuminance(bg), relativeLuminance(inked));
  }

  /// 照片 → 暗角光幕 → 玻璃后的卡片亮度，再算与字色的对比度。
  double cardContrast({
    required List<double> photo,
    required double screenYRatio,
    required List<double> glass,
    required double glassAlpha,
    required Color ink,
  }) {
    final scrim = scrimAlphaAt(screenYRatio);
    final bg = photo.map((c) => c * (1 - scrim)).toList();
    final card = List<double>.generate(
      3,
      (i) => bg[i] * (1 - glassAlpha) + glass[i] * glassAlpha,
    );
    // 半透明的字色（如暗底的白色 82%）要先合成到卡片上，再算对比度
    final inked = List<double>.generate(
      3,
      (i) => card[i] * (1 - ink.a) + [ink.r * 255, ink.g * 255, ink.b * 255][i] * ink.a,
    );
    return contrastRatio(relativeLuminance(card), relativeLuminance(inked));
  }

  /// 1. 取色只认照片明暗：App 主题反过来也不许改字色（这正是「石韵」糊字的根因）。
  for (final wallpaper in planWallpapers.where((w) => w.path != 'none')) {
    for (final darkTheme in [false, true]) {
      testWidgets(
          '${wallpaper.name}（${wallpaper.isDark ? '暗底照片' : '亮底照片'}）+ ${darkTheme ? '深色主题' : '浅色主题'}：玻璃保持原样，只有字色跟照片走',
          (tester) async {
        await seedTodayPlan();
        await pumpTodayPlan(tester, wallpaper: wallpaper.path, darkTheme: darkTheme);

        final palette = renderedPalette(tester);
        // 玻璃只跟 App 主题（原来的通透磨砂），绝不随照片改透明度
        final expectedGlass = darkTheme
            ? const Color(0x6018202F)
            : Colors.white.withValues(alpha: 0.22);
        expect(palette.islandGlass, expectedGlass, reason: '中心岛玻璃保持原来的通透度');
        expect(palette.cardGlass, expectedGlass, reason: '任务卡玻璃保持原来的通透度');
        // 字色才是为了看清而动的部分
        expect(palette.islandInk, wallpaper.isDark ? Colors.white : const Color(0xFF0F172A),
            reason: '中心岛浮在照片中段，字色跟照片明暗档');
        expect(palette.cardInk, Colors.white.withValues(alpha: 0.82),
            reason: '底部任务卡永远压在暗角光幕上，一律白色系（这里是卡上的次级标签）');

        await tester.pump(const Duration(seconds: 60));
      });
    }
  }

  /// 2. 用真实照片像素算对比度：按登记的明暗档取色后，主字/次字在任何一张照片上都够看。
  ///
  /// 调色板只与「明暗档」有关、与具体是哪张照片无关（上面 14 条测试已逐张守过），
  /// 所以这里两档各渲染一次取真实调色板，再逐张照片算对比度，不必为每张照片重开一次页面。
  testWidgets('每张壁纸按登记的明暗档取色后，卡片主字/次字对比度都达标', timeout: const Timeout(Duration(seconds: 60)),
      (tester) async {
    final darkWallpaper = planWallpapers.firstWhere((w) => w.isDark && w.path != 'none');
    final lightWallpaper = planWallpapers.firstWhere((w) => !w.isDark && w.path != 'none');

    await seedTodayPlan();
    await pumpTodayPlan(tester, wallpaper: darkWallpaper.path, darkTheme: false);
    final darkPalette = renderedPalette(tester);
    final islandRect = tester.getRect(
      find.ancestor(of: find.text('今日目标'), matching: find.byType(Container)).first,
    );
    final cardRect = tester.getRect(
      find.ancestor(of: find.text('新词'), matching: find.byType(Container)).first,
    );
    final buttonRect = tester.getRect(find.text('开始学习'));
    final headerRect = tester.getRect(find.byIcon(Icons.tune_rounded));
    final viewport = tester.view.physicalSize / tester.view.devicePixelRatio;

    await tester.pumpWidget(const SizedBox.shrink());
    await pumpTodayPlan(tester, wallpaper: lightWallpaper.path, darkTheme: true);
    final lightPalette = renderedPalette(tester);

    for (final wallpaper in planWallpapers.where((w) => w.path != 'none')) {
      final palette = wallpaper.isDark ? darkPalette : lightPalette;

      // 两块玻璃卡：中心岛（浮在照片中段）与底部任务卡（压在暗角光幕上）
      // 玻璃保持原来的通透度，可读性由「选对字色 + 字上一圈淡光晕」兜住，
      // 所以这里守的是这套组合的底线，而不是 4.5 那种不透明卡才有的高线。
      for (final (rect, glass, primaryInk, mutedInk, floor1, floor2, label) in [
        (islandRect, palette.islandGlass, palette.islandInk, palette.islandMutedInk, 3.0, 2.5, '中心岛'),
        (cardRect, palette.cardGlass, palette.cardInk, palette.cardInk, 3.5, 3.0, '任务卡'),
      ]) {
        // 解码与取像素是真实引擎异步，必须走 runAsync（testWidgets 的假时钟不会推进它们）
        final photo = (await tester.runAsync(() async {
          final image = await decodedImage(wallpaper.path);
          return photoAverage(image, rect, viewport);
        }))!;
        final yRatio = rect.center.dy / viewport.height;
        final glassRgb = [glass.r * 255, glass.g * 255, glass.b * 255];

        final primary = cardContrast(
          photo: photo,
          screenYRatio: yRatio,
          glass: glassRgb,
          glassAlpha: glass.a,
          ink: primaryInk,
        );
        final muted = cardContrast(
          photo: photo,
          screenYRatio: yRatio,
          glass: glassRgb,
          glassAlpha: glass.a,
          ink: mutedInk,
        );

        expect(primary, greaterThanOrEqualTo(floor1),
            reason: '${wallpaper.name} 的$label主字对比度（实测 ${primary.toStringAsFixed(2)}）');
        expect(muted, greaterThanOrEqualTo(floor2),
            reason: '${wallpaper.name} 的$label次字对比度（实测 ${muted.toStringAsFixed(2)}）');
      }

      // 直接压在照片上的两处前景没有玻璃托底：底部按钮永远在暗角光幕里，顶栏图标跟着照片明暗
      for (final (rect, ink, threshold, label) in [
        (buttonRect, palette.actionInk, 5.0, '主按钮'),
        // 图标是非文本图形，按 WCAG 1.4.11 的 3:1 收口（且它还带一层光晕）
        (headerRect, palette.headerInk, 3.0, '右上设置图标'),
      ]) {
        final photo = (await tester.runAsync(() async {
          final image = await decodedImage(wallpaper.path);
          return photoAverage(image, rect, viewport);
        }))!;
        final measured = photoContrast(
          photo: photo,
          screenYRatio: rect.center.dy / viewport.height,
          ink: ink,
        );
        expect(measured, greaterThanOrEqualTo(threshold),
            reason: '${wallpaper.name} 的$label在照片上的对比度（实测 ${measured.toStringAsFixed(2)}）');
      }
    }

    await tester.pump(const Duration(seconds: 60));
  });
}
