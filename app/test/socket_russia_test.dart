import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/socket_io.dart';

void main() {
  group('SocketIoClient Russia Game Tests', () {
    test('should handle russia game state correctly', () {
      final client = SocketIoClient.instance;
      
      // 初始状态应该是false
      expect(client.isConnectedToSocketServer, false);
      
      // 设置russia游戏状态
      client.setInRussiaGame(true);
      
      // 模拟连接状态变化
      client.isConnectedToSocketServer = true;
      expect(client.isConnectedToSocketServer, true);
      
      client.isConnectedToSocketServer = false;
      expect(client.isConnectedToSocketServer, false);
      
      // 离开russia游戏
      client.setInRussiaGame(false);
    });

    test('should handle listeners correctly', () {
      final client = SocketIoClient.instance;
      
      bool connectedCalled = false;
      bool disconnectedCalled = false;
      
      final listener = _TestSocketStatusListener(
        onConnectedCallback: () => connectedCalled = true,
        onDisconnectedCallback: () => disconnectedCalled = true,
      );
      
      // 添加监听器
      client.socketStatusListeners.add(listener);
      expect(client.socketStatusListeners.length, 1);
      
      // 测试监听器回调
      listener.onConnected();
      expect(connectedCalled, true);
      
      listener.onDisconnected();
      expect(disconnectedCalled, true);
      
      // 移除监听器
      client.removeSocketStatusListener(listener);
      expect(client.socketStatusListeners, isEmpty);
    });
  });
}

class _TestSocketStatusListener implements SocketStatusListener {
  final void Function() onConnectedCallback;
  final void Function() onDisconnectedCallback;
  
  _TestSocketStatusListener({
    required this.onConnectedCallback,
    required this.onDisconnectedCallback,
  });
  
  @override
  void onConnected() => onConnectedCallback();
  
  @override
  void onDisconnected() => onDisconnectedCallback();
}
