import '../api/api.dart';
import 'prefs.dart';

/// 服务端内容开关的拉取与本地缓存。
///
/// 目前只有一个开关：是否隐藏中小学教育类内容（K12 词书分组与游戏大厅）。
/// 系统管理员在服务端改完配置后，客户端在【启动】以及每次进入【选书页 / 游戏大厅】
/// 时刷新一次，无需重启 App。
class ContentConfig {
  /// 拉取最新开关并写入本地缓存。
  ///
  /// 网络异常时保留上次配置，不抛异常、不阻断页面加载。
  static Future<void> refresh() async {
    try {
      final result = await Api.client.getHideK12Content();
      if (result.success && result.data != null) {
        await Prefs.setHideK12Content(result.data!);
      }
    } catch (e) {
      // 网络异常时沿用上次配置
    }
  }
}
