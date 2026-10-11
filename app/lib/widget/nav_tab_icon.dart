import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// 底部导航栏与收纳菜单共用的线性图标（Lucide：24 网格 / 2px 圆头笔宽）。
///
/// 走 SVG 资源而不是图标字体：Lucide 现成的 pub 包会连带 6 档字重、共 2.9MB 的
/// ttf 一起进安装包——Flutter 的图标裁剪只处理代码里真正引用过的字体家族，其余
/// 家族原样打包。这 5 个 SVG 加起来 2.5KB，笔宽与圆头也留在仓库里看得见、改得动。
class NavTabIcon extends StatelessWidget {
  const NavTabIcon(
    this.asset, {
    super.key,
    required this.color,
    this.size = 24,
    this.shadow,
  });

  /// SVG 资源路径。沿用了 Lucide 的原始文件名，将来对照上游升级时一一对得上。
  final String asset;

  final Color color;
  final double size;

  /// 压在壁纸照片上时托一层柔光，把图标从照片的明暗噪点里拎出来；
  /// 底栏底下没有照片的页面留空即可。
  final Shadow? shadow;

  @override
  Widget build(BuildContext context) {
    final glyph = SvgPicture.asset(
      asset,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
    final shadow = this.shadow;
    if (shadow == null) return glyph;

    // 光晕允许溢出图标框：它只是托底，不该把底栏布局撑大一圈。
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: shadow.blurRadius, sigmaY: shadow.blurRadius),
            child: Transform.translate(
              offset: shadow.offset,
              child: SvgPicture.asset(
                asset,
                width: size,
                height: size,
                colorFilter: ColorFilter.mode(shadow.color, BlendMode.srcIn),
              ),
            ),
          ),
          glyph,
        ],
      ),
    );
  }
}
