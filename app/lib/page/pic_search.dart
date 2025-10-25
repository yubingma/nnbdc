import 'dart:async';
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
  final GlobalKey webViewKey = GlobalKey();
  InAppWebViewController? webViewController;
  InAppWebViewSettings settings = InAppWebViewSettings(isInspectable: kDebugMode);
  late ContextMenu contextMenu;

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

    contextMenu = ContextMenu(
        menuItems: [
          ContextMenuItem(
              id: 1,
              title: "Special",
              action: () async {
                const snackBar = SnackBar(
                  content: Text("Special clicked!"),
                  duration: Duration(seconds: 1),
                );
                ScaffoldMessenger.of(context).showSnackBar(snackBar);
              })
        ],
        onCreateContextMenu: (hitTestResult) async {
          this.hitTestResult = hitTestResult;
          Global.logger.d(this.hitTestResult.toString());
          if (this.hitTestResult!.type == InAppWebViewHitTestResultType.SRC_IMAGE_ANCHOR_TYPE ||
              this.hitTestResult!.type == InAppWebViewHitTestResultType.IMAGE_TYPE) {
            showAddPicDlg(context);
          }
        },
        onContextMenuActionItemClicked: (menuItem) {
          final snackBar = SnackBar(
            content: Text("Menu item with ID ${menuItem.id} and title '${menuItem.title}' clicked!"),
            duration: const Duration(seconds: 1),
          );
          ScaffoldMessenger.of(context).showSnackBar(snackBar);
        });
  }

  /// 在底部显示对话框
  Future<void> showAddPicDlg(BuildContext context) async {
    showGeneralDialog(
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
                                  if (hitTestResult!.extra!.startsWith('data:image')) {
                                    imgBase64 = hitTestResult!.extra!.split(',')[1];
                                  }
                                  if (hitTestResult!.extra!.startsWith('http')) {
                                    imgBase64 = await Util.networkImageToBase64(hitTestResult!.extra!);
                                  }

                                  if (imgBase64 != null) {
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
                                          authorId: wordImageDto.authorId,
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
            contextMenu: contextMenu,
            initialSettings: settings,
            onWebViewCreated: (InAppWebViewController controller) {
              webViewController = controller;
            },
          )),
        ]));
  }
}
