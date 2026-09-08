import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../state.dart';
import '../theme/app_theme.dart';
import '../theme/app_theme_background.dart';
import '../theme/page_vibrancy.dart';

/// BuildContext 主题便捷扩展
/// 让任意 Widget 都可以直接通过 `context.primaryColor` 或 `context.themeConfig` 访问当前动态主题
extension AppThemeContextExtension on BuildContext {
  AppThemeStyle get themeStyle {
    // 若在非构建周期（如事件回调、异步方法、dialog 触发时），Provider 禁止 listen: true，自动退化为安全读取
    if (kDebugMode && this is Element) {
      final isBuilding = (this as Element).owner?.debugBuilding ?? false;
      if (!isBuilding) {
        return read<DarkMode>().themeStyle;
      }
    }
    try {
      return watch<DarkMode>().themeStyle;
    } on Object catch (_) {
      return read<DarkMode>().themeStyle;
    }
  }

  AppThemeConfig get themeConfig => AppThemeConfig.of(themeStyle);

  /// 是否窄高屏（手机）：宽高比 < 0.62。与 AppThemeBackground 的分屏口径一致。
  bool get _isNarrow {
    final size = MediaQuery.of(this).size;
    return size.width / size.height < 0.62;
  }

  Color get primaryColor => themeConfig.primaryColor;
  Color get subtleBg => themeConfig.subtleBg;
  /// 默认卡片底色（跟随 base，且按设备自动乘平板系数）
  Color get cardBg => PageVibrancyConfig.base.cardColor(themeConfig, isNarrow: _isNarrow);
  /// 指定页面配置的卡片底色（按设备自动乘平板系数）
  Color pageCardBg(PageVibrancyConfig config) =>
      config.cardColor(themeConfig, isNarrow: _isNarrow);
  /// 默认卡片阴影（随卡片透明度联动，卡越透影越淡；按设备乘平板系数）
  BoxShadow get cardShadow =>
      PageVibrancyConfig.base.cardShadow(themeConfig, isNarrow: _isNarrow);
  /// 指定页面配置的卡片阴影
  BoxShadow pageCardShadow(PageVibrancyConfig config) =>
      config.cardShadow(themeConfig, isNarrow: _isNarrow);
  Color get buttonBg => themeConfig.cardBg.withValues(alpha: Constants.buttonOpacity);
  Color get cardBorder => themeConfig.cardBorder;
  Color get textPrimary => themeConfig.textPrimary;
  Color get textSecondary => themeConfig.textSecondary;
  Color get textMuted => themeConfig.textMuted;
  Color get dakaStudiedColor => themeConfig.dakaStudiedColor;
  Color get warmAccentColor => themeConfig.warmAccentColor;
  List<BoxShadow> get cardShadows => themeConfig.cardShadows;
  List<Color> get appBarGradient => themeConfig.appBarGradient;
  bool get isDarkMode => themeConfig.isDark;
}

/// 统一的页面基础脚手架
/// 自动集成：
/// 1. 当前风格的 AppThemeBackground 流光渐变背景
/// 2. Scaffold 底色自动透明穿透
/// 3. 安全区与统一交互支持
class AppScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget? body;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Widget? drawer;
  final Widget? endDrawer;
  final Widget? bottomSheet;
  final bool? resizeToAvoidBottomInset;
  final bool extendBodyBehindAppBar;
  final bool extendBody;
  final bool showBackground;
  /// 背景"提气"调参（提气强度 + 渐变幅度 + 卡片透明度）。页面显式指定的是"基准(手机)档"；
  /// 传 null 时用 [PageVibrancyConfig.base]。平板时自动对该基准调用 [PageVibrancyConfig.forTablet]
  /// 乘各分字段系数，从而复用手机调整成果，无需单独调平板。值越大越亮，无上限，但饱和度和
  /// 明度有 [0,1] 物理上限，到纯白即封顶。
  final PageVibrancyConfig? vibrancy;
  final Key? scaffoldKey;

  const AppScaffold({
    super.key,
    this.appBar,
    this.body,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.drawer,
    this.endDrawer,
    this.bottomSheet,
    this.resizeToAvoidBottomInset,
    this.extendBodyBehindAppBar = false,
    this.extendBody = false,
    this.showBackground = true,
    this.vibrancy,
    this.scaffoldKey,
  });

  /// 解析本页最终使用的配置：以页面显式配置(未指定则 [PageVibrancyConfig.base])为基准；
  /// 窄高屏(手机, 宽高比<0.62)直接用基准，方正屏(平板)用基准 × 平板系数。
  /// 与 AppThemeBackground 的窄/方屏判断口径保持一致。
  PageVibrancyConfig _resolveVibrancy(BuildContext context) {
    final base = vibrancy ?? PageVibrancyConfig.base;
    final size = MediaQuery.of(context).size;
    final isNarrow = size.width / size.height < 0.62;
    return isNarrow ? base : base.forTablet();
  }

  @override
  Widget build(BuildContext context) {
    final style = context.themeStyle;
    final resolved = _resolveVibrancy(context);

    final scaffold = Scaffold(
      key: scaffoldKey,
      backgroundColor: Colors.transparent,
      appBar: appBar,
      body: body,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      drawer: drawer,
      endDrawer: endDrawer,
      bottomSheet: bottomSheet,
      resizeToAvoidBottomInset: resizeToAvoidBottomInset,
      extendBodyBehindAppBar: extendBodyBehindAppBar,
      extendBody: extendBody,
    );

    if (!showBackground) {
      return scaffold;
    }

    return Stack(
      children: [
        Positioned.fill(
          child: AppThemeBackground(
            themeStyle: style,
            vibrancy: resolved.vibrancy,
            midLight: resolved.midLight,
            topShift: resolved.topShift,
            bottomShift: resolved.bottomShift,
          ),
        ),
        scaffold,
      ],
    );
  }
}

/// 统一的顶栏应用栏组件
/// 自动根据当前主题渲染渐变色与微光投影，免去手动编写 BoxDecoration 的繁琐操作
class AppAppBar extends StatelessWidget implements PreferredSizeWidget {
  final dynamic title; // String 或 Widget
  final List<Widget>? actions;
  final Widget? leading;
  final bool centerTitle;
  final double elevation;
  final PreferredSizeWidget? bottom;
  final double toolbarHeight;
  final bool automaticallyImplyLeading;
  final bool showGradient;
  final TextStyle? titleTextStyle;

  const AppAppBar({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.centerTitle = true,
    this.elevation = 0,
    this.bottom,
    this.toolbarHeight = kToolbarHeight,
    this.automaticallyImplyLeading = true,
    this.showGradient = true,
    this.titleTextStyle,
  });

  @override
  Size get preferredSize => Size.fromHeight(
        toolbarHeight + (bottom?.preferredSize.height ?? 0.0),
      );

  @override
  Widget build(BuildContext context) {
    final config = context.themeConfig;

    Widget titleWidget;
    if (title is Widget) {
      titleWidget = title as Widget;
    } else {
      titleWidget = Text(
        title.toString(),
        style: titleTextStyle ??
            const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 0.3,
            ),
      );
    }

    return AppBar(
      title: titleWidget,
      actions: actions,
      leading: leading,
      centerTitle: centerTitle,
      elevation: elevation,
      bottom: bottom,
      toolbarHeight: toolbarHeight,
      automaticallyImplyLeading: automaticallyImplyLeading,
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      flexibleSpace: showGradient
          ? Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: config.appBarGradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: config.primaryColor.withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
            )
          : null,
    );
  }
}
