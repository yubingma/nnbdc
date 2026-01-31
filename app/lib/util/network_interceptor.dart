import 'package:dio/dio.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/network_util.dart';

/// 网络访问拦截器
/// 在API请求前检查网络连接，如果网络不可用则阻止请求
class NetworkInterceptor extends Interceptor {
  final NetworkUtil _networkUtil = NetworkUtil();

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    // 检查网络连接
    bool isConnected = await _networkUtil.isConnected();
    if (!isConnected) {
      Global.logger.d('🌐 网络连接不可用，静默阻止API请求: ${options.path}');

      // 返回网络错误，但不显示给用户
      final error = DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
        message: '网络连接不可用',
      );

      handler.reject(error);
      return;
    }

    // 网络可用，继续请求
    handler.next(options);
  }
}
