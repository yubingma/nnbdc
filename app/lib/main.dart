import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/page/bdc.dart';
import 'package:nnbdc/page/before_bdc.dart';
import 'package:nnbdc/page/finish.dart';
import 'package:nnbdc/page/first.dart';
import 'package:nnbdc/page/game.dart';
import 'package:nnbdc/page/index.dart';
import 'package:nnbdc/page/login.dart';
import 'package:nnbdc/page/msg.dart';
import 'package:nnbdc/page/pic_search.dart';
import 'package:nnbdc/page/privacy.dart';
import 'package:nnbdc/page/protocol.dart';
import 'package:nnbdc/page/russia.dart';
import 'package:nnbdc/page/search.dart';
import 'package:nnbdc/page/select_book.dart';
import 'package:nnbdc/page/walkman.dart';
import 'package:nnbdc/page/word_detail.dart';
import 'package:nnbdc/page/word_list/word_list.dart';
import 'package:nnbdc/page/word_lists.dart';
import 'package:nnbdc/socket_io.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/test.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:provider/provider.dart';
import 'package:toastification/toastification.dart';

import 'local_word_cache.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => DarkMode()),
      ],
      child: ToastificationWrapper(child: const MyApp()),
    ),
  );

  // 延迟加载初始化操作
  WidgetsBinding.instance.addPostFrameCallback((_) async {

    await GetStorage.init();

    if (PlatformUtils.isAndroid) {
      await FlutterDownloader.initialize(debug: true);
    }

    // 初始化加载服务
    Api.loadingService.init();

    MyDatabase.instance;
    // SocketIoClient改为延迟连接，只在需要时才连接（如进入russia页面）
    LocalWordCache.instance;

    // 预加载当前用户数据
    await Global.loadUserFromDb();
  });
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
        Global.logger.d('应用恢复前台');
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
      title: '泡泡单词',
      debugShowCheckedModeBanner: false,
      theme: themeData,
      initialRoute: '/first',
      routes: {
        '/test': (context) => TestPage(),
        '/first': (context) => const FirstPage(),
        '/email_login': (context) => const LoginPage(),
        '/index': (context) => const IndexPage(),
        '/protocol': (context) => const ProtocolPage(),
        '/privacy': (context) => const PrivacyPage(),
        '/pic_search': (context) => const PicSearchPage(),
        '/select_book': (context) {
          // 添加延迟加载以避免黑屏
          Future.microtask(() {
            // 确保页面过渡动画完成后再进行复杂的数据加载
            Future.delayed(const Duration(milliseconds: 100), () {
              Api.loadingService.init(); // 确保加载服务已初始化
            });
          });
          return const SelectBookPage();
        },
        '/before_bdc': (context) {
          // 添加延迟加载以避免黑屏
          Future.microtask(() {
            // 确保页面过渡动画完成后再进行复杂的数据加载
            Future.delayed(const Duration(milliseconds: 100), () {
              Api.loadingService.init(); // 确保加载服务已初始化
            });
          });
          return const BeforeBdcPage();
        },
        '/word_list': (context) => const WordListPage(),
        '/walkman': (context) => const WalkmanPage(),
        '/game': (context) => const GamePage(),
        '/russia': (context) => const RussiaPage(),
        '/word_detail': (context) => const WordDetailPage(),
        '/bdc': (context) => const BdcPage(),
        '/finish': (context) => const FinishPage(),
        '/word_lists': (context) => const WordListsPage(),
        '/msg': (context) => const MsgPage(),
        '/search': (context) => const SearchPage(),
      },
    );
  }
}

