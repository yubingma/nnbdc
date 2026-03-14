import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:day_night_switcher/day_night_switcher.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift_db_viewer/drift_db_viewer.dart';
import 'package:email_validator/email_validator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart' hide MultipartFile, FormData;
import 'package:dio/dio.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/bo/user_bo.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/page/admin/health_check.dart';
import 'package:nnbdc/page/admin/sync_log_viewer.dart';
import 'package:nnbdc/page/feature_request_wall.dart';
import 'package:nnbdc/page/level_path_page.dart';
import 'package:nnbdc/page/subscription.dart';
import 'package:nnbdc/page/word_list/dict_words.dart';

import 'package:nnbdc/services/sync_log_service.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/socket_io.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/error_handler.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/subscription_util.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/user_helper.dart';
import 'package:nnbdc/util/utils.dart';
import 'package:nnbdc/widget/dict_download_dialog.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:ui' as ui;

import "package:percent_indicator/percent_indicator.dart";
import 'package:provider/provider.dart';

import '../global.dart';
import '../state.dart';
import '../theme/app_theme.dart';
import '../util/level_util.dart';
import '../constants.dart';
import '../config.dart';

class MePage extends StatefulWidget {
  const MePage({super.key});

  @override
  State<StatefulWidget> createState() => _MePageState();
}

class _MePageState extends State<MePage> {
  var isDarkMode = false;
  final email = TextEditingController();
  final password = TextEditingController();
  final password2 = TextEditingController();
  final nickname = TextEditingController();

  late int msgCount = 0;
  late int unreadMsgCount = 0;

  StudyProgress? studyProgress;

  /// 最近30天打卡状态
  List<String>? last30DaysDakaStatus;

  UserVo? loggedInUser;
  final bool _isSyncing = false;
  late Function(String event, List args) _socketEventListener;
  StreamSubscription<List<PurchaseDetails>>? _subscriptionStreamSubscription;

  /// 最近一次同步是否失败
  bool _isLastSyncFailed = false;

  /// 是否正在检查并下载词书（用于防止 loadData 循环触发）
  bool _isCheckingDicts = false;
  Future<Widget>? _learningDictsFuture;

  Future<void> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: Icon(Icons.camera_alt_rounded, color: AppTheme.primaryColor),
              title: const Text('拍照', style: TextStyle(fontFamily: 'NotoSansSC')),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: Icon(Icons.photo_library_rounded, color: AppTheme.primaryColor),
              title: const Text('从相册选择', style: TextStyle(fontFamily: 'NotoSansSC')),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source != null) {
      final XFile? pickedFile = await picker.pickImage(
        source: source,
      );

      if (pickedFile != null) {
        try {
          Uint8List bytes = await pickedFile.readAsBytes();
          
          // 如果文件较大或者为了节省带宽，手动进行二次压缩和缩放
          // 目标：300x300, 质量 70%, 强制 JPEG
          try {
            final ui.Codec codec = await ui.instantiateImageCodec(bytes);
            final ui.FrameInfo fi = await codec.getNextFrame();
            final ui.Image image = fi.image;
            
            // 计算等比例缩放后的尺寸
            double targetWidth = 300;
            double targetHeight = 300;
            double ratio = image.width / image.height;
            if (image.width > image.height) {
              targetHeight = targetWidth / ratio;
            } else {
              targetWidth = targetHeight * ratio;
            }

            final ui.PictureRecorder recorder = ui.PictureRecorder();
            final ui.Canvas canvas = ui.Canvas(recorder);
            final ui.Paint paint = ui.Paint()..filterQuality = ui.FilterQuality.high;
            
            canvas.drawImageRect(
              image,
              ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
              ui.Rect.fromLTWH(0, 0, targetWidth, targetHeight),
              paint,
            );
            
            final ui.Picture picture = recorder.endRecording();
            final ui.Image resizedImage = await picture.toImage(targetWidth.toInt(), targetHeight.toInt());
            final ByteData? byteData = await resizedImage.toByteData(format: ui.ImageByteFormat.png); 
            
            if (byteData != null) {
              bytes = byteData.buffer.asUint8List();
            }
          } catch (e) {
            Global.logger.w('手动压缩失败，使用原始文件: $e');
          }

          Global.logger.d('🖼️ 准备上传头像, 原始文件名: ${pickedFile.name}, 压缩后大小: ${(bytes.length / 1024).toStringAsFixed(2)} KB');
          final userId = loggedInUser?.id;

          if (userId != null) {
            if (bytes.length > 1024 * 1024) {
              ToastUtil.error('图片文件过大，请选择较小的图片');
              return;
            }
            ToastUtil.info('正在上传头像...');
            // 使用专用的 uploadImg 接口上传图片 (FormData 方式，永久解决 Retrofit 生成代码缺少文件名的问题)
            final formData = FormData.fromMap({
              'file': MultipartFile.fromBytes(bytes, filename: pickedFile.name),
              'userId': userId,
              'fileName': pickedFile.name,
            });
            final result = await Api.client.uploadImg(formData);
            
            if (result.success && result.data != null) {
              final newAvatarFilename = result.data!;
              // 目前后端存储的是相对路径或完整URL。如果是 filename，则拼接 CDN 路径
              // 这里我们直接更新用户信息的 avatar 字段
              final db = MyDatabase.instance;
              final user = await db.usersDao.getUserById(userId);
              if (user != null) {
                // 如果后端返回的是 filename，这里可以尝试补全 URL，
                // 但为了保持一致性（VO转化逻辑会处理或读取），我们根据当前已有的 avatar 格式处理
                String finalAvatar = newAvatarFilename;
                if (!newAvatarFilename.startsWith('http')) {
                  finalAvatar = Config.wordImageBaseUrl + newAvatarFilename;
                }

                final updatedUser = user.copyWith(wechatAvatar: drift.Value(finalAvatar));
                await db.usersDao.saveUser(updatedUser, true);
                
                // 刷新本地缓存并更新 UI
                final updatedUserInfo = await Global.refreshLoggedInUser();
                setState(() {
                  loggedInUser = updatedUserInfo;
                });
                
                ToastUtil.success('头像更新成功');
                // 触发同步
                ThrottledDbSyncService().requestSync();
              }
            } else {
              ToastUtil.error('头像上传失败: ${result.msg}');
            }
          }
        } catch (e, stackTrace) {
          ErrorHandler.handleError(e, stackTrace, logPrefix: '上传头像失败');
          ToastUtil.error('上传过程中发生异常');
        }
      }
    }
  }

  @override
  void initState() {
    super.initState();

    // 连接socket服务器
    SocketIoClient.instance.connect();

    // 保存监听器引用以便在dispose中移除
    _socketEventListener = (event, args) {
      if (event == 'persistentMsgCount' && mounted) {
        int newUnread = args[0];
        int newMsg = args[1];
        if (newUnread != unreadMsgCount || newMsg != msgCount) {
          unreadMsgCount = newUnread;
          msgCount = newMsg;
          setState(() {});
        }
      }
    };

    SocketIoClient.instance.registerSocketEventListeners(_socketEventListener);

    // 监听订阅更新事件，以便及时刷新UI
    _subscriptionStreamSubscription = SubscriptionUtil.purchaseUpdatedStream.listen((purchases) {
      if (mounted) {
        setState(() {
          // 订阅状态已更新，UI会重新构建并获取最新的订阅状态
        });
      }
    });

    // 异步执行loadData，避免阻塞UI
    WidgetsBinding.instance.addPostFrameCallback((_) {
      loadData();
    });
  }

  @override
  void dispose() {
    // 移除SocketIoClient事件监听器
    SocketIoClient.instance.removeSocketEventListener(_socketEventListener);

    // 断开socket连接
    SocketIoClient.instance.disconnect();

    // 取消订阅更新监听
    _subscriptionStreamSubscription?.cancel();

    super.dispose();
  }

  Future<void> loadData() async {
    // 禁用loading提示
    Api.setLoadingDisabled(true);

    try {
      final isDarkModeVal = await MyDatabase.instance.localParamsDao.getIsDarkMode();
      final isLastSyncFailedVal = await SyncLogService().isLastSyncFailed();

      UserVo? loggedInUserVal;
      List<String>? last30DaysDakaStatusVal;
      int msgCountVal = 0;
      int unreadMsgCountVal = 0;
      StudyProgress? studyProgressVal;

      if (Global.isGuest) {
        final user = Global.getLoggedInUser();
        loggedInUserVal = user != null ? UserVo.fromUser(user) : null;
      } else {
        var result0 = await UserBo().getLoggedInUser();
        if (result0.success) {
          loggedInUserVal = result0.data;
        } else {
          ToastUtil.error(result0.msg!);
          return;
        }

        // 检查并强制执行会员限制
        await SubscriptionUtil.checkAndEnforceMemberLimits();
        if (loggedInUserVal?.id != null) {
          _syncAndDownloadDicts(loggedInUserVal!.id!);
        }
      }

      if (Global.isGuest) {
        if (loggedInUserVal?.id != null) {
          _checkAndDownloadDicts(loggedInUserVal!.id!);
        }
      }

      final db = MyDatabase.instance;
      User? user = await db.usersDao.getUserById(loggedInUserVal!.id!);
      if (user != null) {
        var learningDicts = await MyDatabase.instance.learningDictsDao.getLearningDictsOfUser(user.id);
        var totalLearningWords = await (db.select(db.learningWords)
              ..where((lw) => lw.userId.equals(user.id))
              ..where((lw) => lw.stability.isSmallerThanValue(Constants.graduationStability)))
            .get();
        var globalLearningWordsCount = totalLearningWords.length;

        var dictWordIds = await (db.selectOnly(db.dictWords)
              ..addColumns([db.dictWords.wordId])
              ..where(db.dictWords.dictId.isIn(learningDicts.map((d) => d.dictId).toList())))
            .get();
        var uniqueWordIdsInDicts = dictWordIds.map((row) => row.read(db.dictWords.wordId)!).toSet();
        var rawWordCount = uniqueWordIdsInDicts.length;

        var learningWordIds = totalLearningWords.map((w) => w.wordId).toSet();
        var learningWordsInSelectedDictsCount = learningWordIds.intersection(uniqueWordIdsInDicts).length;

        var allMasteredWordIdSet = await db.masteredWordsDao.getMasteredWordIdSet(user.id);
        var globalMasteredWordsCount = allMasteredWordIdSet.length;

        var masteredWordIdsInSelectedDicts = allMasteredWordIdSet.intersection(uniqueWordIdsInDicts);
        var masteredWordsInSelectedDictsCount = masteredWordIdsInSelectedDicts.length;

        var allDictsFinished = (learningWordsInSelectedDictsCount + masteredWordsInSelectedDictsCount) >= rawWordCount;
        LevelVo levelVo = LevelUtil.getLevelVoByWordCount(globalMasteredWordsCount);

        studyProgressVal = StudyProgress(
          user.learnedDays,
          user.dakaDayCount,
          user.dakaRatio ?? 0.0,
          UserHelper.calculateTotalScore(user.gameScore, user.dakaScore),
          -1.0,
          rawWordCount,
          user.cowDung,
          levelVo,
          globalMasteredWordsCount,
          globalLearningWordsCount,
          masteredWordsInSelectedDictsCount,
          learningWordsInSelectedDictsCount,
          user.wordsPerDay,
          user.continuousDakaDayCount,
          user.throwDiceChance,
          allDictsFinished,
          UserHelper.isTodayLearningFinishedFromUser(user),
          learningDicts,
          totalLearningSeconds: user.totalLearningSeconds ?? 0,
          todayLearningSeconds: user.todayLearningSeconds ?? 0,
        );

        // 获取个人排名
        if (!Global.isGuest) {
          var result4 = await Api.client.getUserRank(loggedInUserVal.id!);
          if (result4.success) {
            studyProgressVal.userOrder = result4.data;
          }
        }
      }

      var result2 = await UserBo().getDayStatuses(30);
      if (result2.success) {
        last30DaysDakaStatusVal = result2.data!;
      } else {
        last30DaysDakaStatusVal = List.filled(30, UserDayStatus.notLogin.json);
      }

      if (!Global.isGuest) {
        var result3 = await Api.client.getMsgCounts(loggedInUserVal.id!);
        if (result3.success) {
          msgCountVal = result3.data!.first;
          unreadMsgCountVal = result3.data!.second;
        }
      }

      if (mounted) {
        setState(() {
          isDarkMode = isDarkModeVal;
          _isLastSyncFailed = isLastSyncFailedVal;
          loggedInUser = loggedInUserVal;
          if (loggedInUser != null) {
            email.text = loggedInUser!.email ?? (Global.isGuest ? '未登录' : '');
            nickname.text = loggedInUser!.displayNickName ?? (Global.isGuest ? '游客' : '');
          }
          studyProgress = studyProgressVal;
          last30DaysDakaStatus = last30DaysDakaStatusVal;
          msgCount = msgCountVal;
          unreadMsgCount = unreadMsgCountVal;
          
          // 更新 Future 以触发 FutureBuilder 重新加载
          _learningDictsFuture = renderLearningDicts();
        });
      }
    } catch (e, stackTrace) {
      if (ErrorHandler.isNetworkError(e)) {
        ErrorHandler.handleNetworkError(e, stackTrace, api: 'loadData', showToast: true);
      } else {
        ErrorHandler.handleError(e, stackTrace, userMessage: '加载数据失败，请刷新重试', logPrefix: '加载数据失败', showToast: true);
      }
    } finally {
      Api.setLoadingDisabled(false);
    }
  }

  // 辅助方法，同步显示对话框
  Future<void> _showDictDownloadDialog(List<DictVo> dicts) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => DictDownloadDialog(
        dicts: dicts,
        onComplete: () {
          Navigator.of(dialogContext).pop();
          // 词书下载完成后，刷新页面数据以更新学习进度显示
          loadData();
        },
      ),
    );
  }

  /// 同步数据库并下载词书
  /// 同步完成后自动检查并下载本地缺失的词书，显示下载进度对话框
  Future<void> _syncAndDownloadDicts(String userId) async {
    if (_isCheckingDicts) {
      Global.logger.d("正在检查词书中，跳过重复触发");
      return;
    }
    
    _isCheckingDicts = true;
    try {
      // 等待同步完成
      await ThrottledDbSyncService().requestSyncAndWait(immediate: true);

      // 同步完成后，检查并下载词书
      await _checkAndDownloadDicts(userId);
    } catch (e) {
      Global.logger.e("同步或下载词书失败: $e");
      // 同步失败不影响页面显示，静默处理
    } finally {
      _isCheckingDicts = false;
    }
  }

  /// 检查并下载本地缺失的词书
  /// 先检查通用词典，再检查用户选择的词书
  Future<void> _checkAndDownloadDicts(String userId) async {
    if (!mounted) return;

    try {
      // 先检查并下载通用词典
      var db = MyDatabase.instance;
      bool hasWords = await db.dictWordsDao.hasDictWords(Global.commonDictId);
      if (!hasWords) {
        // 通用词典中没有单词，需要下载
        Global.logger.i("通用词典存在但没有单词，需要下载");
        if (mounted) {
          await _showDictDownloadDialog([
            DictVo(
              id: Global.commonDictId,
              name: '通用词典',
              shortName: '通用词典',
              owner: null,
              isShared: true,
              isReady: true,
              visible: true,
              editable: false,
              dictWords: null,
              wordCount: 0,
              createTime: AppClock.now(),
            )
          ]);
        }
      } else {
        Global.logger.i("通用词典已存在且包含单词，无需下载");
      }

      // 再下载用户选择的词书
      // 注意：必须重新查询learningDicts，因为上面的同步可能已经从服务器获取了用户的词书数据
      List<LearningDict> learningDicts = await MyDatabase.instance.learningDictsDao.getLearningDictsOfUser(userId);
      List<DictVo> dictsToDownload = [];

      // 收集需要下载的词书
      for (var learningDict in learningDicts) {
        var db = MyDatabase.instance;
        Dict? existing = await db.dictsDao.findById(learningDict.dictId);

        // 检查词书是否存在，或存在但没有单词
        if (existing == null) {
          // 词书不存在，需要下载
          Global.logger.i("词书不存在，需要下载: ${learningDict.dictId}");

          // 获取词书名称，如果获取不到则使用ID
          String dictName = '词书 ${learningDict.dictId}';
          try {
            // 这里只是获取名称：使用轻量接口，避免下载完整词书资源
            final result = await Api.client.getDictInfo(learningDict.dictId);
            if (result.success && result.data?.name != null) {
              dictName = result.data!.name;
            }
          } catch (e) {
            Global.logger.e("获取词书名称失败: $e");
          }

          // 将dictName处理为无后缀的短名称
          String shortName = getShortName(dictName);

          dictsToDownload.add(DictVo(
            id: learningDict.dictId,
            name: dictName,
            shortName: shortName,
            owner: null,
            isShared: true,
            isReady: true,
            visible: true,
            editable: dictName == '生词本', // 这里初步判断，如果是生词本则 editable
            dictWords: null,
            wordCount: 0,
            createTime: AppClock.now(),
          ));
        } else {
          // 词书存在，但只有当owner是系统用户(系统词书)时才需要检查是否有单词
          if (existing.ownerId == Global.sysUserId) {
            bool hasWords = await db.dictWordsDao.hasDictWords(learningDict.dictId);
            if (!hasWords) {
              // 系统词书中没有单词，需要下载
              Global.logger.i("系统词书存在但没有单词，需要下载: ${learningDict.dictId}");

              // 将dictName处理为无后缀的短名称
              String shortName = getShortName(existing.name);

              dictsToDownload.add(DictVo(
                id: learningDict.dictId,
                name: existing.name,
                shortName: shortName,
                owner: null,
                isShared: true,
                isReady: true,
                visible: true,
                editable: existing.name == '生词本' || (existing.ownerId != Global.sysUserId),
                dictWords: null,
                wordCount: 0,
                createTime: AppClock.now(),
              ));
            } else {
              Global.logger.i("系统词书已存在且包含单词，无需下载, 词书ID: ${learningDict.dictId}");
            }
          } else {
            Global.logger.i("非系统词书已存在，无需检查单词数量, 词书ID: ${learningDict.dictId}, 名称: ${existing.name}");
          }
        }
      }

      // 如果有需要下载的词书，显示下载对话框
      if (dictsToDownload.isNotEmpty && mounted) {
        await _showDictDownloadDialog(dictsToDownload);
      }
    } catch (e) {
      Global.logger.e("下载用户词书失败: $e");
      if (mounted) {
        ToastUtil.error("部分词书下载失败，请重试");
      }
    }
  }

  /// 解析形如：10天 / 360秒 / 15分钟 的时长字符串，返回毫秒；解析失败返回 null
  int? _parseDurationMillis(String duration) {
    final s = duration.trim();
    if (s.isEmpty) return null;
    final reg = RegExp(r'^(\d+)\s*(毫秒|ms|秒|s|分钟|分|m|小时|时|h|天|日|d)$', caseSensitive: false);
    final m = reg.firstMatch(s);
    if (m == null) return null;
    final value = int.tryParse(m.group(1)!);
    if (value == null) return null;
    final unit = (m.group(2) ?? '').toLowerCase();
    switch (unit) {
      case '毫秒':
      case 'ms':
        return value;
      case '秒':
      case 's':
        return value * 1000;
      case '分钟':
      case '分':
      case 'm':
        return value * 60 * 1000;
      case '小时':
      case '时':
      case 'h':
        return value * 60 * 60 * 1000;
      case '天':
      case '日':
      case 'd':
        return value * 24 * 60 * 60 * 1000;
      default:
        return null;
    }
  }

  Widget renderStudyProgress() {
    final isDarkModeEnabled = context.watch<DarkMode>().isDarkMode;
    final textColor = isDarkModeEnabled ? Colors.white : const Color(0xFF1E293B);
    final subtitleColor = isDarkModeEnabled ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final accentColor = isDarkModeEnabled ? const Color(0xFF22D3EE) : const Color(0xFF0EA5E9);
    final cardColor = isDarkModeEnabled ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDarkModeEnabled ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.02);

    return Column(
      children: [
        // 学习成就卡片 (Achievement Card)
        Container(
          margin: EdgeInsets.symmetric(
            vertical: MediaQuery.of(context).size.width > 600 ? 16 : 12,
          ),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDarkModeEnabled ? 0.3 : 0.05),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
            border: Border.all(color: borderColor, width: 1.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. 头像和昵称行
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () {
                      if (loggedInUser != null) {
                        _pickAndUploadAvatar();
                      } else {
                        Get.toNamed('/login');
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: accentColor.withValues(alpha: 0.3), width: 2),
                      ),
                      child: CircleAvatar(
                        radius: MediaQuery.of(context).size.width > 600 ? 32 : 28,
                        backgroundColor: isDarkModeEnabled ? Colors.white10 : const Color(0xFFF1F5F9),
                        backgroundImage: (loggedInUser?.wechatAvatar != null && loggedInUser!.wechatAvatar!.isNotEmpty)
                            ? CachedNetworkImageProvider(loggedInUser!.wechatAvatar!)
                            : null,
                        child: (loggedInUser?.wechatAvatar == null || loggedInUser!.wechatAvatar!.isEmpty)
                            ? Icon(Icons.person_rounded, color: subtitleColor, size: 30)
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // 昵称信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                Util.getNickNameOfUser(loggedInUser),
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.5,
                                  fontFamily: 'NotoSansSC',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (SubscriptionUtil.isPremium()) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.verified, color: Color(0xFF2196F3), size: 18),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          LevelUtil.getTitleQuote(studyProgress!.level.level ?? 1),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: subtitleColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 右上角浮动气泡/等级
                  GestureDetector(
                    onTap: () {
                      Get.to(() => LevelPathPage(currentLevel: studyProgress!.level.level ?? 1));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            studyProgress!.level.figure ?? '',
                            style: const TextStyle(fontSize: 14),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            studyProgress!.level.name!,
                            style: TextStyle(
                              color: accentColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              // 同步状态指示器
              if (_isSyncing) ...[
                Row(
                  children: [
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '同步中...',
                      style: TextStyle(color: subtitleColor, fontSize: 10),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],

              // 2. 会员状况/订阅入口 (移动至此处)
              Builder(builder: (context) {
                final isPremium = SubscriptionUtil.isPremium();
                String? premiumInfoText;
                if (isPremium) {
                  final type = SubscriptionUtil.getSubscriptionType();
                  final expire = SubscriptionUtil.getExpireDate();
                  final isOverride = loggedInUser?.premiumOverrideEnabled == true && (loggedInUser?.isPremiumIos != true);

                  if (type != null && type.isNotEmpty) {
                    final typeText = type == 'monthly' ? '月度会员' : '年度会员';
                    if (expire != null) {
                      premiumInfoText = '$typeText，有效期至：${expire.year}年${expire.month}月${expire.day}日';
                    } else {
                      premiumInfoText = typeText;
                    }
                  } else if (isOverride) {
                    final updateTime = loggedInUser?.premiumOverrideUpdateTime;
                    final duration = loggedInUser?.premiumOverrideDuration;
                    if (duration == null) {
                      premiumInfoText = '会员（永久）';
                    } else if (updateTime != null) {
                      final ms = _parseDurationMillis(duration);
                      if (ms != null && ms > 0) {
                        final expireTime = updateTime.add(Duration(milliseconds: ms));
                        premiumInfoText = '会员，有效期至：${expireTime.year}年${expireTime.month}月${expireTime.day}日';
                      } else {
                        premiumInfoText = '会员';
                      }
                    } else {
                      premiumInfoText = '会员';
                    }
                  } else {
                    premiumInfoText = '会员';
                  }
                }

                if (!isPremium && PlatformUtils.isIOS) {
                  return GestureDetector(
                    onTap: () {
                      Navigator.of(context).push(MaterialPageRoute(builder: (context) => const SubscriptionPage())).then((_) {
                        loadData();
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: isDarkModeEnabled ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
                        border: Border.all(color: Colors.amber.shade300.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.stars_rounded, color: Colors.amber.shade700, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                '解锁每日单词上限及更多特权',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.normal,
                                  color: isDarkModeEnabled ? Colors.amber.shade200 : Colors.amber.shade900,
                                  fontFamily: 'NotoSansSC',
                                ),
                              ),
                            ],
                          ),
                          Icon(Icons.chevron_right, color: Colors.amber.shade700, size: 16),
                        ],
                      ),
                    ),
                  );
                }

                if (isPremium && premiumInfoText != null) { 
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: Colors.blue.withValues(alpha: 0.05),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.verified_user_rounded, color: Colors.blue, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            premiumInfoText,
                            style: const TextStyle(
                              color: Colors.blue,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              fontFamily: 'NotoSansSC',
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return const SizedBox.shrink();
              }),
            ],
          ),
        ),

        // 2. 我的书桌 (My Desk) - 移动到此处
        Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor, width: 1.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDarkModeEnabled ? 0.2 : 0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 词书总进度 - 移动到此处
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "词书学习总进度",
                    style: TextStyle(
                      color: textColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      fontFamily: 'NotoSansSC',
                    ),
                  ),
                  Text(
                    '${((studyProgress!.rawWordCount > 0 ? studyProgress!.masteredWordsInSelectedDictsCount / studyProgress!.rawWordCount : 0.0) * 100).toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Roboto',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                height: 8,
                width: double.infinity,
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: isDarkModeEnabled ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final progress = studyProgress!.rawWordCount > 0
                        ? studyProgress!.masteredWordsInSelectedDictsCount / studyProgress!.rawWordCount
                        : 0.0;
                    final clampedProgress = progress > 1.0 ? 1.0 : progress;
                    return Container(
                      width: constraints.maxWidth * clampedProgress,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [accentColor, accentColor.withValues(alpha: 0.6)],
                        ),
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(
                            color: accentColor.withValues(alpha: 0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '我的书桌',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: textColor,
                      fontFamily: 'NotoSansSC',
                    ),
                  ),
                  GestureDetector(
                    key: const Key('me_choose_book_btn'),
                    onTap: () {
                      Get.toNamed("/select_book")!.then((value) {
                        loadData();
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: isDarkModeEnabled ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF8F9FA),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_circle_outline_rounded, color: subtitleColor, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            '选择词书',
                            style: TextStyle(
                              color: accentColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'NotoSansSC',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FutureBuilder<Widget>(
                future: _learningDictsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator(color: isDarkModeEnabled ? Colors.white24 : Colors.black12));
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        '加载失败',
                        style: TextStyle(color: subtitleColor),
                      ),
                    );
                  }
                  return snapshot.data ??
                      Container(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          '暂无词书',
                          style: TextStyle(color: subtitleColor, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      );
                },
              ),
            ],
          ),
        ),

        // 3. 夜间模式切换 (简化并移动到账户管理附近更合适，但此处先按逻辑保留一个纯净的控制项)
        Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor, width: 1.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDarkModeEnabled ? 0.2 : 0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    isDarkModeEnabled ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                    color: accentColor,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '夜间模式',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                      fontFamily: 'NotoSansSC',
                    ),
                  ),
                ],
              ),
              DayNightSwitcherIcon(
                isDarkModeEnabled: isDarkMode,
                onStateChanged: (isDarkModeEnabled) {
                  setState(() {
                    isDarkMode = isDarkModeEnabled;
                  });
                  MyDatabase.instance.localParamsDao.saveIsDarkMode(isDarkModeEnabled);
                  context.read<DarkMode>().setIsDarkMode(isDarkModeEnabled);
                },
              ),
            ],
          ),
        ),

        // 打卡统计卡片
        Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor, width: 1.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDarkModeEnabled ? 0.2 : 0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '打卡统计',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: textColor,
                  fontFamily: 'NotoSansSC',
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildProgressItem(
                    '打卡天数',
                    studyProgress!.dakaDayCount.toString(),
                  ),
                  _buildProgressItem(
                    '打卡率',
                    '${(studyProgress!.dakaRatio! * 100).toStringAsFixed(1)}%',
                  ),
                  _buildProgressItem(
                    '魔法泡泡',
                    studyProgress!.cowDung.toString(),
                  ),
                ],
              ),
            ],
          ),
        ),

        // 最近30天打卡情况卡片
        Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor, width: 1.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDarkModeEnabled ? 0.2 : 0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '最近30天学习情况',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: textColor,
                  fontFamily: 'NotoSansSC',
                ),
              ),
              const SizedBox(height: 20),
              renderLast30DaysDakaStatus(),
              const SizedBox(height: 16),
              // 图例
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  _buildLegendItem('已打卡', dakaStatus2Color(UserDayStatus.dakaed.json)),
                  const SizedBox(width: 16),
                  _buildLegendItem('未打卡', dakaStatus2Color(UserDayStatus.studied.json)),
                  const SizedBox(width: 16),
                  _buildLegendItem('未学习', dakaStatus2Color(UserDayStatus.notLogin.json)),
                ],
              ),
            ],
          ),
        ),

        // 学习成就卡片 (Stats & Ranking) - 从上方移至此处
        Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor, width: 1.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDarkModeEnabled ? 0.2 : 0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '成就统计',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: textColor,
                  fontFamily: 'NotoSansSC',
                ),
              ),
              const SizedBox(height: 20),
              // 数据小卡片行 (Data Cards)
              Row(
                children: [
                  // 卡片 1: 学习天数
                  _buildStatBox(
                    isDarkModeEnabled,
                    "学习天数",
                    studyProgress!.existDays.toString(),
                    Icons.event_available_rounded,
                    const Color(0xFF0EA5E9),
                  ),
                  const SizedBox(width: 12),
                  // 卡片 2: 已掌握
                  _buildStatBox(
                    isDarkModeEnabled,
                    "已掌握",
                    studyProgress!.masteredWordsCount.toString(),
                    Icons.task_alt_rounded,
                    const Color(0xFF10B981),
                  ),
                  const SizedBox(width: 12),
                  // 卡片 3: 学习时长
                  _buildStatBox(
                    isDarkModeEnabled,
                    "学习小时",
                    (studyProgress!.totalLearningSeconds / 3600.0).toStringAsFixed(1),
                    Icons.timer_outlined,
                    const Color(0xFF8B5CF6),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Vocabulary Ranking Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDarkModeEnabled ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: isDarkModeEnabled ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.02)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "词汇量排名",
                            style: TextStyle(
                              color: textColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text.rich(
                            TextSpan(
                              children: [
                                const TextSpan(text: "掌握: "),
                                TextSpan(
                                  text: "${studyProgress!.masteredWordsCount}",
                                  style: TextStyle(color: textColor, fontWeight: FontWeight.w900, fontFamily: 'Roboto'),
                                ),
                                const TextSpan(text: " 词"),
                                const TextSpan(text: "\n领先: "),
                                if (studyProgress!.userOrder! < 0)
                                  const TextSpan(text: '分析中...')
                                else ...[
                                  TextSpan(
                                    text: "${studyProgress!.userOrder!.toStringAsFixed(1)}%",
                                    style: TextStyle(color: accentColor, fontWeight: FontWeight.w900, fontFamily: 'Roboto'),
                                  ),
                                  const TextSpan(text: " 的用户"),
                                ],
                              ],
                            ),
                            style: TextStyle(
                              color: subtitleColor,
                              fontSize: 12,
                              height: 1.4,
                              fontFamily: 'NotoSansSC',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    _buildVisualRanking(studyProgress!.userOrder ?? -1, accentColor,
                        isDarkModeEnabled ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.02), accentColor),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const SizedBox(height: 16),
            ],
          ),
        ),

        // 账户管理卡片
        Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor, width: 1.0),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDarkModeEnabled ? 0.2 : 0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '账户管理',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: textColor,
                  fontFamily: 'NotoSansSC',
                ),
              ),
              const SizedBox(height: 16),
              _buildMenuTile(
                icon: Icons.person_outline_rounded,
                title: '个人信息',
                onTap: () => showUpdateUserInfoDlg(),
              ),
              _buildMenuTile(
                icon: Icons.chat_bubble_outline_rounded,
                title: '意见建议',
                trailing: msgCount > 0
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: unreadMsgCount == 0 ? Colors.grey : Colors.redAccent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          unreadMsgCount == 0 ? msgCount.toString() : unreadMsgCount.toString(),
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      )
                    : null,
                onTap: () {
                  Get.toNamed('/msg');
                },
              ),
              // 我的小天地 - 仅管理员可见
              if (loggedInUser?.isAdmin == true)
                _buildMenuTile(
                  icon: Icons.eco_outlined,
                  title: '我的小天地',
                  onTap: () {
                    Get.toNamed('/farm');
                  },
                ),
              // AI 助教 - 仅管理员可见
              if (loggedInUser?.isAdmin == true)
                _buildMenuTile(
                  icon: Icons.psychology_outlined,
                  title: 'AI 助教',
                  onTap: () {
                    Get.toNamed('/ai_activation');
                  },
                ),
              _buildMenuTile(
                icon: Icons.edit_note_rounded,
                title: '需求墙',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const FeatureRequestWallPage()),
                  );
                },
              ),
              _buildMenuTile(
                icon: Icons.logout_rounded,
                title: '切换账号',
                onTap: () => Get.toNamed('/login'),
              ),
              _buildMenuTile(
                icon: Icons.no_accounts_outlined,
                title: '注销账号',
                onTap: () => showUnRegisterDlg(),
                isDestructive: true,
              ),

              const SizedBox(height: 12),
              Text(
                '系统',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: subtitleColor,
                  fontFamily: 'NotoSansSC',
                ),
              ),
              const SizedBox(height: 8),
              _buildMenuTile(
                icon: Icons.health_and_safety_outlined,
                title: '健康检查',
                onTap: () => _navigateToDataDiagnostic(),
              ),
              _buildMenuTile(
                icon: Icons.cloud_sync_outlined,
                title: '云同步${_isLastSyncFailed ? "(失败)" : ""}',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SyncLogViewerPage(),
                    ),
                  ).then((_) {
                    // 返回时重新检查同步状态
                    _checkSyncStatus();
                  });
                },
              ),
              _buildMenuTile(
                icon: Icons.cleaning_services_outlined,
                title: '清空本地数据',
                onTap: () => _showWipeLocalDataDialog(),
                isDestructive: true,
              ),
              // 管理员功能入口
              if (loggedInUser?.isAdmin == true) ...[
                const Divider(),
                _buildMenuTile(
                  icon: Icons.admin_panel_settings_outlined,
                  title: '系统管理',
                  onTap: () => Get.toNamed('/admin'),
                ),
                _buildMenuTile(
                  icon: Icons.storage_rounded,
                  title: '数据库查看器',
                  onTap: () => _openDbViewPage(),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 32),
      ],
    );
  }

  // 图例项组件
  Widget _buildLegendItem(String label, Color color) {
    final isDarkModeEnabled = context.watch<DarkMode>().isDarkMode;
    final subtitleColor = isDarkModeEnabled ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: subtitleColor,
            fontWeight: FontWeight.bold,
            fontFamily: 'NotoSansSC',
          ),
        ),
      ],
    );
  }

  Future<void> showUpdateUserInfoDlg() async {
    final isDarkModeEnabled = Provider.of<DarkMode>(context, listen: false).isDarkMode;
    final backgroundColor = isDarkModeEnabled ? const Color(0xFF2D2D2D) : Colors.white;
    final textColor = isDarkModeEnabled ? Colors.white : Colors.black;
    final cardColor = isDarkModeEnabled ? const Color(0xFF3D3D3D) : const Color(0xFFF8F9FA);

    final String oldEmail = loggedInUser?.email ?? '';
    final codeController = TextEditingController();
    int cooldown = 0;
    Timer? timer;
    bool isSendingCode = false;

    bool? choice = await showDialog<bool>(
        barrierDismissible: false,
        context: context,
        builder: (BuildContext context) {
          return StatefulBuilder(builder: (context, setDialogState) {
            final emailChanged = email.text.isNotEmpty && email.text != oldEmail;
            return Dialog(
              backgroundColor: Colors.transparent,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.95,
                margin: const EdgeInsets.symmetric(horizontal: 0),
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 标题栏
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4A90E2),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(20),
                          topRight: Radius.circular(20),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.person_outline,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '修改个人信息',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 表单内容 - 添加可滚动支持
                    Flexible(
                      child: SingleChildScrollView(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Email 输入框与获取验证码按钮同行
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: _buildInputField(
                                      controller: email,
                                      label: '邮箱地址',
                                      icon: Icons.email_outlined,
                                      validator: (value) => EmailValidator.validate(value ?? '') ? null : "请输入有效的邮箱地址",
                                      isDarkMode: isDarkModeEnabled,
                                      cardColor: cardColor,
                                      textColor: textColor,
                                      onChanged: (value) {
                                        setDialogState(() {});
                                      },
                                      inputFormatters: [
                                        FilteringTextInputFormatter.deny(RegExp(r'[\s\u2006\u200B]')),
                                      ],
                                      keyboardType: TextInputType.visiblePassword,
                                    ),
                                  ),
                                  if (emailChanged) ...[
                                    const SizedBox(width: 8),
                                    SizedBox(
                                      height: 50,
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          padding: const EdgeInsets.symmetric(horizontal: 12),
                                        ),
                                        onPressed: (cooldown > 0 || isSendingCode)
                                            ? null
                                            : () async {
                                                final cleanedEmail = email.text.replaceAll(RegExp(r'[\s\u2006\u200B]'), '');
                                                final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
                                                if (!emailRegex.hasMatch(cleanedEmail)) {
                                                  ToastUtil.error('邮箱格式不正确，请检查');
                                                  return;
                                                }
                                                if (!EmailValidator.validate(cleanedEmail)) {
                                                  ToastUtil.error('请输入有效的邮箱地址');
                                                  return;
                                                }
                                                setDialogState(() {
                                                  isSendingCode = true;
                                                });
                                                var result = await Api.client.sendEmailCode(cleanedEmail, "BIND_EMAIL");
                                                if (result.success) {
                                                  ToastUtil.info("验证码已发送");
                                                  setDialogState(() {
                                                    cooldown = 60;
                                                    isSendingCode = false;
                                                  });
                                                  timer = Timer.periodic(const Duration(seconds: 1), (t) {
                                                    setDialogState(() {
                                                      if (cooldown > 0) {
                                                        cooldown--;
                                                      } else {
                                                        timer?.cancel();
                                                        timer = null;
                                                      }
                                                    });
                                                  });
                                                } else {
                                                  ToastUtil.error(result.msg!);
                                                  setDialogState(() {
                                                    isSendingCode = false;
                                                  });
                                                }
                                              },
                                        child: isSendingCode
                                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                                            : Text(cooldown > 0 ? '${cooldown}s' : '获取验证码'),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 12),

                              // 如果修改了邮箱，必须验证新邮箱。仅在用户点击过后（或者计时器启动后）才显示输入框更符合语境，
                              // 但如果希望在「发验证码按钮」存在时就允许输入，那么只要修改了邮箱就显示
                              if (emailChanged) ...[
                                _buildInputField(
                                  controller: codeController,
                                  label: '验证码',
                                  icon: Icons.security,
                                  isDarkMode: isDarkModeEnabled,
                                  cardColor: cardColor,
                                  textColor: textColor,
                                ),
                                const SizedBox(height: 12),
                              ],

                              // 昵称输入框
                              _buildInputField(
                                controller: nickname,
                                label: '昵称',
                                icon: Icons.person_outline,
                                isDarkMode: isDarkModeEnabled,
                                cardColor: cardColor,
                                textColor: textColor,
                              ),

                              const SizedBox(height: 20),

                              // 按钮区域
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildDialogButton(
                                      text: '取消',
                                      onPressed: () {
                                        timer?.cancel();
                                        Navigator.pop(context, false);
                                      },
                                      isPrimary: false,
                                      isDarkMode: isDarkModeEnabled,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildDialogButton(
                                      text: '保存',
                                      onPressed: () async {
                                        if (emailChanged && codeController.text.isEmpty) {
                                          ToastUtil.error("需要输入验证码验证新邮箱");
                                          return;
                                        }

                                        if (emailChanged) {
                                          Api.setLoadingDisabled(false);
                                          final cleanedEmail = email.text.replaceAll(RegExp(r'[\s\u2006\u200B]'), '');
                                          var result = await Api.client.verifyEmailCode(cleanedEmail, codeController.text, "BIND_EMAIL");
                                          Api.setLoadingDisabled(true);

                                          if (!context.mounted) return;
                                          if (!result.success) {
                                            ToastUtil.error(result.msg ?? "验证码错误");
                                            return;
                                          }
                                        }

                                        timer?.cancel();
                                        Navigator.pop(context, true);
                                      },
                                      isPrimary: true,
                                      isDarkMode: isDarkModeEnabled,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          });
        });

    if (choice ?? false) {
      final cleanedEmail = email.text.replaceAll(RegExp(r'[\s\u2006\u200B]'), '');
      // 密码被取消后，传入原来的密码 (这里用空字符串，后端/UserBo里处理空字符串就不修改密码)
      UserBo().updateUserInfo(cleanedEmail, nickname.text, '', '', Global.getLoggedInUser()!.id).then((value) async {
        if (value.success) {
          ToastUtil.info("修改成功");
          // 重新加载用户信息并刷新界面
          var result = await UserBo().getLoggedInUser();
          if (result.success && mounted) {
            setState(() {
              loggedInUser = result.data;
              // 界面会自动刷新，显示更新后的昵称
            });
          }
          // 因为修改了敏感字段，此处触发挥发型防抖同步
          ThrottledDbSyncService().requestSync(immediate: true);
        } else {
          ToastUtil.error(value.msg!);
        }
      });
    }
  }

  // 输入框组件
  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscureText = false,
    String? Function(String?)? validator,
    required bool isDarkMode,
    required Color cardColor,
    required Color textColor,
    void Function(String)? onChanged,
    List<TextInputFormatter>? inputFormatters,
    TextInputType? keyboardType,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDarkMode ? Colors.grey.withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        keyboardType: keyboardType,
        validator: validator,
        onChanged: onChanged,
        inputFormatters: inputFormatters,
        style: TextStyle(
          color: textColor,
          fontSize: 15,
          height: 1.2,
          fontFamily: 'NotoSansSC',
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
            fontSize: 13,
            fontWeight: FontWeight.w400,
            fontFamily: 'NotoSansSC',
          ),
          prefixIcon: Icon(
            icon,
            color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
            size: 18,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          filled: false,
        ),
      ),
    );
  }

  // 对话框按钮组件
  Widget _buildDialogButton({
    required String text,
    required VoidCallback onPressed,
    required bool isPrimary,
    required bool isDarkMode,
  }) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: isPrimary ? const Color(0xFF4A90E2) : (isDarkMode ? const Color(0xFF3D3D3D) : const Color(0xFFF0F0F0)),
        foregroundColor: isPrimary ? Colors.white : (isDarkMode ? Colors.white : Colors.black),
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: isPrimary
              ? BorderSide.none
              : BorderSide(
                  color: isDarkMode ? Colors.grey.withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.2),
                  width: 1,
                ),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 15,
          fontWeight: isPrimary ? FontWeight.w500 : FontWeight.w500,
          letterSpacing: 0.5,
          fontFamily: 'NotoSansSC',
        ),
      ),
    );
  }

  Future<void> showUnRegisterDlg() async {
    final isDarkModeEnabled = Provider.of<DarkMode>(context, listen: false).isDarkMode;
    final backgroundColor = isDarkModeEnabled ? const Color(0xFF2D2D2D) : Colors.white;
    final textColor = isDarkModeEnabled ? Colors.white : Colors.black;

    final TextEditingController confirmController = TextEditingController();

    bool? choice = await showDialog<bool>(
        barrierDismissible: false,
        context: context,
        builder: (BuildContext context) {
          return StatefulBuilder(
            builder: (context, setState) {
              return Dialog(
                backgroundColor: Colors.transparent,
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.95,
                  margin: const EdgeInsets.symmetric(horizontal: 0),
                  decoration: BoxDecoration(
                    color: backgroundColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 标题栏
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE74C3C),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(20),
                            topRight: Radius.circular(20),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.warning_amber_outlined,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              '注销账号',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w500,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // 内容区域
                      Flexible(
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              children: [
                                // 警告文本
                                Text(
                                  '账号注销后，无法恢复!',
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    height: 1.4,
                                    fontFamily: 'NotoSansSC',
                                  ),
                                  textAlign: TextAlign.center,
                                ),

                                const SizedBox(height: 16),
                                TextField(
                                  controller: confirmController,
                                  style: TextStyle(color: textColor, fontSize: 16),
                                  decoration: InputDecoration(
                                    hintText: "输入 okay 确认注销",
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  ),
                                ),
                                const SizedBox(height: 24),

                                // 按钮区域
                                Row(
                                  children: [
                                    Expanded(
                                      child: _buildDialogButton(
                                        text: '取消',
                                        onPressed: () => Navigator.pop(context, false),
                                        isPrimary: false,
                                        isDarkMode: isDarkModeEnabled,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: () {
                                          if (confirmController.text.trim().toLowerCase() != 'okay') {
                                            ToastUtil.error("请输入 'okay' 以确认注销");
                                            return;
                                          }
                                          Navigator.pop(context, true);
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFFE74C3C),
                                          foregroundColor: Colors.white,
                                          elevation: 0,
                                          padding: const EdgeInsets.symmetric(vertical: 16),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                        ),
                                        child: const Text(
                                          '注销',
                                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        });

    // 延迟释放 controller，确保对话框动画完成
    Future.delayed(const Duration(milliseconds: 300), () {
      confirmController.dispose();
    });

    if (choice ?? false) {
      final userId = Global.getLoggedInUser()?.id;
      if (userId == null) {
        ToastUtil.error("用户未登录");
        return;
      }
      UserBo().unRegister(userId).then((value) {
        if (value.success) {
          ToastUtil.info("账户已注销");
          Get.toNamed('/login');
        } else {
          ToastUtil.error(value.msg!);
        }
      });
    }
  }

  Color dakaStatus2Color(String dakaStatus) {
    if (dakaStatus == UserDayStatus.dakaed.json) {
      return const Color(0xFF10B981); // Emerald Green
    } else if (dakaStatus == UserDayStatus.studied.json) {
      return const Color(0xFFFACC15); // Amber/Yellow
    } else {
      return const Color(0xFF94A3B8).withValues(alpha: 0.3); // Slate Grey
    }
  }

  ///最近30天打卡情况
  Widget renderLast30DaysDakaStatus() {
    return LayoutBuilder(
      builder: (context, constraints) {
        const double boxMargin = 1.0;
        // 使用可用宽度而不是屏幕宽度，考虑卡片的内边距
        final availableWidth = constraints.maxWidth;
        final boxWidth = (availableWidth - 20 * boxMargin) / 10; // 10个盒子，每个盒子左右各有margin
        final boxHeight = boxWidth * 0.5; // 高度是宽度的一半

        var rows = <Widget>[]; // 每行对应10天，共3行
        var dayIndex = 0;
        for (int i = 0; i < 3; i++) {
          var dayBoxes = <Widget>[];
          for (int j = 0; j < 10; j++) {
            var box = Container(
              margin: const EdgeInsets.all(boxMargin),
              width: boxWidth,
              height: boxHeight,
              decoration: BoxDecoration(
                color: dakaStatus2Color(last30DaysDakaStatus![dayIndex]),
                borderRadius: BorderRadius.circular(2),
              ),
              child: dayIndex == 29
                  ? Center(
                      child: Text(
                      '今天',
                      style: const TextStyle(
                        fontSize: 8,
                        color: Colors.white,
                        fontWeight: FontWeight.w400,
                        height: 1.1,
                        fontFamily: 'NotoSansSC',
                      ),
                      textScaler: const TextScaler.linear(1.0),
                    ))
                  : dayIndex == 28
                      ? Center(
                          child: Text(
                          '昨天',
                          style: const TextStyle(
                            fontSize: 8,
                            color: Colors.white,
                            fontWeight: FontWeight.w400,
                            height: 1.1,
                            fontFamily: 'NotoSansSC',
                          ),
                          textScaler: const TextScaler.linear(1.0),
                        ))
                      : null,
            );
            dayBoxes.add(box);
            dayIndex++;
          }
          rows.add(Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: dayBoxes,
          ));
        }
        return Column(
          children: rows,
        );
      },
    );
  }

  ///学习中单词书
  Future<Widget> renderLearningDicts() async {
    var dicts = <Widget>[];
    for (LearningDict learningDict in studyProgress!.learningDicts) {
      var dictInfo = await MyDatabase.instance.dictsDao.findById(learningDict.dictId);
      if (dictInfo == null) continue;

      dicts.add(DictCard(
        key: ValueKey('me_learning_dict_${learningDict.dictId}'),
        learningDict: learningDict,
        dictInfo: dictInfo,
        onDictChanged: () => loadData(),
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: dicts,
    );
  }

  String getShortName(String name) {
    if (name.endsWith(".dict")) {
      return name.substring(0, name.lastIndexOf("."));
    } else {
      return name;
    }
  }

  // 进度项组件
  Widget _buildStatBox(bool isDarkMode, String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
        decoration: BoxDecoration(
          color: isDarkMode ? Colors.white.withValues(alpha: 0.02) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDarkMode ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.02),
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: color.withValues(alpha: 0.8)),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                color: isDarkMode ? Colors.white : const Color(0xFF1E293B),
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressItem(String title, String value) {
    final isDarkModeEnabled = context.watch<DarkMode>().isDarkMode;
    final textColor = isDarkModeEnabled ? Colors.white : const Color(0xFF1E293B);
    final subtitleColor = isDarkModeEnabled ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: textColor,
            fontFamily: 'Roboto',
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            color: subtitleColor,
            fontWeight: FontWeight.bold,
            fontFamily: 'NotoSansSC',
          ),
        ),
      ],
    );
  }

  // 打开数据库查看器
  void _openDbViewPage() {
    // 为查看器包裹一个局部主题，解决全局透明 AppBar 导致的图标白色不可见问题
    Navigator.of(context).push(MaterialPageRoute(
        builder: (context) => Theme(
              data: Theme.of(context).copyWith(
                appBarTheme: AppBarTheme(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                ),
              ),
              child: DriftDbViewer(MyDatabase.instance),
            )));
  }

  void _navigateToDataDiagnostic() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const HealthCheckPage(),
      ),
    );
  }

  // 菜单项组件
   Widget _buildMenuTile({
    required IconData icon,
    required String title,
    Widget? trailing,
    required VoidCallback onTap,
    bool isDestructive = false,
    Color? iconColor,
  }) {
    final isDarkModeEnabled = context.watch<DarkMode>().isDarkMode;
    final textColor = isDarkModeEnabled ? Colors.white : const Color(0xFF1E293B);
    final subtitleColor = isDarkModeEnabled ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    // 如果没有指定颜色，则使用一个更克制的次级文字颜色，避免“花花绿绿”
    final effectiveIconColor = iconColor ?? (isDestructive ? Colors.redAccent : subtitleColor);

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: effectiveIconColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: effectiveIconColor,
          size: 22, // 略微调大图标，提升精致感
        ),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isDestructive ? Colors.redAccent : textColor,
          fontWeight: FontWeight.w500, // 降低字重，避免过重
          fontSize: 15,
          fontFamily: 'NotoSansSC',
        ),
      ),
      trailing: trailing ??
          Icon(
            Icons.chevron_right_rounded,
            color: isDarkModeEnabled ? Colors.white24 : Colors.black26,
            size: 18,
          ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    );
  }

  /// 检查同步状态
  Future<void> _checkSyncStatus() async {
    final isFailed = await SyncLogService().isLastSyncFailed();
    if (mounted && _isLastSyncFailed != isFailed) {
      setState(() {
        _isLastSyncFailed = isFailed;
      });
    }
  }

  Future<void> _showWipeLocalDataDialog() async {
    final isDarkModeEnabled = context.read<DarkMode>().isDarkMode;
    bool? choice = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDarkModeEnabled ? const Color(0xFF2D2D2D) : Colors.white,
          title: const Text('确认重建数据库'),
          content: const Text('清除所有本地数据(服务端数据不受影响)吗？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('继续')),
          ],
        );
      },
    );

    if (choice == true) {
      await ErrorHandler.safeExecute(
        () async {
          await MyDatabase.instance.wipeAllTables();
          ToastUtil.info('已重建数据库');
          // 重建后跳转到登录页面
          Get.offAllNamed('/login');
        },
        operationName: '重建数据库',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkModeEnabled = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkModeEnabled ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: (studyProgress == null || last30DaysDakaStatus == null)
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(16, MediaQuery.of(context).padding.top + 16, 16, 0),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      renderStudyProgress(),
                    ]),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildVisualRanking(double percentile, Color markerColor, Color containerColor, Color textColor) {
    return SizedBox(
      width: 80,
      height: 60,
      child: Column(
        children: [
          Expanded(
            child: CustomPaint(
              size: const Size(double.infinity, double.infinity),
              painter: RankingPainter(
                percentile: percentile,
                markerColor: markerColor,
                curveColor: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 独立的词书卡片组件，有自己的状态管理
class DictCard extends StatefulWidget {
  final LearningDict learningDict;
  final Dict dictInfo;
  final VoidCallback onDictChanged;

  const DictCard({
    super.key,
    required this.learningDict,
    required this.dictInfo,
    required this.onDictChanged,
  });

  @override
  State<DictCard> createState() => _DictCardState();
}

class _DictCardState extends State<DictCard> {
  late LearningDict currentLearningDict;
  int? actualWordCount; // 用于存储生词本的实际单词数量
  int learnedCount = 0; // 学习中的单词数
  int masteredCount = 0; // 已掌握的单词数

  @override
  void initState() {
    super.initState();
    currentLearningDict = widget.learningDict;
    _loadActualWordCount();
    _loadLearnedAndMasteredCount();
  }

  @override
  void didUpdateWidget(DictCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.learningDict != widget.learningDict) {
      currentLearningDict = widget.learningDict;
      _loadActualWordCount();
      _loadLearnedAndMasteredCount();
    }
  }

  // 加载学习中和已掌握的单词数量
  Future<void> _loadLearnedAndMasteredCount() async {
    final db = MyDatabase.instance;
    final dictId = widget.learningDict.dictId;
    final userId = widget.learningDict.userId;

    // 获取该词书的所有单词ID
    final dictWords = await (db.select(db.dictWords)..where((dw) => dw.dictId.equals(dictId))).get();
    final wordIds = dictWords.map((dw) => dw.wordId).toSet();

    // 获取学习中的单词（stability < graduationStability）
    final learningWords = await (db.select(db.learningWords)
          ..where((lw) => lw.userId.equals(userId) & lw.stability.isSmallerThanValue(Constants.graduationStability)))
        .get();
    final learningWordIds = learningWords.map((w) => w.wordId).toSet();

    // 获取已掌握的单词
    final masteredWordIds = await db.masteredWordsDao.getMasteredWordIdSet(userId);

    // 计算该词书中学习和掌握的数量
    int learned = 0;
    int mastered = 0;
    for (var wordId in wordIds) {
      if (learningWordIds.contains(wordId)) {
        learned++;
      } else if (masteredWordIds.contains(wordId)) {
        mastered++;
      }
    }

    if (mounted) {
      setState(() {
        learnedCount = learned;
        masteredCount = mastered;
      });
    }
  }

  // 加载生词本的实际单词数量
  Future<void> _loadActualWordCount() async {
    if (widget.dictInfo.name == '生词本') {
      final count = await ErrorHandler.safeExecute<int>(
        () => MyDatabase.instance.dictWordsDao.getDictWordCount(widget.learningDict.dictId),
        operationName: '获取生词本单词数量',
        showToast: false, // 不显示错误提示，静默失败
      );

      if (mounted) {
        setState(() {
          actualWordCount = count ?? 0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalWords = widget.dictInfo.name == '生词本' ? (actualWordCount ?? 0) : widget.dictInfo.wordCount;
    final learnedWords = masteredCount;
    final progress = (totalWords > 0 ? learnedWords / totalWords : 0.0).clamp(0.0, 1.0);
    final progressPercent = (progress * 100).toInt();

    final isDarkMode = context.watch<DarkMode>().isDarkMode;

    final textColor = isDarkMode ? Colors.white : const Color(0xFF1E293B);
    final subtitleColor = isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
    final accentColor = isDarkMode ? const Color(0xFF22D3EE) : const Color(0xFF0EA5E9);
    final cardBgColor = isDarkMode ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDarkMode ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.08);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDarkMode ? 0.3 : 0.06),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 圆形进度指示器
              Stack(
                alignment: Alignment.center,
                children: [
                  CircularPercentIndicator(
                    radius: 26.0,
                    lineWidth: 5.0,
                    percent: progress,
                    backgroundColor: accentColor.withValues(alpha: 0.1),
                    linearGradient: LinearGradient(
                      colors: [accentColor, accentColor.withValues(alpha: 0.6)],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                    circularStrokeCap: CircularStrokeCap.round,
                    animation: true,
                    animationDuration: 1000,
                  ),
                  Text(
                    '$progressPercent%',
                    style: TextStyle(
                      fontSize: 10,
                      color: accentColor,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Roboto',
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              // 词书信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.dictInfo.name.replaceAll('.dict', ''),
                      style: TextStyle(
                        color: textColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                        fontFamily: 'NotoSansSC',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.dictInfo.name == '生词本'
                          ? '$masteredCount / ${actualWordCount ?? 0} 词'
                          : '$masteredCount / ${widget.dictInfo.wordCount} 词',
                      style: TextStyle(
                        color: subtitleColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w500, // 稍微加粗一点
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // 操作按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: _buildDictCheckbox(
                  label: '优先取词',
                  value: currentLearningDict.isPrivileged,
                  onChanged: (bool? value) async {
                    if (value != null) {
                      try {
                        final newPrivilegedStatus = await MyDatabase.instance.learningDictsDao.togglePrivileged(currentLearningDict.userId, currentLearningDict.dictId, true);

                        if (mounted) {
                          setState(() {
                            currentLearningDict = LearningDict(
                              userId: currentLearningDict.userId,
                              dictId: currentLearningDict.dictId,
                              isPrivileged: newPrivilegedStatus,
                              fetchMastered: currentLearningDict.fetchMastered,
                              createTime: currentLearningDict.createTime,
                              updateTime: currentLearningDict.updateTime,
                            );
                          });
                        }

                        // 触发同步
                        ThrottledDbSyncService().requestSync();
                      } catch (error) {
                        Global.logger.d('切换优先取词状态失败: $error');
                        ToastUtil.error('操作失败，请重试');
                      }
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDictActionButton(
                  icon: Icons.list_alt_rounded,
                  label: '单词列表',
                  isActive: true,
                  color: const Color(0xFF3B82F6),
                  onTap: () async {
                    try {
                      await toDictWordsListPage(currentLearningDict.dictId, false);
                      widget.onDictChanged();
                    } catch (e) {
                      ToastUtil.error("无法打开词书");
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDictActionButton(
                  icon: Icons.pause_circle_outline_rounded,
                  label: '停止学习',
                  isActive: true,
                  isDestructive: false,
                  color: const Color(0xFFF59E0B),
                  onTap: () => _handleDictDataAction(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 统一处理词书数据操作（清空单词或删除词书）
  Future<void> _handleDictDataAction() async {
    final db = MyDatabase.instance;
    final user = Global.getLoggedInUser()!;
    final dictName = widget.dictInfo.name.replaceAll('.dict', '');

    // 1. 获取该词书中的所有单词 ID
    final dictWords = await (db.select(db.dictWords)..where((dw) => dw.dictId.equals(currentLearningDict.dictId))).get();
    final wordIdsInDict = dictWords.map((dw) => dw.wordId).toSet();

    // 2. 查询用户所有学习中的单词（stability < graduationStability）
    final learningWords = await (db.select(db.learningWords)
          ..where((lw) => lw.userId.equals(user.id) & lw.stability.isSmallerThanValue(Constants.graduationStability)))
        .get();

    if (!mounted) return;

    // 3. 获取用户书桌上的所有其他词书 ID
    final otherLearningDicts =
        await (db.select(db.learningDicts)..where((ld) => ld.userId.equals(user.id) & ld.dictId.isNotValue(currentLearningDict.dictId))).get();
    final otherDictIds = otherLearningDicts.map((ld) => ld.dictId).toSet();

    if (!mounted) return;

    // 4. 找出仅在当前词书中的学习单词
    final learningWordsOnlyInThisDict = <LearningWord>[];
    for (final lw in learningWords) {
      if (!wordIdsInDict.contains(lw.wordId)) continue;

      final otherDicts = await (db.select(db.dictWords)
            ..where((dw) => dw.wordId.equals(lw.wordId) & dw.dictId.isIn(otherDictIds.isEmpty ? [''] : otherDictIds.toList())))
          .get();

      if (!mounted) return;
      if (otherDicts.isEmpty) {
        learningWordsOnlyInThisDict.add(lw);
      }
    }

    bool deleteLearningWords = false;
    bool shouldProceed = false;

    // 5. 询问用户
    if (learningWordsOnlyInThisDict.isNotEmpty) {
      final confirmResult = await showDialog<bool>(
        context: context,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 顶部警告图标
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.warning_amber_rounded, color: Colors.orange[800], size: 40),
                ),
                const SizedBox(height: 20),
                const Text(
                  '确认停止学习',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  '确定要将词书《$dictName》从书桌移出（停止学习）吗？',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600], fontSize: 15),
                ),
                const SizedBox(height: 20),
                // 独有学习单词提示卡片
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.info_outline, size: 16, color: Colors.orange[800]),
                          const SizedBox(width: 8),
                          Text(
                            '存在学习中单词',
                            style: TextStyle(color: Colors.orange[800], fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '该词书中有 ${learningWordsOnlyInThisDict.length} 个单词正在学习。',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.orange[900], fontSize: 13, height: 1.4),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // 操作按钮
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[400],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('停止学习并删除记录'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.grey[400]!, width: 1.2),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      foregroundColor: Colors.grey[800],
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('仅停止学习'),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.grey[400]!, width: 1.2),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      foregroundColor: Colors.grey[800],
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('取消'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      if (confirmResult != null) {
        shouldProceed = true;
        deleteLearningWords = confirmResult;
      }
    } else {
      // 没有独有学习词，直接确认
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.remove_circle_outline, color: AppTheme.primaryColor, size: 40),
                ),
                const SizedBox(height: 20),
                const Text(
                  '确认操作',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  '确实要将词书《$dictName》从书桌移出？',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600], fontSize: 15),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.grey[400]!, width: 1.2),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          foregroundColor: Colors.grey[800],
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('否'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('是'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
      if (confirmed == true) {
        shouldProceed = true;
      }
    }

    // 6. 执行核心逻辑
    if (shouldProceed && mounted) {
      await db.learningDictsDao.deleteEntity(currentLearningDict, true);
      widget.onDictChanged();

      // 处理相关学习记录
      if (deleteLearningWords) {
        for (final lw in learningWordsOnlyInThisDict) {
          await db.learningWordsDao.deleteEntity(lw, true);
        }
      }

      ThrottledDbSyncService().requestSync();
    }
  }

  Widget _buildDictActionButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    bool isDestructive = false,
    Color? color,
  }) {
    final isDarkMode = context.read<DarkMode>().isDarkMode;

    final bgColor = isDarkMode
        ? (isDestructive ? Colors.red.withValues(alpha: 0.12) : const Color(0xFF334155))
        : (isDestructive ? Colors.red.withValues(alpha: 0.08) : const Color(0xFFF1F5F9));

    final borderColor = isDarkMode
        ? (isDestructive ? Colors.red.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.1))
        : (isDestructive ? Colors.red.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.05));

    final contentColor = isDarkMode
        ? (isDestructive ? Colors.redAccent : (color ?? const Color(0xFFF1F5F9)))
        : (isDestructive ? Colors.red[700]! : (color ?? const Color(0xFF334155)));

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: borderColor,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive ? contentColor : contentColor.withValues(alpha: 0.4),
              size: 20,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isActive ? contentColor : contentColor.withValues(alpha: 0.4),
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.3,
                letterSpacing: 0,
              ),
              textScaler: const TextScaler.linear(1.0),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDictCheckbox({
    required String label,
    required bool value,
    required ValueChanged<bool?> onChanged,
  }) {
    final isDarkMode = context.read<DarkMode>().isDarkMode;
    final accentColor = isDarkMode ? const Color(0xFF22D3EE) : const Color(0xFF0EA5E9);

    final bgColor = isDarkMode ? const Color(0xFF334155) : const Color(0xFFF1F5F9);
    final borderColor = isDarkMode ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.05);
    final contentColor = isDarkMode ? const Color(0xFFF1F5F9) : const Color(0xFF334155);

    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: borderColor,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: accentColor,
              checkColor: Colors.white,
              side: BorderSide(
                color: contentColor.withValues(alpha: 0.6),
                width: 1.5,
              ),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: contentColor,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.3,
                letterSpacing: 0,
              ),
              textScaler: const TextScaler.linear(1.0),
            ),
          ],
        ),
      ),
    );
  }
}

class RankingPainter extends CustomPainter {
  final double percentile;
  final Color markerColor;
  final Color curveColor;

  RankingPainter({
    required this.percentile,
    required this.markerColor,
    required this.curveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final w = size.width;
    final h = size.height;

    // Draw generic bell curve shape
    final path = Path();
    final fillPath = Path();

    // Map x: from -2 to 2 for width
    const double xRange = 2.0;

    fillPath.moveTo(0, h);
    for (double i = 0; i <= w; i += 1) {
      double xNormalized = (i / w) * 2.0 * xRange - xRange; // x from -2 to 2
      double yVal = math.exp(-0.7 * xNormalized * xNormalized);
      double drawY = h - (yVal * h * 0.85);

      if (i == 0) {
        path.moveTo(i, drawY);
      } else {
        path.lineTo(i, drawY);
      }
      fillPath.lineTo(i, drawY);
    }
    fillPath.lineTo(w, h);
    fillPath.close();

    // Paint Area
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          curveColor.withValues(alpha: 0.1),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));
    canvas.drawPath(fillPath, fillPaint);

    // Paint Curve stroke
    final curvePaint = Paint()
      ..color = curveColor.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, curvePaint);

    // Function to calculate curve height and slope (tangent)
    double getCurveValue(double xFrac) {
      double xNormalized = xFrac * 2.0 * xRange - xRange;
      return math.exp(-0.7 * xNormalized * xNormalized);
    }

    // Draw small directional arrows along the curve (Flow from Left to Right)
    final arrowPaint = Paint()
      ..color = curveColor.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    for (double xFrac in [0.2, 0.45, 0.75]) {
      double x = xFrac * w;
      double yVal = getCurveValue(xFrac);
      double y = h - (yVal * h * 0.85);

      // Approximate slope using a small delta
      double nextXFrac = xFrac + 0.01;
      double nextX = nextXFrac * w;
      double nextYVal = getCurveValue(nextXFrac);
      double nextY = h - (nextYVal * h * 0.85);

      double angle = math.atan2(nextY - y, nextX - x);

      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(angle);

      // Draw arrow head ">"
      final arrowPath = Path();
      arrowPath.moveTo(-3, -3);
      arrowPath.lineTo(0, 0);
      arrowPath.lineTo(-3, 3);
      canvas.drawPath(arrowPath, arrowPaint);

      canvas.restore();
    }

    // Draw a small flag at the far right (Goal / Finish)
    const flagXFrac = 0.95;
    final fX = flagXFrac * w;
    final fY = h - (getCurveValue(flagXFrac) * h * 0.85);

    final flagPaint = Paint()
      ..color = curveColor.withValues(alpha: 0.6)
      ..strokeWidth = 1.2;

    // Pole
    canvas.drawLine(Offset(fX, fY), Offset(fX, fY - 10), flagPaint);
    // Flag banner
    final flagBannerPath = Path();
    flagBannerPath.moveTo(fX, fY - 10);
    flagBannerPath.lineTo(fX + 6, fY - 7);
    flagBannerPath.lineTo(fX, fY - 4);
    flagBannerPath.close();
    canvas.drawPath(flagBannerPath, Paint()..color = curveColor.withValues(alpha: 0.4));

    // Marker
    if (percentile >= 0) {
      double xFrac = percentile / 100.0;
      double xPos = xFrac * w;
      double yVal = getCurveValue(xFrac);
      double yPos = h - (yVal * h * 0.85);

      final markerLinePaint = Paint()
        ..color = markerColor.withValues(alpha: 0.3)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(xPos, yPos + 4), Offset(xPos, h), markerLinePaint);

      final glowPaint = Paint()..color = markerColor.withValues(alpha: 0.2);
      canvas.drawCircle(Offset(xPos, yPos), 7, glowPaint);
      canvas.drawCircle(Offset(xPos, yPos), 4, Paint()..color = markerColor);

      // Add a tiny white dot in center for "eye-catching" effect
      canvas.drawCircle(Offset(xPos, yPos), 1.5, Paint()..color = Colors.white.withValues(alpha: 0.8));
    }
  }

  @override
  bool shouldRepaint(covariant RankingPainter oldDelegate) => oldDelegate.percentile != percentile || oldDelegate.markerColor != markerColor;
}
