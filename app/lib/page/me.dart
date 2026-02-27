import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:day_night_switcher/day_night_switcher.dart';
import 'package:drift/drift.dart' as drift;
import 'package:drift_db_viewer/drift_db_viewer.dart';
import 'package:email_validator/email_validator.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/bo/user_bo.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/page/admin/exception_log_viewer.dart';
import 'package:nnbdc/page/admin/health_check.dart';
import 'package:nnbdc/page/admin/page_viewer.dart';
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

import "package:percent_indicator/percent_indicator.dart";
import 'package:provider/provider.dart';

import '../global.dart';
import '../state.dart';
import '../theme/app_theme.dart';
import '../util/level_util.dart';

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

  @override
  void initState() {
    super.initState();

    // 连接socket服务器
    SocketIoClient.instance.connect();

    // 保存监听器引用以便在dispose中移除
    _socketEventListener = (event, args) {
      if (event == 'persistentMsgCount' && mounted) {
        unreadMsgCount = args[0];
        msgCount = args[1];
        setState(() {});
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
      isDarkMode = await MyDatabase.instance.localParamsDao.getIsDarkMode();

      // 检查最近一次同步状态
      _isLastSyncFailed = await SyncLogService().isLastSyncFailed();

      if (Global.isGuest) {
        // 访客模式：直接使用本地用户信息
        final user = Global.getLoggedInUser();
        loggedInUser = user != null ? UserVo.fromUser(user) : null;
        if (mounted) {
          setState(() {
            email.text = '未登录';
            password.text = '';
            password2.text = '';
            nickname.text = loggedInUser?.displayNickName ?? '游客';
          });
        }
        // 访客不进行同步
      } else {
        var result0 = await UserBo().getLoggedInUser();
        if (result0.success) {
          if (mounted) {
            setState(() {
              loggedInUser = result0.data;
              email.text = loggedInUser!.email ?? '';
              password.text = '';
              password2.text = '';
              nickname.text = loggedInUser!.displayNickName!;
            });
          }
        } else {
          ToastUtil.error(result0.msg!);
          return;
        }

        // 检查并强制执行会员限制（非会员每日单词限额 20）
        await SubscriptionUtil.checkAndEnforceMemberLimits();

        // 同步数据库并下载词书
        // 使用异步方式，不阻塞页面加载，同步完成后自动显示下载进度对话框
        _syncAndDownloadDicts();
      }

      // 访客模式：直接检查并下载本地不存在的词书（异步，不阻塞页面）
      if (Global.isGuest) {
        _checkAndDownloadDicts();
      }

      // 从本地数据库获取用户学习进度
      final db = MyDatabase.instance;
      User? user = await db.usersDao.getUserById(loggedInUser!.id!);
      if (user == null) {
        Global.logger.d('User not found in local database for id: ${loggedInUser!.id}');
        return;
      }

      // 获取所有词书的学习状态
      var learningDicts = await MyDatabase.instance.learningDictsDao.getLearningDictsOfUser(user.id);

      // 获取词书中的唯一单词总数
      var dictWordIds = await (db.selectOnly(db.dictWords)
            ..addColumns([db.dictWords.wordId])
            ..where(db.dictWords.dictId.isIn(learningDicts.map((d) => d.dictId).toList())))
          .get();
      var uniqueWordIdsInDicts = dictWordIds.map((row) => row.read(db.dictWords.wordId)!).toSet();
      var rawWordCount = uniqueWordIdsInDicts.length;

      // 获取学习中的单词数量（只统计生命值大于0的且在当前所选词书中的单词）
      var allLearningWords = await (db.select(db.learningWords)
            ..where((lw) => lw.userId.equals(user.id))
            ..where((lw) => lw.lifeValue.isBiggerThanValue(0)))
          .get();
      var learningWordIds = allLearningWords.map((w) => w.wordId).toSet();
      var learningWordsInSelectedDictsCount = learningWordIds.intersection(uniqueWordIdsInDicts).length;
      var learningWordsCount = learningWordsInSelectedDictsCount;

      // 获取已掌握单词数量（从"已掌握"词书的dict_word中查询）
      var allMasteredWordIds = await db.masteredWordsDao.getMasteredWordIdSet(user.id);
      
      // 只统计当前所选词书中的已掌握单词，避免进度超过100%
      var masteredWordIdsInSelectedDicts = allMasteredWordIds.intersection(uniqueWordIdsInDicts);
      var masteredWordsCount = masteredWordIdsInSelectedDicts.length;

      // 判断是否所有词书都已学完(已经取不出词进入学习中单词池了)：学习中+已掌握 >= 总单词数
      var allDictsFinished = (learningWordsCount + masteredWordsCount) >= rawWordCount;

      // 使用LevelUtil根据掌握单词数计算等级
      LevelVo levelVo = LevelUtil.getLevelVoByWordCount(masteredWordsCount);

      if (mounted) {
        setState(() {
          studyProgress = StudyProgress(
            user.learnedDays,
            user.dakaDayCount,
            user.dakaRatio ?? 0.0,
            UserHelper.calculateTotalScore(user.gameScore, user.dakaScore),
            -1.0, // 排名信息通过API获取，初始化为-1表示未获取
            rawWordCount,
            user.cowDung,
            levelVo,
            masteredWordsCount, // 使用直接查询的结果而不是用户表中的字段
            learningWordsCount,
            user.wordsPerDay,
            user.continuousDakaDayCount,
            user.throwDiceChance,
            allDictsFinished,
            UserHelper.isTodayLearningFinishedFromUser(user),
            learningDicts,
            totalLearningSeconds: user.totalLearningSeconds ?? 0,
            todayLearningSeconds: user.todayLearningSeconds ?? 0,
          );
        });
      }

      // 访客和登录用户统一从本地数据库查询打卡状态
      var result2 = await UserBo().getDayStatuses(30);
      if (result2.success) {
        if (mounted) {
          setState(() {
            last30DaysDakaStatus = result2.data!;
          });
        }
      } else {
        // 查询失败时回退为默认状态
        if (mounted) {
          setState(() {
            last30DaysDakaStatus = List.filled(30, UserDayStatus.notLogin.json);
          });
        }
      }

      if (!Global.isGuest) {
        var result3 = await Api.client.getMsgCounts(loggedInUser!.id!);
        if (result3.success) {
          if (mounted) {
            setState(() {
              msgCount = result3.data!.first;
              unreadMsgCount = result3.data!.second;
            });
          }
        } else {
          ToastUtil.error(result3.msg!);
        }

        // 获取用户排名
        var result4 = await Api.client.getUserRank(loggedInUser!.id!);
        if (result4.success && studyProgress != null) {
          if (mounted) {
            setState(() {
              studyProgress!.userOrder = result4.data;
            });
          }
        } else if (!result4.success) {
          Global.logger.w("获取用户排名失败: ${result4.msg}");
        }
      } else {
        // 访客模式：初始化消息数为0
        if (mounted) {
          setState(() {
            msgCount = 0;
            unreadMsgCount = 0;
          });
        }
      }
    } catch (e, stackTrace) {
      // 区分网络异常和其他异常，给用户更明确的提示
      if (ErrorHandler.isNetworkError(e)) {
        ErrorHandler.handleNetworkError(
          e,
          stackTrace,
          api: 'loadData',
          showToast: true,
        );
      } else {
        // 非网络异常，使用通用错误处理
        ErrorHandler.handleError(
          e,
          stackTrace,
          userMessage: '加载数据失败，请刷新重试',
          logPrefix: '加载数据失败',
          showToast: true,
        );
      }
    } finally {
      // 重新启用loading提示
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
  Future<void> _syncAndDownloadDicts() async {
    try {
      // 等待同步完成
      await ThrottledDbSyncService().requestSyncAndWait(immediate: true);

      // 同步完成后，检查并下载词书
      await _checkAndDownloadDicts();
    } catch (e) {
      Global.logger.e("同步或下载词书失败: $e");
      // 同步失败不影响页面显示，静默处理
    }
  }

  /// 检查并下载本地缺失的词书
  /// 先检查通用词典，再检查用户选择的词书
  Future<void> _checkAndDownloadDicts() async {
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
      List<LearningDict> learningDicts = await MyDatabase.instance.learningDictsDao.getLearningDictsOfUser(loggedInUser!.id!);
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
    final textColor = isDarkModeEnabled ? Colors.white : const Color(0xFF2C3E50);
    final subtitleColor = isDarkModeEnabled ? Colors.white70 : const Color(0xFF7F8C8D);
    final numberColor = isDarkModeEnabled ? Colors.amber : const Color(0xFFE67E22);
    final highlightColor = isDarkModeEnabled ? Colors.greenAccent : const Color(0xFF27AE60);
    final iconColor = isDarkModeEnabled ? Colors.white70 : const Color(0xFF95A5A6);
    final cardColor = isDarkModeEnabled ? const Color(0xFF2D2D2D) : Colors.white;

    final borderColor = isDarkModeEnabled 
        ? Colors.white.withValues(alpha: 0.15) 
        : Colors.black.withValues(alpha: 0.05);

    final innerCardBgColor = isDarkModeEnabled
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.03);

    final innerCardBorderColor = isDarkModeEnabled
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.05);

    final progressTrackColor = isDarkModeEnabled
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.05);

    final starContainerColor = isDarkModeEnabled
        ? Colors.purpleAccent.withValues(alpha: 0.2)
        : Colors.orange.withValues(alpha: 0.1);

    return Column(
      children: [
        // 玻璃拟物化学习成就卡片 (Glassmorphism Achievement Card)
        Container(
          margin: EdgeInsets.symmetric(
            vertical: MediaQuery.of(context).size.width > 600 ? 16 : 12,
          ),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: isDarkModeEnabled ? const Color(0xFF2D2D2D) : const Color(0xFFF8F9FA),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: borderColor, width: 1.5),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. 头像和昵称行
              Row(
                children: [
                  // 头像
                  GestureDetector(
                    onTap: () => Get.toNamed('/email_login'),
                    child: Container(
                      padding: const EdgeInsets.all(2), // 边框间距
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: LevelUtil.getTitleColor(studyProgress!.level.level ?? 1),
                      ),
                      child: CircleAvatar(
                        radius: MediaQuery.of(context).size.width > 600 ? 32 : 28,
                        backgroundColor: const Color(0xFF1A1A2E),
                        backgroundImage: (loggedInUser?.wechatAvatar != null && loggedInUser!.wechatAvatar!.isNotEmpty)
                            ? CachedNetworkImageProvider(loggedInUser!.wechatAvatar!)
                            : null,
                        child: (loggedInUser?.wechatAvatar == null || loggedInUser!.wechatAvatar!.isEmpty)
                            ? Icon(Icons.person, color: iconColor, size: 30)
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
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
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
                  // 右上角浮动气泡/等级
                  GestureDetector(
                    onTap: () {
                      Get.to(() => LevelPathPage(currentLevel: studyProgress!.level.level ?? 1));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: innerCardBgColor,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: innerCardBorderColor, width: 1),
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
                              color: textColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
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
                        valueColor: AlwaysStoppedAnimation<Color>(iconColor),
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

              // 2. DAILY MILESTONE 进度条标题
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "词书总进度",
                    style: TextStyle(
                      color: textColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                  Text(
                    '已掌握 ${((studyProgress!.rawWordCount > 0 ? studyProgress!.masteredWordsCount / studyProgress!.rawWordCount : 0.0) * 100).toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: highlightColor,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 发光进度条
              Container(
                height: 8,
                width: double.infinity,
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: progressTrackColor,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final progress = studyProgress!.rawWordCount > 0 ? studyProgress!.masteredWordsCount / studyProgress!.rawWordCount : 0.0;
                    final clampedProgress = progress > 1.0 ? 1.0 : progress;
                    return Container(
                      width: constraints.maxWidth * clampedProgress,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF007F),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),

              // 3. 数据小卡片行 (Glass Cards)
              Row(
                children: [
                  // 卡片 1: DAY Circle
                  Expanded(
                    flex: 1,
                    child: AspectRatio(
                      aspectRatio: 1.0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: innerCardBgColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: innerCardBorderColor),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 70,
                              height: 70,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: numberColor, width: 2),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    "学习天数",
                                    style: TextStyle(
                                      color: numberColor,
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    textScaler: const TextScaler.linear(1.0),
                                  ),
                                  Text(
                                    studyProgress!.existDays.toString(),
                                    style: TextStyle(
                                      color: textColor,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                    ),
                                    textScaler: const TextScaler.linear(1.0),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 卡片 2: Words Learned
                  Expanded(
                    flex: 1,
                    child: AspectRatio(
                      aspectRatio: 1.0,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: innerCardBgColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: innerCardBorderColor),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_box_outlined, color: numberColor, size: 24),
                            const SizedBox(height: 2),
                            Text(
                              studyProgress!.masteredWordsCount.toString(),
                              style: TextStyle(
                                color: isDarkModeEnabled ? Colors.white : Colors.black,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              textScaler: const TextScaler.linear(1.0),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "已掌握\n单词",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: subtitleColor, fontSize: 9, height: 1.1),
                              textScaler: const TextScaler.linear(1.0),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 卡片 3: Learning Duration
                  Expanded(
                    flex: 1,
                    child: AspectRatio(
                      aspectRatio: 1.0,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: innerCardBgColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: innerCardBorderColor),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.schedule, color: numberColor, size: 24),
                            const SizedBox(height: 2),
                            Text(
                              (studyProgress!.totalLearningSeconds / 3600.0).toStringAsFixed(1),
                              style: TextStyle(
                                color: isDarkModeEnabled ? Colors.white : Colors.black,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                              textScaler: const TextScaler.linear(1.0),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "学习总\n时长(时)",
                              textAlign: TextAlign.center,
                              style: TextStyle(color: subtitleColor, fontSize: 9, height: 1.1),
                              textScaler: const TextScaler.linear(1.0),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 4. Milestone Achieved Banner (Glassmorphism)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: innerCardBgColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: innerCardBorderColor),
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
                              fontSize: 14,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "掌握单词: ${studyProgress!.masteredWordsCount} | 超过了: ${studyProgress!.userOrder! < 0 ? '暂无' : '${studyProgress!.userOrder!.toStringAsFixed(2)}%的用户'}",
                            style: TextStyle(
                              color: numberColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // 一个上扬的星星图标效果
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: starContainerColor,
                      ),
                      child: Icon(Icons.leaderboard_rounded, color: numberColor, size: 32),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // 5. 会员状况/订阅入口 (放在卡片内底部)
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
                                '解锁 100+ 每日单词及更多专属特权',
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

                if (isPremium && premiumInfoText != null && PlatformUtils.isIOS) {
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

        // 学习设置卡片
        Container(
          margin: EdgeInsets.symmetric(
            vertical: MediaQuery.of(context).size.width > 600 ? 8 : 6,
          ),
          padding: EdgeInsets.all(MediaQuery.of(context).size.width > 600 ? 16 : 12),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 学习按钮
              SizedBox(
                width: double.infinity,
                child: last30DaysDakaStatus![29] == UserDayStatus.dakaed.json
                    ? GestureDetector(
                        onTap: () {},
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            '✓ 今日已打卡',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.green,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              height: 1.2,
                              fontFamily: 'NotoSansSC',
                            ),
                            textScaler: const TextScaler.linear(1.0),
                          ),
                        ),
                      )
                    : ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: AppTheme.primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.school, color: Colors.white, size: 20),
                        label: Text(
                          '开始学习',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            height: 1.2,
                            fontFamily: 'NotoSansSC',
                          ),
                          textScaler: const TextScaler.linear(1.0),
                        ),
                        onPressed: () {
                          Get.toNamed('/before_bdc');
                        },
                      ),
              ),
            ],
          ),
        ),

        // 夜间模式切换卡片
        Container(
          margin: EdgeInsets.symmetric(
            vertical: MediaQuery.of(context).size.width > 600 ? 8 : 6,
          ),
          padding: EdgeInsets.all(MediaQuery.of(context).size.width > 600 ? 16 : 12),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    isDarkModeEnabled ? Icons.dark_mode : Icons.light_mode,
                    color: AppTheme.primaryColor,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '夜间模式',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                      height: 1.2,
                      fontFamily: 'NotoSansSC',
                    ),
                    textScaler: const TextScaler.linear(1.0),
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

        // 订阅入口已移动到“学习设置/今日单词”上方


        // 打卡统计卡片
        Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '打卡统计',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                  height: 1.2,
                  fontFamily: 'NotoSansSC',
                ),
                textScaler: const TextScaler.linear(1.0),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildProgressItem(
                    '打卡天数',
                    studyProgress!.dakaDayCount.toString(),
                    Icons.calendar_today,
                    const Color(0xFF3498DB),
                  ),
                  _buildProgressItem(
                    '打卡率',
                    '${(studyProgress!.dakaRatio! * 100).toStringAsFixed(1)}%',
                    Icons.analytics,
                    const Color(0xFF9B59B6),
                  ),
                  _buildProgressItem(
                    '魔法泡泡',
                    studyProgress!.cowDung.toString(),
                    Icons.water_drop,
                    const Color(0xFFE67E22),
                    rotationAngle: 3.14159, // 180度 = π 弧度
                  ),
                ],
              ),
            ],
          ),
        ),

        // 最近30天打卡情况卡片
        Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '最近30天学习情况',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                  height: 1.2,
                  fontFamily: 'NotoSansSC',
                ),
                textScaler: const TextScaler.linear(1.0),
              ),
              const SizedBox(height: 16),
              renderLast30DaysDakaStatus(),
              const SizedBox(height: 12),
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

        // 词书管理卡片
        Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.primaryLightColor.withValues(alpha: 0.3), // 保留一点主色调作为底色
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '我的书桌',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w400,
                      color: Colors.white,
                      height: 1.6,
                      letterSpacing: 1.5,
                      fontFamily: null, // 使用系统默认字体
                      decoration: TextDecoration.none,
                    ),
                    textScaler: const TextScaler.linear(1.0),
                  ),
                  OutlinedButton.icon(
                    key: const Key('me_choose_book_btn'),
                    icon: const Icon(Icons.add, color: Colors.white, size: 16),
                    label: const Text(
                      '选择词书',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    onPressed: () {
                      Get.toNamed("/select_book")!.then((value) {
                        loadData();
                      });
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FutureBuilder<Widget>(
                future: renderLearningDicts(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Colors.white));
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Error: ${snapshot.error}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    );
                  }
                  return snapshot.data ??
                      Container(
                        padding: const EdgeInsets.all(16),
                        child: const Text(
                          '暂无词书，点击上方按钮添加',
                          style: TextStyle(color: Colors.white70, fontSize: 14),
                          textAlign: TextAlign.center,
                        ),
                      );
                },
              ),
            ],
          ),
        ),

        // 账户管理卡片
        Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '账户管理',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 16),
              _buildMenuTile(
                icon: Icons.person,
                title: '个人信息',
                onTap: () => showUpdateUserInfoDlg(),
              ),
              _buildMenuTile(
                icon: Icons.feedback,
                title: '意见建议',
                trailing: msgCount > 0
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: unreadMsgCount == 0 ? Colors.grey : Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          unreadMsgCount == 0 ? msgCount.toString() : unreadMsgCount.toString(),
                          style: const TextStyle(color: Colors.white, fontSize: 12),
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
                  icon: Icons.eco,
                  title: '我的小天地',
                  onTap: () {
                    Get.toNamed('/farm');
                  },
                ),
              // AI 助教 - 仅管理员可见
              if (loggedInUser?.isAdmin == true)
                _buildMenuTile(
                  icon: Icons.psychology,
                  title: 'AI 助教',
                  onTap: () {
                    Get.toNamed('/ai_activation');
                  },
                ),
              _buildMenuTile(
                icon: Icons.rate_review,
                title: '需求墙',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const FeatureRequestWallPage()),
                  );
                },
              ),
              _buildMenuTile(
                icon: Icons.swap_horiz,
                title: '切换账号',
                onTap: () => Get.toNamed('/email_login'),
              ),
              _buildMenuTile(
                icon: Icons.delete_forever,
                title: '注销账号',
                onTap: () => showUnRegisterDlg(),
                isDestructive: true,
              ),

              // 杂项
              Builder(
                builder: (context) {
                  final isDarkModeEnabled = context.watch<DarkMode>().isDarkMode;
                  return Divider(
                    color: isDarkModeEnabled ? Colors.grey[700] : Colors.grey[300],
                    height: 32,
                    thickness: 1,
                  );
                },
              ),
              Builder(
                builder: (context) {
                  final isDarkModeEnabled = context.watch<DarkMode>().isDarkMode;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      '杂项',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDarkModeEnabled ? Colors.grey[400] : const Color(0xFF7F8C8D),
                      ),
                    ),
                  );
                },
              ),
              _buildMenuTile(
                icon: Icons.health_and_safety,
                title: '健康检查',
                onTap: () => _navigateToDataDiagnostic(),
              ),
              _buildMenuTile(
                icon: Icons.cloud_sync,
                title: '云同步${_isLastSyncFailed ? "(失败)" : ""}',
                iconColor: _isLastSyncFailed ? Colors.red : null,
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
                icon: Icons.cleaning_services,
                title: '清空本地数据',
                onTap: () => _showWipeLocalDataDialog(),
                isDestructive: true,
              ),
              // 管理员功能入口
              if (loggedInUser?.isAdmin == true) ...[
                const Divider(),
                _buildMenuTile(
                  icon: Icons.admin_panel_settings,
                  title: '系统管理',
                  onTap: () => Get.toNamed('/admin'),
                ),
                _buildMenuTile(
                  icon: Icons.storage,
                  title: '数据库查看器(版本:${MyDatabase.instance.schemaVersion})',
                  onTap: () => _openDbViewPage(),
                ),
                _buildMenuTile(
                  icon: Icons.pageview,
                  title: '页面查看器',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const PageViewerPage(),
                      ),
                    );
                  },
                ),
                _buildMenuTile(
                  icon: Icons.bug_report,
                  title: '异常日志',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const ExceptionLogViewerPage(),
                      ),
                    );
                  },
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

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isDarkModeEnabled ? Colors.grey[400] : const Color(0xFF7F8C8D),
            height: 1.3,
            letterSpacing: 0.3,
            fontWeight: FontWeight.w400,
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
                                        onPressed: (cooldown > 0 || isSendingCode) ? null : () async {
                                          if (!EmailValidator.validate(email.text)) {
                                            ToastUtil.error("请输入有效的邮箱地址");
                                            return;
                                          }
                                          setDialogState(() {
                                            isSendingCode = true;
                                          });
                                          var result = await Api.client.sendEmailCode(email.text, "BIND_EMAIL");
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
                                        child: isSendingCode ? 
                                              const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : 
                                              Text(cooldown > 0 ? '${cooldown}s' : '获取验证码'),
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
                                          var result = await Api.client.verifyEmailCode(email.text, codeController.text, "BIND_EMAIL");
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
      // 密码被取消后，传入原来的密码 (这里用空字符串，后端/UserBo里处理空字符串就不修改密码)
      UserBo().updateUserInfo(email.text, nickname.text, '', '', Global.getLoggedInUser()!.id).then((value) async {
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
        validator: validator,
        onChanged: onChanged,
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
          Get.toNamed('/email_login');
        } else {
          ToastUtil.error(value.msg!);
        }
      });
    }
  }

  Color dakaStatus2Color(String dakaStatus) {
    if (dakaStatus == UserDayStatus.dakaed.json) {
      return Colors.lightGreen;
    } else if (dakaStatus == UserDayStatus.studied.json) {
      return const Color(0xccff6347);
    } else {
      return const Color(0x77777777);
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
  Widget _buildProgressItem(String title, String value, IconData icon, Color color, {double? rotationAngle}) {
    final isDarkModeEnabled = context.watch<DarkMode>().isDarkMode;

    Widget iconWidget = Icon(icon, color: color, size: 24);
    if (rotationAngle != null) {
      iconWidget = Transform.rotate(
        angle: rotationAngle,
        child: iconWidget,
      );
    }

    return Column(
      children: [
        iconWidget,
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            color: isDarkModeEnabled ? Colors.grey[400] : const Color(0xFF7F8C8D),
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
    final textColor = isDarkModeEnabled ? Colors.white : const Color(0xFF2C3E50);

    return ListTile(
      leading: Icon(
        icon,
        color: iconColor ?? (isDestructive ? Colors.red : const Color(0xFF3498DB)),
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isDestructive ? Colors.red : textColor,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: trailing ??
          Icon(
            Icons.chevron_right,
            color: isDarkModeEnabled ? Colors.grey[400] : const Color(0xFF7F8C8D),
          ),
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
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
          Get.offAllNamed('/email_login');
        },
        operationName: '重建数据库',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkModeEnabled = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkModeEnabled ? const Color(0xFF1A1A1A) : const Color(0xFFF5F5F5);

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

    // 获取学习中的单词（生命值>0）
    final learningWords = await (db.select(db.learningWords)..where((lw) => lw.userId.equals(userId) & lw.lifeValue.isBiggerThanValue(0))).get();
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
    final progress = totalWords > 0 ? learnedWords / totalWords : 0.0;
    final progressPercent = (progress * 100).toInt();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
      ),
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
                    radius: 25.0,
                    lineWidth: 4.0,
                    percent: progress,
                    backgroundColor: Colors.white.withValues(alpha: 0.3),
                    progressColor: Colors.white, // 使用白色，与绿色渐变背景形成对比
                    circularStrokeCap: CircularStrokeCap.round,
                  ),
                  Text(
                    '$progressPercent%',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 16),
              // 词书信息
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.dictInfo.name.replaceAll('.dict', ''),
                        key: Key('me_dict_name_${widget.learningDict.dictId}'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 19,
                          fontWeight: FontWeight.w300,
                          height: 1.6,
                          letterSpacing: 1.2,
                          fontFamily: null,
                          decoration: TextDecoration.none,
                        ),
                        overflow: TextOverflow.ellipsis,
                        textScaler: const TextScaler.linear(1.0),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.dictInfo.name == '生词本'
                            ? '$masteredCount / ${actualWordCount ?? 0}'
                            : '$masteredCount / ${widget.dictInfo.wordCount}',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.8),
                          fontSize: 14,
                          height: 1.3,
                          letterSpacing: 0.3,
                          fontWeight: FontWeight.w400,
                          fontFamily: 'NotoSansSC',
                        ),
                        textScaler: const TextScaler.linear(1.0),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 操作按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildDictCheckbox(
                label: '优先取词',
                value: currentLearningDict.isPrivileged,
                onChanged: (bool? value) async {
                  if (value != null) {
                    try {
                      final newPrivilegedStatus =
                          await MyDatabase.instance.learningDictsDao.togglePrivileged(currentLearningDict.userId, currentLearningDict.dictId, true);

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
              _buildDictActionButton(
                icon: Icons.list_alt,
                label: '单词列表',
                isActive: true,
                onTap: () async {
                  try {
                    await toDictWordsListPage(currentLearningDict.dictId, false);
                    widget.onDictChanged();
                  } catch (e) {
                    ToastUtil.error("无法打开词书");
                  }
                },
              ),
              _buildDictActionButton(
                icon: Icons.remove_circle_outline,
                label: '移出',
                isActive: true,
                isDestructive: true,
                onTap: () => _handleDictDataAction(),
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

    // 2. 查询用户所有学习中的单词（lifeValue > 0）
    final learningWords = await (db.select(db.learningWords)..where((lw) => lw.userId.equals(user.id) & lw.lifeValue.isBiggerThanValue(0))).get();

    if (!mounted) return;

    // 3. 获取用户书桌上的所有其他词书 ID
    final otherLearningDicts = await (db.select(db.learningDicts)..where((ld) => ld.userId.equals(user.id) & ld.dictId.isNotValue(currentLearningDict.dictId)))
        .get();
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
                  '确认移出书桌',
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
                    child: const Text('移出书桌并删除学习记录'),
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
                    child: const Text('仅移出书桌'),
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

  // 词书操作按钮组件
  Widget _buildDictActionButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isActive ? (isDestructive ? Colors.red[300] : Colors.white) : Colors.white.withValues(alpha: 0.6),
              size: 20,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.6),
                fontSize: 13,
                fontWeight: FontWeight.w300,
                height: 1.5,
                letterSpacing: 0.6,
                fontFamily: null,
              ),
              textScaler: const TextScaler.linear(1.0),
            ),
          ],
        ),
      ),
    );
  }

  // 词书复选框组件
  Widget _buildDictCheckbox({
    required String label,
    required bool value,
    required ValueChanged<bool?> onChanged,
  }) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.3),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: Colors.white,
              checkColor: const Color(0xFF0097A7),
              side: BorderSide(
                color: Colors.white.withValues(alpha: 0.6),
                width: 1.5,
              ),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w300,
                height: 1.5,
                letterSpacing: 0.6,
                fontFamily: null,
              ),
              textScaler: const TextScaler.linear(1.0),
            ),
          ],
        ),
      ),
    );
  }
}
