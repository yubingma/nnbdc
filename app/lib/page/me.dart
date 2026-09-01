import 'dart:async';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift_db_viewer/drift_db_viewer.dart';
import 'package:email_validator/email_validator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/bo/user_bo.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/event/events.dart';
import 'package:nnbdc/page/admin/health_check.dart';
import 'package:nnbdc/page/admin/sync_log_viewer.dart';
import 'package:nnbdc/page/feature_request_wall.dart';
import 'package:nnbdc/page/level_path_page.dart';
import 'package:nnbdc/page/subscription.dart';
import 'package:nnbdc/page/word_list/dict_words.dart';
import 'package:nnbdc/page/review_distribution.dart';
import 'package:nnbdc/page/badge/badge_wall_page.dart';


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
import 'package:nnbdc/util/date_utils.dart' as bdc_date;
import 'package:nnbdc/widget/dict_download_dialog.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/theme/app_theme_background.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:nnbdc/util/notification_util.dart';
import '../util/permission_util.dart';
import 'dart:ui' as ui;
import 'package:provider/provider.dart';

import '../global.dart';
import '../state.dart';
import '../util/level_util.dart';
import '../constants.dart';
import '../config.dart';
import '../util/asr.dart';

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
  PromoActivityVo? _activePromo;
  final bool _isSyncing = false;
  late Function(String event, List args) _socketEventListener;
  StreamSubscription<List<PurchaseDetails>>? _subscriptionStreamSubscription;
  StreamSubscription<DictDownloadCompletedEvent>? _dictDownloadCompletedSub;

  /// 最近一次同步是否失败
  bool _isLastSyncFailed = false;

  /// 是否正在检查并下载词书（用于防止 loadData 循环触发）
  bool _isCheckingDicts = false;
  Future<Widget>? _learningDictsFuture;

  /// 近期已下载/尝试下载的词书 ID 集合（用于防止导入后异步可见性延迟导致的循环）
  /// key: dictId, value: 下载完成时间
  static final Map<String, DateTime> _recentlyDownloadedAt = {};
  static const Duration _reDownloadCooldown = Duration(seconds: 30);

  /// 检查指定词书是否在近期已下载过（冷却期内不重复下载）
  bool _isRecentlyDownloaded(String dictId) {
    final lastAt = _recentlyDownloadedAt[dictId];
    if (lastAt == null) return false;
    if (AppClock.now().difference(lastAt) > _reDownloadCooldown) {
      _recentlyDownloadedAt.remove(dictId);
      return false;
    }
    return true;
  }

  /// 标记词书为已尝试下载（无论成功/失败），防止冷却期内重复下载
  void _markDictsDownloaded(List<DictVo> dicts) {
    final now = AppClock.now();
    for (final d in dicts) {
      _recentlyDownloadedAt[d.id] = now;
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Text(
                '权限使用说明：${Global.appName}需要您的相机和存储权限，用于拍摄或选择照片作为您的个人头像，这些信息不会被挪作他用。',
                style: TextStyle(
                  fontSize: 13,
                  color: isDarkMode ? const Color(0xFFE2E8F0) : const Color(0xFF64748B),
                  height: 1.5,
                  fontFamily: 'NotoSansSC',
                ),
              ),
            ),
            const Divider(height: 1, thickness: 0.2),
            Material(
              type: MaterialType.transparency,
              child: ListTile(
              leading: const Icon(Icons.camera_alt_rounded, color: Color(0xFF18BA7C)),
              title: const Text('拍照', style: TextStyle(fontFamily: 'NotoSansSC')),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            )),
            Material(
              type: MaterialType.transparency,
              child: ListTile(
              leading: const Icon(Icons.photo_library_rounded, color: Color(0xFF18BA7C)),
              title: const Text('从相册选择', style: TextStyle(fontFamily: 'NotoSansSC')),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (source != null) {
      if (source == ImageSource.camera) {
        await PermissionUtil.requestWithRationale(
          permission: Permission.camera,
          title: '相机权限',
          purpose: '用于拍摄您的个人头像图片。',
          icon: Icons.camera_alt_rounded,
          onGranted: () async {
            final XFile? pickedFile = await picker.pickImage(source: source);
            if (pickedFile != null) {
              _processAndUploadAvatar(pickedFile);
            }
          },
        );
      } else {
        await PermissionUtil.requestWithRationale(
          permission: Permission.photos,
          title: '相册/存储权限',
          purpose: '用于从相册选择图片作为您的个人头像。',
          icon: Icons.photo_library_rounded,
          onGranted: () async {
            final XFile? pickedFile = await picker.pickImage(source: source);
            if (pickedFile != null) {
              _processAndUploadAvatar(pickedFile);
            }
          },
        );
      }
    }
  }

  Future<void> _processAndUploadAvatar(XFile pickedFile) async {
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
        // 使用专用的 uploadImg 接口上传图片 (FormData 方式，永久解决 Retrofit 生成代码缺少文件名的问题)
        final formData = FormData.fromMap({
          'file': MultipartFile.fromBytes(bytes, filename: pickedFile.name),
          'userId': userId,
          'fileName': pickedFile.name,
        });
        final result = await Api.client.uploadImg(formData, null, "avatar");

        if (result.success && result.data != null) {
          final newAvatarFilename = result.data!;
          final db = MyDatabase.instance;
          final user = await db.usersDao.getUserById(userId);
          if (user != null) {
            String finalAvatar = newAvatarFilename;
            if (!newAvatarFilename.startsWith('http')) {
                      finalAvatar = '${Config.imgBaseUrl}$newAvatarFilename';
            }

            final updatedUser = user.copyWith(wechatAvatar: drift.Value(finalAvatar));
            await db.usersDao.saveUser(updatedUser, true);

            // 刷新本地缓存并更新 UI
            final updatedUserInfo = await Global.refreshLoggedInUser();
            setState(() {
              loggedInUser = updatedUserInfo;
            });

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

  @override
  void initState() {
    super.initState();
    // 进入“我”页面时强制关闭 ASR
    Asr().stopMicrophone();

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

    // 监听词书下载完成事件（跨页面同步：比如从今日计划页面触发下载后，"我"页面也要刷新）
    _dictDownloadCompletedSub = EventBus.onDictDownloadCompleted().listen((event) {
      if (mounted) {
        Global.logger.i("📥 MePage 收到词书下载完成事件，刷新数据");
        loadData();
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

    // 取消词书下载完成事件监听
    _dictDownloadCompletedSub?.cancel();

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

      if (loggedInUserVal == null || loggedInUserVal.id == null) return;

      final db = MyDatabase.instance;
      User? tempUser = await db.usersDao.getUserById(loggedInUserVal.id!);
      if (tempUser != null) {
        final userId = tempUser.id;
        
        // 动态推导并纠正打卡天数统计，防止多端数据冲突
        try {
          await UserBo().updateAndSyncUserDakaStats(userId);
        } catch (e) {
          Global.logger.e("MePage: 纠正打卡天数统计失败: $e");
        }

        final user = await db.usersDao.getUserById(userId) ?? tempUser;

        // 核心统计数据计算
        var learningDicts = await MyDatabase.instance.learningDictsDao.getLearningDictsOfUser(userId);
        final learningDictIds = learningDicts.map((d) => d.dictId).toList();

        // [性能优化] 使用 SQL 直接在数据库内完成聚合与去重，避免在 Flutter 主线程进行巨大的 Set 操作（尤其是单词量大的时候）
        // 1. 全局正在学习的单词总数
        var globalLearningWordsCount = await (db.selectOnly(db.learningWords)
              ..addColumns([db.learningWords.wordId.count()])
              ..where(db.learningWords.userId.equals(userId))
              ..where(db.learningWords.stability.isNull() | db.learningWords.stability.isSmallerThanValue(Constants.graduationStability)))
            .getSingle()
            .then((r) => r.read(db.learningWords.wordId.count()) ?? 0);

        // 2. 当前选中的词书中的去重单词总数
        var rawWordCount = await db.dictWordsDao.getUniqueWordCountInDicts(learningDictIds);

        // 3. 当前选中的词书中包含的“正在学习”单词总数
        var learningWordsInSelectedDictsCount = await db.learningWordsDao.getLearningWordsCountInDicts(userId, learningDictIds);

        // 4. 全局已掌握单词总数
        // 尝试更新并获取最新的用户掌握数
        await db.masteredWordsDao.updateUserMasteredWordCount(userId);
        final latestUser = await db.usersDao.getUserById(userId);
        var globalMasteredWordsCount = latestUser?.masteredWordsCount ?? 0;

        // 5. 当前选中的词书中包含的“已掌握”单词总数
        var masteredWordsInSelectedDictsCount = await db.masteredWordsDao.getMasteredWordsCountInDicts(userId, learningDictIds);

        Global.logger.d('MePage: 统计数据加载完成 - 学习中: $globalLearningWordsCount, 选中书内学习中: $learningWordsInSelectedDictsCount, 掌握: $globalMasteredWordsCount');

        var allDictsFinished = (learningWordsInSelectedDictsCount + masteredWordsInSelectedDictsCount) >= rawWordCount;
        LevelVo levelVo = LevelUtil.getLevelVoByWordCount(globalMasteredWordsCount);

        // 打卡率定义改为：累计打卡天数 / 注册至今的总天数 (符合主流App定义的出勤率)
        final totalDays = AppClock.today().difference(bdc_date.DateUtils.businessDate(user.createTime)).inDays + 1;
        var actualDakaRatio = totalDays > 0 ? user.dakaDayCount / totalDays : (user.dakaDayCount > 0 ? 1.0 : 0.0);
        if (actualDakaRatio > 1.0) actualDakaRatio = 1.0;

        studyProgressVal = StudyProgress(
          user.learnedDays,
          user.dakaDayCount,
          actualDakaRatio,
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
          user.throwDiceChance,
          allDictsFinished,
          UserHelper.isTodayLearningFinishedFromUser(user),
          learningDicts,
          totalLearningSeconds: user.totalLearningSeconds ?? 0,
          todayLearningSeconds: user.todayLearningSeconds ?? 0,
        );
      }

      var result2 = await UserBo().getDayStatuses(30);
      if (result2.success) {
        last30DaysDakaStatusVal = result2.data!;
      } else {
        last30DaysDakaStatusVal = List.filled(30, UserDayStatus.notLogin.json);
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

      // --- 阶段 2: 异步刷新网络数据 (非阻塞) ---
      if (!Global.isGuest) {
        // 1. 获取个人排名
        try {
          var userId = loggedInUserVal.id!;
          var result4 = await Api.client.getUserRank(userId);
          if (result4.success && studyProgress != null) {
            setState(() {
              studyProgress!.userOrder = result4.data;
            });
          }
        } catch (e) {
          Global.logger.w('获取个人排名失败 (静默忽略): $e');
        }

        // 2. 获取消息计数
        try {
          var result3 = await Api.client.getMsgCounts(loggedInUserVal.id!);
          if (result3.success) {
            setState(() {
              msgCount = result3.data!.first;
              unreadMsgCount = result3.data!.second;
            });
          }
        } catch (e) {
          Global.logger.w('获取消息计数失败 (静默忽略): $e');
        }

        // 3. 获取当前生效的推广活动
        try {
          var promoResult = await Api.client.getActivePromoActivity();
          Global.logger.i('loadData 获取生效推广活动: success=${promoResult.success}, name=${promoResult.data?.name}');
          if (promoResult.success && mounted) {
            setState(() {
              _activePromo = promoResult.data;
            });
          }
        } catch (e) {
          Global.logger.w('获取当前生效推广活动失败: $e');
        }
      }
    } catch (e, stackTrace) {
      if (ErrorHandler.isNetworkError(e)) {
        ErrorHandler.handleNetworkError(e, stackTrace, api: 'loadData', showToast: false);
        // 如果是因为网络原因失败，我们至少要让 UI 能展示出本地已有的数据（即便可能是旧的）
        // 如果 studyProgress 还没被赋值，那么我们需要确保 setState 运行一次停止 spinner
        if (mounted && studyProgress == null) {
          setState(() {
            // 触发刷新，显示本地数据
          });
        }
      } else {
        ErrorHandler.handleError(e, stackTrace, userMessage: '加载数据失败，请刷新重试', logPrefix: '加载数据失败', showToast: true);
      }
    } finally {
      Api.setLoadingDisabled(false);
    }
  }

  // 辅助方法，同步显示对话框
  Future<void> _showDictDownloadDialog(List<DictVo> dicts) async {
    if (DictDownloadDialog.isShowing) return;
    await DictDownloadDialog.show(
      context: context,
      dicts: dicts,
      onComplete: () {
        // 标记这些词书为已尝试下载，防止短时间内重复下载循环
        _markDictsDownloaded(dicts);
        // 通知其他页面词书下载完成
        EventBus.publishDictDownloadCompleted(DictDownloadCompletedEvent(
          dictIds: dicts.map((d) => d.id).toList(),
        ));
        // 词书下载完成后，刷新页面数据以更新学习进度显示
        loadData();
      },
    );
  }

  /// 同步数据库并下载词书
  /// 同步完成后自动检查并下载本地缺失的词书，显示下载进度对话框
  Future<void> _syncAndDownloadDicts(String userId) async {
    if (_isCheckingDicts) return;
    _isCheckingDicts = true;
    try {
      final db = MyDatabase.instance;
      var learningDicts = await db.learningDictsDao.getLearningDictsOfUser(userId);
      
      if (learningDicts.isEmpty) {
        Global.logger.i("本地词书为空，发起阻塞式同步以获取用户数据...");
        await ThrottledDbSyncService().requestSyncAndWait(immediate: true);
      } else {
        ThrottledDbSyncService().requestSync();
      }
      
      await _checkAndDownloadDicts(userId);
    } catch (e) {
      Global.logger.e("同步或下载词书失败: $e");
    } finally {
      _isCheckingDicts = false;
    }
  }

  /// 检查并下载本地缺失的词书
  /// 先检查通用词典，再检查用户选择的词书
  Future<void> _checkAndDownloadDicts(String userId) async {
    if (!mounted) return;
    final now = AppClock.now();

    try {
      final db = MyDatabase.instance;
      // 注意：必须重新查询learningDicts，因为同步可能已经从服务器获取了用户的词书数据
      List<LearningDict> learningDicts = await db.learningDictsDao.getLearningDictsOfUser(userId);
      
      // [性能优化] 批量获取词书详情和单词存在情况，减少数据库查询次数
      final dictIdsToCheck = [Global.commonDictId, ...learningDicts.map((ld) => ld.dictId)];
      final existingDicts = await db.dictsDao.findByIds(dictIdsToCheck);
      final dictMap = {for (var d in existingDicts) d.id: d};
      
      final dictsWithWords = await db.dictWordsDao.findDictsWithWords(dictIdsToCheck);
      final dictsWithWordsSet = dictsWithWords.toSet();
      
      List<DictVo> dictsToDownload = [];

      // 1. 检查通用词典
      if (!dictsWithWordsSet.contains(Global.commonDictId) && !_isRecentlyDownloaded(Global.commonDictId)) {
        Global.logger.i("通用词典内容为空，准备下载");
        dictsToDownload.add(DictVo(
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
          createTime: now,
          updateTime: now,
        ));
      }

      // 2. 收集需要下载的用户词书
      for (var learningDict in learningDicts) {
        if (learningDict.dictId == Global.commonDictId) continue;

        final existing = dictMap[learningDict.dictId];
        String currentDictName = '词书 ${learningDict.dictId}';

        // 检查词书是否存在，或存在但没有单词
        if (existing == null) {
          // 词书不存在，需要从服务端确认信息
          bool dictDeletedOnServer = false;
          try {
            final result = await Api.client.getDictInfo(learningDict.dictId);
            if (result.success && result.data?.name != null) {
              currentDictName = result.data!.name;
            } else if (!result.success && result.msg == '词典不存在') {
              dictDeletedOnServer = true;
            }
          } catch (e) {
            Global.logger.e("获取词书名称失败: $e");
          }

          if (dictDeletedOnServer) {
            Global.logger.w("词书已在服务端删除，移除本地关联: ${learningDict.dictId}");
            await db.learningDictsDao.deleteEntity(learningDict, true);
            continue;
          }

          dictsToDownload.add(DictVo(
            id: learningDict.dictId,
            name: currentDictName,
            shortName: getShortName(currentDictName),
            owner: null,
            isShared: true,
            isReady: true,
            visible: true,
            editable: currentDictName == '生词本',
            dictWords: null,
            wordCount: 0,
            createTime: now,
            updateTime: now,
          ));
        } else if (existing.ownerId == Global.sysUserId && !dictsWithWordsSet.contains(learningDict.dictId)) {
          // 系统词书缺失内容，但近期刚下载过 → 跳过（防止导入后数据库延迟可见导致的循环）
          if (_isRecentlyDownloaded(learningDict.dictId)) {
            Global.logger.i("系统词书内容缺失但近期刚下载，跳过: ${learningDict.dictId}");
            continue;
          }
          Global.logger.i("系统词书内容缺失，准备下载: ${learningDict.dictId}");
          if (!dictsToDownload.any((d) => d.id == learningDict.dictId)) {
            dictsToDownload.add(DictVo(
              id: learningDict.dictId,
              name: existing.name,
              shortName: getShortName(existing.name),
              owner: null,
              isShared: true,
              isReady: true,
              visible: true,
              editable: existing.name == '生词本',
              dictWords: null,
              wordCount: 0,
              baseDictId: existing.baseDictId,
              createTime: now,
              updateTime: now,
            ));
          }

          // 衍生词书依赖检查
          if (existing.baseDictId != null && existing.baseDictId!.isNotEmpty) {
            if (!dictsWithWordsSet.contains(existing.baseDictId!) && !dictsToDownload.any((d) => d.id == existing.baseDictId) && !_isRecentlyDownloaded(existing.baseDictId!)) {
              String baseName = '基础词书';
              try {
                final baseResult = await Api.client.getDictInfo(existing.baseDictId!);
                if (baseResult.success && baseResult.data?.name != null) baseName = baseResult.data!.name;
              } catch (_) {}
              
              dictsToDownload.add(DictVo(
                id: existing.baseDictId!,
                name: baseName,
                shortName: getShortName(baseName),
                owner: null,
                isShared: true,
                isReady: true,
                visible: true,
                editable: false,
                dictWords: null,
                wordCount: 0,
                createTime: now,
                updateTime: now,
              ));
            }
          }
        }
      }

      if (dictsToDownload.isNotEmpty && mounted) {
        // 预标记：在对话框显示前标记为"已尝试下载"，防止对话框被其他页面弹窗拦截时漏标记
        _markDictsDownloaded(dictsToDownload);
        await _showDictDownloadDialog(dictsToDownload);
      }
    } catch (e, stackTrace) {
      Global.logger.e("检查词书下载失败: $e", stackTrace: stackTrace);
    }
  }

  /// 获取当前用户账户类型信息（用于UI展示和排查）
  Map<String, dynamic> _getUserAccountTypeInfo() {
    if (Global.isGuest || loggedInUser == null) {
      return {
        'type': '游客模式',
        'desc': '未登录',
        'isPremium': false,
        'tag': '游客',
      };
    }

    if (loggedInUser?.isSuperAdmin == true) {
      return {
        'type': '超级管理员',
        'desc': '系统全部权限',
        'isPremium': true,
        'tag': '超管',
      };
    }

    if (loggedInUser?.isAdmin == true) {
      return {
        'type': '管理员',
        'desc': '系统管理权限',
        'isPremium': true,
        'tag': '管理员',
      };
    }

    final type = SubscriptionUtil.getSubscriptionType();
    final expire = SubscriptionUtil.getExpireDate();
    final isOverride = loggedInUser?.premiumOverrideEnabled == true && (loggedInUser?.isPremiumIos != true);

    if (type != null && type.isNotEmpty) {
      final typeText = type == 'monthly' ? 'iOS 月度会员' : (type == 'yearly' || type == 'annual' ? 'iOS 年度会员' : 'iOS 订阅会员');
      final desc = expire != null ? '有效期至：${expire.year}年${expire.month}月${expire.day}日' : '订阅生效中';
      return {
        'type': typeText,
        'desc': desc,
        'isPremium': true,
        'tag': 'VIP',
      };
    }

    if (isOverride) {
      final updateTime = loggedInUser?.premiumOverrideUpdateTime;
      final duration = loggedInUser?.premiumOverrideDuration;
      if (duration == null) {
        return {
          'type': '永久会员',
          'desc': '永久有效',
          'isPremium': true,
          'tag': '永久VIP',
        };
      } else if (updateTime != null) {
        final ms = _parseDurationMillis(duration);
        if (ms != null && ms > 0) {
          final expireTime = updateTime.add(Duration(milliseconds: ms));
          final isValid = expireTime.isAfter(DateTime.now());
          return {
            'type': isValid ? '限时会员' : '会员已过期',
            'desc': '有效期至：${expireTime.year}年${expireTime.month}月${expireTime.day}日',
            'isPremium': isValid,
            'tag': isValid ? '限时VIP' : '已过期',
          };
        }
      }
    }

    if (loggedInUser?.vipExpireDate != null) {
      final vipExpire = loggedInUser!.vipExpireDate!;
      final isValid = vipExpire.isAfter(DateTime.now());
      final vipType = loggedInUser?.vipType;
      final typeText = (vipType != null && vipType.isNotEmpty)
          ? (vipType == 'monthly' ? '月度会员' : (vipType == 'annual' ? '年度会员' : 'VIP 会员'))
          : 'VIP 会员';
      return {
        'type': isValid ? typeText : '$typeText (已过期)',
        'desc': '有效期至：${vipExpire.year}年${vipExpire.month}月${vipExpire.day}日',
        'isPremium': isValid,
        'tag': isValid ? 'VIP' : '已过期',
      };
    }

    if (loggedInUser?.isPremiumIos == true) {
      return {
        'type': 'iOS 会员 (永久)',
        'desc': '永久有效',
        'isPremium': true,
        'tag': 'iOS VIP',
      };
    }

    return {
      'type': '普通用户',
      'desc': '未开通会员',
      'isPremium': false,
      'tag': '普通用户',
    };
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

  /// 弹出会员专属特权展示弹窗
  void _showPrivilegesDialog(BuildContext context, Map<String, dynamic> accountInfo) {
    final isDarkMode = Provider.of<DarkMode>(context, listen: false).isDarkMode;
    final isPremium = accountInfo['isPremium'] as bool;
    final accountType = accountInfo['type'] as String;
    final accountDesc = accountInfo['desc'] as String?;
    final accentColor = isDarkMode ? const Color(0xFF2CD88F) : const Color(0xFF18BA7C);
    final cardBg = isDarkMode ? const Color(0xFF1B2825) : Colors.white;
    final textColor = isDarkMode ? const Color(0xFFEAF7F4) : const Color(0xFF152724);
    final subtitleColor = isDarkMode ? const Color(0xFF8EA8A3) : const Color(0xFF5A7570);

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDarkMode ? Colors.white12 : const Color(0x1418BA7C),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDarkMode ? 0.4 : 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 顶部图标与标题
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: isPremium
                        ? accentColor.withValues(alpha: isDarkMode ? 0.2 : 0.12)
                        : const Color(0xFFFF9800).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Icon(
                      isPremium ? Icons.verified_rounded : Icons.workspace_premium_rounded,
                      color: isPremium ? accentColor : const Color(0xFFFF9800),
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  isPremium ? '尊享会员特权' : '会员特权介绍',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    fontFamily: 'NotoSansSC',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  (accountDesc != null && accountDesc.isNotEmpty)
                      ? '$accountType · $accountDesc'
                      : '当前状态：$accountType',
                  style: TextStyle(
                    color: subtitleColor,
                    fontSize: 12,
                    fontFamily: 'NotoSansSC',
                  ),
                ),
                const SizedBox(height: 18),
                // 特权列表 (严格契合系统真实权限设计)
                _buildPrivilegeRow(
                  Icons.all_inclusive_rounded,
                  '每日学习新词量无上限',
                  isPremium ? '已解锁自由设定每日新词量 (无限制)' : '非会员每日计划最多仅可学习 20 个新词',
                  accentColor,
                  textColor,
                  subtitleColor,
                ),
                const SizedBox(height: 12),
                _buildPrivilegeRow(
                  Icons.psychology_rounded,
                  'AI 智能助教与深度解析',
                  isPremium ? '尊享离线/在线模型助教无限量助记与答疑' : '非会员无法使用 AI 助教解析',
                  accentColor,
                  textColor,
                  subtitleColor,
                ),
                const SizedBox(height: 12),
                _buildPrivilegeRow(
                  Icons.auto_stories_rounded,
                  '全量官方词书与导入畅学',
                  isPremium ? '全库海量词书自由畅选，支持自定义导入' : '非会员限制添加与切换新词书',
                  accentColor,
                  textColor,
                  subtitleColor,
                ),
                const SizedBox(height: 20),
                // 底部操作按钮
                Row(
                  children: [
                    if (!isPremium && PlatformUtils.isIOS) ...[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: isDarkMode ? Colors.white24 : const Color(0xFFD0E0DC)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text('稍后再说', style: TextStyle(color: subtitleColor)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            Navigator.of(context).push(MaterialPageRoute(builder: (context) => const SubscriptionPage())).then((_) {
                              loadData();
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('立即开通', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ] else ...[
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            if (PlatformUtils.isIOS) {
                              Navigator.of(context).push(MaterialPageRoute(builder: (context) => const SubscriptionPage())).then((_) {
                                loadData();
                              });
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(PlatformUtils.isIOS ? '管理订阅' : '我知道了', style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPrivilegeRow(IconData icon, String title, String desc, Color accentColor, Color textColor, Color subtitleColor) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: accentColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: textColor, fontSize: 13, fontWeight: FontWeight.w700, fontFamily: 'NotoSansSC')),
              Text(desc, style: TextStyle(color: subtitleColor, fontSize: 10.5, fontFamily: 'NotoSansSC')),
            ],
          ),
        ),
      ],
    );
  }

  Widget renderStudyProgress() {
    final darkModeState = context.watch<DarkMode>();
    final themeStyle = darkModeState.themeStyle;
    final isDarkModeEnabled = themeStyle.isDark;
    final themeConfig = AppThemeConfig.of(themeStyle);

    final textColor = themeConfig.textPrimary;
    final subtitleColor = themeConfig.textSecondary;
    final accentColor = themeConfig.primaryColor;
    final cardColor = themeConfig.cardBg;
    final borderColor = themeConfig.cardBorder;
    final subtleBgColor = themeConfig.subtleBg;
    final cardShadow = themeConfig.cardShadows;

    return Column(
      children: [
        // 1. 个人资料 + 高光展台卡片 (Profile & Highlights Card)
        Container(
          margin: EdgeInsets.symmetric(
            vertical: MediaQuery.of(context).size.width > 600 ? 16 : 10,
          ),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(24),
            boxShadow: cardShadow,
            border: Border.all(color: borderColor, width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1.1 头像和昵称行 (紧凑对齐，1:1 对齐原型头像光圈+小笔头)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () {
                      if (loggedInUser != null) {
                        _pickAndUploadAvatar();
                      } else {
                        context.go('/login');
                      }
                    },
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(2.0),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: accentColor.withValues(alpha: 0.8), width: 2),
                          ),
                          child: CircleAvatar(
                            radius: 26,
                            backgroundColor: isDarkModeEnabled ? Colors.white10 : const Color(0xFFF1F5F9),
                            backgroundImage: (loggedInUser?.wechatAvatar != null && loggedInUser!.wechatAvatar!.isNotEmpty)
                                ? CachedNetworkImageProvider(loggedInUser!.wechatAvatar!)
                                : null,
                            child: (loggedInUser?.wechatAvatar == null || loggedInUser!.wechatAvatar!.isEmpty)
                                ? Icon(Icons.person_rounded, color: subtitleColor, size: 26)
                                : null,
                          ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 18,
                            height: 18,
                            decoration: BoxDecoration(
                              color: accentColor,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDarkModeEnabled ? const Color(0xFF131E1C) : Colors.white,
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  blurRadius: 3,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.edit_rounded,
                                size: 10,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  // 昵称信息及名言
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 顶部行：昵称 + 认证蓝勾 + 右侧等级徽章
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                Util.getNickNameOfUser(loggedInUser),
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  fontFamily: 'NotoSansSC',
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (SubscriptionUtil.isPremium()) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.verified, color: Color(0xFF2196F3), size: 16),
                            ],
                            const Spacer(),
                            // 右上角浮动等级胶囊
                            GestureDetector(
                              onTap: () {
                                Navigator.of(context).push(MaterialPageRoute(
                                    builder: (context) => LevelPathPage(currentLevel: studyProgress!.level.level ?? 1)));
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isDarkModeEnabled ? accentColor.withValues(alpha: 0.15) : const Color(0xFFE8F8F1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (studyProgress!.level.figure != null && studyProgress!.level.figure!.isNotEmpty) ...[
                                      Text(
                                        studyProgress!.level.figure!,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      const SizedBox(width: 3),
                                    ],
                                    Text(
                                      studyProgress!.level.name ?? 'Lv.1',
                                      style: TextStyle(
                                        color: accentColor,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // 名言
                        Text(
                          '“${LevelUtil.getTitleQuote(studyProgress!.level.level ?? 1)}”',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: subtitleColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // 1.2 左右双列横向高光展台 (1:1 严格对齐原型：荣耀勋章墙 + 复习分布图)
              Row(
                children: [
                  // 左：荣耀勋章墙
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const BadgeWallPage())),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: subtleBgColor,
                          border: Border.all(
                            color: borderColor,
                            width: 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: const Color(0xFF6366F1).withValues(alpha: isDarkModeEnabled ? 0.25 : 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Center(
                                child: Text('🎖', style: TextStyle(fontSize: 16)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      '荣耀勋章墙',
                                      style: TextStyle(
                                        color: textColor,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        fontFamily: 'NotoSansSC',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      '点亮成就图鉴',
                                      style: TextStyle(
                                        color: subtitleColor,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                        fontFamily: 'NotoSansSC',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // 右：复习分布图
                  Expanded(
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (context) => const ReviewDistributionPage())),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          color: subtleBgColor,
                          border: Border.all(
                            color: borderColor,
                            width: 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: isDarkModeEnabled ? 0.2 : 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(Icons.bar_chart_rounded, color: accentColor, size: 20),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      '复习分布图',
                                      style: TextStyle(
                                        color: textColor,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w800,
                                        fontFamily: 'NotoSansSC',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      '艾宾浩斯记忆云图',
                                      style: TextStyle(
                                        color: subtitleColor,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w500,
                                        fontFamily: 'NotoSansSC',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // 1.3 VIP / 账户类型状态条 (根据真实账户信息动态展示)
              Builder(builder: (context) {
                final accountInfo = _getUserAccountTypeInfo();
                final isPremium = accountInfo['isPremium'] as bool;
                final accountType = accountInfo['type'] as String;
                final accountDesc = accountInfo['desc'] as String?;
                final accountTag = accountInfo['tag'] as String? ?? (isPremium ? 'PRO' : 'USER');

                final displayText = (accountDesc != null && accountDesc.isNotEmpty)
                    ? '$accountType · $accountDesc'
                    : '账户类型：$accountType';

                return GestureDetector(
                  onTap: () {
                    _showPrivilegesDialog(context, accountInfo);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: isDarkModeEnabled ? accentColor.withValues(alpha: 0.1) : const Color(0xFFE8F8F1),
                      border: Border.all(
                        color: accentColor.withValues(alpha: 0.25),
                        width: 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: accentColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            accountTag,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'NotoSansSC',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            displayText,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'NotoSansSC',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              isPremium ? '特权' : (PlatformUtils.isIOS ? '升级特权' : '详情'),
                              style: TextStyle(
                                color: accentColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                fontFamily: 'NotoSansSC',
                              ),
                            ),
                            const SizedBox(width: 2),
                            Icon(Icons.chevron_right_rounded, size: 14, color: accentColor),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              }),
              if (_activePromo?.showRedeemUi == true) ...[
                const SizedBox(height: 8),
                _PromoRedemptionWidget(
                  activePromo: _activePromo,
                  onRedeemSuccess: () {
                    loadData();
                  },
                ),
              ],
              if (_isSyncing) ...[
                const SizedBox(height: 8),
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
              ],
            ],
          ),
        ),

        // 2. 我的书桌 (My Desk) - 严格对齐原型图布局
        Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDarkModeEnabled ? 0.3 : 0.03),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 2.1 标题行：左边「我的书桌」 + 右边「+ 选择词书」胶囊
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '我的书桌',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: textColor,
                      fontFamily: 'NotoSansSC',
                    ),
                  ),
                  GestureDetector(
                    key: const Key('me_choose_book_btn'),
                    onTap: () {
                      context.push("/select_book").then((value) {
                        loadData();
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: isDarkModeEnabled ? accentColor.withValues(alpha: 0.15) : const Color(0xFFE8F8F1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '+ 选择词书',
                            style: TextStyle(
                              color: accentColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              fontFamily: 'NotoSansSC',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // 2.2 词书总进度条容器 (浅灰底微容器)
              Builder(builder: (context) {
                final totalWords = studyProgress!.rawWordCount;
                final masteredWords = studyProgress!.masteredWordsInSelectedDictsCount;
                final learningWords = studyProgress!.learningWordsInSelectedDictsCount;
                final fetchWords = masteredWords + learningWords;

                final masteryProgress = totalWords > 0 ? masteredWords / totalWords : 0.0;
                final fetchProgress = totalWords > 0 ? fetchWords / totalWords : 0.0;

                final masteryPercentText = (masteryProgress * 100).toStringAsFixed(1);
                final fetchPercentText = (fetchProgress * 100).toStringAsFixed(1);

                final masteredColor = isDarkModeEnabled ? const Color(0xFF2CD88F) : const Color(0xFF18BA7C);
                final fetchColor = isDarkModeEnabled ? const Color(0xFF6EE7B7) : const Color(0xFF34D399);

                return Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: subtleBgColor,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "词书总进度",
                            style: TextStyle(
                              color: subtitleColor,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'NotoSansSC',
                            ),
                          ),
                          Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: '已掌握 ',
                                  style: TextStyle(
                                    color: subtitleColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'NotoSansSC',
                                  ),
                                ),
                                TextSpan(
                                  text: '$masteryPercentText%',
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    fontFamily: 'Roboto',
                                  ),
                                ),
                                TextSpan(
                                  text: ' · 已取词 ',
                                  style: TextStyle(
                                    color: subtitleColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    fontFamily: 'NotoSansSC',
                                  ),
                                ),
                                TextSpan(
                                  text: '$fetchPercentText%',
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    fontFamily: 'Roboto',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 6,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: isDarkModeEnabled ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final clampedMasteryProgress = masteryProgress > 1.0 ? 1.0 : masteryProgress;
                            final clampedFetchProgress = fetchProgress > 1.0 ? 1.0 : fetchProgress;
                            return Stack(
                              children: [
                                if (clampedFetchProgress > 0)
                                  Container(
                                    width: constraints.maxWidth * clampedFetchProgress,
                                    decoration: BoxDecoration(
                                      color: fetchColor,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                if (clampedMasteryProgress > 0)
                                  Container(
                                    width: constraints.maxWidth * clampedMasteryProgress,
                                    decoration: BoxDecoration(
                                      color: masteredColor,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 12),

              // 2.3 词书列表
              FutureBuilder<Widget>(
                future: _learningDictsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(color: accentColor, strokeWidth: 2),
                    ));
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          '加载失败',
                          style: TextStyle(color: subtitleColor),
                        ),
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

        // 3. 学习成就统计卡片 (1:1 对齐原型图：3个微卡片 + 嵌套最近30天打卡记录)
        Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDarkModeEnabled ? 0.3 : 0.03),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '学习成就统计',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: textColor,
                  fontFamily: 'NotoSansSC',
                ),
              ),
              const SizedBox(height: 14),

              // 3.1 三个统计微卡片 (纯净数值 + 标签，1:1 对齐原型)
              Row(
                children: [
                  _buildStatBox(
                    isDarkModeEnabled,
                    "打卡天数",
                    studyProgress!.dakaDayCount.toString(),
                  ),
                  const SizedBox(width: 8),
                  _buildStatBox(
                    isDarkModeEnabled,
                    "已掌握词",
                    studyProgress!.masteredWordsCount.toString(),
                  ),
                  const SizedBox(width: 8),
                  _buildStatBox(
                    isDarkModeEnabled,
                    "超越学友",
                    studyProgress!.userOrder! < 0 ? '98.5%' : '${studyProgress!.userOrder!.toStringAsFixed(1)}%',
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // 3.2 嵌入式「最近 30 天打卡记录」微容器
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: subtleBgColor,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '最近 30 天打卡记录',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: textColor,
                            fontFamily: 'NotoSansSC',
                          ),
                        ),
                        GestureDetector(
                          onTap: () => context.push('/study_stats'),
                          child: Text(
                            '更多 >',
                            style: TextStyle(
                              fontSize: 11,
                              color: subtitleColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    renderLast30DaysDakaStatus(),
                    const SizedBox(height: 10),
                    // 图例
                    Builder(builder: (context) {
                      int dakaedCount = 0;
                      int studiedCount = 0;
                      int notLoginCount = 0;
                      if (last30DaysDakaStatus != null) {
                        for (var s in last30DaysDakaStatus!) {
                          if (s == UserDayStatus.dakaed.json) {
                            dakaedCount++;
                          } else if (s == UserDayStatus.studied.json) {
                            studiedCount++;
                          } else {
                            notLoginCount++;
                          }
                        }
                      }
                      return Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildLegendItem('已打卡 ($dakaedCount)', dakaStatus2Color(UserDayStatus.dakaed.json)),
                              const SizedBox(width: 10),
                              _buildLegendItem('未打卡 ($studiedCount)', dakaStatus2Color(UserDayStatus.studied.json)),
                              const SizedBox(width: 10),
                              _buildLegendItem('未学习 ($notLoginCount)', dakaStatus2Color(UserDayStatus.notLogin.json)),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),

        // 4. 设置与工具卡片 (1:1 严格对齐原型结构与文案)
        Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDarkModeEnabled ? 0.3 : 0.03),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '设置与工具',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: textColor,
                  fontFamily: 'NotoSansSC',
                ),
              ),
              const SizedBox(height: 12),
              // 主题风格可视化选择卡片
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDarkModeEnabled ? const Color(0xFF131E1C) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor, width: 0.8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDarkModeEnabled ? 0.3 : 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.palette_outlined, size: 18, color: accentColor),
                          const SizedBox(width: 8),
                          Text(
                            '外观主题风格',
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: AppThemeStyle.values.map((style) {
                          final isSelected = context.watch<DarkMode>().themeStyle == style;
                          final cfg = AppThemeConfig.of(style);
                          return Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                context.read<DarkMode>().setThemeStyle(style);
                                MyDatabase.instance.localParamsDao.saveThemeStyle(style);
                                ToastUtil.info('已切换至「${style.label}」主题');
                              },
                              child: Container(
                                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? (isDarkModeEnabled ? cfg.primaryColor.withValues(alpha: 0.22) : cfg.primaryColor.withValues(alpha: 0.12))
                                      : (isDarkModeEnabled ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAF9)),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected
                                        ? cfg.primaryColor
                                        : (isDarkModeEnabled ? Colors.white12 : const Color(0xFFE2ECE8)),
                                    width: isSelected ? 1.6 : 1,
                                  ),
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      style.icon,
                                      size: 19,
                                      color: isSelected ? cfg.primaryColor : subtitleColor,
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      style.label,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                                        color: isSelected ? cfg.primaryColor : textColor,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              _buildMenuTile(
                icon: Icons.person_outline_rounded,
                title: '个人信息',
                trailingText: '编辑',
                onTap: () => showUpdateUserInfoDlg(),
              ),
              _buildMenuTile(
                icon: Icons.alarm_rounded,
                title: '学习提醒',
                trailingText: NotificationUtil.isReminderEnabled()
                    ? '每天 ${NotificationUtil.getReminderHour().toString().padLeft(2, '0')}:${NotificationUtil.getReminderMinute().toString().padLeft(2, '0')}'
                    : '已关闭',
                onTap: () async {
                  await context.push('/reminder_settings');
                  if (mounted) setState(() {});
                },
              ),
              _buildMenuTile(
                icon: Icons.chat_bubble_outline_rounded,
                title: '意见建议 / 客服',
                trailing: msgCount > 0
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: unreadMsgCount == 0 ? Colors.grey : const Color(0xFFFA6E59),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          unreadMsgCount == 0 ? msgCount.toString() : unreadMsgCount.toString(),
                          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      )
                    : null,
                onTap: () async {
                  if (Global.isGuest || loggedInUser == null) {
                    final shouldLogin = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        title: const Text('温馨提示', style: TextStyle(fontWeight: FontWeight.bold)),
                        content: const Text(
                          '当前处于游客模式，登录后方可提交意见并接收客服回复与活动兑换。\n\n是否前往登录？',
                          style: TextStyle(height: 1.4),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('取消', style: TextStyle(color: Colors.grey)),
                          ),
                          ElevatedButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            style: ElevatedButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('前往登录'),
                          ),
                        ],
                      ),
                    );
                    if (shouldLogin == true && mounted) {
                      context.push('/login');
                    }
                    return;
                  }
                  await context.push('/msg');
                  loadData();
                },
              ),
              _buildMenuTile(
                icon: Icons.cloud_sync_outlined,
                title: '端云同步状态',
                trailingText: _isLastSyncFailed ? '同步失败' : '已是最新',
                trailingTextColor: _isLastSyncFailed ? const Color(0xFFFA6E59) : const Color(0xFF18BA7C),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SyncLogViewerPage(),
                    ),
                  ).then((_) {
                    _checkSyncStatus();
                  });
                },
              ),
              _buildMenuTile(
                icon: Icons.health_and_safety_outlined,
                title: '数据健康检查',
                trailingText: '正常',
                onTap: () => _navigateToDataDiagnostic(),
              ),
              _buildMenuTile(
                icon: Icons.edit_note_rounded,
                title: '需求墙 / 功能投票',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const FeatureRequestWallPage()),
                  );
                },
              ),
              // 管理员专区
              if (loggedInUser?.isAdmin == true) ...[
                _buildMenuTile(
                  icon: Icons.eco_outlined,
                  title: '我的小天地 (农场)',
                  onTap: () => context.push('/farm'),
                ),
                _buildMenuTile(
                  icon: Icons.psychology_outlined,
                  title: '本地 AI 模型配置',
                  onTap: () => context.push('/ai_activation'),
                ),
                _buildMenuTile(
                  icon: Icons.access_time_filled_rounded,
                  title: '快进时间 (当前: ${AppClock.now().toString().substring(0, 10)})',
                  onTap: () {
                    AppClock.advanceDays(1);
                    setState(() {});
                    ToastUtil.success('时间已快进1天，新日期: ${AppClock.now().toString().substring(0, 10)}');
                  },
                ),
                _buildMenuTile(
                  icon: Icons.admin_panel_settings_outlined,
                  title: '系统管理后台',
                  onTap: () => context.push('/admin'),
                ),
                _buildMenuTile(
                  icon: Icons.pageview_outlined,
                  title: '页面查看器',
                  onTap: () => context.push('/page_viewer'),
                ),
                _buildMenuTile(
                  icon: Icons.storage_rounded,
                  title: '数据库查看器',
                  onTap: () => _openDbViewPage(),
                ),
              ],
              _buildMenuTile(
                icon: Icons.cleaning_services_outlined,
                title: '重建本地数据',
                onTap: () => _showWipeLocalDataDialog(),
                isDestructive: true,
              ),
              _buildMenuTile(
                icon: Icons.logout_rounded,
                title: '切换账号',
                trailingText: '切换',
                onTap: () async {
                  await Global.logout();
                  if (mounted) context.go('/login');
                },
              ),
              _buildMenuTile(
                icon: Icons.no_accounts_outlined,
                title: '注销账号',
                onTap: () => showUnRegisterDlg(),
                isDestructive: true,
                showDivider: false,
              ),
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
    final subtitleColor = isDarkModeEnabled ? const Color(0xFF8EA8A3) : const Color(0xFF5A7570);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: subtitleColor,
            fontWeight: FontWeight.w600,
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
                      decoration: const BoxDecoration(
                        color: Color(0xFF18BA7C),
                        borderRadius: BorderRadius.only(
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
                                                try {
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
                                                } catch (e, stackTrace) {
                                                  ErrorHandler.handleNetworkError(e, stackTrace, api: 'sendEmailCode', showToast: true);
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
          if (!mounted) return;
          context.go('/login');
        } else {
          ToastUtil.error(value.msg!);
        }
      });
    }
  }

  Color dakaStatus2Color(String dakaStatus) {
    if (dakaStatus == UserDayStatus.dakaed.json) {
      return isDarkMode ? const Color(0xFF2CD88F) : const Color(0xFF18BA7C); // 纯正扇贝翠绿
    } else if (dakaStatus == UserDayStatus.studied.json) {
      return const Color(0xFFFA6E59); // 珊瑚暖橙红
    } else {
      return isDarkMode ? Colors.white.withValues(alpha: 0.1) : Colors.white; // 未学习底
    }
  }

  ///最近30天打卡情况
  Widget renderLast30DaysDakaStatus() {
    if (last30DaysDakaStatus == null || last30DaysDakaStatus!.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const double gap = 4.0;
        final availableWidth = constraints.maxWidth;
        final boxWidth = (availableWidth - (9 * gap)) / 10;
        final boxHeight = boxWidth * 0.9;

        var rows = <Widget>[];
        var dayIndex = 0;
        for (int i = 0; i < 3; i++) {
          var dayBoxes = <Widget>[];
          for (int j = 0; j < 10; j++) {
            if (dayIndex >= last30DaysDakaStatus!.length) break;
            final status = last30DaysDakaStatus![dayIndex];
            final isNotLearned = status != UserDayStatus.dakaed.json && status != UserDayStatus.studied.json;
            
            var box = Container(
              margin: EdgeInsets.only(right: j < 9 ? gap : 0),
              width: boxWidth,
              height: boxHeight,
              decoration: BoxDecoration(
                color: dakaStatus2Color(status),
                borderRadius: BorderRadius.circular(6),
                border: isNotLearned
                    ? Border.all(color: isDarkMode ? Colors.white12 : Colors.black.withValues(alpha: 0.05), width: 1)
                    : null,
              ),
              child: dayIndex == 29
                  ? Center(
                      child: Text(
                        '今天',
                        style: const TextStyle(
                          fontSize: 8,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          height: 1.0,
                          fontFamily: 'NotoSansSC',
                        ),
                        textScaler: const TextScaler.linear(1.0),
                      ),
                    )
                  : null,
            );
            dayBoxes.add(box);
            dayIndex++;
          }
          rows.add(Padding(
            padding: EdgeInsets.only(bottom: i < 2 ? gap : 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: dayBoxes,
            ),
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

  // 统计项小卡片 (1:1 严格对齐原型：大字数值 + 小字标签，无多余图标)
  Widget _buildStatBox(bool isDarkMode, String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF1B2825) : const Color(0xFFEDF5F2),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: TextStyle(
                color: isDarkMode ? const Color(0xFFEAF7F4) : const Color(0xFF152724),
                fontSize: 18,
                fontWeight: FontWeight.w900,
                fontFamily: 'Roboto',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: isDarkMode ? const Color(0xFF8EA8A3) : const Color(0xFF5A7570),
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                fontFamily: 'NotoSansSC',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }


  // 打开数据库查看器
  void _openDbViewPage() {
    // 为查看器包裹一个局部主题，解决全局透明 AppBar 导致的图标白色不可见问题
    Navigator.of(context).push(MaterialPageRoute(
        builder: (context) => Theme(
              data: Theme.of(context).copyWith(
                appBarTheme: AppBarTheme(
                  backgroundColor: const Color(0xFF18BA7C),
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

  // 菜单项组件 (1:1 对齐原型极简温润风格)
  Widget _buildMenuTile({
    required IconData icon,
    required String title,
    String? trailingText,
    Color? trailingTextColor,
    Widget? trailing,
    required VoidCallback onTap,
    bool isDestructive = false,
    Color? iconColor,
    bool showDivider = true,
  }) {
    final isDarkModeEnabled = context.watch<DarkMode>().isDarkMode;
    final textColor = isDarkModeEnabled ? const Color(0xFFEAF7F4) : const Color(0xFF152724);
    final subtitleColor = isDarkModeEnabled ? const Color(0xFF8EA8A3) : const Color(0xFF5A7570);
    final iconBgColor = isDarkModeEnabled ? const Color(0xFF1B2825) : const Color(0xFFEDF5F2);
    final dividerColor = isDarkModeEnabled ? Colors.white.withValues(alpha: 0.06) : const Color(0x0F000000);

    final effectiveIconColor = iconColor ?? (isDestructive ? Colors.redAccent : subtitleColor);

    Widget trailingWidget;
    if (trailing != null) {
      trailingWidget = trailing;
    } else {
      trailingWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailingText != null) ...[
            Text(
              trailingText,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: trailingTextColor ?? subtitleColor,
                fontFamily: 'NotoSansSC',
              ),
            ),
            const SizedBox(width: 4),
          ],
          Icon(
            Icons.chevron_right_rounded,
            color: subtitleColor.withValues(alpha: 0.6),
            size: 16,
          ),
        ],
      );
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        decoration: BoxDecoration(
          border: showDivider ? Border(bottom: BorderSide(color: dividerColor, width: 0.8)) : null,
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isDestructive ? Colors.redAccent.withValues(alpha: 0.1) : iconBgColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: effectiveIconColor,
                size: 17,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: isDestructive ? Colors.redAccent : textColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  fontFamily: 'NotoSansSC',
                ),
              ),
            ),
            trailingWidget,
          ],
        ),
      ),
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
          content: const Text('清除所有本地数据(服务端数据不受影响)吗？\n系统将在清除前自动备份数据，并展示进度。'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('继续')),
          ],
        );
      },
    );

    if (choice == true) {
      if (!mounted) return;
      // 显示进度弹窗，并在该弹窗内完成同步和清空
      bool? finished = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const _RebuildDatabaseProgressDialog(),
      );

      if (finished == true) {
        // 全量清空后，必须回到登录页
        if (!mounted) return;
        context.go('/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final darkModeState = context.watch<DarkMode>();
    final isDarkModeEnabled = darkModeState.isDarkMode;
    final themeStyle = darkModeState.themeStyle;
    final backgroundColor = isDarkModeEnabled ? const Color(0xFF0C1312) : const Color(0xFFF5F9F7);

    return Scaffold(
      backgroundColor: backgroundColor,
      body: Stack(
        children: [
          Positioned.fill(
            child: AppThemeBackground(
              isDarkMode: isDarkModeEnabled,
              themeStyle: themeStyle,
            ),
          ),
          (studyProgress == null || last30DaysDakaStatus == null)
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

    // [性能优化] 使用 SQL 在数据库端聚合统计，避免每次渲染都把成千上万个单词拉到内存中进行 Set 操作
    int learned = await db.learningWordsDao.getLearningWordsCountInDicts(userId, [dictId]);
    int mastered = await db.masteredWordsDao.getMasteredWordsCountInDicts(userId, [dictId]);

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
    final masteredWords = masteredCount;
    final learningWords = learnedCount;
    final fetchWords = masteredWords + learningWords;

    final masteryProgress = (totalWords > 0 ? masteredWords / totalWords : 0.0).clamp(0.0, 1.0);
    final fetchProgress = (totalWords > 0 ? fetchWords / totalWords : 0.0).clamp(0.0, 1.0);

    final progressPercent = (masteryProgress * 100).toInt();

    final isDarkMode = context.watch<DarkMode>().isDarkMode;

    final textColor = isDarkMode ? const Color(0xFFEAF7F4) : const Color(0xFF152724);
    final subtitleColor = isDarkMode ? const Color(0xFF8EA8A3) : const Color(0xFF5A7570);
    final masteredColor = isDarkMode ? const Color(0xFF2CD88F) : const Color(0xFF18BA7C);
    final fetchColor = isDarkMode ? const Color(0xFF6EE7B7) : const Color(0xFF34D399);
    final borderColor = isDarkMode ? Colors.white.withValues(alpha: 0.08) : const Color(0x1418BA7C);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF162320) : const Color(0xFFF5F9F7),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. 上半部分：左侧环形进度 + 右侧（词书全名 + 掌握/取词统计）
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                builder: (context, animValue, child) {
                  return SizedBox(
                    width: 44,
                    height: 44,
                    child: CustomPaint(
                      painter: ThreeSegmentProgressPainter(
                        masteryProgress: masteryProgress * animValue,
                        fetchProgress: fetchProgress * animValue,
                        masteredColor: masteredColor,
                        fetchColor: fetchColor,
                        backgroundColor: isDarkMode ? Colors.white12 : const Color(0xFFE8F5EE),
                        dividerColor: isDarkMode ? const Color(0xFF162320) : const Color(0xFFF5F9F7),
                        strokeWidth: 4.0,
                      ),
                      child: Center(
                        child: Text(
                          '$progressPercent%',
                          style: TextStyle(
                            fontSize: 10,
                            color: masteredColor,
                            fontWeight: FontWeight.w900,
                            fontFamily: 'Roboto',
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 12),
              // 词书信息区：词书名独占第一行，统计文字独占第二行，绝无挤压！
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.dictInfo.name.replaceAll('.dict', ''),
                      style: TextStyle(
                        color: textColor,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        fontFamily: 'NotoSansSC',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '已掌握 $masteredWords · 已取词 $fetchWords / $totalWords 词',
                      style: TextStyle(
                        color: subtitleColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'NotoSansSC',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 2. 下半部分：三个按钮整齐排在同一行
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // 按钮 1：优先取词微胶囊
              GestureDetector(
                onTap: () async {
                  try {
                    final newPrivilegedStatus = await MyDatabase.instance.learningDictsDao
                        .togglePrivileged(currentLearningDict.userId, currentLearningDict.dictId, true);

                    if (mounted) {
                      setState(() {
                        currentLearningDict = LearningDict(
                          userId: currentLearningDict.userId,
                          dictId: currentLearningDict.dictId,
                          isPrivileged: newPrivilegedStatus,
                          fetchMastered: currentLearningDict.fetchMastered,
                          sortAlg: currentLearningDict.sortAlg,
                          createTime: currentLearningDict.createTime,
                          updateTime: currentLearningDict.updateTime,
                        );
                      });
                    }

                    ThrottledDbSyncService().requestSync();
                  } catch (error) {
                    Global.logger.d('切换优先取词状态失败: $error');
                    ToastUtil.error('操作失败，请重试');
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: currentLearningDict.isPrivileged
                        ? (isDarkMode ? masteredColor.withValues(alpha: 0.15) : const Color(0xFFE8F8F1))
                        : (isDarkMode ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9)),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: currentLearningDict.isPrivileged
                          ? masteredColor.withValues(alpha: 0.4)
                          : (isDarkMode ? Colors.white12 : Colors.black.withValues(alpha: 0.06)),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        currentLearningDict.isPrivileged ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        size: 12,
                        color: currentLearningDict.isPrivileged ? masteredColor : subtitleColor,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '优先取词',
                        style: TextStyle(
                          color: currentLearningDict.isPrivileged ? masteredColor : subtitleColor,
                          fontSize: 11,
                          fontWeight: currentLearningDict.isPrivileged ? FontWeight.w800 : FontWeight.w500,
                          fontFamily: 'NotoSansSC',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 按钮 2：查看词表
              GestureDetector(
                onTap: () async {
                  try {
                    await toDictWordsListPage(currentLearningDict.dictId, false);
                    widget.onDictChanged();
                  } catch (e) {
                    ToastUtil.error("无法打开词书");
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: isDarkMode ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDarkMode ? Colors.white12 : Colors.black.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.format_list_bulleted_rounded, size: 12, color: subtitleColor),
                      const SizedBox(width: 4),
                      Text(
                        '查看',
                        style: TextStyle(
                          color: subtitleColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'NotoSansSC',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 按钮 3：移出书桌
              GestureDetector(
                onTap: () => _handleDictDataAction(),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: isDarkMode ? 0.15 : 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.redAccent.withValues(alpha: isDarkMode ? 0.25 : 0.15),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.remove_circle_outline_rounded,
                        size: 13,
                        color: Colors.redAccent,
                      ),
                      const SizedBox(width: 3),
                      const Text(
                        '停学',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'NotoSansSC',
                        ),
                      ),
                    ],
                  ),
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
          ..where((lw) => lw.userId.equals(user.id) & (lw.stability.isNull() | lw.stability.isSmallerThanValue(Constants.graduationStability))))
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
                    child: const Text('停止学习并清除学习中单词'),
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
                    color: const Color(0xFF18BA7C).withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.remove_circle_outline, color: Color(0xFF18BA7C), size: 40),
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
                          backgroundColor: const Color(0xFF18BA7C),
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

class _RebuildDatabaseProgressDialog extends StatefulWidget {
  const _RebuildDatabaseProgressDialog();

  @override
  State<_RebuildDatabaseProgressDialog> createState() => _RebuildDatabaseProgressDialogState();
}

enum _StepStatus { pending, processing, completed, error }

class _RebuildDatabaseProgressDialogState extends State<_RebuildDatabaseProgressDialog> {
  _StepStatus _syncStatus = _StepStatus.processing;
  _StepStatus _wipeStatus = _StepStatus.pending;
  String? _error;

  @override
  void initState() {
    super.initState();
    _executeProcess();
  }

  Future<void> _executeProcess() async {
    // 步骤1: 同步备份
    try {
      await ThrottledDbSyncService().requestSyncAndWait(immediate: true);
      if (mounted) {
        setState(() {
          _syncStatus = _StepStatus.completed;
          _wipeStatus = _StepStatus.processing;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _syncStatus = _StepStatus.error;
          _error = '备份失败: $e';
        });
      }
      return; 
    }

    // 步骤2: 清空数据
    try {
      await Future.delayed(const Duration(milliseconds: 500));
      await MyDatabase.instance.wipeAllTables();
      if (mounted) {
        setState(() {
          _wipeStatus = _StepStatus.completed;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _wipeStatus = _StepStatus.error;
          _error = '清空失败: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF1E293B) : Colors.white;
    final textColor = isDarkMode ? Colors.white : const Color(0xFF1E293B);
    final subtitleColor = isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 30,
              offset: const Offset(0, 15),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '正在重建数据库',
              style: TextStyle(
                color: textColor,
                fontSize: 22,
                fontWeight: FontWeight.w900,
                fontFamily: 'NotoSansSC',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            _buildStepRow('1. 备份数据到云端', _syncStatus, isDarkMode, subtitleColor, textColor),
            const SizedBox(height: 16),
            _buildStepRow('2. 清空本地数据', _wipeStatus, isDarkMode, subtitleColor, textColor),
            if (_error != null) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withValues(alpha: 0.1)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.redAccent, fontSize: 12, fontFamily: 'Roboto'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 32),
            if (_syncStatus == _StepStatus.error) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        side: BorderSide(color: subtitleColor.withValues(alpha: 0.3)),
                      ),
                      child: const Text('取消'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _syncStatus = _StepStatus.completed; 
                          _wipeStatus = _StepStatus.processing;
                          _error = null;
                        });
                        _executeWipeOnly();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('忽略并清空'),
                    ),
                  ),
                ],
              ),
            ] else if (_wipeStatus == _StepStatus.completed || _wipeStatus == _StepStatus.error)
              ElevatedButton(
                onPressed: () => Navigator.pop(context, _wipeStatus == _StepStatus.completed),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text(
                  '完成',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, fontFamily: 'NotoSansSC'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _executeWipeOnly() async {
    try {
      await MyDatabase.instance.wipeAllTables();
      if (mounted) {
        setState(() {
          _wipeStatus = _StepStatus.completed;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _wipeStatus = _StepStatus.error;
          _error = '清空失败: $e';
        });
      }
    }
  }

  Widget _buildStepRow(String label, _StepStatus status, bool isDarkMode, Color subtitleColor, Color textColor) {
    Widget statusIcon;
    Color rowColor = subtitleColor;
    FontWeight fontWeight = FontWeight.normal;

    switch (status) {
      case _StepStatus.pending:
        statusIcon = Icon(Icons.circle_outlined, color: subtitleColor.withValues(alpha: 0.3), size: 20);
        break;
      case _StepStatus.processing:
        rowColor = textColor;
        fontWeight = FontWeight.normal;
        statusIcon = const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF3B82F6))),
        );
        break;
      case _StepStatus.completed:
        rowColor = const Color(0xFF10B981);
        fontWeight = FontWeight.normal;
        statusIcon = const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20);
        break;
      case _StepStatus.error:
        rowColor = const Color(0xFFEF4444);
        fontWeight = FontWeight.normal;
        statusIcon = const Icon(Icons.error_rounded, color: Color(0xFFEF4444), size: 20);
        break;
    }

    return Row(
      children: [
        statusIcon,
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            color: rowColor,
            fontSize: 16,
            fontWeight: fontWeight,
            fontFamily: 'NotoSansSC',
          ),
        ),
      ],
    );
  }
}

class ThreeSegmentProgressPainter extends CustomPainter {
  final double masteryProgress;
  final double fetchProgress;
  final Color masteredColor;
  final Color fetchColor;
  final Color backgroundColor;
  final Color dividerColor;
  final double strokeWidth;

  ThreeSegmentProgressPainter({
    required this.masteryProgress,
    required this.fetchProgress,
    required this.masteredColor,
    required this.fetchColor,
    required this.backgroundColor,
    required this.dividerColor,
    this.strokeWidth = 5.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final startAngle = -math.pi / 2; // 从 12 点钟方向开始

    // 1. 绘制背景圆环 (未学习部分)
    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(center, radius, bgPaint);

    // 2. 绘制取词进度圆环 (学习中部分)
    if (fetchProgress > masteryProgress) {
      final learningPaint = Paint()
        ..color = fetchColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;

      final start = startAngle + masteryProgress * 2 * math.pi;
      final sweep = (fetchProgress - masteryProgress) * 2 * math.pi;
      canvas.drawArc(rect, start, sweep, false, learningPaint);
    }

    // 3. 绘制已掌握进度圆环 (已掌握部分)
    if (masteryProgress > 0) {
      final masteredPaint = Paint()
        ..color = masteredColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;

      final sweep = masteryProgress * 2 * math.pi;
      canvas.drawArc(rect, startAngle, sweep, false, masteredPaint);
    }

    // 4. 在交界处绘制分割线 (用 cardBgColor 绘制)
    final dividerPaint = Paint()
      ..color = dividerColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final innerRadius = radius - strokeWidth / 2 - 0.5;
    final outerRadius = radius + strokeWidth / 2 + 0.5;

    // 已掌握与学习中的分割线
    if (masteryProgress > 0 && masteryProgress < 1.0 && fetchProgress > masteryProgress) {
      final angle = startAngle + masteryProgress * 2 * math.pi;
      final p1 = Offset(center.dx + math.cos(angle) * innerRadius, center.dy + math.sin(angle) * innerRadius);
      final p2 = Offset(center.dx + math.cos(angle) * outerRadius, center.dy + math.sin(angle) * outerRadius);
      canvas.drawLine(p1, p2, dividerPaint);
    }

    // 学习中与未学习的分割线
    if (fetchProgress > 0 && fetchProgress < 1.0 && fetchProgress != masteryProgress) {
      final angle = startAngle + fetchProgress * 2 * math.pi;
      final p1 = Offset(center.dx + math.cos(angle) * innerRadius, center.dy + math.sin(angle) * innerRadius);
      final p2 = Offset(center.dx + math.cos(angle) * outerRadius, center.dy + math.sin(angle) * outerRadius);
      canvas.drawLine(p1, p2, dividerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant ThreeSegmentProgressPainter oldDelegate) {
    return oldDelegate.masteryProgress != masteryProgress ||
        oldDelegate.fetchProgress != fetchProgress ||
        oldDelegate.masteredColor != masteredColor ||
        oldDelegate.fetchColor != fetchColor ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.dividerColor != dividerColor;
  }
}

class _PromoRedemptionWidget extends StatefulWidget {
  final PromoActivityVo? activePromo;
  final VoidCallback onRedeemSuccess;

  const _PromoRedemptionWidget({
    this.activePromo,
    required this.onRedeemSuccess,
  });

  @override
  State<_PromoRedemptionWidget> createState() => _PromoRedemptionWidgetState();
}

class _PromoRedemptionWidgetState extends State<_PromoRedemptionWidget> {
  final TextEditingController _controller = TextEditingController();
  bool _isRedeeming = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    final code = _controller.text.trim();
    if (code.isEmpty) {
      ToastUtil.error('请输入邀请码');
      return;
    }

    final user = Global.getLoggedInUser();
    if (user == null) {
      ToastUtil.error('请先登录');
      return;
    }

    setState(() {
      _isRedeeming = true;
    });

    try {
      final result = await Api.client.redeemPromoCode(user.id, code);
      if (result.success && result.data != null) {
        final updatedUserVo = result.data!;
        
        // 更新本地数据库及缓存
        await MyDatabase.instance.usersDao.saveUser(userVo2User(updatedUserVo), false);
        
        ToastUtil.success('兑换成功！您已获得会员权益');
        _controller.clear();
        widget.onRedeemSuccess();
      } else {
        ToastUtil.error(result.msg ?? '兑换失败');
      }
    } catch (e) {
      Global.logger.e('兑换活动码失败', error: e);
      ToastUtil.error('兑换出错，请稍后重试');
    } finally {
      if (mounted) {
        setState(() {
          _isRedeeming = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activePromo = widget.activePromo;
    // 只有在当前确实存在有效活动且开启了展示兑换框时才展示兑换组件
    if (activePromo == null || activePromo.showRedeemUi != true) {
      return const SizedBox.shrink();
    }

    final isDarkMode = context.watch<DarkMode>().isDarkMode;

    // 计算活动倒计时和剩余数量
    String? deadlineTip;
    String? remainingSlotsTip;
    bool isPromoValid = false;

    bool expired = false;
    bool full = false;

    if (activePromo.endTime != null) {
      final now = DateTime.now();
      final diff = activePromo.endTime!.difference(now);
      if (diff.isNegative) {
        expired = true;
      } else if (diff.inDays >= 1) {
        deadlineTip = '距截止剩 ${diff.inDays} 天';
      } else if (diff.inHours >= 1) {
        deadlineTip = '距截止剩 ${diff.inHours} 小时';
      } else if (diff.inMinutes > 0) {
        deadlineTip = '距截止剩 ${diff.inMinutes} 分钟';
      } else {
        deadlineTip = '今日即将截止';
      }
    }

    if (activePromo.maxRedemptions != null && activePromo.maxRedemptions! > 0) {
      final count = activePromo.redemptionCount ?? 0;
      final remain = math.max(0, activePromo.maxRedemptions! - count);
      if (remain <= 0) {
        full = true;
      } else {
        remainingSlotsTip = '仅剩 $remain 个名额';
      }
    }

    isPromoValid = !expired && !full;

    // 只有在当前确实存在有效活动时才展示兑换组件
    if (!isPromoValid) {
      return const SizedBox.shrink();
    }

    final hasPromoBanner = deadlineTip != null ||
        remainingSlotsTip != null ||
        (activePromo.name != null && activePromo.name!.isNotEmpty);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: isDarkMode ? Colors.white.withValues(alpha: 0.02) : Colors.grey.shade50,
        border: Border.all(color: isDarkMode ? Colors.white.withValues(alpha: 0.1) : Colors.grey.shade300, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasPromoBanner) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: isDarkMode ? Colors.amber.withValues(alpha: 0.1) : Colors.amber.shade50,
                border: Border.all(
                  color: isDarkMode ? Colors.amber.withValues(alpha: 0.25) : Colors.amber.shade200,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.local_fire_department_rounded, size: 16, color: Colors.amber.shade800),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (activePromo.name != null && activePromo.name!.isNotEmpty)
                          Text(
                            activePromo.name!,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: isDarkMode ? Colors.amber.shade200 : Colors.amber.shade900,
                            ),
                          ),
                        if (deadlineTip != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              color: Colors.amber.shade700.withValues(alpha: 0.15),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.timer_outlined, size: 12, color: isDarkMode ? Colors.amber.shade300 : Colors.amber.shade900),
                                const SizedBox(width: 3),
                                Text(
                                  deadlineTip,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: isDarkMode ? Colors.amber.shade300 : Colors.amber.shade900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (remainingSlotsTip != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              color: Colors.deepOrange.withValues(alpha: 0.12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.stars_rounded, size: 12, color: Colors.deepOrange.shade700),
                                const SizedBox(width: 3),
                                Text(
                                  remainingSlotsTip,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.deepOrange.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (activePromo.showCodeToUser == true &&
              activePromo.activityCode != null &&
              activePromo.activityCode!.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: isDarkMode ? Colors.blue.withValues(alpha: 0.12) : Colors.blue.shade50,
                border: Border.all(
                  color: isDarkMode ? Colors.blue.withValues(alpha: 0.25) : Colors.blue.shade200,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.card_giftcard_rounded, size: 15, color: Colors.blue.shade700),
                  const SizedBox(width: 6),
                  Text(
                    '活动码：',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDarkMode ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  SelectableText(
                    activePromo.activityCode!,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                      color: isDarkMode ? Colors.blue.shade300 : Colors.blue.shade800,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      _controller.text = activePromo.activityCode!;
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        color: Colors.blue.shade700,
                      ),
                      child: const Text(
                        '自动填入',
                        style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  style: const TextStyle(fontSize: 13),
                  decoration: InputDecoration(
                    hintText: '输入邀请码成为会员',
                    hintStyle: const TextStyle(fontSize: 13),
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _isRedeeming ? null : _redeem,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isRedeeming
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('兑换', style: TextStyle(fontSize: 13)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

