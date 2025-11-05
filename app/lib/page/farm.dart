import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flame/game.dart';
import 'package:get/get.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:provider/provider.dart';
import '../global.dart';
import '../state.dart';
import '../theme/app_theme.dart';
import 'farm_game.dart';

// 泡泡类型
enum BubbleType { seed, egg, resource }

// 物品类型
enum ItemType {
  // 种子类型
  treeSeed, // 树种
  grassSeed, // 草种
  
  // 卵类型
  insectEgg, // 昆虫卵
  birdEgg, // 鸟卵
  
  // 资源类型
  fertilizer, // 化肥
  water, // 水
}

// 物品配置
class ItemConfig {
  final ItemType type;
  final String name;
  final IconData icon;
  final Color color;
  final BubbleType sourceType; // 来源泡泡类型

  const ItemConfig({
    required this.type,
    required this.name,
    required this.icon,
    required this.color,
    required this.sourceType,
  });
}

// 泡泡配置
class FarmBubbleTypeConfig {
  final BubbleType type;
  final String name;
  final Color color;
  final IconData icon;

  const FarmBubbleTypeConfig({
    required this.type,
    required this.name,
    required this.color,
    required this.icon,
  });
}

class FarmPage extends StatefulWidget {
  const FarmPage({super.key});

  @override
  State<FarmPage> createState() => _FarmPageState();
}

class _FarmPageState extends State<FarmPage> with TickerProviderStateMixin {
  late int cowDung; // 魔法泡泡数量
  late List<Map<String, dynamic>> userBubbles; // 用户的泡泡列表
  late List<Map<String, dynamic>> userItems; // 用户的物品列表
  late List<Map<String, dynamic>> farmItems; // 农场中的物品（已播种/孵化的）

  late AnimationController _bubbleGlowController;
  late AnimationController _rayRotationController;
  
  late FarmGame farmGame;

  // 泡泡类型配置
  static const List<FarmBubbleTypeConfig> _bubbleTypes = [
    FarmBubbleTypeConfig(
      type: BubbleType.seed,
      name: '种子',
      color: Colors.green,
      icon: Icons.eco,
    ),
    FarmBubbleTypeConfig(
      type: BubbleType.egg,
      name: '卵',
      color: Colors.amber,
      icon: Icons.egg,
    ),
    FarmBubbleTypeConfig(
      type: BubbleType.resource,
      name: '资源',
      color: Colors.blue,
      icon: Icons.diamond,
    ),
  ];

  // 物品配置
  static final List<ItemConfig> _itemConfigs = [
    // 种子类型 - 树种（多种）
    ItemConfig(type: ItemType.treeSeed, name: '橡树种', icon: Icons.park, color: Colors.brown[700]!, sourceType: BubbleType.seed),
    ItemConfig(type: ItemType.treeSeed, name: '松树种', icon: Icons.park, color: Colors.green[700]!, sourceType: BubbleType.seed),
    ItemConfig(type: ItemType.treeSeed, name: '枫树种', icon: Icons.park, color: Colors.orange[700]!, sourceType: BubbleType.seed),
    // 种子类型 - 草种（多种）
    ItemConfig(type: ItemType.grassSeed, name: '三叶草', icon: Icons.grass, color: Colors.green[600]!, sourceType: BubbleType.seed),
    ItemConfig(type: ItemType.grassSeed, name: '苜蓿草', icon: Icons.grass, color: Colors.green[500]!, sourceType: BubbleType.seed),
    ItemConfig(type: ItemType.grassSeed, name: '蒲公英', icon: Icons.grass, color: Colors.yellow[600]!, sourceType: BubbleType.seed),
    
    // 卵类型 - 昆虫卵（多种）
    ItemConfig(type: ItemType.insectEgg, name: '蝴蝶卵', icon: Icons.bug_report, color: Colors.purple[400]!, sourceType: BubbleType.egg),
    ItemConfig(type: ItemType.insectEgg, name: '蜜蜂卵', icon: Icons.bug_report, color: Colors.orange[400]!, sourceType: BubbleType.egg),
    ItemConfig(type: ItemType.insectEgg, name: '蜻蜓卵', icon: Icons.bug_report, color: Colors.blue[400]!, sourceType: BubbleType.egg),
    // 卵类型 - 鸟卵（多种）
    ItemConfig(type: ItemType.birdEgg, name: '麻雀卵', icon: Icons.egg, color: Colors.brown[400]!, sourceType: BubbleType.egg),
    ItemConfig(type: ItemType.birdEgg, name: '知更鸟卵', icon: Icons.egg, color: Colors.blue[300]!, sourceType: BubbleType.egg),
    ItemConfig(type: ItemType.birdEgg, name: '画眉鸟卵', icon: Icons.egg, color: Colors.grey[600]!, sourceType: BubbleType.egg),
    
    // 资源类型
    ItemConfig(type: ItemType.fertilizer, name: '有机化肥', icon: Icons.agriculture, color: Colors.brown[600]!, sourceType: BubbleType.resource),
    ItemConfig(type: ItemType.fertilizer, name: '营养肥料', icon: Icons.agriculture, color: Colors.green[700]!, sourceType: BubbleType.resource),
    ItemConfig(type: ItemType.water, name: '清水', icon: Icons.water_drop, color: Colors.blue[400]!, sourceType: BubbleType.resource),
    ItemConfig(type: ItemType.water, name: '营养液', icon: Icons.water_drop, color: Colors.teal[400]!, sourceType: BubbleType.resource),
  ];

  @override
  void initState() {
    super.initState();
    
    // 初始化动画控制器
    _bubbleGlowController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);
    
    _rayRotationController = AnimationController(
      duration: const Duration(milliseconds: 30000),
      vsync: this,
    )..repeat();
    
    _loadUserData();
    
    // 初始化Flame游戏
    farmGame = FarmGame(
      onItemTap: _handleItemTap,
      onTileTap: _handleTileTap,
    );
  }

  @override
  void dispose() {
    _bubbleGlowController.dispose();
    _rayRotationController.dispose();
    farmGame.removeFromParent();
    super.dispose();
  }
  
  // 处理物品点击
  void _handleItemTap(ItemConfig config, int gridX, int gridY) {
    // 可以在这里实现物品点击后的操作，比如收获、查看详情等
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(config.name),
        content: Text('位于 ($gridX, $gridY)'),
        actions: [
          TextButton(
            onPressed: () {
              farmGame.removeItem(gridX, gridY);
              setState(() {
                farmItems.removeWhere((item) => 
                  item['gridX'] == gridX && item['gridY'] == gridY
                );
              });
              Get.back();
              ToastUtil.success('已移除 ${config.name}');
            },
            child: const Text('移除'),
          ),
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
  
  // 处理地块点击
  void _handleTileTap(int gridX, int gridY) {
    // 可以在这里实现地块点击后的操作，比如选择放置物品的位置
  }

  // 加载用户数据
  Future<void> _loadUserData() async {
    final user = Global.getLoggedInUser();
    if (user == null) {
      ToastUtil.error('用户未登录');
      Get.back();
      return;
    }

    setState(() {
      cowDung = user.cowDung;
      // 初始化用户泡泡列表（简化版：直接使用cowDung数量，实际应该从数据库加载）
      userBubbles = _generateBubbles(cowDung);
      userItems = []; // 从数据库加载用户物品
      farmItems = []; // 从数据库加载农场物品
    });
  }

  // 生成泡泡列表
  List<Map<String, dynamic>> _generateBubbles(int count) {
    final random = math.Random();
    return List.generate(count, (index) {
      final typeIndex = random.nextInt(_bubbleTypes.length);
      final bubbleType = _bubbleTypes[typeIndex];
      return {
        'id': 'bubble_$index',
        'type': bubbleType.type,
        'config': bubbleType,
      };
    });
  }

  // 打开泡泡，获得随机物品
  void _openBubble(Map<String, dynamic> bubble) {
    final random = math.Random();
    final bubbleType = bubble['type'] as BubbleType;
    
    // 根据泡泡类型获取可能的物品
    final possibleItems = _itemConfigs.where((item) => item.sourceType == bubbleType).toList();
    if (possibleItems.isEmpty) return;
    
    // 随机选择一个物品
    final selectedItem = possibleItems[random.nextInt(possibleItems.length)];
    final quantity = random.nextInt(3) + 1; // 1-3个
    
    setState(() {
      // 移除泡泡
      userBubbles.removeWhere((b) => b['id'] == bubble['id']);
      cowDung--;
      
      // 添加物品
      final existingItemIndex = userItems.indexWhere((item) => item['type'] == selectedItem.type);
      if (existingItemIndex >= 0) {
        userItems[existingItemIndex]['quantity'] += quantity;
      } else {
        userItems.add({
          'type': selectedItem.type,
          'config': selectedItem,
          'quantity': quantity,
        });
      }
    });
    
    ToastUtil.success('获得了 ${selectedItem.name} x$quantity');
  }

  // 使用种子播种
  void _plantSeed(ItemConfig itemConfig, int quantity) {
    if (quantity <= 0) return;
    
    setState(() {
      final itemIndex = userItems.indexWhere((item) => item['type'] == itemConfig.type);
      if (itemIndex >= 0) {
        final useCount = math.min(quantity, userItems[itemIndex]['quantity'] as int);
        userItems[itemIndex]['quantity'] -= useCount;
        if (userItems[itemIndex]['quantity'] <= 0) {
          userItems.removeAt(itemIndex);
        }
        
        // 添加到农场（随机选择空位置）
        final random = math.Random();
        int gridX = random.nextInt(FarmGame.gridWidth);
        int gridY = random.nextInt(FarmGame.gridHeight);
        
        // 确保位置是空的
        while (farmItems.any((item) => item['gridX'] == gridX && item['gridY'] == gridY)) {
          gridX = random.nextInt(FarmGame.gridWidth);
          gridY = random.nextInt(FarmGame.gridHeight);
        }
        
        farmItems.add({
          'type': itemConfig.type,
          'config': itemConfig,
          'gridX': gridX,
          'gridY': gridY,
          'plantTime': DateTime.now(),
        });
        
        // 在游戏中放置物品
        farmGame.placeItem(itemConfig, gridX, gridY);
        
        ToastUtil.success('播种了 ${itemConfig.name} x$useCount');
      }
    });
  }

  // 孵化卵
  void _hatchEgg(ItemConfig itemConfig, int quantity) {
    if (quantity <= 0) return;
    
    setState(() {
      final itemIndex = userItems.indexWhere((item) => item['type'] == itemConfig.type);
      if (itemIndex >= 0) {
        final useCount = math.min(quantity, userItems[itemIndex]['quantity'] as int);
        userItems[itemIndex]['quantity'] -= useCount;
        if (userItems[itemIndex]['quantity'] <= 0) {
          userItems.removeAt(itemIndex);
        }
        
        // 添加到农场（随机选择空位置）
        final random = math.Random();
        int gridX = random.nextInt(FarmGame.gridWidth);
        int gridY = random.nextInt(FarmGame.gridHeight);
        
        // 确保位置是空的
        while (farmItems.any((item) => item['gridX'] == gridX && item['gridY'] == gridY)) {
          gridX = random.nextInt(FarmGame.gridWidth);
          gridY = random.nextInt(FarmGame.gridHeight);
        }
        
        farmItems.add({
          'type': itemConfig.type,
          'config': itemConfig,
          'gridX': gridX,
          'gridY': gridY,
          'hatchTime': DateTime.now(),
        });
        
        // 在游戏中放置物品
        farmGame.placeItem(itemConfig, gridX, gridY);
        
        ToastUtil.success('孵化了 ${itemConfig.name} x$useCount');
      }
    });
  }

  // 使用资源
  void _useResource(ItemConfig itemConfig, int quantity) {
    if (quantity <= 0) return;
    
    setState(() {
      final itemIndex = userItems.indexWhere((item) => item['type'] == itemConfig.type);
      if (itemIndex >= 0) {
        final useCount = math.min(quantity, userItems[itemIndex]['quantity'] as int);
        userItems[itemIndex]['quantity'] -= useCount;
        if (userItems[itemIndex]['quantity'] <= 0) {
          userItems.removeAt(itemIndex);
        }
        
        ToastUtil.success('使用了 ${itemConfig.name} x$useCount');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.watch<DarkMode>().isDarkMode;
    final cardColor = isDarkMode ? Colors.grey[850] : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black87;

    return Scaffold(
      appBar: AppBar(
        title: const Text('我的小天地'),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // 农场区域（使用Flame游戏引擎）
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.brown[200]!,
                    Colors.brown[300]!,
                    Colors.brown[400]!,
                  ],
                ),
              ),
              child: GameWidget<FarmGame>.controlled(
                gameFactory: () => farmGame,
              ),
            ),
          ),
          // 底部泡泡和物品区域
          Container(
            constraints: const BoxConstraints(minHeight: 200),
            color: cardColor,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '魔法泡泡 (${userBubbles.length})',
                  style: TextStyle(
                    color: textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 70,
                  child: _buildBubblesList(isDarkMode),
                ),
                if (userItems.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    '我的物品',
                    style: TextStyle(
                      color: textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 70,
                    child: _buildItemsList(isDarkMode),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // 构建泡泡列表
  Widget _buildBubblesList(bool isDarkMode) {
    if (userBubbles.isEmpty) {
      return Center(
        child: Text(
          '暂无魔法泡泡',
          style: TextStyle(
            color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
            fontSize: 12,
            fontWeight: FontWeight.w400,
          ),
        ),
      );
    }

    return ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: userBubbles.length,
      itemBuilder: (context, index) {
        final bubble = userBubbles[index];
        final config = bubble['config'] as FarmBubbleTypeConfig;
        
        return GestureDetector(
          onTap: () => _openBubble(bubble),
          child: Container(
            margin: const EdgeInsets.only(right: 12),
            width: 50,
            height: 50,
            child: _buildSingleBubble(config, 40),
          ),
        );
      },
    );
  }

  // 构建物品列表
  Widget _buildItemsList(bool isDarkMode) {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      itemCount: userItems.length,
      itemBuilder: (context, index) {
        final item = userItems[index];
        final config = item['config'] as ItemConfig;
        final quantity = item['quantity'] as int;
        
        return GestureDetector(
          onTap: () {
            _showItemActionDialog(config, quantity);
          },
          child: Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: config.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: config.color, width: 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(config.icon, color: config.color, size: 24),
                const SizedBox(height: 4),
                Text(
                  'x$quantity',
                  style: TextStyle(
                    color: isDarkMode ? Colors.white : Colors.black87,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // 显示物品操作对话框
  void _showItemActionDialog(ItemConfig config, int quantity) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(config.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(config.icon, size: 48, color: config.color),
            const SizedBox(height: 16),
            Text('数量: $quantity'),
            const SizedBox(height: 16),
            if (config.sourceType == BubbleType.seed)
              ElevatedButton(
                onPressed: () {
                  Get.back();
                  _plantSeed(config, 1);
                },
                child: const Text('播种'),
              ),
            if (config.sourceType == BubbleType.egg)
              ElevatedButton(
                onPressed: () {
                  Get.back();
                  _hatchEgg(config, 1);
                },
                child: const Text('孵化'),
              ),
            if (config.sourceType == BubbleType.resource)
              ElevatedButton(
                onPressed: () {
                  Get.back();
                  _useResource(config, 1);
                },
                child: const Text('使用'),
              ),
          ],
        ),
      ),
    );
  }

  // 构建单个泡泡（复用finish.dart的样式）
  Widget _buildSingleBubble(FarmBubbleTypeConfig type, double size) {
    final maxGlowExtension = size * 0.5;
    final containerSize = size + maxGlowExtension * 2;
    
    return SizedBox(
      width: containerSize,
      height: containerSize,
      child: AnimatedBuilder(
        animation: Listenable.merge([_bubbleGlowController, _rayRotationController]),
        builder: (context, child) {
          final glowValue = 0.4 + (_bubbleGlowController.value * 0.6);
          final rotationAngle = _rayRotationController.value * 2 * math.pi;
          
          return Stack(
            clipBehavior: Clip.none,
            children: [
              // 外层光晕
              Positioned(
                left: maxGlowExtension - (maxGlowExtension * (1 - glowValue)),
                top: maxGlowExtension - (maxGlowExtension * (1 - glowValue)),
                child: Container(
                  width: size + (maxGlowExtension * 2 * glowValue),
                  height: size + (maxGlowExtension * 2 * glowValue),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        type.color.withValues(alpha: 0.3 * glowValue),
                        type.color.withValues(alpha: 0),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: type.color.withValues(alpha: 0.5 * glowValue),
                        blurRadius: 20 * glowValue,
                        spreadRadius: 5 * glowValue,
                      ),
                    ],
                  ),
                ),
              ),
              // 主泡泡
              Positioned(
                left: maxGlowExtension,
                top: maxGlowExtension,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      center: const Alignment(-0.3, -0.3),
                      colors: [
                        type.color.withValues(alpha: 0.9),
                        type.color,
                        type.color.withValues(alpha: 0.7),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: type.color.withValues(alpha: 0.6 * glowValue),
                        blurRadius: 15 * glowValue,
                        spreadRadius: 3 * glowValue,
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      // 内部光线
                      _buildInternalRays(size, type.color, rotationAngle, glowValue),
                      // 内部图标
                      Center(
                        child: Icon(
                          type.icon,
                          size: size * 0.4,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // 构建内部光线
  Widget _buildInternalRays(double size, Color color, double rotationAngle, double glowValue) {
    const int rayCount = 12;
    final rayHeight = size * 0.35;
    
    return Transform.rotate(
      angle: rotationAngle,
      child: CustomPaint(
        size: Size(size, size),
        painter: _InternalRayPainter(
          rayCount: rayCount,
          rayHeight: rayHeight,
          color: color,
          glowValue: glowValue,
        ),
      ),
    );
  }
}

// 内部光线绘制器
class _InternalRayPainter extends CustomPainter {
  final int rayCount;
  final double rayHeight;
  final Color color;
  final double glowValue;

  _InternalRayPainter({
    required this.rayCount,
    required this.rayHeight,
    required this.color,
    required this.glowValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final angleStep = 2 * math.pi / rayCount;
    
    for (int i = 0; i < rayCount; i++) {
      final angle = i * angleStep;
      final startX = center.dx + math.cos(angle) * (size.width / 2 - rayHeight);
      final startY = center.dy + math.sin(angle) * (size.height / 2 - rayHeight);
      final endX = center.dx + math.cos(angle) * (size.width / 2);
      final endY = center.dy + math.sin(angle) * (size.height / 2);
      
      final paint = Paint()
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.white.withValues(alpha: 0.15 * glowValue),
            Colors.white.withValues(alpha: 0.25 * glowValue),
            Colors.white.withValues(alpha: 0.15 * glowValue),
          ],
        ).createShader(Rect.fromPoints(Offset(startX, startY), Offset(endX, endY)));
      
      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), paint);
    }
  }

  @override
  bool shouldRepaint(_InternalRayPainter oldDelegate) =>
      oldDelegate.rayCount != rayCount ||
      oldDelegate.rayHeight != rayHeight ||
      oldDelegate.color != color ||
      oldDelegate.glowValue != glowValue;
}

