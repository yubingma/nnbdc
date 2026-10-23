import '../api/api.dart';
import 'platform_util.dart';
import 'prefs.dart';

/// 服务端内容开关的拉取与本地缓存。
///
/// 目前有两个开关：
/// - `hideK12Content`：是否隐藏中小学教育类内容（K12 词书分组与游戏大厅）；
/// - `hideAiContent`：是否隐藏 AI 能力（AI 助教对话、AI 短文、单词解释）。
/// 系统管理员在服务端改完配置后，客户端在【启动】时拉取一次并缓存，
/// 改完配置需重开 App 生效。
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
    try {
      final result = await Api.client.getHideAiContent();
      if (result.success && result.data != null) {
        await Prefs.setHideAiContent(result.data!);
      }
    } catch (e) {
      // 网络异常时沿用上次配置
    }
  }

  /// 当前设备是否显示 AI 能力。
  ///
  /// 与 K12 内容开关共用同一套厂商白名单：白名单品牌（华为/荣耀/OPPO/vivo/三星/魅族）
  /// 与非 Android 平台永远显示，小米系、云真机、厂商读不到的设备由服务端开关决定。
  static bool get isAiFeatureVisible =>
      !(Prefs.hideAiContent && !PlatformUtils.isContentSwitchExempt);
}
