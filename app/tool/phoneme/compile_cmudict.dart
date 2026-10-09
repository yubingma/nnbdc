// 把 cmudict 文本编译成随包资源 `assets/cmudict.pho`（预编译紧凑查表格式）。
//
// 为什么要有这一步：运行时把 3.6MB 文本解析成 13 万条嵌套 Map，真机要 4~5 秒、会起两个
// isolate、峰值内存上百 MB，一次加载停摆就会把发音判定链路拖死。改成预编译后，运行时只读
// 一个紧凑二进制资源、查词走二分，毫秒级完成且不碰 isolate（见 lib/util/phoneme_asset.dart）。
//
// 用法（在 app/ 目录下执行）：
//   dart run tool/phoneme/compile_cmudict.dart
//
// 源数据：tool/phoneme/cmudict.dict（Carnegie Mellon Pronouncing Dictionary，0.7b）
import 'dart:io';

import 'package:nnbdc/util/phoneme_asset.dart';

void main() {
  final source = File('tool/phoneme/cmudict.dict');
  if (!source.existsSync()) {
    stderr.writeln('找不到源数据：${source.path}（请在 app/ 目录下运行本脚本）');
    exit(1);
  }
  final dict = parseCmudictText(source.readAsStringSync());
  final bytes = encodePhonemeAsset(dict);
  final target = File('assets/cmudict.pho')..writeAsBytesSync(bytes);
  stdout.writeln('已生成 ${target.path}：${dict.length} 词条，'
      '${(bytes.length / 1024).toStringAsFixed(0)} KB');
}
