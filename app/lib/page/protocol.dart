import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../theme/app_theme.dart';

class ProtocolPage extends StatefulWidget {
  const ProtocolPage({super.key});

  @override
  ProtocolPageState createState() {
    return ProtocolPageState();
  }
}

class ProtocolPageState extends State<ProtocolPage> {
  final GlobalKey webViewKey = GlobalKey();
  InAppWebViewController? webViewController;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppTheme.createGradientAppBar(
        title: '用户使用协议',
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
      ),
    );
  }

  _loadHtmlFromAssets() async {
    String fileText = await rootBundle.loadString('assets/protocol.html');
    webViewController!.loadData(data: fileText, mimeType: 'text/html', encoding: 'utf-8');
  }
}
