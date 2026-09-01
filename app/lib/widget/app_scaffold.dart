import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../state.dart';
import '../theme/app_theme.dart';
import '../theme/app_theme_background.dart';

/// BuildContext 主题便捷扩展
/// 让任意 Widget 都可以直接通过 `context.primaryColor` 或 `context.themeConfig` 访问当前动态主题
extension AppThemeContextExtension on BuildContext {
  AppThemeStyle get themeStyle => watch<DarkMode>().themeStyle;
  AppThemeConfig get themeConfig => AppThemeConfig.of(themeStyle);

  Color get primaryColor => themeConfig.primaryColor;
  Color get subtleBg => themeConfig.subtleBg;
  Color get cardBg => themeConfig.cardBg;
  Color get cardBorder => themeConfig.cardBorder;
  Color get textPrimary => themeConfig.textPrimary;
  Color get textSecondary => themeConfig.textSecondary;
  Color get dakaStudiedColor => themeConfig.dakaStudiedColor;
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
    this.scaffoldKey,
  });

  @override
  Widget build(BuildContext context) {
    final style = context.themeStyle;

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
