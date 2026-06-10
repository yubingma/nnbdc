import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';

class PcaProjectionService {
  static final PcaProjectionService _instance = PcaProjectionService._internal();
  factory PcaProjectionService() => _instance;
  PcaProjectionService._internal();

  List<double>? _mean;
  List<List<double>>? _components;
  bool _initialized = false;

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    await loadConfig();
  }

  Future<void> loadConfig() async {
    try {
      // 1. 尝试从数据库加载最新配置
      final db = MyDatabase.instance;
      final rows = await db.customSelect(
        "SELECT config_json FROM pca_projection_configs WHERE id = 'latest'",
        readsFrom: {},
      ).get();

      String? jsonStr;
      if (rows.isNotEmpty) {
        jsonStr = rows.first.data['config_json'] as String?;
        Global.logger.i('从本地数据库加载最新的 PCA 配置完成。');
      }

      // 2. 降级从 assets 加载
      if (jsonStr == null) {
        try {
          jsonStr = await rootBundle.loadString('assets/pca_config.json');
          Global.logger.i('从 assets 加载默认 of PCA 配置完成。');
        } catch (e) {
          Global.logger.w('未在 assets 找到默认的 PCA 配置，将使用零矩阵初始化: $e');
        }
      }

      if (jsonStr != null) {
        final Map<String, dynamic> config = jsonDecode(jsonStr);
        final List<dynamic> meanList = config['mean'] as List<dynamic>;
        _mean = meanList.map((e) => (e as num).toDouble()).toList();

        final List<dynamic> compList = config['components'] as List<dynamic>;
        _components = compList.map((row) => (row as List<dynamic>).map((e) => (e as num).toDouble()).toList()).toList();
        
        _initialized = true;
        Global.logger.i('PCA 投影矩阵加载成功。维度: mean=${_mean!.length}, components=${_components!.length}x${_components![0].length}');
        return;
      }
    } catch (e) {
      Global.logger.e('加载 PCA 配置失败: $e');
    }

    // 初始化一个全零的 fallback 矩阵
    _mean = List.filled(2048, 0.0);
    _components = List.generate(2048, (_) => List.filled(3, 0.0));
    _initialized = true;
  }

  /// 进行投影
  List<double> projectTo3D(Uint8List embedding1bit) {
    if (!_initialized || _mean == null || _components == null) {
      return [0.0, 0.0, 0.0];
    }
    
    if (embedding1bit.length < 256) {
      return [0.0, 0.0, 0.0];
    }

    double sum0 = 0.0;
    double sum1 = 0.0;
    double sum2 = 0.0;

    for (int i = 0; i < 2048; i++) {
      int byteIdx = i ~/ 8;
      int bitIdx = i % 8;
      bool isOne = (embedding1bit[byteIdx] & (1 << (7 - bitIdx))) != 0;
      double val = isOne ? 1.0 : 0.0;
      double centeredVal = val - _mean![i];

      sum0 += centeredVal * _components![i][0];
      sum1 += centeredVal * _components![i][1];
      sum2 += centeredVal * _components![i][2];
    }

    return [sum0, sum1, sum2];
  }
}
