import 'dart:async';

import 'package:nnbdc/util/platform_util.dart';
import 'package:nnbdc/util/subscription_util.dart';
import 'package:nnbdc/services/ai_runtime_remote.dart';

/// AI 能力等级，用于根据设备和模型情况决定功能开关
enum AiCapabilityLevel {
  none,
  light,
  full,
}

/// AI 任务类型，业务层通过类型和 payload 来描述需求
enum AiTaskType {
  explainWord,
  generateQuiz,
  summarizeMistakes,
  chat,
}

class AiRequest {
  final AiTaskType type;
  final Map<String, dynamic> payload;

  const AiRequest({
    required this.type,
    required this.payload,
  });
}

class AiResponse {
  final bool success;
  final String? text;
  final String? errorMessage;

  const AiResponse({
    required this.success,
    this.text,
    this.errorMessage,
  });

  factory AiResponse.ok(String text) {
    return AiResponse(success: true, text: text);
  }

  factory AiResponse.error(String message) {
    return AiResponse(success: false, errorMessage: message);
  }
}

/// 具体平台上的 AI 运行时实现接口
abstract class AiRuntime {
  AiCapabilityLevel get capabilityLevel;

  Future<AiResponse> runTask(AiRequest request);

  Stream<String> get partialStream;
}

/// 默认的占位实现，在未配置本地模型时使用
class NoopAiRuntime implements AiRuntime {
  @override
  AiCapabilityLevel get capabilityLevel => AiCapabilityLevel.none;

  @override
  Stream<String> get partialStream => const Stream.empty();

  @override
  Future<AiResponse> runTask(AiRequest request) async {
    String platformLabel;
    if (PlatformUtils.isAndroid) {
      platformLabel = 'Android';
    } else if (PlatformUtils.isIOS) {
      platformLabel = 'iOS';
    } else if (PlatformUtils.isWindows) {
      platformLabel = 'Windows';
    } else if (PlatformUtils.isMacOS) {
      platformLabel = 'macOS';
    } else if (PlatformUtils.isWeb) {
      platformLabel = 'Web';
    } else {
      platformLabel = '当前平台';
    }

    final fallbackText = '当前设备上的本地 AI 模型尚未启用或尚未下载，本功能暂时以普通模式运行（$platformLabel）。';

    return AiResponse.ok(fallbackText);
  }
}

/// 提供统一入口的 AI 服务，业务层只依赖这一层
class AiService {
  static final AiService _instance = AiService._internal();

  factory AiService() => _instance;

  AiService._internal();

  AiRuntime _runtime = NoopAiRuntime();
  
  final AiRuntime _remoteRuntime = RemoteAiRuntime();

  // 根据会员状态动态选择运行时
  AiRuntime get runtime {
    if (SubscriptionUtil.isPremium()) {
      return _remoteRuntime;
    }
    return _runtime;
  }

  AiCapabilityLevel get capabilityLevel => runtime.capabilityLevel;

  /// 由平台启动代码或模型管理器在合适的时机注入具体运行时
  void setRuntime(AiRuntime runtime) {
    _runtime = runtime;
  }

  Future<AiResponse> runTask(AiRequest request) {
    return runtime.runTask(request);
  }
}
