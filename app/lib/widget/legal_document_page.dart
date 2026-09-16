import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../global.dart';
import '../state.dart';
import '../theme/app_theme.dart';
import '../theme/page_vibrancy.dart';
import '../util/platform_util.dart';
import 'app_scaffold.dart';
import 'frosted_glass_card.dart';

/// 统一法律文档展示页面（用户协议 / 隐私政策）
///
/// 遵循 `app-ui-aesthetic` 极简排版规范：
/// 1. 接入统一流光背景 [AppScaffold] + [PageVibrancy.base]；
/// 2. 现代极简沉浸式透明 AppBar，返回键与标题字阶严格对齐；
/// 3. 通透毛玻璃大卡片容器 [FrostedGlassCard] + 响应式最大宽度居中约束；
/// 4. 动态注入跨平台现代字体栈与深浅色主题 CSS 排版引擎，支持毫秒级无缝换肤；
/// 5. 超链接外部安全唤起拦截。
class LegalDocumentPage extends StatefulWidget {
  final String title;
  final String iosAssetPath;
  final String androidAssetPath;

  const LegalDocumentPage({
    super.key,
    required this.title,
    required this.iosAssetPath,
    required this.androidAssetPath,
  });

  @override
  State<LegalDocumentPage> createState() => _LegalDocumentPageState();
}

class _LegalDocumentPageState extends State<LegalDocumentPage> {
  final GlobalKey _webViewKey = GlobalKey();
  InAppWebViewController? _webViewController;
  bool _isLoading = true;
  bool? _lastIsDark;
  Color? _lastAccentColor;

  String get _assetPath =>
      PlatformUtils.isAndroid ? widget.androidAssetPath : widget.iosAssetPath;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final themeStyle = context.watch<DarkMode>().themeStyle;
    final isDark = themeStyle.isDark;
    final accentColor = context.primaryColor;

    if (_lastIsDark != null &&
        (_lastIsDark != isDark || _lastAccentColor != accentColor)) {
      _updateThemeInWebView(isDark, accentColor);
    }
    _lastIsDark = isDark;
    _lastAccentColor = accentColor;
  }

  void _updateThemeInWebView(bool isDark, Color accentColor) {
    if (_webViewController == null) return;
    final primaryHex = _colorToHex(accentColor);
    final primaryLight = _colorToRgba(accentColor, isDark ? 0.12 : 0.08);
    final primaryBorder = _colorToRgba(accentColor, isDark ? 0.28 : 0.18);

    final js = '''
      (function() {
        try {
          document.body.className = '${isDark ? 'dark-theme' : 'light-theme'}';
          document.documentElement.style.setProperty('--color-primary', '$primaryHex');
          document.documentElement.style.setProperty('--color-primary-light', '$primaryLight');
          document.documentElement.style.setProperty('--color-primary-border', '$primaryBorder');
        } catch(e) {}
      })();
    ''';
    _webViewController?.evaluateJavascript(source: js);
  }

  String _colorToHex(Color color) {
    final r = ((color.r * 255).round().clamp(0, 255)).toRadixString(16).padLeft(2, '0');
    final g = ((color.g * 255).round().clamp(0, 255)).toRadixString(16).padLeft(2, '0');
    final b = ((color.b * 255).round().clamp(0, 255)).toRadixString(16).padLeft(2, '0');
    return '#$r$g$b';
  }

  String _colorToRgba(Color color, double alpha) {
    final r = (color.r * 255).round().clamp(0, 255);
    final g = (color.g * 255).round().clamp(0, 255);
    final b = (color.b * 255).round().clamp(0, 255);
    return 'rgba($r, $g, $b, ${alpha.toStringAsFixed(2)})';
  }

  Future<void> _loadHtmlContent() async {
    if (_webViewController == null) return;

    try {
      String rawHtml = await rootBundle.loadString(_assetPath);
      if (!mounted) return;
      rawHtml = rawHtml.replaceAll('泡泡单词', Global.appName);

      final isDark = context.read<DarkMode>().themeStyle.isDark;
      final accentColor = context.primaryColor;

      final themedHtml = _buildThemedHtml(
        rawContent: rawHtml,
        isDark: isDark,
        accentColor: accentColor,
      );

      await _webViewController?.loadData(
        data: themedHtml,
        mimeType: 'text/html',
        encoding: 'utf-8',
      );
    } catch (e) {
      Global.logger.e('加载法律文档 HTML 失败: $e');
    }
  }

  String _buildThemedHtml({
    required String rawContent,
    required bool isDark,
    required Color accentColor,
  }) {
    final primaryHex = _colorToHex(accentColor);
    final primaryLight = _colorToRgba(accentColor, isDark ? 0.12 : 0.08);
    final primaryBorder = _colorToRgba(accentColor, isDark ? 0.28 : 0.18);
    final themeClass = isDark ? 'dark-theme' : 'light-theme';

    // 提取原文档 <body> 中的核心内容（去除外层 html/body 标签）
    String bodyContent = rawContent;
    final bodyMatch = RegExp(r'<body[^>]*>([\s\S]*?)<\/body>', caseSensitive: false)
        .firstMatch(rawContent);
    if (bodyMatch != null && bodyMatch.groupCount >= 1) {
      bodyContent = bodyMatch.group(1)!;
    }

    final css = '''
      :root {
        --font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "PingFang SC", "Hiragino Sans GB", "Microsoft YaHei", sans-serif;
        --color-primary: $primaryHex;
        --color-primary-light: $primaryLight;
        --color-primary-border: $primaryBorder;
      }

      /* 浅色模式规范 */
      body.light-theme {
        --color-text-main: #334155;
        --color-text-title: #0F172A;
        --color-text-sub: #64748B;
        --color-border: rgba(0, 0, 0, 0.06);
        --color-table-header: rgba(0, 0, 0, 0.035);
        --color-table-border: rgba(0, 0, 0, 0.08);
      }

      /* 深色模式规范 */
      body.dark-theme {
        --color-text-main: #CBD5E1;
        --color-text-title: #F8FAFC;
        --color-text-sub: #94A3B8;
        --color-border: rgba(255, 255, 255, 0.08);
        --color-table-header: rgba(255, 255, 255, 0.05);
        --color-table-border: rgba(255, 255, 255, 0.1);
      }

      * {
        box-sizing: border-box;
        -webkit-tap-highlight-color: transparent;
      }

      html, body {
        margin: 0;
        padding: 0;
        background-color: transparent !important;
        font-family: var(--font-family);
        font-size: 14px;
        line-height: 1.75;
        color: var(--color-text-main);
        letter-spacing: 0.15px;
        -webkit-font-smoothing: antialiased;
        word-break: break-word;
      }

      .document-wrapper {
        padding: 20px 18px 36px 18px;
      }

      /* 大标题（居中 20pt w700） */
      .doc-title,
      div[style*="text-align: center"] b,
      div[style*="text-align:center"] b {
        display: block;
        font-size: 20px;
        font-weight: 700;
        color: var(--color-text-title);
        text-align: center;
        letter-spacing: -0.3px;
        margin: 2px 0 22px 0;
        line-height: 1.45;
      }

      /* 独立章节标题（如：一、特别提示、1. 适用范围） */
      .section-title,
      body > b,
      .document-wrapper > b {
        display: flex;
        align-items: center;
        font-size: 15.5px;
        font-weight: 600;
        color: var(--color-text-title);
        letter-spacing: -0.2px;
        margin-top: 26px;
        margin-bottom: 10px;
        line-height: 1.45;
      }
      .section-title::before,
      body > b::before,
      .document-wrapper > b::before {
        content: "";
        display: inline-block;
        width: 3.5px;
        height: 14px;
        border-radius: 2px;
        background-color: var(--color-primary);
        margin-right: 8px;
        flex-shrink: 0;
      }

      /* 段落排版 */
      p {
        margin: 0 0 12px 0;
        color: var(--color-text-main);
        text-align: justify;
      }

      /* 行内加粗（保留字重，不独占成行） */
      p b, p strong,
      li b, li strong,
      td b, td strong,
      .callout b, .callout strong {
        display: inline;
        font-size: inherit;
        font-weight: 600;
        color: var(--color-text-title);
        margin: 0;
      }

      /* 提示高亮卡片（游客模式、自动续订、注销说明等） */
      .callout {
        background-color: var(--color-primary-light);
        border: 1px solid var(--color-primary-border);
        border-radius: 12px;
        padding: 12px 14px;
        margin: 14px 0;
        color: var(--color-text-main);
        font-size: 13.5px;
        line-height: 1.7;
      }
      .callout p:last-child {
        margin-bottom: 0;
      }

      /* 列表美化 */
      ul, ol {
        margin: 8px 0 14px 0;
        padding-left: 20px;
      }
      li {
        margin-bottom: 6px;
        color: var(--color-text-main);
        line-height: 1.68;
      }

      /* 极简无黑框表格（第三方 SDK 清单） */
      table {
        width: 100% !important;
        border-collapse: separate !important;
        border-spacing: 0 !important;
        border-radius: 12px !important;
        overflow: hidden !important;
        border: 1px solid var(--color-table-border) !important;
        margin: 16px 0 !important;
        font-size: 12.5px !important;
      }
      th {
        background-color: var(--color-table-header) !important;
        color: var(--color-text-title) !important;
        font-weight: 600 !important;
        text-align: left !important;
        padding: 10px 12px !important;
        border: none !important;
        border-bottom: 1px solid var(--color-table-border) !important;
      }
      td {
        padding: 10px 12px !important;
        border: none !important;
        border-bottom: 1px solid var(--color-table-border) !important;
        color: var(--color-text-main) !important;
        vertical-align: top !important;
        line-height: 1.6 !important;
      }
      tr:last-child td {
        border-bottom: none !important;
      }

      /* 超链接 */
      a {
        color: var(--color-primary);
        text-decoration: none;
        font-weight: 500;
        word-break: break-all;
      }
      a:hover {
        text-decoration: underline;
      }

      /* 极简滚动条 */
      ::-webkit-scrollbar {
        width: 3.5px;
      }
      ::-webkit-scrollbar-track {
        background: transparent;
      }
      ::-webkit-scrollbar-thumb {
        background: rgba(128, 128, 128, 0.25);
        border-radius: 4px;
      }
    ''';

    return '''
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="UTF-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
        <style id="modern-theme-style">$css</style>
      </head>
      <body class="$themeClass">
        <div class="document-wrapper">
          $bodyContent
        </div>
      </body>
      </html>
    ''';
  }

  @override
  Widget build(BuildContext context) {
    final textColor = context.textPrimary;

    return AppScaffold(
      vibrancy: PageVibrancy.base,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: textColor, size: 19),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.title,
          style: TextStyle(
            color: textColor,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            fontFamily: 'NotoSansSC',
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: FrostedGlassCard(
                borderRadius: 20,
                padding: EdgeInsets.zero,
                child: Stack(
                  children: [
                    if (InAppWebViewPlatform.instance != null)
                      InAppWebView(
                        key: _webViewKey,
                        initialSettings: InAppWebViewSettings(
                          transparentBackground: true,
                          supportZoom: false,
                          disableHorizontalScroll: true,
                          overScrollMode: OverScrollMode.NEVER,
                          useShouldOverrideUrlLoading: true,
                        ),
                        onWebViewCreated: (controller) {
                          _webViewController = controller;
                          _loadHtmlContent();
                        },
                        onLoadStop: (controller, url) {
                          if (mounted && _isLoading) {
                            setState(() => _isLoading = false);
                          }
                        },
                        shouldOverrideUrlLoading: (controller, navigationAction) async {
                          final uri = navigationAction.request.url;
                          if (uri != null) {
                            final scheme = uri.scheme.toLowerCase();
                            if (scheme == 'http' || scheme == 'https' || scheme == 'mailto') {
                              final rawUri = Uri.parse(uri.toString());
                              if (await canLaunchUrl(rawUri)) {
                                await launchUrl(rawUri, mode: LaunchMode.externalApplication);
                              }
                              return NavigationActionPolicy.CANCEL;
                            }
                          }
                          return NavigationActionPolicy.ALLOW;
                        },
                      )
                    else
                      const SizedBox.expand(),
                    if (_isLoading && InAppWebViewPlatform.instance != null)
                      const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
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
}
