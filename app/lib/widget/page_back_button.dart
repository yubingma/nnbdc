import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../global.dart';

/// 页面级返回箭头（纯净无底圈，与「单词详情」「成长之路」的返回风格一致）。
///
/// 供既可内嵌在首页底栏、又可被 push 成独立路由打开的功能页使用：
/// 调用方用 `Navigator.of(context).canPop()` 判断当前是否是独立路由，
/// 内嵌在首页时不放入布局，独立打开时才有退路。
class PageBackButton extends StatelessWidget {
  const PageBackButton({super.key, required this.color, this.size = 20});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      radius: 20,
      onTap: () {
        // TODO(临时诊断)：定位「点返回后 go_router 路由表为空」的崩溃，定位后删除
        final GoRouter router = GoRouter.of(context);
        final List<RouteMatchBase> matches =
            router.routerDelegate.currentConfiguration.matches;
        Global.logger.d('[返回诊断] '
            'matchedLocation=${GoRouterState.of(context).matchedLocation} '
            'matchList长度=${matches.length} '
            '各段路由=${matches.map((RouteMatchBase m) => m.route is GoRoute ? (m.route as GoRoute).path : m.runtimeType.toString()).toList()} '
            'navigatorCanPop=${Navigator.of(context).canPop()}');
        Navigator.of(context).pop();
      },
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(Icons.arrow_back_ios_new_rounded, size: size, color: color),
      ),
    );
  }
}
