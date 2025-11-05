import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'farm.dart';

// 等轴测图工具类
class IsometricUtils {
  // 将屏幕坐标转换为等轴测坐标
  static Vector2 screenToIsometric(double x, double y) {
    final isoX = (x + y) / 2;
    final isoY = (y - x) / 2;
    return Vector2(isoX, isoY);
  }

  // 将等轴测坐标转换为屏幕坐标
  static Vector2 isometricToScreen(double isoX, double isoY) {
    final screenX = isoX - isoY;
    final screenY = (isoX + isoY) / 2;
    return Vector2(screenX, screenY);
  }

  // 计算等轴测图的排序深度
  static double calculateDepth(int gridX, int gridY, int gridZ) {
    return (gridX + gridY) * 1000 + gridZ * 100;
  }
}

// 农场地块组件
class FarmTile extends PositionComponent with TapCallbacks {
  final int gridX;
  final int gridY;
  final Color color;
  FarmItem? item; // 地块上的物品

  FarmTile({
    required this.gridX,
    required this.gridY,
    required Vector2 position,
    required Vector2 size,
    this.color = const Color(0xFF8B6F47),
  }) : super(position: position, size: size);

  @override
  void render(Canvas canvas) {
    // 绘制等轴测图的菱形地块
    final paint = Paint()..color = color;
    
    // 创建菱形路径（45度角）
    final path = Path();
    final halfWidth = size.x / 2;
    final halfHeight = size.y / 2;
    
    // 顶
    path.moveTo(halfWidth, 0);
    // 右
    path.lineTo(size.x, halfHeight);
    // 底
    path.lineTo(halfWidth, size.y);
    // 左
    path.lineTo(0, halfHeight);
    path.close();
    
    canvas.drawPath(path, paint);
    
    // 添加边框
    final borderPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawPath(path, borderPaint);
    
    // 如果地块上有物品，绘制阴影
    if (item != null) {
      final shadowPath = Path();
      shadowPath.moveTo(halfWidth, size.y);
      shadowPath.lineTo(size.x, halfHeight);
      shadowPath.lineTo(halfWidth, size.y - 5);
      shadowPath.lineTo(0, halfHeight);
      shadowPath.close();
      
      canvas.drawPath(
        shadowPath,
        Paint()..color = Colors.black.withValues(alpha: 0.2),
      );
    }
  }

  @override
  bool onTapDown(TapDownEvent event) {
    return true; // 处理点击事件
  }
}

// 农场物品组件
class FarmItem extends PositionComponent with TapCallbacks {
  final ItemConfig config;
  final int gridX;
  final int gridY;
  final int gridZ;
  final DateTime placedTime;
  final Function(ItemConfig, int, int)? onTap;

  FarmItem({
    required this.config,
    required this.gridX,
    required this.gridY,
    this.gridZ = 1,
    required Vector2 position,
    required Vector2 size,
    required this.placedTime,
    this.onTap,
  }) : super(position: position, size: size);

  @override
  void render(Canvas canvas) {
    // 绘制等轴测图的物品
    final halfWidth = size.x / 2;
    final halfHeight = size.y / 2;
    
    // 绘制物品的等轴测立方体
    final paint = Paint()..color = config.color;
    
    // 顶面
    final topPath = Path();
    topPath.moveTo(halfWidth, 0);
    topPath.lineTo(size.x, halfHeight);
    topPath.lineTo(halfWidth, size.y);
    topPath.lineTo(0, halfHeight);
    topPath.close();
    
    canvas.drawPath(topPath, paint);
    
    // 添加图标（简化版，使用颜色块）
    final iconPaint = Paint()
      ..color = config.color.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;
    
    canvas.drawCircle(
      Offset(halfWidth, halfHeight),
      size.x * 0.2,
      iconPaint,
    );
    
    // 绘制高光
    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3);
    canvas.drawCircle(
      Offset(halfWidth * 0.7, halfHeight * 0.7),
      size.x * 0.1,
      highlightPaint,
    );
  }

  @override
  bool onTapDown(TapDownEvent event) {
    if (onTap != null) {
      onTap!(config, gridX, gridY);
    }
    return true;
  }
}

// 拖拽地图组件（全屏透明层）
class DragMapComponent extends PositionComponent with DragCallbacks, HasGameRef<FarmGame> {
  Vector2 _cumulativeDrag = Vector2.zero();
  // 多指缩放支持
  final Map<int, Vector2> _activePointers = {};
  final Map<int, Vector2> _startPointers = {};
  bool _isPinching = false;
  double _pinchStartScale = 1.0;
  Vector2 _pinchStartWorldPos = Vector2.zero();

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    size = gameRef.size;
    position = Vector2.zero();
    priority = 10000; // 最高优先级
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);
    this.size = size;
  }

  @override
  bool containsLocalPoint(Vector2 point) {
    return true; // 总是返回true以捕获所有事件
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    _cumulativeDrag = Vector2.zero();
    // 记录指针
    try {
      _activePointers[event.pointerId] = event.localPosition;
      _startPointers[event.pointerId] = event.localPosition.clone();
    } catch (_) {}
    debugPrint('Flame拖拽开始 pointers=${_activePointers.length}');
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    super.onDragUpdate(event);
    final game = gameRef;
    // 更新指针位置（使用累计增量）
    if (_activePointers.containsKey(event.pointerId)) {
      _activePointers[event.pointerId] = _activePointers[event.pointerId]! + event.localDelta;
    }

    // 如果有两指，执行缩放；否则执行平移
    if (_activePointers.length >= 2) {
      // 初始化捏合状态
      if (!_isPinching) {
        _isPinching = true;
        _pinchStartScale = game.worldLayer.scale.x;
        _pinchStartWorldPos = game.worldLayer.position.clone();
      }

      // 取任意两指
      final entries = _activePointers.entries.toList();
      final Vector2 p1Current = entries[0].value;
      final Vector2 p2Current = entries[1].value;
      final Vector2 p1Start = _startPointers[entries[0].key] ?? p1Current;
      final Vector2 p2Start = _startPointers[entries[1].key] ?? p2Current;

      final double startDistance = (p1Start - p2Start).length;
      final double currentDistance = (p1Current - p2Current).length;
      if (startDistance > 0.0) {
        final double desiredScale = (_pinchStartScale * (currentDistance / startDistance))
            .clamp(FarmGame.minScale, FarmGame.maxScale);

        // 焦点为两指中点
        final Vector2 focal = (p1Current + p2Current) / 2;
        final Vector2 worldPoint = (focal - _pinchStartWorldPos) / _pinchStartScale;
        final Vector2 newWorldPos = focal - worldPoint * desiredScale;

        game.worldLayer.scale = Vector2.all(desiredScale);

        // 缩放后边界（考虑scale以及溢出）
        final screenSize = game.size;
        final scaledWorld = Vector2(game.worldWidth, game.worldHeight) * desiredScale;
        final bool widerThanScreen = scaledWorld.x > screenSize.x;
        final bool tallerThanScreen = scaledWorld.y > screenSize.y;
        final double contentCenterOffsetX = (screenSize.x - scaledWorld.x) / 2;
        final double contentCenterOffsetY = (screenSize.y - scaledWorld.y) / 2;
        final double minX = (widerThanScreen ? (screenSize.x - scaledWorld.x) : contentCenterOffsetX) - FarmGame.panOverflow;
        final double maxX = (widerThanScreen ? 0.0 : contentCenterOffsetX) + FarmGame.panOverflow;
        final double minY = (tallerThanScreen ? (screenSize.y - scaledWorld.y) : contentCenterOffsetY) - FarmGame.panOverflow;
        final double maxY = (tallerThanScreen ? 0.0 : contentCenterOffsetY) + FarmGame.panOverflow;

        final Vector2 clamped = Vector2(
          newWorldPos.x.clamp(minX, maxX),
          newWorldPos.y.clamp(minY, maxY),
        );

        game.worldLayer.position = clamped;

        debugPrint('Flame捏合: startDist=${startDistance.toStringAsFixed(2)}, currDist=${currentDistance.toStringAsFixed(2)}, scale=$desiredScale, focal=$focal, pos=${game.worldLayer.position}');
      }
      return;
    }

    // 单指平移
    final delta = event.localDelta;
    _cumulativeDrag += delta;
    final newPos = game.worldLayer.position + delta;
    
    // 边界限制
    final screenSize = game.size;
    final worldSize = Vector2(game.worldWidth, game.worldHeight);
    
    // 计算容器可移动范围（加入溢出范围，允许大范围拖动）
    final bool widerThanScreen = worldSize.x > screenSize.x;
    final bool tallerThanScreen = worldSize.y > screenSize.y;

    final double contentCenterOffsetX = (screenSize.x - worldSize.x) / 2;
    final double contentCenterOffsetY = (screenSize.y - worldSize.y) / 2;

    final double minX = (widerThanScreen ? (screenSize.x - worldSize.x) : contentCenterOffsetX) - FarmGame.panOverflow;
    final double maxX = (widerThanScreen ? 0.0 : contentCenterOffsetX) + FarmGame.panOverflow;
    final double minY = (tallerThanScreen ? (screenSize.y - worldSize.y) : contentCenterOffsetY) - FarmGame.panOverflow;
    final double maxY = (tallerThanScreen ? 0.0 : contentCenterOffsetY) + FarmGame.panOverflow;
    
    // 限制在边界内
    final clampedPos = Vector2(
      newPos.x.clamp(minX, maxX),
      newPos.y.clamp(minY, maxY),
    );
    
    // 更新世界容器位置
    game.worldLayer.position = clampedPos;
    
    debugPrint('Flame拖拽: delta=$delta, 累积=$_cumulativeDrag, 世界位置=${game.worldLayer.position}, 范围:x['
        '$minX,$maxX], y[$minY,$maxY], 屏幕=$screenSize, 世界=$worldSize');
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    debugPrint('Flame拖拽结束');
    _cumulativeDrag = Vector2.zero();
    // 移除指针
    _activePointers.remove(event.pointerId);
    _startPointers.remove(event.pointerId);
    if (_activePointers.length < 2) {
      _isPinching = false;
    }
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    debugPrint('Flame拖拽取消');
    _cumulativeDrag = Vector2.zero();
    _activePointers.clear();
    _startPointers.clear();
    _isPinching = false;
  }

}

// 农场游戏主类
class FarmGame extends FlameGame {
  final Function(ItemConfig, int, int)? onItemTap;
  final Function(int, int)? onTileTap;
  
  final List<FarmTile> tiles = [];
  final List<FarmItem> items = [];
  // 承载农场世界的容器，拖拽时移动该容器
  late final PositionComponent worldLayer;
  
  // 网格配置（增加网格大小以使世界大于屏幕，支持拖动）
  static const int gridWidth = 20;
  static const int gridHeight = 25;
  static const double tileWidth = 60.0;
  static const double tileHeight = 30.0;
  // 拖动溢出范围（允许超出内容边界拖动的距离，像素）
  static const double panOverflow = 1000.0;
  // 缩放限制
  static const double minScale = 0.5;
  static const double maxScale = 3.0;
  
  // 农场世界边界
  double get worldWidth => (gridWidth - 1) * (tileWidth / 2) + tileWidth;
  double get worldHeight => (gridHeight - 1) * (tileHeight / 2) + tileHeight;

  FarmGame({
    this.onItemTap,
    this.onTileTap,
  });

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    
    // 创建世界容器并添加到场景
    worldLayer = PositionComponent(position: Vector2.zero());
    add(worldLayer);
    
    // 创建农场地块网格
    _createFarmTiles();
    
    // 初始位置居中显示农场（通过移动世界容器）
    _centerWorldLayer();
    
    // 添加拖拽地图组件（最高优先级）
    add(DragMapComponent());
  }
  
  // 居中显示农场（移动世界容器）
  void _centerWorldLayer() {
    final screenSize = size;
    final worldSize = Vector2(worldWidth, worldHeight);
    
    debugPrint('居中世界: 屏幕大小=$screenSize, 世界大小=$worldSize');
    
    double offsetX = 0.0;
    double offsetY = 0.0;
    
    if (worldSize.x > screenSize.x) {
      offsetX = -(worldSize.x - screenSize.x) / 2;
    } else {
      // 世界小于屏幕，保持居中
      offsetX = (screenSize.x - worldSize.x) / 2;
    }
    if (worldSize.y > screenSize.y) {
      offsetY = -(worldSize.y - screenSize.y) / 2;
    } else {
      offsetY = (screenSize.y - worldSize.y) / 2;
    }
    
    worldLayer.position = Vector2(offsetX, offsetY);
    debugPrint('世界容器位置设置为: ${worldLayer.position}');
  }
  
  // 移动相机（供外部调用）
  void moveCamera(Vector2 delta) {
    final screenSize = size;
    final worldSize = Vector2(worldWidth, worldHeight);
    
    final newPosition = camera.viewfinder.position - delta;
    
    final maxX = (worldSize.x - screenSize.x).clamp(0.0, double.infinity);
    final maxY = (worldSize.y - screenSize.y).clamp(0.0, double.infinity);
    
    camera.viewfinder.position = Vector2(
      newPosition.x.clamp(0.0, maxX > 0 ? maxX.toDouble() : 0.0),
      newPosition.y.clamp(0.0, maxY > 0 ? maxY.toDouble() : 0.0),
    );
  }

  void _createFarmTiles() {
    tiles.clear();
    
    for (int y = 0; y < gridHeight; y++) {
      for (int x = 0; x < gridWidth; x++) {
        // 计算等轴测图的屏幕位置
        final isoX = (x - y) * (tileWidth / 2);
        final isoY = (x + y) * (tileHeight / 2);
        
        final tile = FarmTile(
          gridX: x,
          gridY: y,
          position: Vector2(isoX, isoY),
          size: Vector2(tileWidth, tileHeight),
          color: _getTileColor(x, y),
        );
        
        worldLayer.add(tile);
        tiles.add(tile);
      }
    }
  }

  Color _getTileColor(int x, int y) {
    // 创建随机但稳定的颜色变化，模拟土地质感
    final seed = (x * 31 + y * 17) % 100;
    if (seed < 60) {
      return const Color(0xFF8B6F47); // 棕色土地
    } else if (seed < 85) {
      return const Color(0xFF9B7F57); // 稍浅的棕色
    } else {
      return const Color(0xFF7B5F37); // 稍深的棕色
    }
  }

  // 在地块上放置物品
  void placeItem(ItemConfig config, int gridX, int gridY) {
    // 移除该位置已有的物品
    removeItem(gridX, gridY);
    
    // 找到对应的地块
    final tile = tiles.firstWhere(
      (t) => t.gridX == gridX && t.gridY == gridY,
      orElse: () => tiles[0],
    );
    
    if (tile == tiles[0] && (tile.gridX != gridX || tile.gridY != gridY)) {
      return; // 无效位置
    }
    
    // 计算物品位置（在地块上方）
    final isoX = (gridX - gridY) * (tileWidth / 2);
    final isoY = (gridX + gridY) * (tileHeight / 2) - 10; // 稍微上移
    
    final item = FarmItem(
      config: config,
      gridX: gridX,
      gridY: gridY,
      gridZ: 1,
      position: Vector2(isoX, isoY),
      size: Vector2(tileWidth * 0.8, tileHeight * 0.8),
      placedTime: DateTime.now(),
      onTap: onItemTap,
    );
    
    tile.item = item;
    worldLayer.add(item);
    items.add(item);
    
    // 更新渲染顺序
    _updateRenderOrder();
  }

  // 移除物品
  void removeItem(int gridX, int gridY) {
    final itemIndex = items.indexWhere(
      (item) => item.gridX == gridX && item.gridY == gridY,
    );
    
    if (itemIndex >= 0) {
      final item = items[itemIndex];
      items.removeAt(itemIndex);
      remove(item);
      
      // 清除地块的物品引用
      final tile = tiles.firstWhere(
        (t) => t.gridX == gridX && t.gridY == gridY,
        orElse: () => tiles[0],
      );
      if (tile.gridX == gridX && tile.gridY == gridY) {
        tile.item = null;
      }
    }
  }

  // 更新渲染顺序（确保前面的物品遮挡后面的）
  void _updateRenderOrder() {
    items.sort((a, b) {
      final depthA = IsometricUtils.calculateDepth(a.gridX, a.gridY, a.gridZ);
      final depthB = IsometricUtils.calculateDepth(b.gridX, b.gridY, b.gridZ);
      return depthA.compareTo(depthB);
    });
    
    tiles.sort((a, b) {
      final depthA = IsometricUtils.calculateDepth(a.gridX, a.gridY, 0);
      final depthB = IsometricUtils.calculateDepth(b.gridX, b.gridY, 0);
      return depthA.compareTo(depthB);
    });
  }

  // 清除所有物品
  void clearAllItems() {
    for (final item in List<FarmItem>.from(items)) {
      remove(item);
    }
    items.clear();
    
    for (final tile in tiles) {
      tile.item = null;
    }
  }
}
