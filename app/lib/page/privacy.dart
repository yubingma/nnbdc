import 'package:flutter/material.dart';
import '../widget/legal_document_page.dart';

/// 隐私政策页面
class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegalDocumentPage(
      title: '隐私政策',
      iosAssetPath: 'assets/privacy.html',
      androidAssetPath: 'assets/privacy_android.html',
    );
  }
}
