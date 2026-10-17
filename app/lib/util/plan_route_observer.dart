import 'package:flutter/widgets.dart';

/// 全局路由观察者：页面被新页面盖住时，让它自己收掉挂在根 Overlay 上的浮层。
///
/// 典型场景：首页的宠物气泡挂在根 Overlay（比任何页面内容都高），
/// 进入学习页/词表页时若不收掉，气泡会「跨界」闪现在别的页面上。
/// 放在独立文件里，避免 router 与页面互相 import 形成循环依赖。
final RouteObserver<ModalRoute<dynamic>> planRouteObserver = RouteObserver<ModalRoute<dynamic>>();
