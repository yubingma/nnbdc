part of '../bdc.dart';

Color _getRatingColor(FsrsRating rating, bool isDarkMode) {
  switch (rating) {
    case FsrsRating.again:
      return isDarkMode ? Colors.redAccent : const Color(0xFFD32F2F);
    case FsrsRating.hard:
      return isDarkMode ? Colors.orangeAccent : const Color(0xFFF57C00);
    case FsrsRating.easy:
      return isDarkMode ? Colors.greenAccent : const Color(0xFF2E7D32);
    case FsrsRating.good:
      return AppTheme.primaryColor;
  }
}

extension BdcPageStateDialogs on BdcPageState {
  BdcState get state => ref.watch(bdcNotifierProvider);
  BdcNotifier get notifier => ref.read(bdcNotifierProvider.notifier);
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
                                  context.read<DarkMode>().isDarkMode,
                                  (value) {
                                    setState(() {
                                      context.read<DarkMode>().setIsDarkMode(value);
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
                                        isDarkModeEnabled: context.read<DarkMode>().isDarkMode,
                                        onStateChanged: (isDarkModeEnabled) {
                                          setState(() {
                                            context.read<DarkMode>().setIsDarkMode(isDarkModeEnabled);
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
                            notifier.updateAsrPassRuleCache(localAsrPassRule);
                            notifier.updateAutoJumpCh2En(
                                localAutoJumpAfterCorrectCh2En);
                            notifier.updateAutoJumpEn2Ch(
                                localAutoJumpAfterCorrectEn2Ch);
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
      // 设置已在确定按钮中保存，这里调用专属的刷新方法以重建 ASR 识别并重绘界面
      try {
        await notifier.refreshConfigAndAsr();
      } catch (e) {
        ToastUtil.error('刷新界面失败: $e');
      }
    }
  }


  Future<void> showErrorReportDlg() async {
    errorReportController.text = '';
    final pickedImages = <XFile>[];
    final imagePreviewBytesList = <Uint8List>[];

    await showDialog<bool>(
        barrierDismissible: false,
        context: context,
        builder: (BuildContext context) {
          // 这些变量在 showDialog builder 作用域内（仅创建一次），
          // StatefulBuilder 的 closure 可以读写它们，且不会因 dialogSetState 重建而被重置
          var isSubmitting = false;
          String? submitError;

          return StatefulBuilder(builder: (context, dialogSetState) {
            final isDark = context.watch<DarkMode>().isDarkMode;

            Future<void> pickImages() async {
              try {
                final picker = ImagePicker();
                final source = await showModalBottomSheet<ImageSource>(
                  context: context,
                  backgroundColor: isDark
                      ? const Color(0xFF1E1E1E)
                      : Colors.white,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                        top: Radius.circular(20)),
                  ),
                  builder: (context) => SafeArea(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 8),
                        ListTile(
                          leading: Icon(Icons.camera_alt_rounded,
                              color: Global.highlight),
                          title: const Text('拍照',
                              style: TextStyle(fontFamily: 'NotoSansSC')),
                          onTap: () => Navigator.pop(
                              context, ImageSource.camera),
                        ),
                        ListTile(
                          leading: Icon(Icons.photo_library_rounded,
                              color: Global.highlight),
                          title: const Text('从相册选择',
                              style: TextStyle(fontFamily: 'NotoSansSC')),
                          onTap: () => Navigator.pop(
                              context, ImageSource.gallery),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                );
                if (source == null) return;

                if (source == ImageSource.gallery) {
                  final files = await picker.pickMultiImage(
                    imageQuality: 85,
                    maxWidth: 1920,
                    maxHeight: 1920,
                  );
                  for (final file in files) {
                    final bytes = await file.readAsBytes();
                    if (context.mounted) {
                      dialogSetState(() {
                        pickedImages.add(file);
                        imagePreviewBytesList.add(bytes);
                      });
                    }
                  }
                } else {
                  final XFile? file = await picker.pickImage(
                    source: source,
                    maxWidth: 1920,
                    maxHeight: 1920,
                    imageQuality: 85,
                  );
                  if (file != null) {
                    final bytes = await file.readAsBytes();
                    if (context.mounted) {
                      dialogSetState(() {
                        pickedImages.add(file);
                        imagePreviewBytesList.add(bytes);
                      });
                    }
                  }
                }
              } catch (e) {
                ToastUtil.error('选择图片失败: $e');
              }
            }

            void removeImageAt(int index) {
              dialogSetState(() {
                pickedImages.removeAt(index);
                imagePreviewBytesList.removeAt(index);
              });
            }

            Future<void> handleSubmit() async {
              if (errorReportController.text.trim().isEmpty) {
                dialogSetState(() {
                  submitError = '请填写报错内容';
                });
                return;
              }

              dialogSetState(() {
                isSubmitting = true;
                submitError = null;
              });

              try {
                final imageFileNames = <String>[];
                for (int i = 0; i < pickedImages.length; i++) {
                  final bytes = imagePreviewBytesList[i];
                  if (bytes.length > 1024 * 1024) {
                    dialogSetState(() {
                      submitError = '图片 "${pickedImages[i].name}" 过大，请选择较小的图片';
                      isSubmitting = false;
                    });
                    return;
                  }
                  final formData = FormData.fromMap({
                    'file': MultipartFile.fromBytes(bytes,
                        filename: pickedImages[i].name),
                    'userId': Global.getLoggedInUser()?.id ?? '',
                  });
                  final uploadResult = await Api.client.uploadImg(formData, 800);
                  if (uploadResult.success && uploadResult.data != null) {
                    imageFileNames.add(uploadResult.data!);
                  } else {
                    dialogSetState(() {
                      submitError = '图片上传失败: ${uploadResult.msg}';
                      isSubmitting = false;
                    });
                    return;
                  }
                }

                final imageFilesJson = imageFileNames.isNotEmpty
                    ? jsonEncode(imageFileNames)
                    : null;
                var result = await UserBo().saveErrorReport(
                    state.word!.spell, errorReportController.text,
                    imageFiles: imageFilesJson);
                if (result.success) {
                  if (context.mounted) {
                    Navigator.pop(context, true);
                    ToastUtil.info('报错成功！感谢你付出宝贵时间');
                  }
                } else {
                  dialogSetState(() {
                    submitError = result.msg ?? '提交失败，请稍后重试';
                    isSubmitting = false;
                  });
                }
              } catch (e) {
                dialogSetState(() {
                  submitError = '提交失败，请稍后重试';
                  isSubmitting = false;
                });
              }
            }

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
                constraints: const BoxConstraints(maxHeight: 480),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '请输入单词(${state.word!.spell})的报错内容',
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
                            maxLines: 8,
                            decoration: const InputDecoration(
                              hintText: '请尽量描述具体问题，方便我们快速修复',
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Image preview gallery
                      if (imagePreviewBytesList.isNotEmpty) ...[
                        SizedBox(
                          height: 100,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: imagePreviewBytesList.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              return Stack(
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.memory(
                                      imagePreviewBytesList[index],
                                      width: 100,
                                      height: 100,
                                      fit: BoxFit.cover,
                                    ),
                                  ),
                                  Positioned(
                                    top: 2,
                                    right: 2,
                                    child: GestureDetector(
                                      onTap: () => removeImageAt(index),
                                      child: Container(
                                        padding: const EdgeInsets.all(3),
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: const Icon(
                                          Icons.close,
                                          size: 14,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      // Add image button
                      OutlinedButton.icon(
                        onPressed: isSubmitting ? null : pickImages,
                        icon: const Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 18,
                        ),
                        label: Text(
                          pickedImages.isNotEmpty
                              ? '继续添加截图 (${pickedImages.length}张)'
                              : '添加截图',
                          style: const TextStyle(fontFamily: 'NotoSansSC'),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Global.highlight,
                          side: BorderSide(
                            color: Global.highlight.withValues(alpha: 0.4),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      // Submit error text
                      if (submitError != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.red.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline,
                                  size: 16, color: Colors.red),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  submitError!,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Colors.red,
                                    fontFamily: 'NotoSansSC',
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
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.pop(context, false),
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
                  onPressed: isSubmitting ? null : handleSubmit,
                  child: isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          '提交',
                          textScaler: TextScaler.linear(1.0),
                          style: TextStyle(fontFamily: "NotoSansSC"),
                        ),
                ),
              ],
            );
          });
        });
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
                                          notifier.updateIsWordImageEdited(true);
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
                                          notifier.updateIsWordImageEdited(true);
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
                                  notifier.resetHighlightedWordImg();
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
                                      notifier.reloadWord();
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
                                notifier.resetHighlightedWordImg();
                                Navigator.pop(context, false);
                                if (state.isWordImageEdited) {
                                  notifier.reloadWord();
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
        String finalReason = state.lastFsrsRatingReason ?? '';
        // 巩固环节中，只有当自动评分被限制（高于测评环节评分）时才显示提示
        if (state.currentGetWordResult != null &&
            state.currentGetWordResult!.stepIndex > 0 &&
            state.assessmentRating != null &&
            state.lastFsrsRating != null &&
            state.lastFsrsRating!.index > state.assessmentRating!.index) {
          if (finalReason.isNotEmpty) {
            finalReason += '\n';
          }
          finalReason += '⚠️ 当前处于巩固环节，自动评分上限被限制为测评结果（${state.assessmentRating!.label}）。';
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
                    if (state.lastFsrsRatingReason != null) ...[
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
                              child: _buildRichReason(finalReason, context),
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
                  trailing: state.lastFsrsRating == rating
                      ? Icon(Icons.check, color: ratingColor)
                      : null,
                  onTap: () {
                    Navigator.of(context).pop();
                    notifier.updateFsrsRating(rating);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }







  void _showLearningHistoryDialog() async {
    final wordId = state.wordWrapper?.word.id;
    if (wordId == null) return;

    final history = await MyDatabase.instance.learningLogsDao
        .getHistory(Global.getLoggedInUser()!.id, wordId);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) {
        final isDarkMode = context.watch<DarkMode>().isDarkMode;
        final bgColor = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
        final textColor = isDarkMode ? Colors.white70 : Colors.black87;

        return AlertDialog(
          backgroundColor: bgColor,
          title: Text('记忆历史',
              style: TextStyle(
                  color: textColor, fontSize: 18, fontWeight: FontWeight.bold)),
          content: history.isEmpty
              ? Text('暂无记忆历史',
                  style: TextStyle(color: textColor.withValues(alpha: 0.6)))
              : SizedBox(
                  width: double.maxFinite,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: history.length,
                    itemBuilder: (context, index) {
                      final log = history[index];
                      final rating = FsrsRatingExt.fromInt(log.rating);
                      final timeStr =
                          '${log.createTime.year}-${log.createTime.month.toString().padLeft(2, '0')}-${log.createTime.day.toString().padLeft(2, '0')} ${log.createTime.hour.toString().padLeft(2, '0')}:${log.createTime.minute.toString().padLeft(2, '0')}';

                      Color ratingColor;
                      switch (rating) {
                        case FsrsRating.again:
                          ratingColor = Colors.redAccent;
                          break;
                        case FsrsRating.hard:
                          ratingColor = Colors.orangeAccent;
                          break;
                        case FsrsRating.good:
                          ratingColor = AppTheme.primaryColor;
                          break;
                        case FsrsRating.easy:
                          ratingColor = Colors.greenAccent;
                          break;
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDarkMode
                              ? Colors.white.withValues(alpha: 0.03)
                              : Colors.black.withValues(alpha: 0.02),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: ratingColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: ratingColor.withValues(alpha: 0.2)),
                              ),
                              child: Text(
                                rating.label,
                                style: TextStyle(
                                    color: ratingColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                            text: '下次复习: ',
                                            style: TextStyle(
                                                color: textColor,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500)),
                                        TextSpan(
                                          text: '${log.scheduledDays}',
                                          style: TextStyle(
                                            color: isDarkMode
                                                ? Colors.white70
                                                : Colors.black54,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        TextSpan(
                                            text: '天后',
                                            style: TextStyle(
                                                color: textColor,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500)),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    timeStr,
                                    style: TextStyle(
                                        color: textColor.withValues(alpha: 0.5),
                                        fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded,
                                size: 16,
                                color: textColor.withValues(alpha: 0.3)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('关闭', style: TextStyle(color: AppTheme.primaryColor)),
            ),
          ],
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        );
      },
    );
  }


  void _showDebugOverlay() async {
    final user = Global.getLoggedInUser();
    if (user == null) return;

    // 获取今日所有学习单词及其状态
    final words = await LearningService.getTodayLearningWordsFromDb(user.id);
    final activeSteps = state.activeUserStudySteps;

    // 获取用户已掌握的单词 ID 集，用于准确反映调度状态
    final masteredWords = await MyDatabase.instance.masteredWordsDao
        .getMasteredWordsForUser(user.id);
    final masteredWordIds = masteredWords.map((w) => w.wordId).toSet();

    // 助手函数：判断单词是否已掌握 (调度层的一致性逻辑)
    bool isEffectivelyMastered(dynamic word) {
      if (masteredWordIds.contains(word.wordId)) {
        return true;
      }
      if (word.stability != null &&
          (word.stability ?? 0.0) >= Constants.graduationStability) {
        return true;
      }
      return false;
    }

    // 获取单词的拼写
    final Map<String, String> spellings = {};
    for (var w in words) {
      if (!spellings.containsKey(w.wordId)) {
        final wordData =
            await MyDatabase.instance.wordsDao.getWordById(w.wordId);
        spellings[w.wordId] = wordData?.spell ?? w.wordId;
      }
    }

    if (!mounted) return;

    // 分批次并按照学习序号排序
    words.sort((a, b) {
      if (a.batchId != b.batchId) {
        return (a.batchId ?? 0).compareTo(b.batchId ?? 0);
      }
      return a.learningOrder.compareTo(b.learningOrder);
    });

    // 分组：底层调度系统固定是 10 个词为一个学习循环（也就是一个 Batch）
    const int batchSize = 10;
    final Map<int, List<dynamic>> batches = {};
    for (int i = 0; i < words.length; i++) {
      final w = words[i];
      // 计算其实际属于第几个调度轮次 (从 1 开始)
      final chunkId = (i ~/ batchSize) + 1;
      batches.putIfAbsent(chunkId, () => []).add(w);
    }

    // 计算即将到来的待办单元格 sequence
    List<Map<String, dynamic>> pendingCells = [];
    for (var batchId in batches.keys) {
      final batchWords = batches[batchId]!;
      for (int sIndex = 0; sIndex < activeSteps.length; sIndex++) {
        for (var w in batchWords) {
          if (w.todayLearnedTimes == sIndex) {
            pendingCells.add({'wordId': w.wordId, 'sIndex': sIndex});
          }
        }
      }
    }

    String? nextWordId;
    int? nextStepIndex;
    String? currentWordId = state.currentGetWordResult?.learningWord?.word.id;

    if (pendingCells.isNotEmpty) {
      int currentIndex = -1;
      if (currentWordId != null) {
        currentIndex =
            pendingCells.indexWhere((cell) => cell['wordId'] == currentWordId);
      }

      if (currentIndex != -1 && currentIndex + 1 < pendingCells.length) {
        nextWordId = pendingCells[currentIndex + 1]['wordId'];
        nextStepIndex = pendingCells[currentIndex + 1]['sIndex'];
      } else if (currentIndex == -1) {
        nextWordId = pendingCells[0]['wordId'];
        nextStepIndex = pendingCells[0]['sIndex'];
      }
    }

    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: "Debug",
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, anim1, anim2) {
        return const SizedBox.shrink();
      },
      transitionBuilder: (context, anim1, anim2, child) {
        final bool isDark = context.watch<DarkMode>().isDarkMode;
        final Color textColor = isDark ? Colors.white : Colors.black87;
        final Color subTextColor = isDark ? Colors.white70 : Colors.black54;

        Widget buildLegendItem(bool done, bool mastered, String label) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: done
                      ? Colors.green
                      : (isDark
                          ? Colors.white24
                          : Colors.grey.withValues(alpha: 0.3)),
                  borderRadius: mastered
                      ? BorderRadius.circular(2)
                      : BorderRadius.circular(6),
                ),
              ),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 10, color: subTextColor)),
            ],
          );
        }

        return BackdropFilter(
          filter: ImageFilter.blur(
              sigmaX: 5 * anim1.value, sigmaY: 5 * anim1.value),
          child: FadeTransition(
            opacity: anim1,
            child: ScaleTransition(
              scale: CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
              child: AlertDialog(
                backgroundColor: isDark
                    ? const Color(0xFF1E1E1E).withValues(alpha: 0.85)
                    : Colors.white.withValues(alpha: 0.9),
                elevation: 24,
                shadowColor: Colors.black54,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: BorderSide(
                    color: isDark ? Colors.white12 : Colors.black12,
                    width: 0.5,
                  ),
                ),
                titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.blueAccent.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.analytics_outlined,
                              color: Colors.blueAccent, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '今日取词流水线',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: textColor,
                                letterSpacing: 0.5,
                              ),
                            ),
                            Text(
                              '实时调度状态可视化',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: subTextColor,
                                  fontWeight: FontWeight.normal),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        buildLegendItem(true, false, '学过'),
                        buildLegendItem(false, false, '未学'),
                        buildLegendItem(true, true, '已掌握'),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: Colors.green,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: Colors.blueAccent, width: 1.5),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text('当前',
                                style: TextStyle(
                                    fontSize: 10, color: subTextColor)),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white24
                                    : Colors.grey.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                    color: Colors.orange, width: 1.5),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text('下一个',
                                style: TextStyle(
                                    fontSize: 10, color: subTextColor)),
                          ],
                        ),
                      ],
                    ),
                    const Divider(height: 24, thickness: 0.5),
                  ],
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                content: SizedBox(
                  width: 400,
                  height: 520,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: words.isEmpty
                        ? Center(
                            child: Text(
                              '今日还没有学习单词',
                              style: TextStyle(color: subTextColor),
                            ),
                          )
                        : ListView.builder(
                            itemCount: batches.keys.length,
                            physics: const BouncingScrollPhysics(),
                            itemBuilder: (ctx, index) {
                              // 确保批次 ID 按顺序排列
                              final sortedBatchIds = batches.keys.toList()
                                ..sort();
                              int batchId = sortedBatchIds[index];
                              final batchWords = batches[batchId]!;

                              // 判断是否为当前批次
                              final bool isCurrentBatch = batchWords
                                  .any((w) => w.wordId == currentWordId);

                              return Container(
                                margin: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.05)
                                      : Colors.black.withValues(alpha: 0.02),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isCurrentBatch
                                        ? Colors.blueAccent
                                        : (isDark
                                            ? Colors.white12
                                            : Colors.black12),
                                    width: isCurrentBatch ? 2.0 : 1.0,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Batch $batchId',
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color: textColor),
                                    ),
                                    const SizedBox(height: 12),
                                    SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Word Headers
                                          Row(
                                            children: [
                                              const SizedBox(
                                                  width:
                                                      60), // Space for step names
                                              ...batchWords.map((w) {
                                                final isCurrentWord =
                                                    state.currentGetWordResult
                                                            ?.learningWord
                                                            ?.word
                                                            .id ==
                                                        w.wordId;
                                                return Tooltip(
                                                  message:
                                                      spellings[w.wordId] ??
                                                          w.wordId,
                                                  child: Container(
                                                    width: 30,
                                                    alignment:
                                                        Alignment.bottomCenter,
                                                    height:
                                                        70, // Room for rotated text
                                                    child: RotatedBox(
                                                      quarterTurns:
                                                          3, // text going up
                                                      child: Text(
                                                        spellings[w.wordId] ??
                                                            w.wordId,
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: isCurrentWord
                                                              ? Colors
                                                                  .blueAccent
                                                              : textColor,
                                                          fontWeight:
                                                              isCurrentWord
                                                                  ? FontWeight
                                                                      .bold
                                                                  : FontWeight
                                                                      .normal,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              }),
                                              const SizedBox(
                                                  width:
                                                      16), // Padding right for scrolling
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          // Data Rows (Steps)
                                          ...List.generate(activeSteps.length,
                                              (sIndex) {
                                            final stepInfo =
                                                activeSteps[sIndex];
                                            return Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 4),
                                              child: Row(
                                                mainAxisAlignment:
                                                    MainAxisAlignment.start,
                                                children: [
                                                  SizedBox(
                                                    width: 60,
                                                    child: Text(
                                                      '${sIndex + 1}: ${stepInfo.studyStep}',
                                                      style: TextStyle(
                                                          fontSize: 10,
                                                          color: subTextColor),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                  ...batchWords.map((w) {
                                                    // Is the user learning this exact word in this exact step right now?
                                                    final isCurrentStep =
                                                        state.currentGetWordResult
                                                                    ?.learningWord
                                                                    ?.word
                                                                    .id ==
                                                                w.wordId &&
                                                            w.todayLearnedTimes ==
                                                                sIndex;
                                                    final isNextStep =
                                                        nextWordId ==
                                                                w.wordId &&
                                                            nextStepIndex ==
                                                                sIndex;
                                                    // 已掌握的唯一标准：稳定度大于等于毕业阈值，或者在已掌握表中
                                                    final isWordFinished =
                                                        isEffectivelyMastered(
                                                            w);

                                                    // 从用户视角看：如果我处于这个环节，或者处于之后的环节，或者单词已掌握，则该格显绿
                                                    final isStepCompleted =
                                                        isWordFinished ||
                                                            w.todayLearnedTimes >
                                                                sIndex ||
                                                            isCurrentStep;

                                                    return Container(
                                                      width: 30,
                                                      alignment:
                                                          Alignment.center,
                                                      child: Container(
                                                        width: 14,
                                                        height: 14,
                                                        decoration:
                                                            BoxDecoration(
                                                          color: isStepCompleted
                                                              ? Colors.green
                                                              : (isDark
                                                                  ? Colors
                                                                      .white24
                                                                  : Colors.grey
                                                                      .withValues(
                                                                          alpha:
                                                                              0.3)),
                                                          borderRadius:
                                                              isWordFinished
                                                                  ? BorderRadius
                                                                      .circular(
                                                                          3)
                                                                  : BorderRadius
                                                                      .circular(
                                                                          7), // 矩形(圆角3)/圆形(圆角7)
                                                          border: isCurrentStep
                                                              ? Border.all(
                                                                  color: Colors
                                                                      .blueAccent,
                                                                  width: 2)
                                                              : (isNextStep
                                                                  ? Border.all(
                                                                      color: Colors
                                                                          .orange,
                                                                      width: 2)
                                                                  : null),
                                                        ),
                                                      ),
                                                    );
                                                  }),
                                                  const SizedBox(
                                                      width:
                                                          16), // Padding right for scrolling
                                                ],
                                              ),
                                            );
                                          }),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ),
                actions: [
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text('我知道了',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRichReason(String text, BuildContext context) {
    final isDarkMode = context.read<DarkMode>().isDarkMode;
    final Map<String, Color> labelColors = {
      FsrsRating.again.label: _getRatingColor(FsrsRating.again, isDarkMode),
      FsrsRating.hard.label: _getRatingColor(FsrsRating.hard, isDarkMode),
      FsrsRating.easy.label: _getRatingColor(FsrsRating.easy, isDarkMode),
      FsrsRating.good.label: _getRatingColor(FsrsRating.good, isDarkMode),
    };

    List<InlineSpan> spans = [];
    String pattern = labelColors.keys.map((l) => RegExp.escape(l)).join('|');
    RegExp regex = RegExp(pattern);

    int lastIndex = 0;
    for (Match match in regex.allMatches(text)) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(text: text.substring(lastIndex, match.start)));
      }
      String label = match.group(0)!;
      spans.add(TextSpan(
        text: label,
        style: TextStyle(
            color: labelColors[label],
            fontFamily: "NotoSansSC"),
      ));
      lastIndex = match.end;
    }
    if (lastIndex < text.length) {
      spans.add(TextSpan(text: text.substring(lastIndex)));
    }

    return Text.rich(
      TextSpan(children: spans),
      style: const TextStyle(
        fontSize: 13,
        height: 1.4,
        color: AppTheme.primaryColor,
        fontFamily: "NotoSansSC",
      ),
    );
  }
}
