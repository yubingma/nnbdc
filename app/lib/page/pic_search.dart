import 'dart:async';
import 'dart:collection';
import 'package:nnbdc/global.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:go_router/go_router.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/dto.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:provider/provider.dart';

import '../state.dart';
import '../util/toast_util.dart';
import '../util/utils.dart';
import '../theme/app_theme.dart';
import '../db/db.dart';

class PicSearchPageArgs {
  String wordId;
  String spell;

  PicSearchPageArgs(this.wordId, this.spell);
}

class PicSearchPage extends StatefulWidget {
  const PicSearchPage({super.key});

  @override
  PicSearchPageState createState() {
    return PicSearchPageState();
  }
}

class PicSearchPageState extends State<PicSearchPage> {
  late PicSearchPageArgs args;
  InAppWebViewHitTestResult? hitTestResult;
  String? longPressImageUrl;
  final GlobalKey webViewKey = GlobalKey();
  InAppWebViewController? webViewController;
  bool _isAddPicDialogShowing = false;

  /// 单词配图数量上限（与服务端 WordImageBo.MAX_IMAGES_PER_WORD 保持一致）。
  static const int _maxImagesPerWord = 2;

  /// 该单词当前已有配图数；进入页面时就加载，用于提前提示用户剩余配额/是否已达上限。
  int? _imageCount;
  bool _imageCountLoaded = false;
  InAppWebViewSettings settings = InAppWebViewSettings(
    isInspectable: kDebugMode,
    disableContextMenu: true,
    disableLongPressContextMenuOnLinks: true,
  );

  static const String _disableSystemContextMenuJs = '''
    (function() {
      try {
        document.addEventListener('contextmenu', function(e) { e.preventDefault(); }, { capture: true });
        var style = document.getElementById('__nnbdc_disable_longpress_style__');
        if (!style) {
          style = document.createElement('style');
          style.id = '__nnbdc_disable_longpress_style__';
          style.innerHTML = 'img, a, body, html { -webkit-touch-callout: none !important; -webkit-user-select: none !important; user-select: none !important; }';
          document.head.appendChild(style);
        }
      } catch (e) {}
    })();
  ''';

  static const String _longPressImageHandlerJs = '''
    (function() {
      if (window.__nnbdc_longpress_installed) return;
      window.__nnbdc_longpress_installed = true;

      var timer = null;
      var startTarget = null;
      var startX = 0;
      var startY = 0;
      var moveThreshold = 10;

      function clearTimer() {
        if (timer) {
          clearTimeout(timer);
          timer = null;
        }
        startTarget = null;
      }

      function getImageTarget(t) {
        if (!t) return null;
        if (t.tagName === 'IMG') return t;
        if (t.closest) return t.closest('img');
        return null;
      }

      function getImageUrl(img) {
        if (!img) return null;
        return img.currentSrc || img.src || img.getAttribute('data-src') || img.getAttribute('data-original') || img.getAttribute('src');
      }

      document.addEventListener('touchstart', function(e) {
        if (!e || !e.touches || e.touches.length !== 1) return;
        var img = getImageTarget(e.target);
        if (!img) return;
        startTarget = img;
        startX = e.touches[0].clientX;
        startY = e.touches[0].clientY;
        timer = setTimeout(function() {
          var url = getImageUrl(startTarget);
          clearTimer();
          if (url && window.flutter_inappwebview && window.flutter_inappwebview.callHandler) {
            window.flutter_inappwebview.callHandler('nnbdcLongPressImage', url);
          }
        }, 450);
      }, { capture: true, passive: true });

      document.addEventListener('touchmove', function(e) {
        if (!timer || !e || !e.touches || e.touches.length !== 1) return;
        var dx = Math.abs(e.touches[0].clientX - startX);
        var dy = Math.abs(e.touches[0].clientY - startY);
        if (dx > moveThreshold || dy > moveThreshold) {
          clearTimer();
        }
      }, { capture: true, passive: true });

      document.addEventListener('touchend', function(e) {
        clearTimer();
      }, { capture: true, passive: true });

      document.addEventListener('touchcancel', function(e) {
        clearTimer();
      }, { capture: true, passive: true });
    })();
  ''';

  Future<void> init() async {
    if (PlatformUtils.isAndroid) {
      await InAppWebViewController.setWebContentsDebuggingEnabled(true);
    }
  }

  @override
  void initState() {
    super.initState();
    init();

    Future.delayed(Duration.zero, () {
      if (mounted) {
        const snackBar = SnackBar(
          content: Text("请长按目标图片，将其加为单词配图"),
          duration: Duration(seconds: 3),
        );
        ScaffoldMessenger.of(context).showSnackBar(snackBar);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final extra = GoRouterState.of(context).extra;
    if (extra is PicSearchPageArgs) {
      args = extra;
      // 进入页面时立即加载该单词已有配图数，用于提前提示配额，避免用户浪费时间选图后才被拦。
      if (!_imageCountLoaded) {
        _imageCountLoaded = true;
        _loadImageCount();
      }
    }
  }

  /// 加载该单词当前已有配图数量，用于提前展示配额/上限提示。
  Future<void> _loadImageCount() async {
    try {
      final images = await MyDatabase.instance.wordImagesDao
          .getImagesByWordId(args.wordId);
      if (!mounted) return;
      setState(() => _imageCount = images.length);
    } catch (e, s) {
      Global.logger.e('加载单词配图数量失败', error: e, stackTrace: s);
    }
  }

  Future<void> showAddPicDlg(BuildContext context) async {
    if (_isAddPicDialogShowing) return;

    final imageExtra = hitTestResult?.extra ?? longPressImageUrl;
    if (imageExtra == null || imageExtra.isEmpty) return;

    // 提前拦截：单词配图已达上限时直接提示，不再弹出"加为单词配图"，避免用户白耗时间。
    try {
      final images = await MyDatabase.instance.wordImagesDao
          .getImagesByWordId(args.wordId);
      if (!context.mounted) return;
      if (images.length >= _maxImagesPerWord) {
        ToastUtil.error('该单词已有 $_maxImagesPerWord 张配图，无法再添加；如需更换请先删除现有配图');
        return;
      }
    } catch (e, s) {
      Global.logger.e('检查单词配图上限失败', error: e, stackTrace: s);
    }

    _isAddPicDialogShowing = true;
    try {
      await showGeneralDialog(
          context: context,
          barrierDismissible: true,
          barrierLabel: '',
          transitionDuration: const Duration(milliseconds: 100),
          transitionBuilder: (context, animation, secondaryAnimation, child) {
            return FractionalTranslation(
                translation: Offset(0, 1 - animation.value), child: child);
          },
          pageBuilder: (context, animation, secondaryAnimation) {
            return StatefulBuilder(builder: (context, setState) {
              return Align(
                  alignment: const Alignment(0, 1),
                  child: Container(
                      width: MediaQuery.of(context).size.width,
                      height: 70,
                      margin: MediaQuery.of(context).viewInsets,
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                      color: context.read<DarkMode>().isDarkMode
                          ? const Color(0xff333333)
                          : Colors.white,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  backgroundColor: Colors.green,
                                ),
                                child: const Text('取消'),
                                onPressed: () {
                                  Navigator.pop(context, false);
                                },
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  backgroundColor: Colors.green,
                                ),
                                child: const Text('加为单词配图'),
                                onPressed: () async {
                                  Navigator.pop(context, false);
                                  final navigator = Navigator.of(context);

                                  try {
                                    // 先校验配图上限（下载前），避免用户白白等待图片下载后才得知无法添加。
                                    final localImages = await MyDatabase
                                        .instance.wordImagesDao
                                        .getImagesByWordId(args.wordId);
                                    if (localImages.length >=
                                        _maxImagesPerWord) {
                                      ToastUtil.error(
                                          '每个单词最多只能有 $_maxImagesPerWord 张配图');
                                      return;
                                    }

                                    String? imgBase64;
                                    if (imageExtra.startsWith('data:image')) {
                                      imgBase64 = imageExtra.split(',')[1];
                                    }
                                    if (imageExtra.startsWith('http')) {
                                      imgBase64 =
                                          await Util.networkImageToBase64(
                                              imageExtra);
                                    }

                                    if (imgBase64 != null) {
                                      final result = await Api.client
                                          .uploadWordImg(args.wordId, imgBase64,
                                              Global.getLoggedInUser()!.id);
                                      if (result.success) {
                                        ToastUtil.info('添加配图成功');
                                        try {
                                          final wordImageDto =
                                              result.data as WordImageDto;
                                          await MyDatabase
                                              .instance.wordImagesDao
                                              .insertEntity(WordImage(
                                            id: wordImageDto.id,
                                            imageFile: wordImageDto.imageFile,
                                            foot: wordImageDto.foot,
                                            hand: wordImageDto.hand,
                                            authorId:
                                                wordImageDto.authorId ?? "",
                                            ownerId: wordImageDto.ownerId ?? "",
                                            wordId: wordImageDto.wordId,
                                            createTime: wordImageDto.createTime,
                                            updateTime: wordImageDto.updateTime,
                                          ));
                                        } catch (e, s) {
                                          Global.logger.e('写入本地WordImages失败',
                                              error: e, stackTrace: s);
                                        }
                                        navigator.maybePop();
                                      } else {
                                        ToastUtil.error(result.msg ?? '添加配图失败');
                                      }
                                    } else {
                                      ToastUtil.error('获取图片信息失败');
                                    }
                                  } catch (e, s) {
                                    Global.logger.e('uploadWordImg2 调用异常',
                                        error: e, stackTrace: s);
                                    ToastUtil.error('添加配图失败，请稍后重试');
                                  }
                                },
                              ),
                            ],
                          ),
                        ],
                      )));
            });
          });
    } finally {
      _isAddPicDialogShowing = false;
    }
  }

  /// 进入页面即展示的配图配额提示：已达上限时以醒目样式提醒用户不要再浪费时间选图。
  Widget _buildCapacityHint() {
    final count = _imageCount;
    if (count == null) return const SizedBox.shrink();
    final isDark = context.read<DarkMode>().isDarkMode;
    final atLimit = count >= _maxImagesPerWord;
    final bg = atLimit
        ? (isDark ? const Color(0x33F59E0B) : const Color(0x12F59E0B))
        : (isDark ? const Color(0x220F766E) : const Color(0x0D0F766E));
    final fg = atLimit
        ? (isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309))
        : (isDark ? const Color(0xFF5EEAD4) : const Color(0xFF0F766E));
    final text = atLimit
        ? '该单词已有 $count 张配图（上限 $_maxImagesPerWord 张），无法再添加；如需更换请先在单词页删除现有配图'
        : '该单词已有 $count/$_maxImagesPerWord 张配图，长按搜索结果图即可添加';
    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Icon(atLimit ? Icons.info_rounded : Icons.image_outlined,
              size: 15, color: fg),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text,
                style: TextStyle(fontSize: 12, color: fg, height: 1.35)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppTheme.createGradientAppBar(
          title: '添加单词配图',
        ),
        body: Column(children: <Widget>[
          _buildCapacityHint(),
          Expanded(
              child: InAppWebView(
            key: webViewKey,
            initialUrlRequest: URLRequest(
                url: WebUri(
                    "https://cn.bing.com/images/search?q=${args.spell}&go=%E6%90%9C%E7%B4%A2&qs=ds&form=QBIR&first=2&tsc=ImageHoverTitle")),
            initialUserScripts: UnmodifiableListView([
              UserScript(
                source: _longPressImageHandlerJs,
                injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
                forMainFrameOnly: true,
              ),
            ]),
            initialSettings: settings,
            onWebViewCreated: (InAppWebViewController controller) {
              webViewController = controller;
              controller.addJavaScriptHandler(
                  handlerName: 'nnbdcLongPressImage',
                  callback: (args) {
                    if (!mounted || args.isEmpty) return;
                    final url = args[0] as String?;
                    if (url == null || url.isEmpty) return;
                    longPressImageUrl = url;
                    hitTestResult = null;
                    showAddPicDlg(context);
                  });
            },
            onLoadStop: (controller, url) async {
              if (PlatformUtils.isIOS) {
                await controller.evaluateJavascript(
                    source: _disableSystemContextMenuJs);
              }
            },
            onLongPressHitTestResult: (controller, hitTestResult) {
              if (!mounted) return;
              this.hitTestResult = hitTestResult;
              Global.logger.d(hitTestResult.toString());
              if (hitTestResult.type ==
                      InAppWebViewHitTestResultType.SRC_IMAGE_ANCHOR_TYPE ||
                  hitTestResult.type ==
                      InAppWebViewHitTestResultType.IMAGE_TYPE) {
                showAddPicDlg(context);
              }
            },
          )),
        ]));
  }
}
