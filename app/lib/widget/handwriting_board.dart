import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nnbdc/util/ocr_service.dart';
import '../theme/app_theme.dart';

class HandwritingBoard extends StatefulWidget {
  final Function(String) onRecognized;
  final VoidCallback onCancel;
  final ValueNotifier<bool>? rightZoneVisibleNotifier;
  final VoidCallback? onHint;

  final VoidCallback? onStartWriting;
  final VoidCallback? onPointerUp;
  final VoidCallback? onSwipeUp;
  final VoidCallback? onSwipeDown;
  final bool showCloseButton;
  final bool showHeader;
  final bool useBoxDecoration;
  final bool showCanvasButtons;
  final bool enableNavigationGestures;
  final double smartRightZoneWidth;

  const HandwritingBoard({
    super.key,
    required this.onRecognized,
    required this.onCancel,
    this.onStartWriting,
    this.onPointerUp,
    this.onSwipeUp,
    this.onSwipeDown,
    this.showCloseButton = true,
    this.showHeader = true,
    this.useBoxDecoration = true,
    this.showCanvasButtons = true,
    this.enableNavigationGestures = true,
    this.smartRightZoneWidth = 0.0,
    this.rightZoneVisibleNotifier,
    this.onHint,
    this.onUndo,
    this.onRewrite,
    this.language = 'en-US',
    this.manualSubmit = false,
    this.cellCount = 1,
    this.onRecognizedPreview,
  });

  final VoidCallback? onUndo;
  final VoidCallback? onRewrite;

  /// 手写识别语言（ML Kit 数字墨迹语言标签）。英文拼写默认 'en-US'；中文默写传 'zh-Hani'
  /// （ML Kit 的中文模型标签是 zh-Hani，而非 BCP-47 的 zh-Hans）。
  final String language;

  /// 手动提交模式（用于中文默写）：停笔后不自动识别，而是在底部操作栏新增「提交」按钮，
  /// 只有在用户点击提交后才一次性识别完整笔画并匹配，避免对不完整/中间态笔画切分
  /// 导致"多个汉字被合成一个字"；键盘输入不受此影响。
  final bool manualSubmit;

  /// 分格书写数量。>1 时（中文默写）画布横向均分为 [cellCount] 个格子，每个格子写一个汉字，
  /// "第一笔进入另一个格子"即视为开始写下一个字——识别上一格、清空上一格，显著提升单字识别率；
  /// 提交时拼接所有格子识别结果判题。=1（英文拼写）时维持整块书写/识别。
  final int cellCount;

  /// 提前回显回调：分格模式下，每识别完一个格子就把"已识别前缀"同步到输入框供用户反馈，不判题。
  /// 判题只在提交后走 [onRecognized]。
  final ValueChanged<String>? onRecognizedPreview;

  @override
  State<HandwritingBoard> createState() => HandwritingBoardState();
}

class PointWithTime {
  final Offset offset;
  final int t;
  PointWithTime(this.offset, this.t);
}

class HandwritingBoardState extends State<HandwritingBoard> {
  List<List<PointWithTime>> _lines = [];
  bool _isRecognizing = false;
  int _recognitionVersion = 0;
  final GlobalKey<_HandwritingCanvasState> _canvasKey = GlobalKey<_HandwritingCanvasState>();

  /// 手写画布尺寸，识别时作为 WritingArea 上下文传给 ML Kit，帮助正确切分多字连写。
  Size? _writingAreaSize;

  /// 分格模式下已识别出的字序列（每个格子一个字）。提交时拼接成最终答案。
  List<String> _recognizedChars = [];

  /// 当前正在书写的格子索引（分格模式下有效）。
  int _activeCell = 0;

  /// 串行化逐格识别，保证"已识别字"按书写顺序追加（避免异步 OCR 乱序）。
  Future<void> _finalizeChain = Future.value();

  void _handleWritingArea(Size size) {
    _writingAreaSize = size;
  }

  /// 竖屏（高>宽）时为上下两格，横屏（宽>=高）时为左右两格。
  bool get _isVerticalLayout =>
      (_writingAreaSize?.width ?? 0) < (_writingAreaSize?.height ?? 0);

  /// 计算某"落笔起点"落在哪个格子。换字只看新一笔的起点，忽略笔画延伸/终点进入其他格子。
  int _cellIndexAt(Offset pos) {
    final size = _writingAreaSize;
    if (size == null) return 0;
    if (_isVerticalLayout) {
      final cellH = size.height / widget.cellCount;
      if (cellH <= 0) return 0;
      return (pos.dy / cellH).floor().clamp(0, widget.cellCount - 1);
    }
    final cellW = size.width / widget.cellCount;
    if (cellW <= 0) return 0;
    return (pos.dx / cellW).floor().clamp(0, widget.cellCount - 1);
  }

  /// 画布上报"新一笔落点"：分格模式下若起点已换到新格子，就完成上一格识别并清空，切换到新格子。
  void _handleCellChange(Offset pos) {
    if (widget.cellCount <= 1) return;
    final cell = _cellIndexAt(pos);
    if (cell != _activeCell) {
      unawaited(_enqueueFinalize());
      _activeCell = cell;
      if (mounted) setState(() {});
    }
  }

  /// 把一次逐格识别排队执行（串行，保证顺序）。
  Future<void> _enqueueFinalize() {
    final next = _finalizeChain.then((_) => _finalizeCurrentCell());
    _finalizeChain = next.catchError((_) {});
    return next;
  }

  /// 分格模式下：识别当前格子笔画，追加到已识别序列，清空当前格，并提前回显前缀。
  Future<void> _finalizeCurrentCell() async {
    if (_lines.isEmpty) return;
    // 先快照当前格笔画并清空，避免后续写入新格笔画影响本格识别
    final snapshot = List<List<PointWithTime>>.generate(_lines.length,
        (i) => List<PointWithTime>.from(_lines[i]));
    _lines = [];
    _recognitionVersion++;
    final char = await _recognizeLines(snapshot, cellIndex: _activeCell);
    if (char.isNotEmpty) {
      _recognizedChars.add(char);
    }
    // 提前反馈：把已识别前缀同步到输入框（不判题）
    widget.onRecognizedPreview?.call(_recognizedChars.join());
    if (mounted) setState(() {});
  }

  /// 识别给定笔画并返回文本。分格模式下：把该字笔画归一化到自身包围盒，并以包围盒尺寸作为
  /// WritingArea（单字识别更准，且对"横/竖屏"布局都成立）；单格（英文拼写）保持整幅画布。
  Future<String> _recognizeLines(List<List<PointWithTime>> strokes,
      {int cellIndex = 0}) async {
    if (strokes.isEmpty) return '';

    final canvasW = _writingAreaSize?.width ?? 0;
    final canvasH = _writingAreaSize?.height ?? 0;

    final bool isCellMode = widget.cellCount > 1;
    double areaW = canvasW;
    double areaH = canvasH;
    double offsetX = 0.0;
    double offsetY = 0.0;

    if (isCellMode) {
      // 以该字笔画包围盒为坐标系原点+尺寸，使单字以最合适尺度送入 ML Kit
      double minX = double.infinity, maxX = -double.infinity;
      double minY = double.infinity, maxY = -double.infinity;
      for (final line in strokes) {
        for (final p in line) {
          final x = p.offset.dx;
          final y = p.offset.dy;
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
      if (maxX < minX || maxY < minY) return '';
      offsetX = minX;
      offsetY = minY;
      areaW = (maxX - minX).clamp(1.0, double.infinity);
      areaH = (maxY - minY).clamp(1.0, double.infinity);
    }

    final strokesData = strokes.map((line) => line.map((p) => {
      'x': p.offset.dx - offsetX,
      'y': p.offset.dy - offsetY,
      't': p.t,
    }).toList()).toList();

    try {
      final response = await OcrService.recognizeHandwriting(strokesData,
          language: widget.language,
          writingAreaWidth: areaW > 0 ? areaW : null,
          writingAreaHeight: areaH > 0 ? areaH : null)
          .timeout(const Duration(seconds: 5));
      return _postProcess(response);
    } catch (e) {
      debugPrint('HB: Recognition error: $e');
      return '';
    }
  }

  /// 根据语言对识别结果做后处理（中文保留汉字；英文做近形替换/字母过滤）。
  String _postProcess(String text) {
    if (widget.language == 'zh-Hani') {
      return text.replaceAll(RegExp(r'\s+'), ' ').trim();
    }
    String processedText = text
        .replaceAll('1', 'l')
        .replaceAll('0', 'o')
        .replaceAll('5', 's')
        .replaceAll('2', 'z')
        .replaceAll('8', 'b')
        .replaceAll('9', 'g')
        .replaceAll('6', 'g')
        .replaceAll('4', 'a')
        .replaceAll('7', 't');
    return processedText
        .replaceAll('|', 'l')
        .replaceAll('/', 'l')
        .replaceAll('\\', 'l')
        .replaceAll(RegExp(r"[^a-zA-Z\s\-']"), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  @override
  void initState() {
    super.initState();
    // 异步静默加载当前识别语言的手写模型，避免用户在写完第一笔时因模型下载引发卡顿
    OcrService.prepareModel(language: widget.language);
  }
  
  void hideRightZone() {
    widget.rightZoneVisibleNotifier?.value = false;
  }

  void showRightZone() {
    widget.rightZoneVisibleNotifier?.value = true;
  }

  void clearBoard() {
    setState(() {
      _lines = [];
      _isRecognizing = false;
      _recognitionVersion++;
    });
    if (widget.cellCount > 1) {
      // 分格模式：只清空当前格笔画，已识别前缀保留（提前回显不变）
      widget.onRecognizedPreview?.call(_recognizedChars.join());
    } else {
      // 内容清空时，同步清空外部输入框
      widget.onRecognized("");
    }
  }

  void clearBoardSilently() {
    _canvasKey.currentState?._controller.clear();
    _lines.clear();
    _isRecognizing = false;
    _recognitionVersion++;
  }

  void _clear() {
    clearBoard();
    widget.onRewrite?.call();
  }

  void _incrementVersion() {
    _recognitionVersion++;
    widget.onUndo?.call();
  }

  Future<void> _recognize() async {
    // 分格模式（中文默写）：提交时先识别当前格，再拼接所有格子成完整答案
    if (widget.cellCount > 1) {
      await _enqueueFinalize();
      final answer = _recognizedChars.join();
      _recognizedChars = [];
      _activeCell = 0;
      widget.onRecognized(answer);
      return;
    }

    // 单格（英文拼写）：整块识别
    if (_lines.isEmpty) {
      widget.onRecognized("");
      return;
    }
    final int currentVersion = ++_recognitionVersion;
    setState(() {
      _isRecognizing = true;
    });
    final result = await _recognizeLines(_lines, cellIndex: 0);
    if (currentVersion == _recognitionVersion) {
      if (mounted) {
        setState(() {
          _isRecognizing = false;
        });
      }
      widget.onRecognized(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: widget.useBoxDecoration ? BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ) : null,
      child: Column(
        children: [
          if (widget.showHeader)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.gesture, size: 20, color: AppTheme.primaryColor),
                  const SizedBox(width: 8),
                  const Text(
                    '手写板',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87),
                  ),
                  const Spacer(),
                  if (_isRecognizing)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primaryColor),
                    ),
                  const SizedBox(width: 12),
                  if (widget.showCloseButton)
                    GestureDetector(
                      onTap: widget.onCancel,
                      child: const Icon(Icons.close, size: 20, color: Colors.grey),
                    ),
                ],
              ),
            ),

          Expanded(
            child: Stack(
              children: [
                _HandwritingCanvas(
                  key: _canvasKey,
                  lines: _lines,
                  isRecognizing: _isRecognizing,
                  onRewrite: _clear,
                  onUndo: _incrementVersion,
                  onRecognize: _recognize,
                  onStartWriting: widget.onStartWriting,
                  onPointerUp: widget.onPointerUp,
                  onSwipeUp: widget.onSwipeUp,
                  onSwipeDown: widget.onSwipeDown,
                  showButtons: widget.showCanvasButtons,
                  onCancel: widget.onCancel,
                  enableNavigationGestures: widget.enableNavigationGestures,
                  smartRightZoneWidth: widget.smartRightZoneWidth,
                  rightZoneVisibleNotifier: widget.rightZoneVisibleNotifier,
                  onHint: widget.onHint,
                  manualSubmit: widget.manualSubmit,
                  onWritingAreaChanged: _handleWritingArea,
                  cellCount: widget.cellCount,
                  activeCellIndex: _activeCell,
                  onCellChanged: _handleCellChange,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HandwritingCanvas extends StatefulWidget {
  final List<List<PointWithTime>> lines;
  final bool isRecognizing;
  final VoidCallback onRewrite;
  final VoidCallback onUndo;
  final VoidCallback onRecognize;
  final VoidCallback? onStartWriting;
  final VoidCallback? onPointerUp;
  final VoidCallback? onSwipeUp;
  final VoidCallback? onSwipeDown;
  final bool showButtons;
  final VoidCallback? onCancel;
  final bool enableNavigationGestures;
  final double smartRightZoneWidth;
  final ValueNotifier<bool>? rightZoneVisibleNotifier;
  final VoidCallback? onHint;
  final bool manualSubmit;
  final ValueChanged<Size>? onWritingAreaChanged;
  final int cellCount;
  final int activeCellIndex;
  final ValueChanged<Offset>? onCellChanged;

  const _HandwritingCanvas({
    super.key,
    required this.lines,
    required this.isRecognizing,
    required this.onRewrite,
    required this.onUndo,
    required this.onRecognize,
    this.onStartWriting,
    this.onPointerUp,
    this.onSwipeUp,
    this.onSwipeDown,
    required this.showButtons,
    this.onCancel,
    this.enableNavigationGestures = true,
    this.smartRightZoneWidth = 0.0,
    this.rightZoneVisibleNotifier,
    this.onHint,
    this.manualSubmit = false,
    this.onWritingAreaChanged,
    this.cellCount = 1,
    this.activeCellIndex = 0,
    this.onCellChanged,
  });

  @override
  State<_HandwritingCanvas> createState() => _HandwritingCanvasState();
}

class _HandwritingCanvasState extends State<_HandwritingCanvas> {
  late final _HandwritingController _controller;
  int? _activePointerId;
  final Set<int> _ignoredPointers = {}; 
  DateTime _lastStrokeEndTime = DateTime.fromMillisecondsSinceEpoch(0);
  late double _currentSmartZoneWidth;
  Timer? _autoRecognizeTimer;
  late final bool _isIos;

  @override
  void dispose() {
    _autoRecognizeTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _isIos = defaultTargetPlatform == TargetPlatform.iOS;
    _controller = _HandwritingController(widget.lines);
    _currentSmartZoneWidth = widget.smartRightZoneWidth;
  }

  @override
  void didUpdateWidget(_HandwritingCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.rawLines = widget.lines;
    if (widget.lines.isEmpty && oldWidget.lines.isNotEmpty) {
      _controller.clear();
      _autoRecognizeTimer?.cancel();
    }
  }

  /// 手写画布底部的操作按钮（重写/回退/提交/关闭/提示）
  /// 采用主题感知的柔光薄雾胶囊，替代原先生硬的灰色药丸，保持与整体极简美学一致。
  Widget _buildCanvasControlButton({
    required double left,
    required double top,
    required double width,
    required double height,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isDark,
    required Color foreground,
    required Color background,
    required Color border,
  }) {
    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(height / 2),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7),
            child: Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(height / 2),
                border: Border.all(color: border, width: 0.8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.08),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: foreground, size: 20),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleRewrite() {
    _autoRecognizeTimer?.cancel();
    _controller.clear();
    widget.onRewrite();
  }

  void _handleUndo() {
    _autoRecognizeTimer?.cancel();
    setState(() {
      _controller.removeLast();
    });
    widget.onUndo();
    // 自动模式：回退后重新识别并判题（维持原行为）
    if (!widget.manualSubmit) {
      widget.onRecognize();
      if (widget.lines.isEmpty) {
        widget.onRewrite();
      }
    }
    // 手动提交模式（中文默写）：回退仅撤销笔画，不识别不判题（识别只在点「提交」后一次性进行）
  }

  void _handleSubmit() {
    _autoRecognizeTimer?.cancel();
    widget.onRecognize();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final width = constraints.maxWidth;
        // 上报手写区尺寸，供识别时作为 WritingArea 上下文帮助 ML Kit 切分多字连写
        widget.onWritingAreaChanged?.call(Size(width, height));
        
        final bool isNarrow = width < 500;
        final bool hasHint = widget.onHint != null;
        final bool isDark = Theme.of(context).brightness == Brightness.dark;
        // 主题感知配色：笔迹跟随主题主色，控钮使用次级灰阶 + 柔和薄雾胶囊
        final Color penColor = context.primaryColor;
        final Color controlFg = context.textSecondary;
        final Color controlBg = isDark
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.black.withValues(alpha: 0.045);
        final Color controlBorder = isDark
            ? Colors.white.withValues(alpha: 0.12)
            : Colors.black.withValues(alpha: 0.06);
        final double zoneHeight = isNarrow ? 56 : 65;
        final double bottomMargin = isNarrow ? 10 : 16; 
        // 让操作按钮在底部操作栏内垂直居中（操作栏高度 = zoneHeight + bottomMargin + 10）
        final double zoneTop = height - zoneHeight - bottomMargin - 10 + (bottomMargin + 10) / 2;

        // 底部操作按钮（自左向右）。中文默写（手动提交）额外增加「提交」按钮。
        final List<({IconData icon, String label, VoidCallback onTap})> controls = [
          (icon: Icons.delete_sweep_outlined, label: '重写', onTap: _handleRewrite),
          (icon: Icons.undo_outlined, label: '回退', onTap: _handleUndo),
          if (widget.manualSubmit)
            (icon: Icons.check, label: '提交', onTap: _handleSubmit),
          (icon: Icons.close, label: '关闭', onTap: () => widget.onCancel?.call()),
          if (hasHint)
            (icon: Icons.lightbulb_outline, label: '提示', onTap: () => widget.onHint?.call()),
        ];

        const double controlGap = 10;
        final double controlSide = isNarrow ? 8 : 12;
        final int controlCount = controls.length;
        // 依据按钮数量自适应宽度，确保全部按钮居中且不超出屏幕
        final double zoneWidth =
            ((width - controlSide * 2 - controlGap * (controlCount - 1)) / controlCount)
                .clamp(56.0, 110.0);
        final double totalWidth =
            zoneWidth * controlCount + controlGap * (controlCount - 1);
        final double startX = width / 2 - totalWidth / 2;
        final List<Rect> controlZones = List.generate(controlCount, (i) {
          return Rect.fromLTWH(
              startX + i * (zoneWidth + controlGap), zoneTop, zoneWidth, zoneHeight);
        });

        return Listener(
          behavior: _currentSmartZoneWidth > 0 ? HitTestBehavior.translucent : HitTestBehavior.opaque,
          onPointerDown: (event) {
            if (_activePointerId != null) return;
            final p = event.localPosition;
            
            if (_currentSmartZoneWidth > 0) {
              final inRightZone = p.dx > width - _currentSmartZoneWidth;
              final isRecentWriting = DateTime.now().difference(_lastStrokeEndTime).inMilliseconds < 600;
              if (inRightZone && !isRecentWriting) {
                _ignoredPointers.add(event.pointer);
                return;
              }
            }

            if (controlZones.any((zone) => zone.contains(p))) {
              _ignoredPointers.add(event.pointer);
              return;
            }

            _activePointerId = event.pointer;
            _ignoredPointers.remove(event.pointer);
            widget.onStartWriting?.call();
            _autoRecognizeTimer?.cancel();
            // 分格模式：新一笔的落笔起点落在哪个格子就决定当前字（起点换格即新字，识别上一格）
            widget.onCellChanged?.call(p);
            _controller.start(p, DateTime.now().millisecondsSinceEpoch);
          },
          onPointerMove: (event) {
            if (event.pointer != _activePointerId) return;
            _controller.move(event.localPosition, event.localDelta, DateTime.now().millisecondsSinceEpoch, _isIos);
          },
          onPointerUp: (event) {
            if (event.pointer != _activePointerId) {
              _ignoredPointers.remove(event.pointer);
              return;
            }
            
            _lastStrokeEndTime = DateTime.now();
            widget.onPointerUp?.call();

            _activePointerId = null;
            _controller.end();
            
            if (widget.lines.isNotEmpty) {
              _autoRecognizeTimer?.cancel();
              // 自动模式（英文拼写）：停笔后自动识别+判题（维持原行为）。
              // 手动提交模式（中文默写）：停笔不自动识别，只在用户点击「提交」后一次性识别，
              // 避免对不完整/中间态笔画做切分导致"多个汉字被合成一个字"。
              if (!widget.manualSubmit) {
                _autoRecognizeTimer = Timer(const Duration(milliseconds: 300), () {
                  if (mounted && widget.lines.isNotEmpty) {
                    debugPrint('HB: Auto-triggering recognition via timer');
                    widget.onRecognize();
                  }
                });
              }
            } else {
              debugPrint('HB: Skip auto-trigger because lines is empty');
            }
            setState(() {});
          },
          onPointerCancel: (event) {
            if (event.pointer != _activePointerId) {
              _ignoredPointers.remove(event.pointer);
              return;
            }
            _activePointerId = null;
            _controller.end();
            setState(() {});
          },
          child: Stack(
            children: [
              if (widget.cellCount > 1)
                CustomPaint(
                  painter: _CellGuidePainter(
                    cellCount: widget.cellCount,
                    activeCell: widget.activeCellIndex,
                    isDark: isDark,
                    accent: context.primaryColor,
                  ),
                  size: Size.infinite,
                ),
              RepaintBoundary(
                child: CustomPaint(
                  painter: _HandwritingPainter(_controller, penColor),
                  size: Size.infinite,
                ),
              ),
              
              if (widget.showButtons) ...[
                // 底部操作栏：局部毛玻璃面板，把底下透出的列表文字晕成朦胧色块，避免与按钮纠缠
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  height: zoneHeight + bottomMargin + 10,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                          blurRadius: 20,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: ClipRect(
                      child: BackdropFilter(
                        filter: ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7),
                        child: Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xB81C2127) : const Color(0x4DFFFFFF),
                            border: Border(
                              top: BorderSide(
                                color: isDark ? const Color(0x33FFFFFF) : const Color(0x1FFFFFFF),
                                width: 1.0,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                for (int i = 0; i < controls.length; i++)
                  _buildCanvasControlButton(
                    left: controlZones[i].left,
                    top: controlZones[i].top,
                    width: zoneWidth,
                    height: zoneHeight,
                    icon: controls[i].icon,
                    label: controls[i].label,
                    onTap: controls[i].onTap,
                    isDark: isDark,
                    foreground: controlFg,
                    background: controlBg,
                    border: controlBorder,
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _HandwritingController extends ChangeNotifier {
  List<List<PointWithTime>> rawLines;
  Path finishedPath = Path();
  Path? activePath;
  Offset? lastRenderPoint; 
  Offset? midRenderPoint;
  Offset lastDelta = Offset.zero;
  Offset? lastSmoothPoint;

  _HandwritingController(this.rawLines) {
    _rebuildFinishedPath();
  }

  void _rebuildFinishedPath() {
    finishedPath = Path();
    for (var line in rawLines) {
      if (line.isEmpty) continue;
      finishedPath.moveTo(line[0].offset.dx, line[0].offset.dy);
      for (int i = 1; i < line.length - 1; i++) {
        final p0 = line[i].offset;
        final p1 = line[i + 1].offset;
        finishedPath.quadraticBezierTo(
            p0.dx, p0.dy, (p0.dx + p1.dx) / 2.0, (p0.dy + p1.dy) / 2.0);
      }
      if (line.length > 1) {
        finishedPath.lineTo(line.last.offset.dx, line.last.offset.dy);
      }
    }
  }

  void start(Offset p, int t) {
    rawLines.add([PointWithTime(p, t)]);
    activePath = Path();
    activePath!.moveTo(p.dx, p.dy);
    lastRenderPoint = p;
    midRenderPoint = p;
    lastSmoothPoint = p;
    lastDelta = Offset.zero;
    notifyListeners();
  }

  void clear() {
    rawLines.clear();
    finishedPath = Path();
    activePath = null;
    notifyListeners();
  }

  void removeLast() {
    if (rawLines.isNotEmpty) {
      rawLines.removeLast();
      _rebuildFinishedPath();
      activePath = null;
      notifyListeners();
    }
  }

  void move(Offset p, Offset delta, int t, bool isIos) {
    if (activePath == null || lastRenderPoint == null || lastSmoothPoint == null) return;
    if ((p - lastSmoothPoint!).distanceSquared < 0.1) return;
    
    // 调整 iOS 的平滑系数：
    // 原系数为 0.45 (旧值) / 0.55 (新值)。
    // 对于 iOS，我们适当减小对上一状态的依赖，增加当前采样点的权重 (0.35 / 0.65)，
    // 这样可以保留更多 iOS 高频采样的细节，减少由于过度平滑导致的字迹粘连。
    final smoothWeight = isIos ? 0.35 : 0.45;
    final currentWeight = 1.0 - smoothWeight;
    
    final smoothedPoint = lastSmoothPoint! * smoothWeight + p * currentWeight;
    rawLines.last.add(PointWithTime(smoothedPoint, t)); 
    lastDelta = delta;
    final newMidPoint =
        Offset((lastRenderPoint!.dx + smoothedPoint.dx) / 2.0, (lastRenderPoint!.dy + smoothedPoint.dy) / 2.0);
    activePath!.quadraticBezierTo(
        lastRenderPoint!.dx, lastRenderPoint!.dy, newMidPoint.dx, newMidPoint.dy);
    midRenderPoint = newMidPoint;
    lastRenderPoint = smoothedPoint;
    lastSmoothPoint = smoothedPoint;
    notifyListeners();
  }

  void end() {
    if (activePath != null && lastRenderPoint != null) {
      activePath!.lineTo(lastRenderPoint!.dx, lastRenderPoint!.dy);
      finishedPath.addPath(activePath!, Offset.zero);
      activePath = null;
      lastRenderPoint = null;
      midRenderPoint = null;
      lastSmoothPoint = null;
      notifyListeners();
    }
  }
}

class _HandwritingPainter extends CustomPainter {
  final _HandwritingController controller;
  final Color color;
  late final Paint _linePaint;

  _HandwritingPainter(this.controller, this.color) : super(repaint: controller) {
    _linePaint = Paint()
      ..color = color
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 4.8
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(controller.finishedPath, _linePaint);
    if (controller.activePath != null &&
        controller.lastRenderPoint != null &&
        controller.midRenderPoint != null) {
      canvas.drawPath(controller.activePath!, _linePaint);
      final predictedTip = controller.lastRenderPoint! + controller.lastDelta * 1.5;
      canvas.drawLine(controller.midRenderPoint!, predictedTip, _linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _HandwritingPainter oldDelegate) => true;
}

/// 分格书写提示：绘制格子分隔线，并高亮当前正在书写的格子。
class _CellGuidePainter extends CustomPainter {
  final int cellCount;
  final int activeCell;
  final bool isDark;
  final Color accent;

  _CellGuidePainter({
    required this.cellCount,
    required this.activeCell,
    required this.isDark,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 竖屏（高>宽）为上下两格（行），横屏（宽>=高）为左右两格（列）
    final bool vertical = size.height > size.width;
    final double cellMajor = (vertical ? size.height : size.width) / cellCount;

    // 高亮当前格（浅色填充 + 主题色描边）
    final Rect activeRect = vertical
        ? Rect.fromLTWH(0, activeCell * cellMajor, size.width, cellMajor)
        : Rect.fromLTWH(activeCell * cellMajor, 0, cellMajor, size.height);
    final highlight = Paint()
      ..color = accent.withValues(alpha: isDark ? 0.10 : 0.08);
    canvas.drawRect(activeRect, highlight);
    final activeBorder = Paint()
      ..color = accent.withValues(alpha: isDark ? 0.55 : 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    canvas.drawRect(activeRect.deflate(1.0), activeBorder);

    // 分隔线
    final line = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.18)
      ..strokeWidth = 1.0;
    for (int i = 1; i < cellCount; i++) {
      if (vertical) {
        final y = cellMajor * i;
        canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
      } else {
        final x = cellMajor * i;
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CellGuidePainter oldDelegate) =>
      oldDelegate.cellCount != cellCount ||
      oldDelegate.activeCell != activeCell ||
      oldDelegate.isDark != isDark ||
      oldDelegate.accent != accent;
}
