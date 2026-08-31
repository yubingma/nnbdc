import 'package:flutter/material.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/config.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/utils.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/util/toast_util.dart';

class WordImagesWidget extends StatefulWidget {
  final List<WordImageVo> images;
  final bool isEditMode;
  final Function(WordImageVo) onImageTap;
  final String? highlightedWordImg;
  final int maxImages;

  const WordImagesWidget({
    super.key,
    required this.images,
    required this.isEditMode,
    required this.onImageTap,
    this.highlightedWordImg,
    this.maxImages = 2,
  });

  @override
  State<WordImagesWidget> createState() => _WordImagesWidgetState();
}

class _WordImagesWidgetState extends State<WordImagesWidget> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 使用实际可用宽度而不是屏幕宽度
        final availableWidth = constraints.maxWidth;
        final imageCount = 2; // 每行显示2张图片
        final spacing = 12.0; // 固定间距

        // 动态计算较大图片的宽度，同时在Web上限制最大尺寸
        double imageWidth = (availableWidth - spacing) / imageCount - 0.1;
        if (PlatformUtils.isWeb && imageWidth > 320.0) {
          imageWidth = 320.0;
        }
        final imageHeight = imageWidth * 0.75; // 4:3比例计算高度

        return Container(
          margin: const EdgeInsets.fromLTRB(0, 12, 0, 12),
          width: availableWidth,
          alignment: Alignment.center,
          child: Wrap(
            alignment: WrapAlignment.center, // 居中对齐
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: spacing,
            runSpacing: 12.0, // 行间距
            children: [
              for (var image in widget.images.take(widget.maxImages))
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Global.logger
                        .d('GestureDetector onTap image: ${image.imageFile}');
                    widget.onImageTap(image);
                  },
                  child: SizedBox(
                    width: imageWidth,
                    child: IgnorePointer(
                      ignoring: true,
                      child: Builder(
                        builder: (context) {
                          final imageUrl = Uri.encodeFull('${Config.imgBaseUrl}word/${image.imageFile}');
                          Global.logger.d('加载单词图片 [做题区]: $imageUrl');
                          return Image.network(
                            imageUrl,
                            width: imageWidth,
                            height: imageHeight,
                            fit: BoxFit.contain,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    value: loadingProgress.expectedTotalBytes !=
                                            null
                                        ? loadingProgress.cumulativeBytesLoaded /
                                            loadingProgress.expectedTotalBytes!
                                        : null,
                                    strokeWidth: 2,
                                    color: Colors.indigoAccent,
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) {
                              Global.logger.e('图片加载失败 [做题区]: $imageUrl', error: error);
                              // 图片加载失败，显示错误图标，不尝试解码
                              return const Center(
                                child: Icon(
                                  Icons.broken_image,
                                  color: Colors.red,
                                  size: 24,
                                ),
                              );
                            },
                          );
                        }
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// 预览单词配图的大图弹窗（使用当前上下文）
void showImagePreviewWithContext(BuildContext context, WordImageVo image,
    {VoidCallback? onDeleted}) {
  Global.logger.d('showDialog start for image: ${image.imageFile}');
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      Global.logger.d('showDialog builder for image: ${image.imageFile}');
      return Dialog(
        insetPadding: const EdgeInsets.all(16),
        backgroundColor: Colors.transparent,
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(8),
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 3.0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 作者昵称
                    Builder(
                      builder: (context) {
                        String authorName = Util.getNickNameOfUser(image.author);
                        if (authorName.isEmpty) {
                          final current = Global.getLoggedInUser();
                          final authorId = image.author.id;
                          if (current != null && (authorId == current.id || authorId == null || authorId.isEmpty)) {
                            authorName = (current.nickName != null && current.nickName!.trim().isNotEmpty)
                                ? current.nickName!.trim()
                                : current.userName;
                          }
                        }
                        if (authorName.isEmpty || authorName == '系统用户') {
                          authorName = '泡泡';
                        }
                        return Padding(
                          padding:
                              const EdgeInsets.only(left: 8, right: 40, bottom: 8),
                          child: Text(
                            '上传者: $authorName',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500),
                          ),
                        );
                      },
                    ),
                    // 大图
                    Builder(
                      builder: (context) {
                        final imageUrl = Uri.encodeFull('${Config.imgBaseUrl}word/${image.imageFile}');
                        Global.logger.d('加载单词图片 [预览弹窗]: $imageUrl');
                        return Image.network(
                          imageUrl,
                          width: PlatformUtils.isWeb ? 720.0 : double.infinity,
                          height: PlatformUtils.isWeb ? 480.0 : 360.0,
                          fit: BoxFit.contain,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return const Center(
                              child: CircularProgressIndicator(color: Colors.white),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            Global.logger.e('图片加载失败 [预览弹窗]: $imageUrl', error: error);
                            return const Center(
                              child: Icon(Icons.broken_image,
                                  color: Colors.red, size: 48),
                            );
                          },
                        );
                      }
                    ),
                  ],
                ),
              ),
            ),
            // 右上角关闭按钮
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            // 右下角删除按钮（仅作者本人或管理员可见）
            if (image.author.id == Global.getLoggedInUser()?.id ||
                (Global.getLoggedInUser()?.isAdmin ?? false) ||
                (Global.getLoggedInUser()?.isSuperAdmin ?? false))
              Positioned(
                right: 8,
                bottom: 8,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                    backgroundColor: Colors.red,
                  ),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('删除'),
                  onPressed: () async {
                    try {
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                      final result = await Api.client.deleteWordImage(
                          image.id, Global.getLoggedInUser()!.id);
                      if (result.success) {
                        ToastUtil.info('删除成功');
                        // 本地同步移除 SQLite 记录
                        try {
                          await MyDatabase.instance.wordImagesDao.deleteById(image.id);
                        } catch (e, s) {
                          Global.logger.e('删除本地WordImages失败', error: e, stackTrace: s);
                        }
                        // 触发页面即时重绘
                        if (onDeleted != null) {
                          onDeleted();
                        }
                      } else {
                        ToastUtil.error(result.msg ?? '删除失败');
                      }
                    } catch (e, s) {
                      Global.logger.e('删除图片异常', error: e, stackTrace: s);
                      ToastUtil.error('删除异常');
                    }
                  },
                ),
              ),
          ],
        ),
      );
    },
  );
}
