import 'dart:async';

import 'package:nnbdc/config.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/network_util.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

abstract class SocketStatusListener {
  onConnected();

  onDisconnected();
}

class SocketIoClient {
  static SocketIoClient instance = SocketIoClient();
  Timer? heartBeatTimer;
  late io.Socket socket;
  var isConnectedToSocketServer = false;
  var socketEventListeners = <Function(String event, List args)>[];
  var socketStatusListeners = <SocketStatusListener>[];
  bool _disposed = false;
  bool _initialized = false;
  final NetworkUtil _networkUtil = NetworkUtil();

  Timer? _disconnectToastTimer;

  // 当前是否在russia游戏页面
  bool _isInRussiaGame = false;
  
  // 连接引用计数，用于管理多个页面对socket的需求
  int _connectionRefCount = 0;

  SocketIoClient() {
    Global.logger.d('SocketIoClient: 单例创建（延迟连接模式）');
  }
  
  /// 初始化socket实例（但不立即连接）
  void _initSocket() {
    if (_initialized) return;
    
    Global.logger.d('SocketIoClient: 开始初始化Socket实例');

    // 创建 socket.io 实例，但不自动连接
    var opts = io.OptionBuilder()
        .setTransports(['websocket'])
        .disableAutoConnect()  // 禁用自动连接
        .build();
    socket = io.io(Config.socketServerUrl, opts);

    Global.logger.d('SocketIoClient: Socket实例已创建，开始设置事件监听器');

    socket.onConnect((_) {
      Global.logger.d('SocketIoClient: 收到连接事件');
      if (_disposed) {
        Global.logger.d('SocketIoClient: 已销毁，忽略连接事件');
        return;
      }
      tryReportUserToSocketServer();
      isConnectedToSocketServer = true;

      Global.logger.d('SocketIoClient: 连接成功，isConnectedToSocketServer = true');

      _disconnectToastTimer?.cancel();
      _disconnectToastTimer = null;

      for (var listener in socketStatusListeners) {
        listener.onConnected();
      }
    });
    socket.on("inviteYouToGame", (args) {
      if (_disposed) return;
      for (var listener in socketEventListeners) {
        listener("inviteYouToGame", args);
      }
    });
    socket.on("persistentMsgCount", (args) {
      if (_disposed) return;
      for (var listener in socketEventListeners) {
        listener("persistentMsgCount", args);
      }
    });
    socket.onDisconnect((_) {
      Global.logger.d('SocketIoClient: 收到断开连接事件');
      if (_disposed) {
        Global.logger.d('SocketIoClient: 已销毁，忽略断开连接事件');
        return;
      }
      isConnectedToSocketServer = false;

      Global.logger.w('检测到游戏服务器连接断开');


      for (var listener in socketStatusListeners) {
        listener.onDisconnected();
      }
    });

    _initialized = true;
    Global.logger.d('SocketIoClient: Socket实例初始化完成');
  }
  
  /// 请求连接（带引用计数）
  void connect() async {
    // 检查网络连接
    bool isConnected = await _networkUtil.isConnected();
    if (!isConnected) {
      Global.logger.d('🌐 网络连接不可用，静默跳过Socket连接');
      return;
    }
    
    _initSocket();
    
    _connectionRefCount++;
    Global.logger.d('SocketIoClient: 连接请求，引用计数: $_connectionRefCount');
    
    if (_connectionRefCount == 1) {
      // 第一个连接请求，真正执行连接
      Global.logger.d('SocketIoClient: 开始连接到服务器');
      socket.connect();
      
      // 启动心跳定时器
      _startHeartbeat();
    }
  }
  
  /// 释放连接（带引用计数）
  void disconnect() {
    if (_connectionRefCount <= 0) return;
    
    _connectionRefCount--;
    Global.logger.d('SocketIoClient: 断开请求，引用计数: $_connectionRefCount');
    
    if (_connectionRefCount == 0) {
      // 没有任何页面需要连接了，真正断开
      Global.logger.d('SocketIoClient: 断开与服务器的连接');
      
      // 停止心跳定时器
      _stopHeartbeat();
      
      // 断开socket连接
      socket.disconnect();
      isConnectedToSocketServer = false;
    }
  }
  
  /// 启动心跳定时器
  void _startHeartbeat() {
    if (heartBeatTimer != null) return;
    
    Global.logger.d('SocketIoClient: 启动心跳定时器');
    heartBeatTimer = Timer.periodic(const Duration(milliseconds: 5000), (Timer timer) async {
      if (_disposed) {
        Global.logger.d('SocketIoClient: 已销毁，取消心跳定时器');
        timer.cancel();
        return;
      }

      // 如果引用计数为0，不需要重连
      if (_connectionRefCount == 0) {
        return;
      }

      // 检查网络连接
      bool isConnected = await _networkUtil.isConnected();
      if (!isConnected) {
        Global.logger.d('🌐 网络连接不可用，静默跳过Socket重连');
        return;
      }

      // 连接中断则重连
      if (!socket.connected) {
        Global.logger.d('尝试重新连接游戏服务器...');
        socket.connect();
      }

      socket.emit("heartBeat", "");
    });
  }
  
  /// 停止心跳定时器
  void _stopHeartbeat() {
    if (heartBeatTimer != null) {
      Global.logger.d('SocketIoClient: 停止心跳定时器');
      heartBeatTimer?.cancel();
      heartBeatTimer = null;
    }
  }

  /// 设置是否在russia游戏页面
  void setInRussiaGame(bool inRussiaGame) {
    _isInRussiaGame = inRussiaGame;
    Global.logger.d('SocketIoClient: 设置russia游戏状态: $_isInRussiaGame');
  }



  void tryReportUserToSocketServer() {
    if (_disposed || !_initialized) return;
    if (Global.getLoggedInUser() != null && socket.connected) {
      socket.emit('reportUser', Global.getLoggedInUser()!.id);
    }
  }

  void registerSocketEventListeners(Function(String event, List args) listener) {
    if (_disposed) return;
    socketEventListeners.add(listener);
  }

  /// 清理所有资源，防止内存泄漏
  void dispose() {
    if (_disposed) return;

    Global.logger.d('SocketIoClient: 开始清理资源');
    _disposed = true;

    // 停止心跳定时器
    _stopHeartbeat();

    // 取消断连提示定时器
    _disconnectToastTimer?.cancel();
    _disconnectToastTimer = null;

    // 断开socket连接
    if (_initialized) {
      socket.disconnect();
      socket.dispose();
    }

    // 清空监听器列表
    socketEventListeners.clear();
    socketStatusListeners.clear();

    // 重置连接状态
    isConnectedToSocketServer = false;
    _isInRussiaGame = false;
    _connectionRefCount = 0;

    Global.logger.d('SocketIoClient: 资源清理完成');
  }

  /// 移除事件监听器
  void removeSocketEventListener(Function(String event, List args) listener) {
    socketEventListeners.remove(listener);
  }

  /// 移除状态监听器
  void removeSocketStatusListener(SocketStatusListener listener) {
    socketStatusListeners.remove(listener);
  }
}
