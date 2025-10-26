import 'package:day_night_switcher/day_night_switcher.dart';
import 'package:drift_db_viewer/drift_db_viewer.dart';
import 'package:email_validator/email_validator.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/bo/user_bo.dart';
import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:drift/drift.dart' as drift;
import 'package:nnbdc/page/select_book.dart';
import 'package:nnbdc/util/error_handler.dart';
import 'package:nnbdc/util/app_clock.dart';

import 'package:nnbdc/page/word_list/learning_words.dart';
import 'package:nnbdc/page/word_list/mastered_words.dart';
import 'package:nnbdc/page/word_list/dict_words.dart';
import 'package:nnbdc/services/throttled_sync_service.dart';
import 'package:nnbdc/socket_io.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/utils.dart';
import "package:percent_indicator/percent_indicator.dart";
import 'package:provider/provider.dart';
import 'package:nnbdc/widget/dict_download_dialog.dart';
import 'package:nnbdc/page/admin/data_diagnostic.dart';

import '../config.dart';
import '../global.dart';
import '../state.dart';
import '../theme/app_theme.dart';

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

    super.dispose();
  }

  Future<void> loadData() async {
    // 禁用loading提示
    Api.setLoadingDisabled(true);

    try {
      isDarkMode = await MyDatabase.instance.localParamsDao.getIsDarkMode();

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

      // 同步数据库：检查是否有本地学习词书，决定是否等待同步完成
      final existingLearningDicts = await MyDatabase.instance.learningDictsDao.getLearningDictsOfUser(loggedInUser!.id!);
      if (existingLearningDicts.isNotEmpty) {
        // 有本地词书，异步同步即可
        ThrottledDbSyncService().requestSync();
      } else {
        // 没有本地词书，等待同步完成以获取用户词书数据
        await ThrottledDbSyncService().requestSync();
      }

      // 下载本地数据库不存在的词书
      try {
        // 先检查并下载通用词典
        var db = MyDatabase.instance;
        bool hasWords = await db.dictWordsDao.hasDictWords(Global.commonDictId);
        if (!hasWords) {
          // 通用词典中没有单词，需要下载
          Global.logger.i("通用词典存在但没有单词，需要下载");
          if (mounted) {
            await _showDictDownloadDialog([DictVo(Global.commonDictId, '通用词典', '通用词典', null, true, true, true, null, 0, AppClock.now())]);
          }
        } else {
          Global.logger.i("通用词典已存在且包含单词，无需下载");
        }

        // 再下载用户选择的词书
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
              var dictRes = await SelectBookPageState.getDictRes(learningDict.dictId);
              if (dictRes?.dict?.name != null) {
                dictName = dictRes!.dict!.name;
              }
            } catch (e) {
              Global.logger.e("获取词书名称失败: $e");
            }

            // 将dictName处理为无后缀的短名称
            String shortName = getShortName(dictName);

            dictsToDownload.add(DictVo(learningDict.dictId, dictName, shortName, null, true, true, true, null, 0, AppClock.now()));
          } else {
            // 词书存在，但只有当owner是系统用户(系统词书)时才需要检查是否有单词
            if (existing.ownerId == Global.sysUserId) {
              bool hasWords = await db.dictWordsDao.hasDictWords(learningDict.dictId);
              if (!hasWords) {
                // 系统词书中没有单词，需要下载
                Global.logger.i("系统词书存在但没有单词，需要下载: ${learningDict.dictId}");

                // 将dictName处理为无后缀的短名称
                String shortName = getShortName(existing.name);

                dictsToDownload.add(DictVo(learningDict.dictId, existing.name, shortName, null, true, true, true, null, 0, AppClock.now()));
              } else {
                Global.logger.i("系统词书已存在且包含单词，无需下载, 词书ID: ${learningDict.dictId}");
              }
            } else {
              Global.logger.i("非系统词书已存在，无需检查单词数量, 词书ID: ${learningDict.dictId}");
            }
          }
        }

        // 如果有需要下载的词书，显示下载对话框
        if (dictsToDownload.isNotEmpty && mounted) {
          await _showDictDownloadDialog(dictsToDownload);
        }
      } catch (e) {
        Global.logger.e("下载用户词书失败: $e");
        ToastUtil.error("部分词书下载失败，请重试");
      }

      // 从本地数据库获取用户学习进度
      User? user = await MyDatabase.instance.usersDao.getUserById(loggedInUser!.id!);
      if (user == null) {
        Global.logger.d('User not found in local database for id: ${loggedInUser!.id}');
        return;
      }

      // 获取用户等级
      var db = MyDatabase.instance;
      var level = await (db.select(db.levels)..where((l) => l.id.equals(user.levelId))).getSingleOrNull();

      if (level != null) {
        // 获取学习中的单词数量（只统计生命值大于0的单词）
        var learningWords = await (db.select(db.learningWords)
              ..where((lw) => lw.userId.equals(user.id))
              ..where((lw) => lw.lifeValue.isBiggerThanValue(0)))
            .get();
        var learningWordsCount = learningWords.length;

        // 获取所有词书的学习状态
        var learningDicts = await MyDatabase.instance.learningDictsDao.getLearningDictsOfUser(user.id);
        var allDictsFinished = true;
        for (var dict in learningDicts) {
          var dictInfo = await MyDatabase.instance.dictsDao.findById(dict.dictId);
          if (dictInfo != null && (dict.currentWordSeq ?? 0) < dictInfo.wordCount) {
            allDictsFinished = false;
          }
        }

        // 获取词书中的单词总数
        var dictWords = await (db.select(db.dictWords)..where((dw) => dw.dictId.isIn(learningDicts.map((d) => d.dictId).toList()))).get();
        var rawWordCount = dictWords.length;

        // 获取已掌握单词数量（直接从mastered_words表查询，确保准确）
        var masteredWordsQuery = db.selectOnly(db.masteredWords)
          ..addColumns([drift.countAll()])
          ..where(db.masteredWords.userId.equals(user.id));
        var masteredWordsResult = await masteredWordsQuery.getSingle();
        var masteredWordsCount = masteredWordsResult.read(drift.countAll()) ?? 0;

        if (mounted) {
          setState(() {
            studyProgress = StudyProgress(
              user.learnedDays,
              user.dakaDayCount,
              user.dakaRatio ?? 0.0,
              user.totalScore,
              -1, // 排名信息通过API获取，初始化为-1表示未获取
              rawWordCount,
              user.cowDung,
              LevelVo(level.id)..name = level.name,
              masteredWordsCount, // 使用直接查询的结果而不是用户表中的字段
              learningWordsCount,
              user.wordsPerDay,
              user.continuousDakaDayCount,
              user.throwDiceChance,
              allDictsFinished,
              user.isTodayLearningFinished,
              learningDicts,
            );
          });
        }
      } else {
        ToastUtil.error("获取用户等级失败");
      }

      var result2 = await UserBo().getDayStatuses(30);
      if (result2.success) {
        if (mounted) {
          setState(() {
            last30DaysDakaStatus = result2.data!;
          });
        }
      } else {
        ToastUtil.error(result2.msg!);
      }

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
        },
      ),
    );
  }

  Widget renderStudyProgress() {
    final isDarkModeEnabled = context.watch<DarkMode>().isDarkMode;
    final textColor = isDarkModeEnabled ? Colors.white : Colors.black;
    final cardColor = isDarkModeEnabled ? const Color(0xFF2D2D2D) : Colors.white;

    return Column(
      children: [
        // 用户头像和基本信息卡片
        Container(
          margin: EdgeInsets.symmetric(
            vertical: MediaQuery.of(context).size.width > 600 ? 16 : 12,
          ),
          padding: EdgeInsets.all(MediaQuery.of(context).size.width > 600 ? 20 : 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppTheme.primaryLightColor, AppTheme.primaryDarkColor],
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryColor.withValues(alpha: 0.3),
                spreadRadius: 2,
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              // 用户头像
              Container(
                width: MediaQuery.of(context).size.width > 600 ? 80 : 60,
                height: MediaQuery.of(context).size.width > 600 ? 80 : 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.2),
                  border: Border.all(color: Colors.white, width: 3),
                ),
                child: Icon(
                  Icons.person,
                  size: MediaQuery.of(context).size.width > 600 ? 40 : 30,
                  color: Colors.white,
                ),
              ),
              SizedBox(height: MediaQuery.of(context).size.width > 600 ? 12 : 8),
              // 用户昵称
              Text(
                Util.getNickNameOfUser(loggedInUser),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: MediaQuery.of(context).size.width > 600 ? 20 : 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              // 同步状态指示器
              if (_isSyncing) ...[
                SizedBox(height: MediaQuery.of(context).size.width > 600 ? 8 : 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: MediaQuery.of(context).size.width > 600 ? 16 : 12,
                      height: MediaQuery.of(context).size.width > 600 ? 16 : 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    SizedBox(width: MediaQuery.of(context).size.width > 600 ? 8 : 6),
                    Text(
                      '同步中...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: MediaQuery.of(context).size.width > 600 ? 12 : 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
              SizedBox(height: MediaQuery.of(context).size.width > 600 ? 8 : 6),
              // 等级信息
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  studyProgress!.level.name!,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: MediaQuery.of(context).size.width > 600 ? 14 : 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              SizedBox(height: MediaQuery.of(context).size.width > 600 ? 16 : 12),
              // 学习天数
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    studyProgress!.existDays.toString(),
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: MediaQuery.of(context).size.width > 600 ? 32 : 24,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '天',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: MediaQuery.of(context).size.width > 600 ? 16 : 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // 今日打卡状态
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: last30DaysDakaStatus![29] == UserDayStatus.dakaed.json
                      ? Colors.green.withValues(alpha: 0.8)
                      : Colors.orange.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Text(
                  last30DaysDakaStatus![29] == UserDayStatus.dakaed.json ? '✓ 今日已打卡' : '○ 今日未打卡',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: MediaQuery.of(context).size.width > 600 ? 12 : 10,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
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
            boxShadow: [
              BoxShadow(
                color: isDarkModeEnabled ? Colors.black.withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.1),
                spreadRadius: 1,
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '学习设置',
                style: TextStyle(
                  fontSize: MediaQuery.of(context).size.width > 600 ? 18 : 16,
                  fontWeight: FontWeight.w500,
                  color: textColor,
                  height: 1.2,
                  fontFamily: 'NotoSansSC',
                ),
                textScaler: const TextScaler.linear(1.0),
              ),
              SizedBox(height: MediaQuery.of(context).size.width > 600 ? 16 : 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '今日单词',
                    style: TextStyle(
                      fontSize: MediaQuery.of(context).size.width > 600 ? 16 : 14,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                      height: 1.2,
                      fontFamily: 'NotoSansSC',
                    ),
                    textScaler: const TextScaler.linear(1.0),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isDarkModeEnabled ? const Color(0xFF3D3D3D) : const Color(0xFFF0F0F0),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButton<int>(
                      value: loggedInUser!.wordsPerDay!,
                      underline: const SizedBox(),
                      icon: Icon(
                        Icons.arrow_drop_down,
                        color: isDarkModeEnabled ? Colors.white : Colors.black,
                      ),
                      dropdownColor: isDarkModeEnabled ? const Color(0xFF2D2D2D) : Colors.white,
                      style: TextStyle(
                        color: isDarkModeEnabled ? Colors.white : Colors.black,
                        fontSize: 14,
                      ),
                      items: const [
                        DropdownMenuItem<int>(value: 10, child: Text('10')),
                        DropdownMenuItem<int>(value: 20, child: Text('20')),
                        DropdownMenuItem<int>(value: 30, child: Text('30')),
                        DropdownMenuItem<int>(value: 50, child: Text('50')),
                        DropdownMenuItem<int>(value: 75, child: Text('75')),
                        DropdownMenuItem<int>(value: 100, child: Text('100')),
                        DropdownMenuItem<int>(value: 150, child: Text('150')),
                        DropdownMenuItem<int>(value: 200, child: Text('200')),
                        DropdownMenuItem<int>(value: 300, child: Text('300')),
                        DropdownMenuItem<int>(value: 400, child: Text('400')),
                        DropdownMenuItem<int>(value: 500, child: Text('500')),
                      ],
                      onChanged: (value) async {
                        int newValue = value as int;
                        setState(() {
                          loggedInUser!.wordsPerDay = newValue;
                        });
                        await Global.setLoggedInUser(loggedInUser!);
                        await MyDatabase.instance.usersDao.updateWordsPerDay(loggedInUser!.id!, newValue);
                        ThrottledDbSyncService().requestSync();
                      },
                    ),
                  ),
                ],
              ),
              SizedBox(height: MediaQuery.of(context).size.width > 600 ? 16 : 12),
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
                          elevation: 4,
                          shadowColor: AppTheme.primaryColor.withValues(alpha: 0.3),
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
            boxShadow: [
              BoxShadow(
                color: isDarkModeEnabled ? Colors.black.withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.1),
                spreadRadius: 1,
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
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

        // 统计数据网格
        Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      icon: Icons.emoji_events,
                      title: '积分',
                      value: studyProgress!.totalScore.toString(),
                      color: const Color(0xFFFF6B6B),
                      onTap: null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      icon: Icons.trending_up,
                      title: '排名',
                      value: studyProgress!.userOrder! == -1 ? '未排名' : studyProgress!.userOrder!.toString(),
                      color: const Color(0xFF4ECDC4),
                      onTap: null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      icon: Icons.check_circle,
                      title: '已掌握',
                      value: studyProgress!.masteredWordsCount.toString(),
                      color: const Color(0xFF45B7D1),
                      onTap: () {
                        toMasteredWordsListPage(true)?.then((value) => loadData());
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      icon: Icons.school,
                      title: '学习中',
                      value: studyProgress!.learningWordsCount.toString(),
                      color: const Color(0xFF96CEB4),
                      onTap: () {
                        toLearningWordsListPage(true)?.then((value) => loadData());
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // 打卡统计卡片
        Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: isDarkModeEnabled ? Colors.black.withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.1),
                spreadRadius: 1,
                blurRadius: 8,
                offset: const Offset(0, 2),
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
                    '泡泡糖',
                    studyProgress!.cowDung.toString(),
                    Icons.pets,
                    const Color(0xFFE67E22),
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
            boxShadow: [
              BoxShadow(
                color: isDarkModeEnabled ? Colors.black.withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.1),
                spreadRadius: 1,
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '最近30天打卡记录',
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
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppTheme.primaryLightColor, AppTheme.primaryDarkColor],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppTheme.primaryColor.withValues(alpha: 0.25),
                spreadRadius: 2,
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '我的词书',
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
            boxShadow: [
              BoxShadow(
                color: isDarkModeEnabled ? Colors.black.withValues(alpha: 0.3) : Colors.grey.withValues(alpha: 0.1),
                spreadRadius: 1,
                blurRadius: 8,
                offset: const Offset(0, 2),
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
              _buildMenuTile(
                icon: Icons.swap_horiz,
                title: '切换账号',
                onTap: () => Get.toNamed('/email_login'),
              ),
              _buildMenuTile(
                icon: Icons.health_and_safety,
                title: '故障诊断',
                onTap: () => _navigateToDataDiagnostic(),
              ),
              if (Config.showDbButton)
                _buildMenuTile(
                  icon: Icons.storage,
                  title: '数据库查看器',
                  onTap: () => _openDbViewPage(),
                ),
              _buildMenuTile(
                icon: Icons.cleaning_services,
                title: '清空本地数据',
                onTap: () => _showWipeLocalDataDialog(),
                isDestructive: true,
              ),
              _buildMenuTile(
                icon: Icons.delete_forever,
                title: '注销账号',
                onTap: () => showUnRegisterDlg(),
                isDestructive: true,
              ),
              // 管理员功能入口
              if (loggedInUser?.isAdmin == true) ...[
                const Divider(),
                _buildMenuTile(
                  icon: Icons.admin_panel_settings,
                  title: '管理页面',
                  onTap: () => Get.toNamed('/admin'),
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

    bool? choice = await showDialog<bool>(
        barrierDismissible: false,
        context: context,
        builder: (BuildContext context) {
          return Dialog(
            backgroundColor: Colors.transparent,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.95,
              margin: const EdgeInsets.symmetric(horizontal: 0),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: isDarkModeEnabled ? Colors.black.withValues(alpha: 0.5) : Colors.black.withValues(alpha: 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 标题栏
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF4A90E2), Color(0xFF7B68EE)],
                      ),
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
                          children: [
                            // Email 输入框
                            _buildInputField(
                              controller: email,
                              label: '邮箱地址',
                              icon: Icons.email_outlined,
                              validator: (value) => EmailValidator.validate(value ?? '') ? null : "请输入有效的邮箱地址",
                              isDarkMode: isDarkModeEnabled,
                              cardColor: cardColor,
                              textColor: textColor,
                            ),
                            const SizedBox(height: 12),

                            // 昵称输入框
                            _buildInputField(
                              controller: nickname,
                              label: '昵称',
                              icon: Icons.person_outline,
                              isDarkMode: isDarkModeEnabled,
                              cardColor: cardColor,
                              textColor: textColor,
                            ),
                            const SizedBox(height: 12),

                            // 密码输入框
                            _buildInputField(
                              controller: password,
                              label: '新密码',
                              icon: Icons.lock_outline,
                              obscureText: true,
                              isDarkMode: isDarkModeEnabled,
                              cardColor: cardColor,
                              textColor: textColor,
                            ),
                            const SizedBox(height: 12),

                            // 确认密码输入框
                            _buildInputField(
                              controller: password2,
                              label: '确认新密码',
                              icon: Icons.lock_outline,
                              obscureText: true,
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
                                    onPressed: () => Navigator.pop(context, false),
                                    isPrimary: false,
                                    isDarkMode: isDarkModeEnabled,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _buildDialogButton(
                                    text: '保存',
                                    onPressed: () {
                                      if (password.text != password2.text) {
                                        ToastUtil.error("两次输入的密码不一致");
                                        return;
                                      }
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

    if (choice ?? false) {
      UserBo().updateUserInfo(email.text, nickname.text, password.text, password2.text, Global.getLoggedInUser()!.id).then((value) async {
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
        elevation: isPrimary ? 4 : 0,
        shadowColor: isPrimary ? const Color(0xFF4A90E2).withValues(alpha: 0.3) : Colors.transparent,
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
                    boxShadow: [
                      BoxShadow(
                        color: isDarkModeEnabled ? Colors.black.withValues(alpha: 0.5) : Colors.black.withValues(alpha: 0.1),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 标题栏
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFFE74C3C), Color(0xFFC0392B)],
                          ),
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
                                          elevation: 4,
                                          shadowColor: const Color(0xFFE74C3C).withValues(alpha: 0.3),
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

  // 统计卡片组件
  Widget _buildStatCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
    VoidCallback? onTap,
  }) {
    final isDarkModeEnabled = context.watch<DarkMode>().isDarkMode;
    final cardColor = isDarkModeEnabled ? const Color(0xFF2D2D2D) : Colors.white;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: isDarkModeEnabled ? Colors.black.withValues(alpha: 0.3) : color.withValues(alpha: 0.1),
              spreadRadius: 1,
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                color: isDarkModeEnabled ? Colors.grey[400] : const Color(0xFF7F8C8D),
                height: 1.2,
                fontWeight: FontWeight.w400,
                fontFamily: 'NotoSansSC',
              ),
              textScaler: const TextScaler.linear(1.0),
            ),
          ],
        ),
      ),
    );
  }

  // 进度项组件
  Widget _buildProgressItem(String title, String value, IconData icon, Color color) {
    final isDarkModeEnabled = context.watch<DarkMode>().isDarkMode;

    return Column(
      children: [
        Icon(icon, color: color, size: 24),
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
    Navigator.of(context).push(MaterialPageRoute(
        builder: (context) => Scaffold(
              appBar: AppTheme.createGradientAppBar(
                title: '数据库查看器',
                automaticallyImplyLeading: true, // 恢复默认的回退行为
              ),
              body: DriftDbViewer(MyDatabase.instance),
            )));
  }

  void _navigateToDataDiagnostic() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const DataDiagnosticPage(),
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
  }) {
    final isDarkModeEnabled = context.watch<DarkMode>().isDarkMode;
    final textColor = isDarkModeEnabled ? Colors.white : const Color(0xFF2C3E50);

    return ListTile(
      leading: Icon(
        icon,
        color: isDestructive ? Colors.red : const Color(0xFF3498DB),
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

  Future<void> _showWipeLocalDataDialog() async {
    final isDarkModeEnabled = context.read<DarkMode>().isDarkMode;
    bool? choice = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDarkModeEnabled ? const Color(0xFF2D2D2D) : Colors.white,
          title: const Text('确认清空所有表'),
          content: const Text('此操作将清空本地所有数据，应用将回到初始状态，是否继续？'),
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
          ToastUtil.info('已清空所有表');
          // 清空后跳转到登录页面
          Get.offAllNamed('/email_login');
        },
        operationName: '清空所有表',
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
                SliverAppBar(
                  expandedHeight: 60,
                  floating: false,
                  pinned: true,
                  backgroundColor: backgroundColor,
                  elevation: 0,
                  centerTitle: true,
                  title: Text(
                    '我的',
                    style: TextStyle(
                      color: isDarkModeEnabled ? Colors.white : Colors.black,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2.0,
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
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

  @override
  void initState() {
    super.initState();
    currentLearningDict = widget.learningDict;
    _loadActualWordCount();
  }

  @override
  void didUpdateWidget(DictCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.learningDict != widget.learningDict) {
      currentLearningDict = widget.learningDict;
      _loadActualWordCount();
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
    final progress = totalWords > 0 ? (currentLearningDict.currentWordSeq ?? 0) / totalWords : 0.0;
    final progressPercent = (progress * 100).toInt();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColor.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
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
                            ? '${currentLearningDict.currentWordSeq ?? 0} / ${actualWordCount ?? 0}'
                            : '${currentLearningDict.currentWordSeq ?? 0} / ${widget.dictInfo.wordCount}',
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
                            currentWordSeq: currentLearningDict.currentWordSeq,
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
                icon: widget.dictInfo.name == '生词本' ? Icons.clear_all : Icons.delete_outline,
                label: widget.dictInfo.name == '生词本' ? '清空' : '删除',
                isActive: true,
                isDestructive: true,
                onTap: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('确认'),
                      content: widget.dictInfo.name == '生词本'
                          ? Text('确实要清空"${widget.dictInfo.name}"中的单词?')
                          : Text('确实要删除词书(${widget.dictInfo.name.replaceAll('.dict', '')})?'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('否'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('是'),
                        ),
                      ],
                    ),
                  );

                  if (confirmed == true) {
                    if (widget.dictInfo.name == '生词本') {
                      MyDatabase.instance.dictWordsDao.clearDictWord(currentLearningDict.dictId, true);

                      final updatedDict = LearningDict(
                        userId: currentLearningDict.userId,
                        dictId: currentLearningDict.dictId,
                        isPrivileged: currentLearningDict.isPrivileged,
                        fetchMastered: currentLearningDict.fetchMastered,
                        currentWordSeq: 0,
                        createTime: currentLearningDict.createTime,
                        updateTime: currentLearningDict.updateTime,
                      );
                      await MyDatabase.instance.learningDictsDao.saveEntity(updatedDict, true);

                      if (mounted) {
                        setState(() {
                          currentLearningDict = updatedDict;
                          actualWordCount = 0; // 清空后更新实际单词数量
                        });
                      }
                    } else {
                      await MyDatabase.instance.learningDictsDao.deleteEntity(currentLearningDict, true);
                      widget.onDictChanged();
                    }
                    ThrottledDbSyncService().requestSync();
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
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
