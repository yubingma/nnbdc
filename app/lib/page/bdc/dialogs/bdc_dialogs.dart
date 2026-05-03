part of '../../bdc.dart';

extension BdcPageStateDialogs on BdcPageState {
  Widget _buildSettingItem(String title, bool value, Function(bool) onChanged,
      {Widget? customTrailing, String? subtitle}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
      dense: true,
      title: Text(
        title,
        textScaler: const TextScaler.linear(1.0),
        style: const TextStyle(
          fontFamily: "NotoSansSC",
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              textScaler: const TextScaler.linear(1.0),
              style: TextStyle(
                fontFamily: "NotoSansSC",
                fontSize: 12,
                color: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.color
                    ?.withValues(alpha: 0.6),
              ),
            )
          : null,
      trailing: customTrailing ??
          Transform.scale(
            scale: 0.5,
            alignment: Alignment.centerRight,
            child: Switch.adaptive(
              value: value,
              onChanged: onChanged,
              activeTrackColor: Global.highlight,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
      onTap: () {
        if (customTrailing == null) {
          onChanged(!value);
        }
      },
    );
  }


  Widget _buildDistractorStrategySelector(
      String currentValue, Function(String) onChanged) {
    const Map<String, String> options = {
      'RecentlyLearned': '最近学习的单词',
      'ShapeSimilar': '形近词',
    };

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
      dense: true,
      title: Text(
        '混淆词取词策略',
        textScaler: const TextScaler.linear(1.0),
        style: const TextStyle(
          fontFamily: "NotoSansSC",
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        options[currentValue] ?? '最近学习的单词',
        textScaler: const TextScaler.linear(1.0),
        style: TextStyle(
          fontFamily: "NotoSansSC",
          fontSize: 12,
          color: Theme.of(context)
              .textTheme
              .bodySmall
              ?.color
              ?.withValues(alpha: 0.6),
        ),
      ),
      trailing: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        position: PopupMenuPosition.over,
        onSelected: onChanged,
        itemBuilder: (BuildContext context) {
          return options.entries.map((entry) {
            return PopupMenuItem<String>(
              value: entry.key,
              child: Text(
                entry.value,
                style: const TextStyle(
                  fontFamily: "NotoSansSC",
                  fontSize: 13,
                ),
              ),
            );
          }).toList();
        },
        child: SizedBox(
          width: 48,
          child: Align(
            alignment: Alignment.centerRight,
            child: Icon(
              Icons.arrow_drop_down,
              color: Global.highlight,
            ),
          ),
        ),
      ),
    );
  }


  Widget _buildAsrPassRuleSelector(
      String currentValue, Function(String) onChanged) {
    const Map<String, String> options = {
      'ONE': '说出一个意思即可',
      'HALF': '说出半数意思',
      'ALL': '说出全部意思',
    };

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
      dense: true,
      title: Text(
        '语音识别通过规则',
        textScaler: const TextScaler.linear(1.0),
        style: const TextStyle(
          fontFamily: "NotoSansSC",
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
      subtitle: Text(
        options[currentValue] ?? '说出一个意思即可',
        textScaler: const TextScaler.linear(1.0),
        style: TextStyle(
          fontFamily: "NotoSansSC",
          fontSize: 12,
          color: Theme.of(context)
              .textTheme
              .bodySmall
              ?.color
              ?.withValues(alpha: 0.6),
        ),
      ),
      trailing: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        position: PopupMenuPosition.over,
        onSelected: onChanged,
        itemBuilder: (BuildContext context) {
          return options.entries.map((entry) {
            return PopupMenuItem<String>(
              value: entry.key,
              child: Text(
                entry.value,
                style: const TextStyle(
                  fontFamily: "NotoSansSC",
                  fontSize: 13,
                ),
              ),
            );
          }).toList();
        },
        child: SizedBox(
          width: 48,
          child: Align(
            alignment: Alignment.centerRight,
            child: Icon(
              Icons.arrow_drop_down,
              color: Global.highlight,
            ),
          ),
        ),
      ),
    );
  }


  Future<void> showSettingDlg() async {
    // 在StatefulBuilder外部初始化本地状态
    var currentUser = Global.getLoggedInUser();
    var studyConfig = StudyConfig.fromCurrentUser();
    var localAutoPlayWord = studyConfig.autoPlayWord;
    var localAutoPlaySentence = studyConfig.autoPlaySentence;
    var localShowAnswersDirectly = studyConfig.showAnswersDirectly;
    var localEnableAllWrong = studyConfig.enableAllWrong;
    var localEnableWordImage = studyConfig.enableWordImage;
    var localAsrPassRule = studyConfig.asrPassRule;
    var localAutoJumpAfterCorrectCh2En = studyConfig.autoJumpAfterCorrectCh2En;
    var localAutoJumpAfterCorrectEn2Ch = studyConfig.autoJumpAfterCorrectEn2Ch;
    var localDistractorStrategy = studyConfig.distractorStrategy;

    if (!mounted) return;

    bool? choice = await showDialog<bool>(
        barrierDismissible: false,
        context: context,
        builder: (BuildContext context) {
          return StatefulBuilder(builder: (context, setState) {
            return AlertDialog(
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              titlePadding: EdgeInsets.zero,
              contentPadding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              title: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Global.highlight.withValues(alpha: 0.1),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.settings_outlined,
                      color: Global.highlight,
                      size: 22,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '学习设置',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Global.highlight,
                        fontFamily: "NotoSansSC",
                      ),
                    ),
                  ],
                ),
              ),
              content: SizedBox(
                width: min(MediaQuery.of(context).size.width * 0.92, 540),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 2),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.5,
                      ),
                      child: SingleChildScrollView(
                        child: Container(
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                    ? const Color(0xFF1C1C1E)
                                    : const Color(0xFFF9F9F9),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.white.withValues(alpha: 0.05)
                                    : Colors.black.withValues(alpha: 0.05),
                                width: 0.5),
                          ),
                          padding: const EdgeInsets.symmetric(
                              vertical: 2, horizontal: 0),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final List<Widget> items = [
                                _buildSettingItem(
                                  '深色模式',
                                  _isDarkMode,
                                  (value) {
                                    setState(() {
                                      _isDarkMode = value;
                                    });
                                    MyDatabase.instance.localParamsDao
                                        .saveIsDarkMode(value);
                                    context
                                        .read<DarkMode>()
                                        .setIsDarkMode(value);
                                  },
                                  customTrailing: Transform.translate(
                                    offset: const Offset(20, 0),
                                    child: Transform.scale(
                                      scale: 1.8,
                                      alignment: Alignment.centerRight,
                                      child: DayNightSwitcherIcon(
                                        isDarkModeEnabled: _isDarkMode,
                                        onStateChanged: (isDarkModeEnabled) {
                                          setState(() {
                                            _isDarkMode = isDarkModeEnabled;
                                          });
                                          MyDatabase.instance.localParamsDao
                                              .saveIsDarkMode(
                                                  isDarkModeEnabled);
                                          context
                                              .read<DarkMode>()
                                              .setIsDarkMode(isDarkModeEnabled);
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                                _buildAsrPassRuleSelector(
                                  localAsrPassRule,
                                  (value) {
                                    setState(() {
                                      localAsrPassRule = value;
                                    });
                                  },
                                ),
                                _buildDistractorStrategySelector(
                                  localDistractorStrategy,
                                  (value) {
                                    setState(() {
                                      localDistractorStrategy = value;
                                    });
                                  },
                                ),
                                _buildSettingItem(
                                  '自动播放单词发音',
                                  localAutoPlayWord,
                                  (value) {
                                    setState(() {
                                      localAutoPlayWord = value;
                                    });
                                  },
                                ),
                                _buildSettingItem(
                                  '自动播放例句',
                                  localAutoPlaySentence,
                                  (value) {
                                    setState(() {
                                      localAutoPlaySentence = value;
                                    });
                                  },
                                ),
                                _buildSettingItem(
                                  '直接显示备选答案',
                                  localShowAnswersDirectly,
                                  (value) {
                                    setState(() {
                                      localShowAnswersDirectly = value;
                                    });
                                  },
                                ),
                                _buildSettingItem(
                                  '备选答案含[都不对]选项',
                                  localEnableAllWrong,
                                  (value) {
                                    setState(() {
                                      localEnableAllWrong = value;
                                    });
                                  },
                                ),
                                _buildSettingItem(
                                  '显示单词配图',
                                  localEnableWordImage,
                                  (value) {
                                    setState(() {
                                      localEnableWordImage = value;
                                    });
                                  },
                                ),
                                _buildSettingItem(
                                  '中英极速：答对后直接下一词',
                                  localAutoJumpAfterCorrectCh2En,
                                  (value) {
                                    setState(() {
                                      localAutoJumpAfterCorrectCh2En = value;
                                    });
                                  },
                                ),
                                _buildSettingItem(
                                  '英中极速：答对后直接下一词',
                                  localAutoJumpAfterCorrectEn2Ch,
                                  (value) {
                                    setState(() {
                                      localAutoJumpAfterCorrectEn2Ch = value;
                                    });
                                  },
                                ),
                              ];

                              return Column(
                                children: [
                                  for (int i = 0; i < items.length; i++) ...[
                                    if (i > 0)
                                      Divider(
                                        height: 1,
                                        thickness: 0.5,
                                        indent: 16,
                                        endIndent: 16,
                                        color: Theme.of(context).brightness ==
                                                Brightness.dark
                                            ? Colors.white
                                                .withValues(alpha: 0.08)
                                            : Colors.grey
                                                .withValues(alpha: 0.2),
                                      ),
                                    items[i],
                                  ]
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      width: 88,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          foregroundColor:
                              Theme.of(context).brightness == Brightness.dark
                                  ? Colors.grey[300]
                                  : Colors.grey[700],
                          backgroundColor:
                              Theme.of(context).brightness == Brightness.dark
                                  ? Colors.grey[800]
                                  : Colors.grey[200],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onPressed: () {
                          Navigator.pop(context, false);
                        },
                        child: const Text('取消',
                            style: TextStyle(
                                fontSize: 13, fontFamily: "NotoSansSC")),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 88,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Global.highlight,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                        onPressed: () async {
                          // 保存所有设置
                          if (currentUser != null) {
                            var studyConfigToSave =
                                StudyConfig.fromCurrentUser();
                            studyConfigToSave.autoPlayWord = localAutoPlayWord;
                            studyConfigToSave.autoPlaySentence =
                                localAutoPlaySentence;
                            studyConfigToSave.showAnswersDirectly =
                                localShowAnswersDirectly;
                            studyConfigToSave.enableAllWrong =
                                localEnableAllWrong;
                            studyConfigToSave.autoJumpAfterCorrectCh2En =
                                localAutoJumpAfterCorrectCh2En;
                            studyConfigToSave.autoJumpAfterCorrectEn2Ch =
                                localAutoJumpAfterCorrectEn2Ch;
                            studyConfigToSave.asrPassRule = localAsrPassRule;
                            studyConfigToSave.enableWordImage = localEnableWordImage;
                            studyConfigToSave.distractorStrategy = localDistractorStrategy;
                            await studyConfigToSave.saveToCurrentUser();
                          }

                          // 在异步操作后检查context是否仍然有效
                          if (context.mounted) {
                            _asrPassRuleCache = localAsrPassRule;
                            _autoJumpAfterCorrectCh2En =
                                localAutoJumpAfterCorrectCh2En;
                            _autoJumpAfterCorrectEn2Ch =
                                localAutoJumpAfterCorrectEn2Ch;
                            Navigator.pop(context, true);
                          }
                        },
                        child: const Text('确定',
                            style: TextStyle(
                                fontSize: 13,
                                fontFamily: "NotoSansSC",
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ],
            );
          });
        });

    if (choice ?? false) {
      // 设置已在确定按钮中保存，这里刷新界面
      try {
        // 刷新界面，以体现最新配置
        await asr.stopAsr();
        handleWord(_currentGetWordResult);
      } catch (e) {
        ToastUtil.error('刷新界面失败: $e');
      }
    }
  }


  Future<void> showErrorReportDlg() async {
    errorReportController.text = '';
    bool? choice = await showDialog<bool>(
        barrierDismissible: false,
        context: context,
        builder: (BuildContext context) {
          return StatefulBuilder(builder: (context, setState) {
            final isDark = context.watch<DarkMode>().isDarkMode;
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              titlePadding: EdgeInsets.zero,
              contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              title: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Global.highlight.withValues(alpha: 0.08),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(18),
                    topRight: Radius.circular(18),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.report_problem_outlined,
                        color: Global.highlight, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '问题反馈',
                      textScaler: const TextScaler.linear(1.0),
                      style: TextStyle(
                        fontFamily: "NotoSansSC",
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Global.highlight,
                      ),
                    ),
                  ],
                ),
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '请输入单词(${_word!.spell})的报错内容',
                        textScaler: const TextScaler.linear(1.0),
                        style: const TextStyle(
                          fontFamily: "NotoSansSC",
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 10),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF1F2430)
                              : const Color(0xFFF7FAFF),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.black.withValues(alpha: 0.06),
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: TextField(
                            controller: errorReportController,
                            minLines: 4,
                            maxLines: 10,
                            decoration: const InputDecoration(
                              hintText: '请尽量描述具体问题，方便我们快速修复',
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text(
                    '取消',
                    textScaler: TextScaler.linear(1.0),
                    style: TextStyle(fontFamily: "NotoSansSC"),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Global.highlight,
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text(
                    '提交',
                    textScaler: TextScaler.linear(1.0),
                    style: TextStyle(fontFamily: "NotoSansSC"),
                  ),
                ),
              ],
            );
          });
        });

    if (choice ?? false) {
      var result = await UserBo()
          .saveErrorReport(_word!.spell, errorReportController.text);
      if (result.success) {
        ToastUtil.info('报错成功！感谢你付出宝贵时间');
      } else {
        ToastUtil.error((result.msg!));
      }
    }
  }


  Future<void> showEditPicDlg(
      BuildContext context, WordImageVo wordImage) async {
    Future<bool>? voteFuture;
    showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: '',
        transitionDuration: const Duration(milliseconds: 100),
        transitionBuilder: (context, animation, secondaryAnimation, child) {
          return FractionalTranslation(
              translation: Offset(1 - animation.value, 0), // 从中部出现
              child: child);
        },
        pageBuilder: (context, animation, secondaryAnimation) {
          return StatefulBuilder(builder: (context, dialogSetState) {
            voteFuture ??= wordImageHasBeenVoted(wordImage);
            return Align(
              alignment: const Alignment(0, 0),
              child: Container(
                width: PlatformUtils.isWeb
                    ? 600
                    : MediaQuery.of(context).size.width,
                height: PlatformUtils.isWeb ? 480 : 320,
                margin: MediaQuery.of(context).viewInsets,
                // 当软键盘弹出时，对话框自动上移
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                color: context.read<DarkMode>().isDarkMode
                    ? const Color(0xff333333)
                    : Colors.white,
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            margin: const EdgeInsets.fromLTRB(0, 8, 0, 0),
                            child: Image.network(
                                Uri.encodeFull('${Config.wordImageBaseUrl}${wordImage.imageFile}'),
                                width: PlatformUtils.isWeb ? 400 : 200,
                                height: PlatformUtils.isWeb ? 300 : 150,
                                fit: BoxFit.contain, loadingBuilder:
                                    (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return const Center(
                                child: CircularProgressIndicator(
                                  color: Colors.indigoAccent,
                                  strokeWidth: 2,
                                ),
                              );
                            }, errorBuilder: (context, error, stackTrace) {
                              return const Center(
                                child: Icon(
                                  Icons.broken_image,
                                  color: Colors.red,
                                  size: 32,
                                ),
                              );
                            }),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                                'by：${Util.getNickNameOfUser(wordImage.author)}'),
                          ],
                        ),
                      ),
                      FutureBuilder<bool>(
                          future: voteFuture,
                          builder: (BuildContext context,
                              AsyncSnapshot<bool> snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.done) {
                              return Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  InkWell(
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.favorite_outline,
                                            size: 24,
                                            color: snapshot.data!
                                                ? Util.voteColorDisabled(
                                                    context)
                                                : Util.voteColorEnabled(
                                                    context),
                                          ),
                                          Text(' ${wordImage.hand}',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: snapshot.data!
                                                      ? Util.voteColorDisabled(
                                                          context)
                                                      : Util.voteColorEnabled(
                                                          context))),
                                        ],
                                      ),
                                      onTap: () async {
                                        if (snapshot.data!) {
                                          ToastUtil.error('不能重复投票');
                                          return;
                                        }
                                        var result = await Api.client
                                            .handWordImage(wordImage.id);
                                        if (result.success) {
                                           final now = AppClock.now();
                                          MyDatabase.instance.votedWordImagesDao
                                              .createEntity(VotedWordImage(
                                                  userId:
                                                      Global.getLoggedInUser()!
                                                          .id,
                                                  imageId: wordImage.id,
                                                  vote: 'HAND',
                                                  createTime: now,
                                                  updateTime: now));
                                          wordImage.hand += 1;
                                          _wordImageEdited = true;
                                          voteFuture = Future.value(true);
                                          if (mounted) {
                                            dialogSetState(() {});
                                          }
                                        } else {
                                          ToastUtil.error(result.msg!);
                                        }
                                      }),
                                  InkWell(
                                      child: Container(
                                        margin: const EdgeInsets.only(left: 24),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.heart_broken_outlined,
                                              size: 24,
                                              color: snapshot.data!
                                                  ? Util.voteColorDisabled(
                                                      context)
                                                  : Util.voteColorEnabled(
                                                      context),
                                            ),
                                            Text(' ${wordImage.foot}',
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color: snapshot.data!
                                                        ? Util
                                                            .voteColorDisabled(
                                                                context)
                                                        : Util.voteColorEnabled(
                                                            context))),
                                          ],
                                        ),
                                      ),
                                      onTap: () async {
                                        if (snapshot.data!) {
                                          ToastUtil.error('不能重复投票');
                                          return;
                                        }
                                        var result = await Api.client
                                            .footWordImage(wordImage.id);
                                        if (result.success) {
                                           final now = AppClock.now();
                                          MyDatabase.instance.votedWordImagesDao
                                              .createEntity(VotedWordImage(
                                                  userId:
                                                      Global.getLoggedInUser()!
                                                          .id,
                                                  imageId: wordImage.id,
                                                  vote: 'FOOT',
                                                  createTime: now,
                                                  updateTime: now));
                                          wordImage.foot += 1;
                                          _wordImageEdited = true;
                                          voteFuture = Future.value(true);
                                          if (mounted) {
                                            dialogSetState(() {});
                                          }
                                        } else {
                                          ToastUtil.error(result.msg!);
                                        }
                                      }),
                                ],
                              );
                            } else {
                              return Container();
                            }
                          }),
                      Container(
                        margin: const EdgeInsets.fromLTRB(0, 32, 0, 0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            if (wordImage.author.id ==
                                    Global.getLoggedInUser()!.id ||
                                (Global.getLoggedInUser()!.isAdmin ?? false) ||
                                (Global.getLoggedInUser()!.isSuperAdmin ??
                                    false))
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  backgroundColor: Colors.red, // foreground
                                ),
                                child: const Text('删除'),
                                onPressed: () {
                                  // 先关闭对话框，再执行异步操作
                                  resetHighlightedWordImg();
                                  Navigator.pop(context, false);

                                  // 然后执行异步删除操作
                                  Api.client
                                      .deleteWordImage(wordImage.id,
                                          Global.getLoggedInUser()!.id)
                                      .then((result) {
                                    if (result.success) {
                                      ToastUtil.info("删除成功");
                                    } else {
                                      ToastUtil.error(result.msg!);
                                    }

                                    if (mounted) {
                                      reloadWord();
                                    }
                                  });
                                },
                              ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                foregroundColor: Colors.white,
                                backgroundColor: Colors.green, // foreground
                              ),
                              child: const Text('关闭'),
                              onPressed: () {
                                resetHighlightedWordImg();
                                Navigator.pop(context, false);
                                if (_wordImageEdited) {
                                  reloadWord();
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          });
        });
  }


  void _showRatingModifyDialog() {
    showDialog(
      context: context,
      builder: (context) {
        String finalReason = _lastFsrsRatingReason ?? '';
        // 巩固环节中，只有当自动评分被限制（高于测评环节评分）时才显示提示
        if (_currentGetWordResult != null &&
            _currentGetWordResult!.stepIndex > 0 &&
            _assessmentRating != null &&
            _lastFsrsRating != null &&
            _lastFsrsRating!.index > _assessmentRating!.index) {
          if (finalReason.isNotEmpty) {
            finalReason += '\n';
          }
          finalReason += '⚠️ 当前处于巩固环节，自动评分上限被限制为测评结果（${_assessmentRating!.label}）。';
        }
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          titlePadding: const EdgeInsets.fromLTRB(24, 12, 8, 8),
          title: Row(
            children: [
              const Expanded(
                child: Text('修改今日评分',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.of(context).pop(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).dividerColor.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Text(
                        '评分影响该单词今后的复习频率。如果自动评分不合实际，可手动修正',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.color
                              ?.withValues(alpha: 0.9),
                          height: 1.4,
                        ),
                      ),
                    ),
                    if (_lastFsrsRatingReason != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppTheme.primaryColor.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                finalReason,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.primaryColor,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ...FsrsRating.values.map((rating) {
                Color ratingColor;
                final isDarkMode = context.read<DarkMode>().isDarkMode;
                switch (rating) {
                  case FsrsRating.again:
                    ratingColor = isDarkMode ? Colors.redAccent : const Color(0xFFD32F2F);
                    break;
                  case FsrsRating.hard:
                    ratingColor = isDarkMode ? Colors.orangeAccent : const Color(0xFFF57C00);
                    break;
                  case FsrsRating.easy:
                    ratingColor = isDarkMode ? Colors.greenAccent : const Color(0xFF2E7D32);
                    break;
                  case FsrsRating.good:
                    ratingColor = AppTheme.primaryColor;
                    break;
                }

                return ListTile(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  title: Text(
                    rating.label,
                    style: TextStyle(
                      color: ratingColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  trailing: _lastFsrsRating == rating
                      ? Icon(Icons.check, color: ratingColor)
                      : null,
                  onTap: () {
                    Navigator.of(context).pop();
                    _updateFsrsRating(rating);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }


}
