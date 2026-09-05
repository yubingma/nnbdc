import 'dart:ui' as ui;

import 'package:chat_bubbles/chat_bubbles.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/util/toast_util.dart';

import '../global.dart';
import '../util/client_type.dart';
import '../theme/app_theme.dart';

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
  bool _isSending = false;

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
    } catch (e) {
      msgs = [];
    }

    if (mounted) {
      setState(() {
        dataLoaded = true;
      });
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || _isSending) {
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
      final result = await Api.client.sendAdvice(_messageController.text.trim(), clientType.name, user.id);
      if (result.success) {
        if (result.data != null) {
          // 意见建议兑换会员成功，立即更新本地数据库与内存用户状态
          await MyDatabase.instance.usersDao.saveUser(userVo2User(result.data!), false);
        }
        _messageController.clear();
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
      reverse: true, // 自动滚动到最后
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      children: [
        for (var msg in msgs)
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

  // 系统/客服回复：左侧奶牛头像 + 中性色气泡
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
          child: BubbleSpecialOne(
            text: msg.content,
            color: bubbleColor,
            textStyle: _bubbleStyle(context.textPrimary),
            tail: true,
            isSender: false,
          ),
        ),
      ],
    );
  }

  Widget _buildAdminAvatar(MsgVo msg) {
    return SizedBox(
      height: 40,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          const Image(
            image: AssetImage("assets/images/cow.png"),
            height: 40,
            gaplessPlayback: true,
          ),
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

  // 用户发出的消息：右侧主题色气泡 + 我
  Widget _buildSenderRow(MsgVo msg) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Flexible(
          child: BubbleSpecialOne(
            text: msg.content,
            color: context.primaryColor,
            textStyle: const TextStyle(
              fontSize: 15,
              height: 1.45,
              color: Colors.white,
              fontFamily: 'NotoSansSC',
            ),
            tail: true,
            isSender: true,
          ),
        ),
        const SizedBox(width: 6),
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Text(
            '我',
            style: TextStyle(fontSize: 12, color: context.textSecondary, fontFamily: 'NotoSansSC'),
          ),
        ),
      ],
    );
  }

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
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
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
              ),
            ),
          ),
        ),
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
    List<String> msgIds = [];
    for (var msg in msgs) {
      msgIds.add(msg.id);
    }
    Api.client.setMsgsAsViewed(msgIds, Global.getLoggedInUser()!.id);
    _messageController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
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
