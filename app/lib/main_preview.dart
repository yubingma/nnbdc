import 'package:flutter/material.dart';
import 'package:nnbdc/page/admin/core_image_orbit_preview_page.dart';
import 'package:nnbdc/state.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:provider/provider.dart';

/// 核心意象环绕布局·独立预览入口
///
/// 用法：flutter run -t lib/main_preview.dart
/// 只挂一个页面，用来在真机/模拟器上确认环形排版与 8.5px 字号的实际观感，
/// 避免每次都走「登录 → admin → 预览」的路径。
void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => DarkMode(),
      child: Consumer<DarkMode>(
        builder: (context, darkMode, _) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.getThemeData(darkMode.themeStyle),
          home: const CoreImageOrbitPreviewPage(),
        ),
      ),
    ),
  );
}
