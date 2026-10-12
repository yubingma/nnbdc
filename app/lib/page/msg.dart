import 'dart:convert';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/util/advice_content.dart';
import 'package:nnbdc/util/permission_util.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:permission_handler/permission_handler.dart';

import '../global.dart';
import '../util/client_type.dart';
import '../theme/app_theme.dart';
import '../theme/page_vibrancy.dart';

class MsgPage extends StatefulWidget {
  const MsgPage({super.key});

  @override
  MsgPageState createState() {
    return MsgPageState();
  }
}

class MsgPageState extends State<MsgPage> {
  bool dataLoaded = false;
  late List<MsgVo> msgs;
  final TextEditingController _messageController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;

  /// 已经选好、还没随消息发出去的截图
  final List<AdviceImageAttachment> _pendingImages = [];

  /// 泡泡单词品牌 logo，作为系统自动回复的客服头像
  static const String _bubbleLogoAsset = 'assets/images/logo.png';

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    final user = Global.getLoggedInUser();
    if (user == null || Global.isGuest) {
      if (mounted) {
        setState(() {
          msgs = [];
          dataLoaded = true;
        });
      }
      return;
    }

    try {
      msgs = await Api.client.getLastestMsgsBetweenUserAndSys(user.id, 9999);
      // 尊重传统聊天气泡习惯：老消息在上、新消息在下（List 内按时间升序保存）
      msgs.sort((a, b) => a.createTime.compareTo(b.createTime));
    } catch (e) {
      msgs = [];
    }

    if (mounted) {
      setState(() {
        dataLoaded = true;
      });
      _scrollToBottom();
    }
  }

  /// 普通滚动视图下，把最新消息滚到底部；消息不足一屏时自然停留在顶部（先从上方开始排布）
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if ((_scrollController.position.pixels - target).abs() > 1) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if ((text.isEmpty && _pendingImages.isEmpty) || _isSending) {
      return;
    }

    final user = Global.getLoggedInUser();
    if (user == null || Global.isGuest) {
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
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: context.primaryColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

    setState(() {
      _isSending = true;
    });

    try {
      final clientType = getClientType();
      // 只发截图、没打字时给一句占位正文，服务端不允许空内容
      final content = text.isEmpty ? AdviceContent.screenshotOnlyText : text;
      final imagePaths = _pendingImages
          .map((image) => image.uploadedPath)
          .whereType<String>()
          .toList();
      final result = await Api.client.sendAdvice(
        content,
        clientType.name,
        user.id,
        imageFiles: imagePaths.isEmpty ? null : jsonEncode(imagePaths),
      );
      if (result.success) {
        if (result.data != null) {
          // 意见建议兑换会员成功，立即更新本地数据库与内存用户状态
          await MyDatabase.instance.usersDao.saveUser(userVo2User(result.data!), false);
        }
        _messageController.clear();
        _pendingImages.clear();
        ToastUtil.info("发送成功");
        // 重新加载消息列表
        await loadData();
      } else {
        ToastUtil.error(result.msg ?? "发送失败");
      }
    } catch (e) {
      ToastUtil.error("发送失败");
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }

  /// 选截图并上传。上传失败的图一张都不会留在待发送列表里，避免"看起来发出去了其实没图"。
  Future<void> _pickImages() async {
    if (_isSending) return;

    final user = Global.getLoggedInUser();
    if (user == null || Global.isGuest) {
      ToastUtil.info('登录后才能发送截图');
      return;
    }

    final source = await AdviceImages.pickSource(context);
    if (source == null || !mounted) return;

    await PermissionUtil.requestWithRationale(
      permission: source == ImageSource.camera ? Permission.camera : Permission.photos,
      title: source == ImageSource.camera ? '相机权限' : '相册/存储权限',
      purpose: source == ImageSource.camera ? '用于拍下问题现场发给客服。' : '用于把手机里的截图发给客服。',
      icon: source == ImageSource.camera ? Icons.camera_alt_rounded : Icons.photo_library_rounded,
      onGranted: () => _uploadPickedImages(user.id, source),
    );
  }

  Future<void> _uploadPickedImages(String userId, ImageSource source) async {
    try {
      final picked = await AdviceImages.pickAndUpload(
        context: context,
        userId: userId,
        source: source,
        baseline: _pendingImages,
      );
      if (picked.isEmpty || !mounted) return;
      setState(() {
        _pendingImages.addAll(picked);
      });
    } catch (e) {
      if (mounted) {
        ToastUtil.error(e.toString().replaceFirst('Exception: ', ''));
      }
    }
  }

  // ---- 消息列表 ----

  Widget _buildMessageArea() {
    final accentColor = context.primaryColor;

    if (!dataLoaded) {
      return Center(child: CircularProgressIndicator(color: accentColor));
    }

    if (msgs.isEmpty) {
      return _buildEmptyState();
    }

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      children: [
        // 升序遍历：老消息在上、新消息在下；加载后自动滚到底部看到最新一条
        for (final msg in msgs)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              children: [
                _buildTimestamp(msg),
                const SizedBox(height: 10),
                (msg.msgType == 'AdviceReply')
                    ? _buildAdminRow(msg)
                    : _buildSenderRow(msg),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildTimestamp(MsgVo msg) {
    return Text(
      DateFormat('yyyy-MM-dd HH:mm').format(msg.createTime.toLocal()),
      style: TextStyle(
        fontSize: 11.5,
        letterSpacing: 0.2,
        color: context.textMuted,
        fontFamily: 'NotoSansSC',
      ),
    );
  }

  TextStyle _bubbleStyle(Color color) => TextStyle(
        fontSize: 15,
        height: 1.45,
        letterSpacing: 0,
        color: color,
        fontFamily: 'NotoSansSC',
      );

  /// 气泡里的内容：引用块 + 正文 + 随消息发上来的截图
  Widget _buildBubbleContent(MsgVo msg, {required Color textColor}) {
    final text = AdviceContent.text(msg.content);
    final images = AdviceContent.imageFiles(msg.content);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (msg.quotedMsgId != null) _buildQuoteBlock(msg, textColor: textColor),
        if (text.isNotEmpty) Text(text, style: _bubbleStyle(textColor)),
        if (images.isNotEmpty) ...[
          if (text.isNotEmpty) const SizedBox(height: 6),
          _buildMessageImages(images),
        ],
      ],
    );
  }

  /// 引用块：明明白白告诉用户「这条回复是在回你哪一句」
  Widget _buildQuoteBlock(MsgVo msg, {required Color textColor}) {
    final quoted = AdviceContent.preview(msg.quotedContent ?? '', maxLength: 60);
    final hasQuoted = quoted.isNotEmpty;
    // 用户自己的话在气泡上方标「我」，管理员的话标「客服」
    final speaker = msg.quotedMsgType == 'AdviceReply' ? '客服' : '我';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: textColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: textColor.withValues(alpha: 0.35), width: 2),
        ),
      ),
      child: Text(
        hasQuoted ? '$speaker：$quoted' : '原消息已删除',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12.5,
          height: 1.35,
          color: textColor.withValues(alpha: 0.72),
          fontFamily: 'NotoSansSC',
        ),
      ),
    );
  }

  /// 截图预览：点击看大图。用 contain 完整显示，避免长截图被裁掉关键信息。
  Widget _buildMessageImages(List<String> imageFiles) {
    final isDarkMode = context.isDarkMode;
    return SizedBox(
      height: 160,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        shrinkWrap: true,
        itemCount: imageFiles.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final url = AdviceContent.imageUrl(imageFiles[index]);
          return GestureDetector(
            onTap: () => _showImagePreview(url),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 160,
                color: isDarkMode ? const Color(0xFF2A333D) : Colors.black.withValues(alpha: 0.04),
                child: CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.contain,
                  placeholder: (_, __) => const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  errorWidget: (_, __, ___) => Icon(
                    Icons.broken_image_outlined,
                    color: isDarkMode ? Colors.white38 : Colors.black26,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showImagePreview(String url) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: InteractiveViewer(
            child: CachedNetworkImage(imageUrl: url, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  // 系统/客服回复：左侧头像（管理员头像 / 泡泡 logo）+ 中性色气泡
  Widget _buildAdminRow(MsgVo msg) {
    final isDarkMode = context.isDarkMode;
    final bubbleColor = isDarkMode ? const Color(0xFF27313B) : Colors.white;

    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildAdminAvatar(msg),
        const SizedBox(width: 8),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: _buildBubbleContent(msg, textColor: context.textPrimary),
          ),
        ),
      ],
    );
  }

  Widget _buildAdminAvatar(MsgVo msg) {
    // 自动回复来自系统账号（userName=sys），使用泡泡 logo；人工管理员回复使用其头像
    final isAutoReply = _isAutoReply(msg);
    final adminAvatar = msg.fromUser.wechatAvatar ?? '';
    final avatar = isAutoReply
        ? _buildAvatar(assetName: _bubbleLogoAsset, radius: 20)
        : _buildAvatar(
            url: adminAvatar.isEmpty ? null : adminAvatar,
            assetName: adminAvatar.isEmpty ? _bubbleLogoAsset : null,
            radius: 20,
          );

    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          // 未读的新回复：头像右上角轻量主题色小圆点
          if (!msg.viewed)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: context.primaryColor,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // 用户发出的消息：右侧主题色气泡 + 用户头像（顶部对齐，与左侧管理员头像对称）
  Widget _buildSenderRow(MsgVo msg) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: context.primaryColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
                bottomLeft: Radius.circular(14),
                bottomRight: Radius.circular(4),
              ),
            ),
            child: _buildBubbleContent(msg, textColor: Colors.white),
          ),
        ),
        const SizedBox(width: 6),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: _buildUserAvatar(),
        ),
      ],
    );
  }

  // 当前登录用户头像（无头像时取昵称首字占位）
  Widget _buildUserAvatar() {
    final user = Global.getLoggedInUser();
    final avatar = user?.wechatAvatar ?? '';
    final name = user?.nickName ?? '我';
    return _buildAvatar(
      url: avatar.isEmpty ? null : avatar,
      initial: name,
      radius: 17,
    );
  }

  Widget _buildAvatar({String? url, String? assetName, String? initial, required double radius}) {
    if (url != null && url.isNotEmpty) {
      return CircleAvatar(radius: radius, backgroundImage: CachedNetworkImageProvider(url));
    }
    if (assetName != null) {
      return CircleAvatar(radius: radius, backgroundImage: AssetImage(assetName));
    }
    final name = initial ?? '我';
    final first = name.runes.isEmpty ? '我' : String.fromCharCode(name.runes.first);
    return CircleAvatar(
      radius: radius,
      backgroundColor: context.primaryColor.withValues(alpha: 0.16),
      child: Text(
        first,
        style: TextStyle(
          fontSize: radius * 0.78,
          fontWeight: FontWeight.w700,
          color: context.primaryColor,
          fontFamily: 'NotoSansSC',
        ),
      ),
    );
  }

  // 系统自动回复账号：服务端 Constants.SYS_USER_SYS = "sys" / SYS_USER_SYS_ID = "15118"
  bool _isAutoReply(MsgVo msg) =>
      msg.fromUser.userName == 'sys' || msg.fromUser.id == '15118';

  Widget _buildEmptyState() {
    final accent = context.primaryColor;
    final muted = context.textMuted;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.08),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.chat_bubble_outline_rounded, size: 28, color: accent.withValues(alpha: 0.55)),
          ),
          const SizedBox(height: 14),
          Text(
            '还没有消息',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: context.textPrimary, fontFamily: 'NotoSansSC'),
          ),
          const SizedBox(height: 6),
          Text(
            '留下你的宝贵建议，我们会认真对待',
            style: TextStyle(fontSize: 12.5, color: muted, fontFamily: 'NotoSansSC'),
          ),
        ],
      ),
    );
  }

  // ---- 底部输入区 ----

  Widget _buildInputArea() {
    final isDarkMode = context.isDarkMode;
    final textColor = context.textPrimary;
    final hintColor = context.textMuted;
    final fieldBg = isDarkMode ? const Color(0xFF232C37) : const Color(0xFFF0F3F7);
    final fieldBorder = isDarkMode ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04);
    const inputRadius = BorderRadius.vertical(top: Radius.circular(20));

    // 局部毛玻璃输入区：仅模糊输入条自身的圆角几何区域，屏幕其余部分保持清晰；
    // sigma=6 既能晕开底下消息文字的轮廓，又保留温柔的水墨暗斑质感。
    return Container(
      decoration: BoxDecoration(
        borderRadius: inputRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDarkMode ? 0.35 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: inputRadius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDarkMode
                    ? const [Color(0xB8161B26), Color(0x9910141D)]
                    : const [Color(0x66FFFFFF), Color(0x4DFFFFFF)],
              ),
              border: Border.all(
                color: isDarkMode ? const Color(0x33FFFFFF) : const Color(0x80FFFFFF),
                width: 1.0,
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_pendingImages.isNotEmpty) ...[
                      _buildPendingImagesRow(),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _buildPickImageButton(),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: fieldBg,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(color: fieldBorder, width: 1),
                            ),
                            child: TextField(
                              controller: _messageController,
                              focusNode: _focusNode,
                              maxLines: 4,
                              minLines: 1,
                              style: TextStyle(color: textColor, fontSize: 15, fontFamily: 'NotoSansSC'),
                              decoration: InputDecoration(
                                hintText: '输入您的意见建议...',
                                hintStyle: TextStyle(color: hintColor, fontSize: 15, fontFamily: 'NotoSansSC'),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                border: InputBorder.none,
                              ),
                              onSubmitted: (_) => _sendMessage(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _buildSendButton(),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 加号：选截图（相册 / 拍照）并上传，发出去之前还能单张删掉
  Widget _buildPickImageButton() {
    final isDarkMode = context.isDarkMode;
    return GestureDetector(
      onTap: _isSending ? null : _pickImages,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF232C37) : const Color(0xFFF0F3F7),
          shape: BoxShape.circle,
          border: Border.all(
            color: isDarkMode ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
          ),
        ),
        child: Icon(
          Icons.add_photo_alternate_outlined,
          size: 22,
          color: context.textSecondary,
        ),
      ),
    );
  }

  /// 待发送截图的缩略图，右上角一个小叉可以移除
  Widget _buildPendingImagesRow() {
    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        shrinkWrap: true,
        itemCount: _pendingImages.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final image = _pendingImages[index];
          return Stack(
            clipBehavior: Clip.none,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(image.bytes, width: 64, height: 64, fit: BoxFit.cover),
              ),
              Positioned(
                right: -6,
                top: -6,
                child: GestureDetector(
                  onTap: () => setState(() => _pendingImages.removeAt(index)),
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                    child: const Icon(Icons.close_rounded, size: 13, color: Colors.white),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSendButton() {
    final accent = context.primaryColor;
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: context.appBarGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: _isSending ? null : _sendMessage,
          child: Center(
            child: _isSending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    final List<String> msgIds = msgs.map((m) => m.id).toList();
    final user = Global.getLoggedInUser();
    // 没有消息（或未登录）时无需请求后端，避免空列表导致服务端 400
    if (msgIds.isNotEmpty && user != null) {
      Api.client.setMsgsAsViewed(msgIds, user.id);
    }
    _messageController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      vibrancy: PageVibrancy.message,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        // 顶栏透明化：让顶部与主题晨雾流光背景无缝融合，状态栏图标颜色随主题切换
        systemOverlayStyle: context.isDarkMode ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: context.textSecondary, size: 19),
        ),
        title: Text(
          '意见建议',
          style: TextStyle(
            color: context.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            fontFamily: 'NotoSansSC',
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // 消息列表区域
          Expanded(child: _buildMessageArea()),
          // 底部输入框
          _buildInputArea(),
        ],
      ),
    );
  }
}
