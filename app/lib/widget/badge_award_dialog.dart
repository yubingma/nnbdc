import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/widget/badge_svg_assets.dart';

/// 勋章获得/升级 仪式感恭贺弹窗
class BadgeAwardDialog extends StatelessWidget {
  final UserBadgeVo userBadge;
  final VoidCallback? onEquip;
  final VoidCallback? onShare;

  const BadgeAwardDialog({
    super.key,
    required this.userBadge,
    this.onEquip,
    this.onShare,
  });

  static Future<void> show(
    BuildContext context, {
    required UserBadgeVo userBadge,
    VoidCallback? onEquip,
    VoidCallback? onShare,
  }) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => BadgeAwardDialog(
        userBadge: userBadge,
        onEquip: onEquip,
        onShare: onShare,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final badge = userBadge.badge;
    final code = badge?.code ?? '';
    final name = badge?.name ?? '荣耀勋章';
    final tier = badge?.tier ?? 'BRONZE';
    final tierName = BadgeSvgAssets.getTierName(tier);
    final tierColor = BadgeSvgAssets.getTierColor(tier);
    final categoryName = BadgeSvgAssets.getCategoryName(badge?.category);
    final obtainCount = userBadge.obtainCount ?? 1;
    final starLevel = userBadge.starLevel ?? 1;
    final isStackable = badge?.isStackable ?? false;
    final rewardBubbles = badge?.rewardBubbles ?? 0;
    final description = badge?.description ?? '';

    final svgCode = BadgeSvgAssets.getSvgByCode(code);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Center(
        child: Container(
          width: 340,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1B2E),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: tierColor.withValues(alpha: 0.6),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: tierColor.withValues(alpha: 0.25),
                blurRadius: 30,
                spreadRadius: 2,
              ),
              const BoxShadow(
                color: Colors.black54,
                blurRadius: 20,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 顶部小标题
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.auto_awesome, color: Color(0xFFFBBF24), size: 18),
                  const SizedBox(width: 6),
                  Text(
                    obtainCount > 1 ? '🎉 勋章再次进阶！' : '🎉 恭喜斩获新勋章！',
                    style: const TextStyle(
                      color: Color(0xFFFBBF24),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 勋章 SVG 主体
              Stack(
                alignment: Alignment.center,
                children: [
                  // 背景呼吸光晕
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: tierColor.withValues(alpha: 0.35),
                          blurRadius: 40,
                          spreadRadius: 10,
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 110,
                    height: 110,
                    child: SvgPicture.string(svgCode),
                  ),
                  // 多次获得角标
                  if (isStackable && obtainCount > 1)
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEC4899),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: const [
                            BoxShadow(color: Colors.black38, blurRadius: 4),
                          ],
                        ),
                        child: Text(
                          '×$obtainCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),

              // 勋章名称
              Text(
                name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 4),

              // 品阶与分类
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: tierColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: tierColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  '$tierName · $categoryName',
                  style: TextStyle(
                    color: tierColor,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),

              // 星级展示 (如果是可累加学霸系列)
              if (isStackable) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    return Icon(
                      index < starLevel ? Icons.star : Icons.star_border,
                      color: const Color(0xFFFBBF24),
                      size: 18,
                    );
                  }),
                ),
              ],

              const SizedBox(height: 12),

              // 描述/故事
              Text(
                description,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 16),

              // 奖励魔法泡泡
              if (rewardBubbles > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF38BDF8).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF38BDF8).withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🫧', style: TextStyle(fontSize: 14)),
                      const SizedBox(width: 6),
                      Text(
                        '获得奖励: 魔法泡泡 +$rewardBubbles',
                        style: const TextStyle(
                          color: Color(0xFF38BDF8),
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 24),

              // 操作按钮
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        onShare?.call();
                        ToastUtil.success('已准备好高清炫耀长图！');
                      },
                      child: const Text('炫耀一下'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        onEquip?.call();
                      },
                      child: const Text('开心收下'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
