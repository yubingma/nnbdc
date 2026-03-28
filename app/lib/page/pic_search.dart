import 'dart:async';
import 'dart:collection';
import 'package:nnbdc/global.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
// import 'package:http/http.dart' as http;
// import 'package:path_provider/path_provider.dart';
// import 'dart:io';
import 'package:get/get.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/dto.dart';
// import 'package:nnbdc/config.dart';
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
  InAppWebViewSettings settings = InAppWebViewSettings(
    isInspectable: kDebugMode,
    // 禁用系统长按菜单，避免 iOS 弹出默认菜单遮挡功能
    disableContextMenu: true,
    // iOS 链接长按菜单也一并关闭（需 JS，默认开启）
    disableLongPressContextMenuOnLinks: true,
  );

  // iOS 下通过 JS 禁用系统长按菜单（不影响我们捕获长按的 hitTest）
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

  // 通过 JS 在按住一段时间后立即回调（无需松手）
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
    args = Get.arguments;
    init();

    // 操作提示
    Future.delayed(Duration.zero, () {
      if (mounted) {
        const snackBar = SnackBar(
          content: Text("请长按目标图片，将其加为单词配图"),
          duration: Duration(seconds: 3),
        );
        ScaffoldMessenger.of(context).showSnackBar(snackBar);
      }
    });

    // 通过 onLongPressHitTestResult 处理长按，不依赖系统菜单
  }

  /// 在底部显示对话框
  Future<void> showAddPicDlg(BuildContext context) async {
    if (_isAddPicDialogShowing) return;
    _isAddPicDialogShowing = true;

    final imageExtra = hitTestResult?.extra ?? longPressImageUrl;
    if (imageExtra == null || imageExtra.isEmpty) {
      _isAddPicDialogShowing = false;
      return;
    }

    try {
      await showGeneralDialog(
          context: context,
          barrierDismissible: true,
          barrierLabel: '',
          transitionDuration: const Duration(milliseconds: 100),
          transitionBuilder: (context, animation, secondaryAnimation, child) {
            return FractionalTranslation(
                translation: Offset(0, 1 - animation.value), // 从底部出现
                child: child);
          },
          pageBuilder: (context, animation, secondaryAnimation) {
            return StatefulBuilder(builder: (context, setState) {
              return Align(
                  alignment: const Alignment(0, 1),
                  child: Container(
                      width: MediaQuery.of(context).size.width,
                      height: 70,
                      margin: MediaQuery.of(context).viewInsets,
                      // 当软键盘弹出时，对话框自动上移
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                      color: context.read<DarkMode>().isDarkMode ? const Color(0xff333333) : Colors.white,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  foregroundColor: Colors.white, backgroundColor: Colors.green, // foreground
                                ),
                                child: const Text('取消'),
                                onPressed: () {
                                  Navigator.pop(context, false);
                                },
                              ),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  foregroundColor: Colors.white, backgroundColor: Colors.green, // foreground
                                ),
                                child: const Text('加为单词配图'),
                                onPressed: () async {
                                  Navigator.pop(context, false);
                                  // Capture navigator before async gaps to avoid using BuildContext across awaits
                                  final navigator = Navigator.of(context);

                                  try {
                                    String? imgBase64;
                                    if (imageExtra.startsWith('data:image')) {
                                      imgBase64 = imageExtra.split(',')[1];
                                    }
                                    if (imageExtra.startsWith('http')) {
                                      imgBase64 = await Util.networkImageToBase64(imageExtra);
                                    }

                                    if (imgBase64 != null) {
                                      // 再次检查本地图片数量，防止在pic_search页面连续添加超出限制
                                      final localImages = await MyDatabase.instance.wordImagesDao.getImagesByWordId(args.wordId);
                                      if (localImages.length >= 2) {
                                        ToastUtil.error('每个单词最多只能有 2 张配图');
                                        return;
                                      }

                                      final result = await Api.client.uploadWordImg(args.wordId, imgBase64, Global.getLoggedInUser()!.id);
                                      if (result.success) {
                                        ToastUtil.info('添加配图成功');
                                        // 写入本地 WordImages 表
                                        try {
                                          final wordImageDto = result.data as WordImageDto;
                                          await MyDatabase.instance.wordImagesDao.insertEntity(WordImage(
                                            id: wordImageDto.id,
                                            imageFile: wordImageDto.imageFile,
                                            foot: wordImageDto.foot,
                                            hand: wordImageDto.hand,
                                            authorId: wordImageDto.authorId ?? "",
                                            wordId: wordImageDto.wordId,
                                            createTime: wordImageDto.createTime,
                                            updateTime: wordImageDto.updateTime,
                                          ));
                                        } catch (e, s) {
                                          Global.logger.e('写入本地WordImages失败', error: e, stackTrace: s);
                                        }
                                        // Use captured navigator; no BuildContext after awaits
                                        navigator.maybePop();
                                      } else {
                                        ToastUtil.error(result.msg ?? '添加配图失败');
                                      }
                                    } else {
                                      ToastUtil.error('获取图片信息失败');
                                    }
                                  } catch (e, s) {
                                    Global.logger.e('uploadWordImg2 调用异常', error: e, stackTrace: s);
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

  // 预取逻辑已改为写入本地DB，不再需要网络预取

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppTheme.createGradientAppBar(
          title: '添加单词配图',
        ),
        body: Column(children: <Widget>[
          Expanded(
              child: InAppWebView(
            key: webViewKey,
            initialUrlRequest: URLRequest(
                url: WebUri("https://cn.bing.com/images/search?q=${args.spell}&go=%E6%90%9C%E7%B4%A2&qs=ds&form=QBIR&first=2&tsc=ImageHoverTitle")),
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
                await controller.evaluateJavascript(source: _disableSystemContextMenuJs);
              }
            },
            onLongPressHitTestResult: (controller, hitTestResult) {
              if (!mounted) return;
              this.hitTestResult = hitTestResult;
              Global.logger.d(hitTestResult.toString());
              if (hitTestResult.type == InAppWebViewHitTestResultType.SRC_IMAGE_ANCHOR_TYPE ||
                  hitTestResult.type == InAppWebViewHitTestResultType.IMAGE_TYPE) {
                showAddPicDlg(context);
              }
            },
          )),
        ]));
  }
}
