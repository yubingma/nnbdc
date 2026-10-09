import 'dart:convert';
import 'dart:typed_data';

/// 音素词典的紧凑随包资源（预编译，运行时零解析、按需查表）。
///
/// 背景：原来把 3.6MB 的 cmudict 文本在运行时解析成 13 万条嵌套 Map —— 真机实测要
/// 4~5 秒、会起两个 isolate（>50KB 资源先由 isolate 做 UTF-8 解码，解析再起一个）、
/// 峰值内存上百 MB，一旦那次加载停摆，整条发音判定链路就会静默卡死。
///
/// 现在把解析挪到构建期（`tool/phoneme/compile_cmudict.dart`），运行时只读一个紧凑
/// 二进制资源：内存占用就是资源本身的大小，查词走二分查找，毫秒级完成、不碰 isolate。
///
/// 文件布局（全部小端）：
/// ```
/// [0..4)    magic 'PHO1'
/// [4..8)    uint32 wordCount
/// [8..12)   uint32 tableOffset
/// [12..16)  uint32 wordsOffset
/// [16..20)  uint32 variantsOffset
/// [20..24)  uint32 fileSize
/// table    (wordCount + 1) 条 (uint32 wordStart, uint32 variantStart)
///          —— start 分别相对 wordsOffset / variantsOffset；末条是哨兵，用来取长度
/// words    全部词条（小写 ASCII）按字节序升序拼接，无分隔符
/// variants 每条词的读音：多个读音用 '\n' 分隔，读音内部的音素用 ' ' 分隔
/// ```
class PhonemeAsset {
  static const int _headerSize = 24;
  static const List<int> _magic = [0x50, 0x48, 0x4F, 0x31]; // 'PHO1'

  final ByteData _bytes;
  final int _tableOffset;
  final int _wordsOffset;
  final int _variantsOffset;

  PhonemeAsset._(
    this._bytes,
    this._tableOffset,
    this._wordsOffset,
    this._variantsOffset,
  );

  factory PhonemeAsset.fromBytes(ByteData bytes) {
    if (bytes.lengthInBytes < _headerSize) {
      throw const FormatException('音素词典资源被截断：连文件头都不完整');
    }
    for (var i = 0; i < _magic.length; i++) {
      if (bytes.getUint8(i) != _magic[i]) {
        throw const FormatException("音素词典资源格式不对：magic 不是 'PHO1'");
      }
    }
    final fileSize = bytes.getUint32(20, Endian.little);
    if (fileSize > bytes.lengthInBytes) {
      throw FormatException(
          '音素词典资源被截断：声明 $fileSize 字节，实际只有 ${bytes.lengthInBytes} 字节');
    }
    return PhonemeAsset._(
      bytes,
      bytes.getUint32(8, Endian.little),
      bytes.getUint32(12, Endian.little),
      bytes.getUint32(16, Endian.little),
    );
  }

  /// 词条总数。
  int get wordCount => _bytes.getUint32(4, Endian.little);

  /// 查一个词条的全部读音；查不到返回 null。[key] 必须已是小写、去掉 `(n)` 的形态。
  List<List<String>>? variantsOf(String key) {
    final target = utf8.encode(key);
    var low = 0;
    var high = wordCount - 1;
    while (low <= high) {
      final mid = (low + high) >> 1;
      final order = _compareWord(mid, target);
      if (order == 0) return _decodeVariants(mid);
      if (order < 0) {
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return null;
  }

  /// 把第 [index] 条词与 [target] 按字节序比较。
  int _compareWord(int index, List<int> target) {
    final start = _wordsOffset + _bytes.getUint32(_tableOffset + index * 8, Endian.little);
    final end = _wordsOffset + _bytes.getUint32(_tableOffset + (index + 1) * 8, Endian.little);
    final length = end - start;
    final common = length < target.length ? length : target.length;
    for (var i = 0; i < common; i++) {
      final byte = _bytes.getUint8(start + i);
      if (byte != target[i]) return byte < target[i] ? -1 : 1;
    }
    return length.compareTo(target.length);
  }

  List<List<String>> _decodeVariants(int index) {
    final start = _variantsOffset + _bytes.getUint32(_tableOffset + index * 8 + 4, Endian.little);
    final end = _variantsOffset + _bytes.getUint32(_tableOffset + (index + 1) * 8 + 4, Endian.little);
    final text = utf8.decode(Uint8List.sublistView(_bytes, start, end));
    return text.split('\n').map((variant) => variant.split(' ')).toList();
  }
}

/// 解析 cmudict 文本。只在构建期脚本与单元测试里用，运行时不再走这条路。
Map<String, List<List<String>>> parseCmudictText(String content) {
  final Map<String, List<List<String>>> data = {};
  for (var line in content.split('\n')) {
    line = line.trim();
    if (line.isEmpty || line.startsWith(';') || line.startsWith('#')) continue;
    final parts = line.split(RegExp(r'\s+'));
    if (parts.length < 2) continue;
    var head = parts.first;
    final paren = head.indexOf('(');
    if (paren > 0 && head.endsWith(')')) head = head.substring(0, paren);
    data.putIfAbsent(head.toLowerCase(), () => []).add(
        parts.sublist(1).map((phoneme) => phoneme.replaceAll(RegExp(r'\d+'), '')).toList());
  }
  return data;
}

/// 把「词 → 读音列表」编码成紧凑资源。构建期脚本与单元测试共用，保证两边格式一致。
Uint8List encodePhonemeAsset(Map<String, List<List<String>>> dict) {
  final entries = dict.entries
      .map((entry) => (key: utf8.encode(entry.key), variants: entry.value))
      .toList()
    ..sort((a, b) => _compareBytes(a.key, b.key));

  final table = ByteData((entries.length + 1) * 8);
  final words = BytesBuilder();
  final variants = BytesBuilder();
  for (var i = 0; i < entries.length; i++) {
    table.setUint32(i * 8, words.length, Endian.little);
    table.setUint32(i * 8 + 4, variants.length, Endian.little);
    words.add(entries[i].key);
    variants.add(utf8.encode(
        entries[i].variants.map((variant) => variant.join(' ')).join('\n')));
  }
  table.setUint32(entries.length * 8, words.length, Endian.little);
  table.setUint32(entries.length * 8 + 4, variants.length, Endian.little);

  final wordBytes = words.takeBytes();
  final variantBytes = variants.takeBytes();
  final wordsOffset = PhonemeAsset._headerSize + table.lengthInBytes;
  final variantsOffset = wordsOffset + wordBytes.length;

  final header = ByteData(PhonemeAsset._headerSize);
  for (var i = 0; i < PhonemeAsset._magic.length; i++) {
    header.setUint8(i, PhonemeAsset._magic[i]);
  }
  header.setUint32(4, entries.length, Endian.little);
  header.setUint32(8, PhonemeAsset._headerSize, Endian.little);
  header.setUint32(12, wordsOffset, Endian.little);
  header.setUint32(16, variantsOffset, Endian.little);
  header.setUint32(20, variantsOffset + variantBytes.length, Endian.little);

  final out = BytesBuilder();
  out.add(header.buffer.asUint8List());
  out.add(table.buffer.asUint8List());
  out.add(wordBytes);
  out.add(variantBytes);
  return out.takeBytes();
}

int _compareBytes(List<int> a, List<int> b) {
  final common = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < common; i++) {
    if (a[i] != b[i]) return a[i] < b[i] ? -1 : 1;
  }
  return a.length.compareTo(b.length);
}
