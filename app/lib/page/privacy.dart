import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../theme/app_theme.dart';

class PrivacyPage extends StatefulWidget {
  const PrivacyPage({super.key});

  @override
  PrivacyPageState createState() {
    return PrivacyPageState();
  }
}

class PrivacyPageState extends State<PrivacyPage> {
  final GlobalKey webViewKey = GlobalKey();
  InAppWebViewController? webViewController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppTheme.createGradientAppBar(
          title: '隐私政策',
          leading: IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
        ),
        body: Container(
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
          child: InAppWebView(
            key: webViewKey,
            initialUrlRequest: URLRequest(url: WebUri("about:blank")),
            onWebViewCreated: (InAppWebViewController controller) {
              webViewController = controller;
              _loadHtmlFromAssets();
            },
          ),
        ));
  }

  _loadHtmlFromAssets() async {
    String fileText = await rootBundle.loadString('assets/privacy.html');
    webViewController!.loadData(data: fileText, mimeType: 'text/html', encoding: 'utf-8');
  }
}
