import 'package:chat_bubbles/chat_bubbles.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:nnbdc/api/api.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:provider/provider.dart';

import '../global.dart';
import '../util/utils.dart';
import '../state.dart';
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

  static const double leftPadding = 16;
  static const double rightPadding = 16;

  @override
  void initState() {
    super.initState();
    loadData();
  }

  Future<void> loadData() async {
    msgs = await Api.client.getLastestMsgsBetweenUserAndSys(Global.getLoggedInUser()!.id, 9999);

    setState(() {
      dataLoaded = true;
    });
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || _isSending) {
      return;
    }

    setState(() {
      _isSending = true;
    });

    try {
      final result = await Api.client.sendAdvice(_messageController.text.trim(), Global.getLoggedInUser()!.id);
      if (result.success) {
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

  Widget renderPage() {
    return ListView(
      reverse: true, // 自动滚动到最后
      children: [
        Column(
          children: [
            for (var msg in msgs)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Column(
                  children: [
                    Text(DateFormat('yyyy-MM-dd HH:mm').format(msg.createTime), style: const TextStyle(color: Colors.grey)),
                    Util.getNickNameOfUser(msg.fromUser) == '牛牛'
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Image(
                                image: AssetImage("assets/images/cow.png"),
                                height: 40,
                              ),
                              Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
                                    child: BubbleSpecialOne(
                                      text: msg.content,
                                      color: Color(msg.viewed ? 0xFFE8E8EE : 0xFF1B97F3),
                                      textStyle: TextStyle(color: msg.viewed ? Colors.black : Colors.white),
                                      tail: true,
                                      isSender: false,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          )
                        // 用户发出的消息
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(0, 4, 0, 0),
                                child: BubbleSpecialOne(
                                  text: msg.content,
                                  color: const Color(0xFFE8E8EE),
                                  tail: true,
                                  isSender: true,
                                ),
                              ),
                              const Text('我', style: TextStyle(fontSize: 16)),
                            ],
                          ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildInputArea() {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF1A1A1A) : Colors.white;
    final borderColor = isDarkMode ? Colors.grey[700] : Colors.grey[300];
    final textColor = isDarkMode ? Colors.white : Colors.black87;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border(
          top: BorderSide(
            color: borderColor!,
            width: 0.5,
          ),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: isDarkMode ? Colors.grey[800] : Colors.grey[100],
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: borderColor.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                child: TextField(
                  controller: _messageController,
                  focusNode: _focusNode,
                  maxLines: 4,
                  minLines: 1,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 16,
                    fontFamily: 'NotoSansSC',
                  ),
                  decoration: InputDecoration(
                    hintText: '输入您的意见建议...',
                    hintStyle: TextStyle(
                      color: isDarkMode ? Colors.grey[500] : Colors.grey[600],
                      fontSize: 16,
                      fontFamily: 'NotoSansSC',
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    border: InputBorder.none,
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [
                    AppTheme.gradientStartColor,
                    AppTheme.gradientEndColor,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primaryColor.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: _isSending ? null : _sendMessage,
                  child: Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    child: _isSending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(
                            Icons.send_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                  ),
                ),
              ),
            ),
          ],
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
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final backgroundColor = isDarkMode ? const Color(0xFF121212) : const Color(0xFFF8F9FA);

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppTheme.createGradientAppBar(
        title: '意见建议',
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back, color: Colors.white),
        ),
      ),
      body: Column(
        children: [
          // 消息列表区域
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(leftPadding, 16, rightPadding, 0),
              child: (!dataLoaded) ? const Center(child: Text('')) : renderPage(),
            ),
          ),
          // 底部输入框
          _buildInputArea(),
        ],
      ),
    );
  }
}
