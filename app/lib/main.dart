import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:umeng_common_sdk/umeng_common_sdk.dart';

import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/api/bo/user_bo.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/page/admin.dart';
import 'package:nnbdc/page/ai_activation.dart';
import 'package:nnbdc/page/ai_diagnostic.dart';
import 'package:nnbdc/page/bdc/bdc.dart';
import 'package:nnbdc/page/walkman.dart';

import 'package:nnbdc/page/farm.dart';
import 'package:nnbdc/page/finish.dart';
import 'package:nnbdc/page/first.dart';
import 'package:nnbdc/page/game.dart';
import 'package:nnbdc/page/index.dart';
import 'package:nnbdc/page/login.dart';
import 'package:nnbdc/page/email_login.dart';
import 'package:nnbdc/page/msg.dart';
import 'package:nnbdc/page/pic_search.dart';
import 'package:nnbdc/page/privacy.dart';
import 'package:nnbdc/page/protocol.dart';
import 'package:nnbdc/page/russia.dart';
import 'package:nnbdc/page/search.dart';
import 'package:nnbdc/page/select_book.dart';
import 'package:nnbdc/page/word_detail.dart';
import 'package:nnbdc/page/word_lists.dart';
import 'package:nnbdc/page/word_list/word_list.dart';
import 'package:nnbdc/socket_io.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/test.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/error_handler.dart';
import 'package:nnbdc/services/ai_service.dart';
import 'package:nnbdc/services/ai_model_manager.dart';
import 'package:nnbdc/services/ai_runtime_apple.dart';
import 'package:nnbdc/services/ai_runtime_android.dart';
import 'package:provider/provider.dart' as provider;
import 'package:toastification/toastification.dart';
import 'package:nnbdc/page/admin/golden_master_tool.dart';
import 'package:nnbdc/util/subscription_util.dart';
import 'package:nnbdc/util/notification_util.dart';
import 'package:nnbdc/util/analytics_util.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/page/study_stats.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config.dart';
import 'local_word_cache.dart';

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

void main() async {
  HttpOverrides.global = MyHttpOverrides();
  // 使用Zone捕获所有未处理的异步异常
  runZonedGuarded(
    () async {
      // 确保Flutter绑定已初始化（在同一个zone中）
      WidgetsFlutterBinding.ensureInitialized();
      
      // 初始化存储（必须在检查隐私版本前）
      await GetStorage.init();

      // 隐私政策版本检查
      const int currentPrivacyVersion = 20260310;
      int acceptedVersion = GetStorage().read<int>('accepted_privacy_version') ?? 0;
      bool hasApprovedRecentPrivacy = (acceptedVersion >= currentPrivacyVersion);

      // 只有在 Android 或 iOS 上处理 Umeng 和 自定义分析
      if (PlatformUtils.isAndroid || PlatformUtils.isIOS) {
        // 更新分析工具的状态
        AnalyticsUtil.init(hasApprovedRecentPrivacy);

        try {
          // 如果用户已经同意过最新版本的隐私协议，则进行正式初始化
          if (hasApprovedRecentPrivacy) {
            UmengCommonSdk.initCommon(Config.umengAndroidAppKey, Config.umengIosAppKey, Config.umengChannel);
            debugPrint('Umeng fully initialized (Privacy Approved)');
          } else {
            debugPrint('Umeng initialization skipped (Pending Privacy Approval)');
          }
        } catch (e) {
          debugPrint('Umeng setup failed: $e');
        }
      }

      // 捕获Flutter框架层的错误（同步错误）
      FlutterError.onError = (FlutterErrorDetails details) {
        // 检查是否为图像相关的错误（非致命错误，不需要在控制台显示）
        final exceptionString = details.exceptionAsString();
        final stackString = details.stack?.toString() ?? '';
        final isImageError = exceptionString.contains('Invalid image data') ||
            exceptionString.contains('Exception: Invalid image data') ||
            exceptionString.contains('Failed to decode image') ||
            exceptionString.contains('ImageDecoder') ||
            exceptionString.contains('DecodeException') ||
            stackString.contains('MemoryImage') ||
            stackString.contains('image_provider.dart') ||
            stackString.contains('ImageDecoder') ||
            stackString.contains('decodeImage');

        if (isImageError) {
          // 图像错误只记录到日志，不输出到控制台（避免干扰）
          Global.logger.w(
            '【图像加载错误】${details.exceptionAsString()}',
            error: details.exception,
            stackTrace: details.stack,
          );
        } else {
          // 其他错误正常处理
          Global.logger.e(
            '【Flutter框架错误】${details.exceptionAsString()}',
            error: details.exception,
            stackTrace: details.stack,
          );

          // 在debug模式下，也输出到控制台
          FlutterError.presentError(details);

          // 上报到 Umeng Analytics (仅限移动端)
          if (PlatformUtils.isAndroid || PlatformUtils.isIOS) {
            UmengCommonSdk.onEvent('flutter_error', {
              'exception': details.exceptionAsString(),
              'stack': details.stack?.toString() ?? ''
            });
          }
        }
      };

      // 捕获平台层和异步错误
      PlatformDispatcher.instance.onError = (error, stack) {
        Global.logger.e(
          '【未捕获的平台/异步错误】',
          error: error,
          stackTrace: stack,
        );

        // 上报到 Umeng Analytics (仅限移动端)
        if (PlatformUtils.isAndroid || PlatformUtils.isIOS) {
          UmengCommonSdk.onEvent('flutter_async_error', {
            'error': error.toString(),
            'stack': stack.toString()
          });
        }

        return true; // 返回true表示错误已处理
      };

      // 尝试部署预置数据库（黄金母版）
      // 注意：必须在 runApp 之前调用，确保在应用 UI 初始化（可能会触发数据库访问）之前完成数据库文件的部署
      await MyDatabase.initPrepopulatedDb();

      runApp(
        ProviderScope(
          child: provider.MultiProvider(
            providers: [
              provider.ChangeNotifierProvider(create: (context) => DarkMode()),
            ],
            child: ToastificationWrapper(child: const MyApp()),
          ),
        ),
      );

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          // 这里不再需要再次 init() 了，main() 顶部已经做过了

          if (PlatformUtils.isAndroid) {
            await FlutterDownloader.initialize(debug: true);
          }

          // 初始化加载服务
          Api.loadingService.init();

          // 初始化数据库并确保数据库完整性
          MyDatabase.instance;
          await MyDatabase.ensureDatabaseIntegrity();

          // SocketIoClient改为延迟连接，只在需要时才连接（如进入russia页面）
          LocalWordCache.instance;

          // 预加载当前用户数据并处理自动登录业务逻辑
          final user = await Global.loadUserFromDb();
          if (user != null) {
            await UserBo().handleAutoLogin(user.id);
          }

          // 检查并强制执行会员限制（非会员每日单词限额 20）
          await SubscriptionUtil.checkAndEnforceMemberLimits();

          // 初始化通知服务并安排每日提醒
          try {
            await NotificationUtil.init();
            await NotificationUtil.scheduleDailyReminder();
          } catch (e) {
            Global.logger.e('初始化通知失败: $e');
          }

          // 初始化 AI 运行时（Apple 平台，如果已下载模型且用户是管理员）
          if ((PlatformUtils.isMacOS || PlatformUtils.isIOS) && Global.getLoggedInUser()?.isAdmin == true) {
            _initializeAppleAiRuntimeIfReady();
          }
        } catch (e, stackTrace) {
          // 初始化过程中的错误
          // 同时将错误写入全局状态，供启动页展示（不是toast）
          Global.setStartupError('应用初始化失败：$e');
          ErrorHandler.handleError(
            e,
            stackTrace,
            logPrefix: '应用初始化失败',
            userMessage: '应用初始化失败，请重启应用',
            showToast: false, // 此时UI可能还未准备好
          );
        }
      });
    },
    (error, stack) {
      // Zone中捕获的未处理异常
      Global.logger.e(
        '【Zone捕获的未处理异常】',
        error: error,
        stackTrace: stack,
      );

      // 上报到 Umeng Analytics (仅限移动端)
      if (PlatformUtils.isAndroid || PlatformUtils.isIOS) {
        UmengCommonSdk.onEvent('zone_error', {
          'error': error.toString(),
          'stack': stack.toString()
        });
      }
    },
  );
}

/// 初始化 Apple AI 运行时（如果模型已就绪）
void _initializeAppleAiRuntimeIfReady() async {
  try {
    // 检查是否已下载模型
    final manager = AiModelManager();
    final localState = await manager.loadLocalState();

    if (localState != null && localState.localPath.isNotEmpty) {
      Global.logger.i('检测到模型已下载，开始自动初始化 AI 运行时...');
      if (PlatformUtils.isAndroid) {
        await initializeAndroidAiRuntime();
      } else if (PlatformUtils.isIOS || PlatformUtils.isMacOS) {
        await initializeAppleAiRuntime();
      }
    } else {
      Global.logger.d('模型尚未下载，跳过 AI 运行时初始化');
    }
  } catch (e, st) {
    Global.logger.e('自动初始化 AI 运行时失败', error: e, stackTrace: st);
  }
}

/// 初始化 Android AI 运行时（手动调用）
Future<bool> initializeAndroidAiRuntime() async {
  try {
    Global.logger.i('开始初始化 Android AI 运行时...');

    // 1. 预检查设备能力，决定下载哪个级别的模型
    const channel = MethodChannel('com.nnbdc.ai_inference');
    final capResult = await channel.invokeMethod('checkCapability');
    AiModelProfile preferredProfile = AiModelProfile.mobileLite;

    if (capResult is Map) {
      final capStr = capResult['capability'] as String?;
      if (capStr == 'full') {
        preferredProfile = AiModelProfile.desktopFull;
        Global.logger.i('检测到设备内存充足，选用桌面级模型 (desktopFull)');
      } else if (capStr == 'light') {
        preferredProfile = AiModelProfile.mobileLite;
        Global.logger.i('检测到设备内存适中，选用移动端轻量级模型 (mobileLite)');
      } else {
        Global.logger.w('设备能力报告为不足，将尝试加载 mobileLite 模型');
        preferredProfile = AiModelProfile.mobileLite;
      }
    }

    // 2. 确保模型已下载
    final manager = AiModelManager();
    final modelState = await manager.ensureModel(preferredProfile);

    if (modelState == null || modelState.localPath.isEmpty) {
      Global.logger.w('Android AI 模型 [${preferredProfile.name}] 未就绪，跳过初始化');
      return false;
    }

    // 3. 创建并初始化 Android AI 运行时
    final runtime = AndroidAiRuntime(modelPath: modelState.localPath);
    final success = await runtime.initialize();

    if (success) {
      // 4. 注入到 AiService
      AiService().setRuntime(runtime);
      Global.logger.i('Android AI 运行时初始化成功，能力等级: ${runtime.capabilityLevel}');
      return true;
    } else {
      Global.logger.w('Android AI 运行时初始化失败');
      return false;
    }
  } catch (e, st) {
    Global.logger.e('Android AI 运行时初始化异常', error: e, stackTrace: st);
    return false;
  }
}

/// 初始化 Apple AI 运行时（手动调用）
Future<bool> initializeAppleAiRuntime() async {
  try {
    Global.logger.i('开始初始化 Apple AI 运行时...');

    // 1. 预检查设备能力，决定下载哪个级别的模型
    const channel = MethodChannel('com.nnbdc.ai_inference');
    final capResult = await channel.invokeMethod('checkCapability');
    AiModelProfile preferredProfile = AiModelProfile.desktopFull;

    if (capResult is Map) {
      final capStr = capResult['capability'] as String?;
      if (capStr == 'light') {
        preferredProfile = AiModelProfile.mobileLite;
        Global.logger.i('检测到设备内存较小，优先选用移动端轻量级模型 (mobileLite)');
      } else if (capStr == 'none') {
        Global.logger.w('设备能力报告为不足，可能会尝试加载 mobileLite 但风险较高');
        preferredProfile = AiModelProfile.mobileLite;
      }
    }

    // 2. 确保模型已下载
    final manager = AiModelManager();
    final modelState = await manager.ensureModel(preferredProfile);

    if (modelState == null || modelState.localPath.isEmpty) {
      Global.logger.w('Apple AI 模型 [${preferredProfile.name}] 未就绪，跳过初始化');
      return false;
    }

    // 3. 创建并初始化 Apple AI 运行时
    final runtime = AppleAiRuntime(modelPath: modelState.localPath);
    final success = await runtime.initialize();

    if (success) {
      // 4. 注入到 AiService
      AiService().setRuntime(runtime);
      Global.logger.i('Apple AI 运行时初始化成功，能力等级: ${runtime.capabilityLevel}');
      return true;
    } else {
      Global.logger.w('Apple AI 运行时初始化失败');
      return false;
    }
  } catch (e, st) {
    Global.logger.e('Apple AI 运行时初始化异常', error: e, stackTrace: st);
    return false;
  }
}

/// 反激活 AI 运行时（手动调用）
Future<void> deinitializeAppleAiRuntime() async {
  try {
    Global.logger.i('开始反激活 AI 运行时...');

    // 1. 如果当前已经是某个运行时，调用它的 dispose
    final aiService = AiService();
    if (aiService.capabilityLevel != AiCapabilityLevel.none) {
      const MethodChannel('com.nnbdc.ai_inference').invokeMethod('unloadModel');
    }

    // 2. 重置为 NoopRuntime
    aiService.setRuntime(NoopAiRuntime());

    Global.logger.i('AI 运行时已卸载并重置');
  } catch (e, st) {
    Global.logger.e('AI 运行时反激活异常', error: e, stackTrace: st);
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    loadData();
  }

  @override
  void dispose() {
    // 清理所有全局资源
    WidgetsBinding.instance.removeObserver(this);
    IsolateNameServer.removePortNameMapping('downloader_send_port');

    // 清理SocketIoClient资源
    SocketIoClient.instance.dispose();

    // 关闭数据库连接
    MyDatabase.closeDatabase();

    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.paused:
        // 应用进入后台时，清理一些资源
        Global.logger.d('应用进入后台');
        break;
      case AppLifecycleState.resumed:
        // 应用恢复时，重新连接必要的服务
        Global.logger.d('应用恢复前台，触发数据库同步');
        ThrottledDbSyncService().requestSync();
        break;
      case AppLifecycleState.detached:
        // 应用即将关闭时，确保资源清理
        Global.logger.d('应用即将关闭');
        SocketIoClient.instance.dispose();
        break;
      default:
        break;
    }
  }

  loadData() async {
    var isDarkMode = await MyDatabase.instance.localParamsDao.getIsDarkMode();
    if (mounted) {
      context.read<DarkMode>().setIsDarkMode(isDarkMode);
    }
  }

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    var themeData = context.watch<DarkMode>().isDarkMode ? AppTheme.darkTheme() : AppTheme.lightTheme();
    return GetMaterialApp(
      title: Global.appName,
      debugShowCheckedModeBanner: false,
      theme: themeData,
      initialRoute: '/first',
      getPages: [
        GetPage(name: '/test', page: () => TestPage()),
        GetPage(name: '/first', page: () => const FirstPage()),
        GetPage(name: '/login', page: () => const LoginPage()),
        GetPage(name: '/email_login', page: () => const EmailLoginPage()),
        GetPage(name: '/index', page: () => const IndexPage()),
        GetPage(name: '/protocol', page: () => const ProtocolPage()),
        GetPage(name: '/privacy', page: () => const PrivacyPage()),
        GetPage(name: '/pic_search', page: () => const PicSearchPage()),
        GetPage(
          name: '/select_book',
          page: () {
            // 添加延迟加载以避免黑屏
            Future.microtask(() {
              // 确保页面过渡动画完成后再进行复杂的数据加载
              Future.delayed(const Duration(milliseconds: 100), () {
                Api.loadingService.init(); // 确保加载服务已初始化
              });
            });
            return const SelectBookPage();
          },
        ),
        GetPage(
          name: '/bdc',
          page: () => const BdcPage(),
        ),
        GetPage(name: '/walkman', page: () => const WalkmanPage()),
        GetPage(name: '/game', page: () => const GamePage()),
        GetPage(name: '/russia', page: () => const RussiaPage()),
        GetPage(name: '/word_detail', page: () => const WordDetailPage()),
        GetPage(name: '/word_list', page: () => const WordListPage()),
        GetPage(name: '/finish', page: () => const FinishPage()),
        GetPage(name: '/farm', page: () => const FarmPage()),
        GetPage(name: '/word_lists', page: () => const WordListsPage()),
        GetPage(name: '/msg', page: () => const MsgPage()),
        GetPage(name: '/search', page: () => const SearchPage()),
        GetPage(name: '/admin', page: () => const AdminPage()),
        GetPage(name: '/ai_activation', page: () => const AiActivationPage()),
        GetPage(name: '/ai_diagnostic', page: () => const AiDiagnosticPage()),
        GetPage(name: '/golden_master', page: () => const GoldenMasterToolPage()),
        GetPage(name: '/study_stats', page: () => const StudyStatsPage()),
      ],
    );
  }
}
