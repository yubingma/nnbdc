import 'package:flutter/material.dart';
import '../widget/legal_document_page.dart';

/// 用户使用协议页面
class ProtocolPage extends StatelessWidget {
  const ProtocolPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalDocumentPage(
      title: '用户使用协议',
      iosAssetPath: 'assets/protocol.html',
      androidAssetPath: 'assets/protocol_android.html',
    );
  }
}
