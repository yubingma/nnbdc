import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart' as ja;
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:nnbdc/util/platform_util.dart';

enum AudioMode { playback, record, idle }

class SoundUtil {
  /// 安全创建 AudioPlayer 实例，通过子 Zone 守卫优雅拦截并消化底层可能因 uuid 冲突抛出的 PlatformException
  static ja.AudioPlayer createAudioPlayer() {
    late final ja.AudioPlayer player;
    runZonedGuarded(() {
      player = ja.AudioPlayer();
    }, (error, stack) {
      final errStr = error.toString();
      if (errStr.contains('already exists') || errStr.contains('Platform player')) {
        debugPrint('🔊 [SoundUtil] Zone 拦截到 ja.AudioPlayer() 底层重复 ID 注册异常 (安全忽略): $error');
      } else {
        throw error;
      }
    });
    return player;
  }

  static void prefetchSounds(List<String> urls) {
    if (PlatformUtils.isWeb || PlatformUtils.isTesting) return;
    for (var url in urls) {
      unawaited(() async {
        try {
          await DefaultCacheManager().downloadFile(url);
        } catch (_) {}
      }());
    }
  }
}
