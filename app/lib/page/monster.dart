import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state.dart';
import '../theme/app_theme.dart';
import '../widget/monster_sprite.dart';
import '../widget/page_back_button.dart';

/// 小馋怪小游戏的入口页。
///
/// 现在这一版先复现角色的完整动效（走过来 → 被命中 → 被打哭 → 转身逃跑），
/// 它是 `design/ideas.html` 里 IDEA #010「打哭小馋怪：左右二选一守桥」的载体，
/// 桥面左右二选一的答题玩法后续接在这条时间线上。
class MonsterPage extends StatelessWidget {
  const MonsterPage({super.key});

  @override
  Widget build(BuildContext context) {
    final themeStyle = context.watch<DarkMode>().themeStyle;
    final themeConfig = AppThemeConfig.of(themeStyle);

    return Scaffold(
      backgroundColor: const Color(0xFF3A7FA8),
      body: Stack(
        fit: StackFit.expand,
        children: [
          const MonsterSprite(),
          SafeArea(
            child: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 8, top: 4),
                child: PageBackButton(color: themeConfig.textPrimary),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 28),
                child: Text(
                  '小馋怪正朝你走来',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.4,
                    color: themeConfig.textPrimary.withValues(alpha: 0.85),
                    shadows: const [Shadow(color: Color(0x66000000), blurRadius: 8)],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
