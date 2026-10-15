import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../state.dart';
import '../theme/app_theme.dart';
import '../util/prefs.dart';
import '../widget/monster_sprite.dart';
import '../widget/page_back_button.dart';

/// 小馋怪小游戏的入口页。
///
/// 现在这一版先复现角色的完整动效（走过来 → 被命中 → 被打哭 → 转身逃跑），
/// 它是 `design/ideas.html` 里 IDEA #010「打哭小馋怪：左右二选一守桥」的载体，
/// 桥面左右二选一的答题玩法后续接在这条时间线上。
///
/// **横屏**：守桥的构图是「一条向纵深收拢的桥 + 两侧水面」，横屏才放得下左右两个
/// 答案箱和桥两侧的余地；竖屏下桥只能占中间窄窄一条，两侧全是空白。
/// 因此这里像随身听页一样自管屏幕方向，离开时恢复竖屏。
class MonsterPage extends StatefulWidget {
  const MonsterPage({super.key});

  @override
  State<MonsterPage> createState() => _MonsterPageState();
}

class _MonsterPageState extends State<MonsterPage> {
  @override
  void initState() {
    super.initState();
    // 横屏游戏页：沉浸全屏 + 只允许横屏两个方向（不锁单侧，方便用户随手翻转）
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    // 退出时恢复外部界面的系统 UI 与竖屏方向
    Prefs.applyFullScreenMode();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

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
                padding: const EdgeInsets.only(bottom: 14),
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
