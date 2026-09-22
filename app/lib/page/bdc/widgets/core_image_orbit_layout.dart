import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

/// 核心意象环绕图的布局算法（纯计算，不含任何绘制）。
///
/// 约束来自真机实测：椭圆水平半径只有一个卡片宽，
/// 而「释义框 + 线上文字 + 箭头」在水平方向就要吃掉大半，
/// 所以标签绝不能落在水平方向 —— 把圆周限制成上下两个扇区，
/// 中间留出「禁区」，禁区越大中心图越大、扇区容量越小，
/// 这里扫描一圈取「扇区刚好塞满」的最大禁区。
class CoreImageOrbitLayout {
  /// 简笔画/配图在中心容器内的占比（见 [CoreImageOrbitPainter] 的 viewBox 120、圆 r=52）
  static const double ringFactor = 52 / 60;

  /// 上下扇区内部，标签之间保留的弧长间隙
  static const double _gap = 10;

  /// 线上文字与释义框边缘之间留给箭头的距离
  static const double _arrowRoom = 22;

  /// 中心图边缘与线上文字之间至少留出的距离
  static const double _hubPad = 8;

  static OrbitLayoutResult compute({
    required Size canvas,
    required List<OrbitNodeMetrics> metrics,
    required Size labelSize,
  }) {
    final cx = canvas.width / 2;
    final cy = canvas.height / 2;

    var maxBoxHW = 0.0, maxBoxHH = 0.0;
    for (final m in metrics) {
      maxBoxHW = math.max(maxBoxHW, m.boxHalfW);
      maxBoxHH = math.max(maxBoxHH, m.boxHalfH);
    }

    final rx = canvas.width / 2 - maxBoxHW - 6;
    final ry = canvas.height / 2 - maxBoxHH - 8;

    final alloc = _bestSectorLayout(metrics, rx, ry);

    final nodes = <OrbitNodePlacement>[];
    var minGap = double.infinity;

    for (var i = 0; i < metrics.length; i++) {
      final th = alloc.angles[i];
      final bx = cx + math.cos(th) * rx;
      final by = cy + math.sin(th) * ry;

      // 椭圆上的点并不在 cos/sin 射线上，用真实连线方向算投影才准
      final ddx = bx - cx, ddy = by - cy;
      final dFrame = math.sqrt(ddx * ddx + ddy * ddy);
      final ux = ddx / dFrame, uy = ddy / dFrame;

      final m = metrics[i];
      final projBox = ux.abs() * m.boxHalfW + uy.abs() * m.boxHalfH;
      final projText = ux.abs() * m.textHalfW + uy.abs() * m.textHalfH;

      final t = dFrame - projBox - _arrowRoom - projText;
      final tx = cx + ux * t, ty = cy + uy * t;

      final gx = math.max(0.0, (tx - cx).abs() - m.textHalfW);
      final gy = math.max(0.0, (ty - cy).abs() - m.textHalfH);
      minGap = math.min(minGap, math.sqrt(gx * gx + gy * gy));

      nodes.add(OrbitNodePlacement(
        index: i,
        boxCenter: Offset(bx, by),
        textCenter: Offset(tx, ty),
        direction: Offset(ux, uy),
        projBox: projBox,
      ));
    }

    // 中心图半径：圆内还要放得下「核心意象」文字（按文字高度处的弦宽校验）
    final hubRadius = math.max(30.0, minGap - _hubPad);

    final ringRadius = hubRadius * ringFactor;
    final labelCenter = Offset(cx, cy + ringRadius * 0.45);
    final labelFits = labelSize.width <= 2 * ringRadius * math.sqrt(1 - 0.45 * 0.45);

    final placements = <OrbitNodePlacement>[];
    for (final n in nodes) {
      placements.add(n.copyWith(
        lineStart: Offset(cx + n.direction.dx * hubRadius, cy + n.direction.dy * hubRadius),
        lineEnd: Offset(
          n.boxCenter.dx - n.direction.dx * (n.projBox + 5),
          n.boxCenter.dy - n.direction.dy * (n.projBox + 5),
        ),
      ));
    }

    final overlaps = _detectOverlaps(placements, metrics);

    return OrbitLayoutResult(
      canvas: canvas,
      center: Offset(cx, cy),
      hubRadius: hubRadius,
      imageDiameter: hubRadius * 2 * ringFactor,
      labelCenter: labelCenter,
      labelFits: labelFits,
      nodes: placements,
      forbiddenDeg: alloc.forbiddenDeg,
      sectorUsage: alloc.usage,
      feasible: alloc.feasible && overlaps.isEmpty,
    );
  }

  static List<String> _detectOverlaps(
    List<OrbitNodePlacement> nodes,
    List<OrbitNodeMetrics> metrics,
  ) {
    bool hit(Offset a, double ahw, double ahh, Offset b, double bhw, double bhh, double slack) =>
        (a.dx - b.dx).abs() < ahw + bhw + slack && (a.dy - b.dy).abs() < ahh + bhh + slack;

    final out = <String>[];
    for (var i = 0; i < nodes.length; i++) {
      for (var j = i + 1; j < nodes.length; j++) {
        final a = nodes[i], b = nodes[j];
        final ma = metrics[a.index], mb = metrics[b.index];
        if (hit(a.boxCenter, ma.boxHalfW, ma.boxHalfH, b.boxCenter, mb.boxHalfW, mb.boxHalfH, 0)) {
          out.add('框${i + 1}·${j + 1}');
        }
        if (hit(a.textCenter, ma.textHalfW, ma.textHalfH, b.textCenter, mb.textHalfW, mb.textHalfH, 0)) {
          out.add('文${i + 1}·${j + 1}');
        }
        if (hit(a.boxCenter, ma.boxHalfW, ma.boxHalfH, b.textCenter, mb.textHalfW, mb.textHalfH, 0)) {
          out.add('框${i + 1}-文${j + 1}');
        }
        if (hit(b.boxCenter, mb.boxHalfW, mb.boxHalfH, a.textCenter, ma.textHalfW, ma.textHalfH, 0)) {
          out.add('框${j + 1}-文${i + 1}');
        }
      }
    }
    return out;
  }

  /// 扫描禁区角，取「还塞得下」里最大的那个（禁区越大中心图越大）
  static _SectorAlloc _bestSectorLayout(
    List<OrbitNodeMetrics> metrics,
    double rx,
    double ry,
  ) {
    _SectorAlloc? best;
    _SectorAlloc? fallback;
    for (var fb = 8; fb <= 55; fb++) {
      final a = _sectorAngles(metrics, rx, ry, fb.toDouble());
      if (a.feasible && (best == null || a.usage > best.usage)) best = a;
      if (fallback == null || a.usage < fallback.usage) fallback = a;
    }
    return best ?? fallback!;
  }

  static _SectorAlloc _sectorAngles(
    List<OrbitNodeMetrics> metrics,
    double rx,
    double ry,
    double forbidDeg,
  ) {
    final forbid = forbidDeg * math.pi / 180;
    final table = _ArcTable.build(rx, ry, -forbid);

    final half = (metrics.length + 1) ~/ 2;
    final up = metrics.sublist(0, half);
    final lo = metrics.sublist(half);

    final sF1 = table.arcAt(forbid);
    final sF2 = table.arcAt(math.pi - forbid);
    final sF3 = table.arcAt(math.pi + forbid);

    final loOrder = _centerFirst(lo.length);
    final upOrder = _centerFirst(up.length);

    final lower = _placeInSpan(
      loOrder.map((i) => lo[i]).toList(), sF1, sF2, table, rx, ry);
    final upper = _placeInSpan(
      upOrder.map((i) => up[i]).toList(), sF3, table.total, table, rx, ry);

    // 还原回原始顺序
    final angles = List<double>.filled(metrics.length, 0);
    for (var k = 0; k < upOrder.length; k++) {
      angles[upOrder[k]] = upper.angles[k];
    }
    for (var k = 0; k < loOrder.length; k++) {
      angles[half + loOrder[k]] = lower.angles[k];
    }

    return _SectorAlloc(
      angles: angles,
      forbiddenDeg: forbidDeg.round(),
      usage: math.max(upper.total / upper.spanLen, lower.total / lower.spanLen),
      feasible: upper.total <= upper.spanLen && lower.total <= lower.spanLen,
    );
  }

  /// 扇区从中间往两侧铺，让列表首条（核心义）落在扇区正中，而不是被排到边缘
  static List<int> _centerFirst(int n) {
    final mid = (n - 1) / 2;
    final idx = List<int>.generate(n, (i) => i);
    idx.sort((a, b) => (a - mid).abs().compareTo((b - mid).abs()));
    return idx;
  }

  static _SpanPlacement _placeInSpan(
    List<OrbitNodeMetrics> list,
    double a,
    double b,
    _ArcTable table,
    double rx,
    double ry,
  ) {
    final spanLen = b - a;
    var angles = List<double>.generate(
      list.length,
      (i) => table.thetaAt(a + ((i + 0.5) / list.length) * spanLen),
    );

    List<double> need = const [];
    for (var it = 0; it < 6; it++) {
      need = [
        for (var i = 0; i < list.length; i++) _tangentWidth(list[i], angles[i], rx, ry),
      ];
      final sum = need.fold<double>(0, (p, e) => p + e);
      final k = spanLen / sum;
      var s = a;
      angles = [
        for (final w in need)
          () {
            s += w * k / 2;
            final th = table.thetaAt(s);
            s += w * k / 2;
            return th;
          }(),
      ];
    }
    need = [
      for (var i = 0; i < list.length; i++) _tangentWidth(list[i], angles[i], rx, ry),
    ];
    return _SpanPlacement(
      angles: angles,
      spanLen: spanLen,
      total: need.fold<double>(0, (p, e) => p + e),
    );
  }

  /// 标签在环上的「切向投影宽度」＝它需要的弧长预算
  static double _tangentWidth(OrbitNodeMetrics m, double th, double rx, double ry) {
    final tx = -rx * math.sin(th), ty = ry * math.cos(th);
    final len = math.sqrt(tx * tx + ty * ty);
    if (len == 0) return _gap;
    return ((tx / len).abs() * m.boxHalfW + (ty / len).abs() * m.boxHalfH) * 2 + _gap;
  }
}

/// 椭圆弧长表：参数角 ↔ 从起点累积的弧长
class _ArcTable {
  _ArcTable._(this._theta, this._arc, this.total);

  final List<double> _theta;
  final List<double> _arc;
  final double total;

  static const int _steps = 720;

  factory _ArcTable.build(double rx, double ry, double startTh) {
    final theta = List<double>.filled(_steps + 1, 0);
    final arc = List<double>.filled(_steps + 1, 0);
    var acc = 0.0;
    for (var i = 0; i <= _steps; i++) {
      final th = startTh + (i / _steps) * 2 * math.pi;
      if (i > 0) {
        final th0 = startTh + ((i - 1) / _steps) * 2 * math.pi;
        final dx = rx * (math.cos(th) - math.cos(th0));
        final dy = ry * (math.sin(th) - math.sin(th0));
        acc += math.sqrt(dx * dx + dy * dy);
      }
      theta[i] = th;
      arc[i] = acc;
    }
    return _ArcTable._(theta, arc, acc);
  }

  /// 弧长 → 参数角
  double thetaAt(double s) {
    var x = s % total;
    if (x < 0) x += total;
    var lo = 0, hi = _arc.length - 1;
    while (lo < hi - 1) {
      final mid = (lo + hi) >> 1;
      if (_arc[mid] <= x) {
        lo = mid;
      } else {
        hi = mid;
      }
    }
    final span = _arc[hi] - _arc[lo];
    final f = span == 0 ? 0.0 : (x - _arc[lo]) / span;
    return _theta[lo] + (_theta[hi] - _theta[lo]) * f;
  }

  /// 参数角 → 弧长（参数角均匀步进，按索引比例定位即可）
  double arcAt(double th) {
    final start = _theta[0];
    var d = th - start;
    while (d < 0) {
      d += 2 * math.pi;
    }
    while (d >= 2 * math.pi) {
      d -= 2 * math.pi;
    }
    final idx = ((d / (2 * math.pi)) * _steps).round().clamp(0, _steps);
    return _arc[idx];
  }
}

class _SectorAlloc {
  const _SectorAlloc({
    required this.angles,
    required this.forbiddenDeg,
    required this.usage,
    required this.feasible,
  });

  final List<double> angles;
  final int forbiddenDeg;
  final double usage;
  final bool feasible;
}

class _SpanPlacement {
  const _SpanPlacement({required this.angles, required this.spanLen, required this.total});

  final List<double> angles;
  final double spanLen;
  final double total;
}

/// 单个分支在绘制前量出来的尺寸
class OrbitNodeMetrics {
  const OrbitNodeMetrics({
    required this.boxHalfW,
    required this.boxHalfH,
    required this.textHalfW,
    required this.textHalfH,
  });

  final double boxHalfW, boxHalfH, textHalfW, textHalfH;
}

/// 单个分支的落位结果
class OrbitNodePlacement {
  const OrbitNodePlacement({
    required this.index,
    required this.boxCenter,
    required this.textCenter,
    required this.direction,
    required this.projBox,
    this.lineStart = Offset.zero,
    this.lineEnd = Offset.zero,
  });

  final int index;
  final Offset boxCenter;
  final Offset textCenter;
  final Offset direction;
  final double projBox;
  final Offset lineStart;
  final Offset lineEnd;

  OrbitNodePlacement copyWith({Offset? lineStart, Offset? lineEnd}) => OrbitNodePlacement(
        index: index,
        boxCenter: boxCenter,
        textCenter: textCenter,
        direction: direction,
        projBox: projBox,
        lineStart: lineStart ?? this.lineStart,
        lineEnd: lineEnd ?? this.lineEnd,
      );
}

/// 整张图的布局结果
class OrbitLayoutResult {
  const OrbitLayoutResult({
    required this.canvas,
    required this.center,
    required this.hubRadius,
    required this.imageDiameter,
    required this.labelCenter,
    required this.labelFits,
    required this.nodes,
    required this.forbiddenDeg,
    required this.sectorUsage,
    required this.feasible,
  });

  final Size canvas;
  final Offset center;
  final double hubRadius;
  final double imageDiameter;
  final Offset labelCenter;

  /// 核心意象文字是否放得进圆心弦宽
  final bool labelFits;
  final List<OrbitNodePlacement> nodes;
  final int forbiddenDeg;
  final double sectorUsage;
  final bool feasible;
}
