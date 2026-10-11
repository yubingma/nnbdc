import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 页面级返回箭头（纯净无底圈，与「单词详情」「成长之路」的返回风格一致）。
///
/// 供既可内嵌在首页底栏、又可被 push 成独立路由打开的功能页使用。
///
/// 「底下还有没有一层可退」由本组件自己实时判定，调用方不必再用
/// `Navigator.of(context).canPop()` 提前算一遍：那个值只是当次 build 的快照，
/// 路由栈变浅后不会自动刷新，箭头会滞留在一个已经退无可退的页面上——点下去会把
/// 首页那一层壳也一起弹掉，而 go_router 在匹配栈清空后只渲染一个空盒子
/// （go_router/lib/src/builder.dart 的 `matchList.isEmpty` 分支），整屏就只剩
/// main.dart 铺在最底层的全局背景。2026-10-11「首页底栏 · 比赛 → 对局 → 返回 →
/// 再点返回」整屏空白即由此而来。
class PageBackButton extends StatelessWidget {
  const PageBackButton({super.key, required this.color, this.size = 20});

  final Color color;
  final double size;

  /// 本页之下是否还有一层可退。
  ///
  /// go_router 环境下按匹配栈判断，而不是 `Navigator.canPop()`：后者在退场动画期间
  /// 仍把正在弹出的那一页算作"存在"，箭头会在退回后继续滞留。
  static bool _hasPreviousPage(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      return router.routerDelegate.currentConfiguration.matches.length > 1;
    }
    return Navigator.of(context).canPop();
  }

  @override
  Widget build(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    if (router == null) {
      return _buildArrow(context);
    }
    // 订阅匹配栈：进/退一层就重算一次，箭头随栈深实时出现或消失。
    return ListenableBuilder(
      listenable: router.routerDelegate,
      builder: (context, _) => _buildArrow(context),
    );
  }

  Widget _buildArrow(BuildContext context) {
    if (!_hasPreviousPage(context)) {
      return const SizedBox.shrink();
    }
    return InkResponse(
      radius: 20,
      onTap: () => Navigator.of(context).pop(),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child:
            Icon(Icons.arrow_back_ios_new_rounded, size: size, color: color),
      ),
    );
  }
}
