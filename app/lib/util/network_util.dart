import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:nnbdc/global.dart';

/// 网络连接检测工具类
class NetworkUtil {
  static final NetworkUtil _instance = NetworkUtil._internal();
  factory NetworkUtil() => _instance;
  NetworkUtil._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  /// 检查网络连接状态
  /// 返回 true 表示有网络连接，false 表示无网络连接
  Future<bool> isConnected() async {
    try {
      // 检查网络连接类型
      List<ConnectivityResult> connectivityResults = await _connectivity.checkConnectivity();
      
      // 如果没有网络连接
      if (connectivityResults.isEmpty || connectivityResults.contains(ConnectivityResult.none)) {
        Global.logger.d('🌐 网络连接检测：无网络连接，静默跳过网络操作');
        return false;
      }

      // 检查是否能真正访问互联网（通过ping一个可靠的服务器）
      bool hasInternet = await _hasInternetAccess();
      if (!hasInternet) {
        Global.logger.d('🌐 网络连接检测：有网络但无法访问互联网，静默跳过网络操作');
        return false;
      }

      return true;
    } catch (e) {
      Global.logger.e('🌐 网络连接检测失败: $e，跳过所有网络操作');
      return false;
    }
  }

  /// 检查是否能真正访问互联网
  /// 通过尝试连接到一个可靠的服务器来验证
  Future<bool> _hasInternetAccess() async {
    try {
      // 尝试连接到一个可靠的服务器
      final result = await InternetAddress.lookup('www.baidu.com')
          .timeout(Duration(seconds: 5));
      
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        return true;
      }
    } catch (e) {
      Global.logger.d('🌐 互联网访问检测失败: $e');
    }

    // 如果百度连接失败，尝试连接谷歌DNS
    try {
      final result = await InternetAddress.lookup('8.8.8.8')
          .timeout(Duration(seconds: 3));
      
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        return true;
      }
    } catch (e) {
      Global.logger.d('🌐 DNS服务器连接检测失败: $e');
    }

    return false;
  }

  /// 监听网络连接状态变化
  /// 当网络状态发生变化时会调用回调函数
  void listenToConnectivityChanges(Function(bool isConnected) onConnectivityChanged) {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      (List<ConnectivityResult> results) async {
        bool connected = await isConnected();
        onConnectivityChanged(connected);
      },
    );
  }

  /// 停止监听网络连接状态变化
  void stopListening() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
  }

  /// 获取当前网络连接类型
  Future<String> getConnectionType() async {
    try {
      List<ConnectivityResult> results = await _connectivity.checkConnectivity();
      
      if (results.isEmpty || results.contains(ConnectivityResult.none)) {
        return '无网络';
      }
      
      if (results.contains(ConnectivityResult.wifi)) {
        return 'WiFi';
      }
      
      if (results.contains(ConnectivityResult.mobile)) {
        return '移动网络';
      }
      
      if (results.contains(ConnectivityResult.ethernet)) {
        return '以太网';
      }
      
      if (results.contains(ConnectivityResult.bluetooth)) {
        return '蓝牙';
      }
      
      if (results.contains(ConnectivityResult.vpn)) {
        return 'VPN';
      }
      
      return '其他';
    } catch (e) {
      Global.logger.e('🌐 获取网络连接类型失败: $e');
      return '未知';
    }
  }

  /// 清理资源
  void dispose() {
    stopListening();
  }
}
