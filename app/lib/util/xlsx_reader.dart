import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// 一个工作表的只读内容：行 × 列的文本矩阵。
class XlsxSheet {
  final String name;

  /// 单元格原始文本；缺失单元格为空串。
  final List<List<String>> rows;

  const XlsxSheet(this.name, this.rows);
}

/// 面向「导入词表」场景的最小 .xlsx 读取器。
///
/// 只覆盖词表所需：共享字符串、内联字符串、数字与布尔单元格。
/// 不计算公式、不解析日期序列号、不处理样式与合并单元格——
/// 这些超出词表导入的语义范围，需要时应显式扩展而非默默兜底。
class XlsxReader {
  const XlsxReader._();

  /// 是否为旧版 .xls（OLE2 复合文档：D0 CF 11 E0）。
  ///
  /// .xls 与 .xlsx 是完全不同的格式，无法互相解析；
  /// 调用方可据此给出「请另存为 .xlsx」的明确引导。
  static bool isLegacyXls(Uint8List bytes) {
    return bytes.length >= 4 && bytes[0] == 0xD0 && bytes[1] == 0xCF && bytes[2] == 0x11 && bytes[3] == 0xE0;
  }

  /// 解析 .xlsx 字节并返回**第一个**工作表。
  ///
  /// 结构异常时抛出 [FormatException]，让问题暴露而不是返回空表。
  static XlsxSheet read(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const FormatException('文件不是有效的 .xlsx（无法解压）');
    }

    final workbook = _parseXml(archive, 'xl/workbook.xml');
    final rels = _parseXml(archive, 'xl/_rels/workbook.xml.rels');
    if (workbook == null || rels == null) {
      throw const FormatException('文件缺少 workbook 结构，可能不是标准 .xlsx');
    }

    final sheetElement = _firstElement(workbook.descendants.whereType<XmlElement>(), 'sheet');
    if (sheetElement == null) {
      throw const FormatException('文件中没有任何工作表');
    }

    final sheetName = sheetElement.getAttribute('name') ?? 'Sheet1';
    final relId = _attributeByLocalName(sheetElement, 'id');
    final sheetPath = _sheetPathFromRels(rels, relId);
    if (sheetPath == null) {
      throw FormatException('无法定位工作表「$sheetName」的内容');
    }

    final sheetDoc = _parseXml(archive, sheetPath);
    if (sheetDoc == null) {
      throw FormatException('工作表「$sheetName」内容缺失');
    }

    final sharedStrings = _readSharedStrings(archive);
    return XlsxSheet(sheetName, _readRows(sheetDoc, sharedStrings));
  }

  static XmlDocument? _parseXml(Archive archive, String path) {
    final file = archive.findFile(path);
    if (file == null) return null;
    return XmlDocument.parse(utf8.decode(file.content, allowMalformed: true));
  }

  static String? _sheetPathFromRels(XmlDocument rels, String? relId) {
    if (relId == null) return null;
    for (final rel in rels.descendants.whereType<XmlElement>()) {
      if (rel.name.local != 'Relationship') continue;
      if (_attributeByLocalName(rel, 'Id') != relId) continue;
      final target = rel.getAttribute('Target');
      if (target == null) return null;
      return _normalizeRelationshipTarget(target);
    }
    return null;
  }

  /// 把 [Relationship.Target] 规范化为包内路径。
  static String _normalizeRelationshipTarget(String target) {
    if (target.startsWith('/')) return target.substring(1);
    return 'xl/$target';
  }

  static List<String> _readSharedStrings(Archive archive) {
    final doc = _parseXml(archive, 'xl/sharedStrings.xml');
    if (doc == null) return const [];
    final result = <String>[];
    for (final si in doc.descendants.whereType<XmlElement>()) {
      if (si.name.local == 'si') result.add(_concatenatedText(si));
    }
    return result;
  }

  static List<List<String>> _readRows(XmlDocument sheetDoc, List<String> sharedStrings) {
    final rows = <List<String>>[];
    for (final rowElement in sheetDoc.descendants.whereType<XmlElement>()) {
      if (rowElement.name.local != 'row') continue;

      final cells = <int, String>{};
      var maxColumn = -1;
      var nextColumn = 0;
      for (final cell in rowElement.childElements) {
        if (cell.name.local != 'c') continue;

        final reference = cell.getAttribute('r');
        final column = reference != null && reference.isNotEmpty ? _columnIndexOf(reference) : nextColumn;
        if (column < 0) continue;

        cells[column] = _cellText(cell, sharedStrings);
        nextColumn = column + 1;
        if (column > maxColumn) maxColumn = column;
      }

      final row = List<String>.filled(maxColumn + 1, '');
      cells.forEach((column, text) => row[column] = text);
      rows.add(row);
    }
    return rows;
  }

  static String _cellText(XmlElement cell, List<String> sharedStrings) {
    final type = cell.getAttribute('t');

    if (type == 'inlineStr') {
      final inline = _firstElement(cell.childElements, 'is');
      return inline == null ? '' : _concatenatedText(inline);
    }

    final value = _firstElement(cell.childElements, 'v')?.innerText ?? '';
    if (type == 's') {
      final index = int.tryParse(value);
      if (index == null || index < 0 || index >= sharedStrings.length) return '';
      return sharedStrings[index];
    }
    return value;
  }

  /// 拼接 `<si>` / `<is>` 下所有 `<t>` 的文本，兼容富文本分片。
  static String _concatenatedText(XmlElement element) {
    final buffer = StringBuffer();
    for (final text in element.descendants.whereType<XmlElement>()) {
      if (text.name.local == 't') buffer.write(text.innerText);
    }
    return buffer.toString();
  }

  /// "BC12" → 1（0 基列索引）。
  static int _columnIndexOf(String reference) {
    var index = 0;
    for (final code in reference.codeUnits) {
      if (code >= 0x41 && code <= 0x5A) {
        index = index * 26 + (code - 0x40);
      } else if (code >= 0x61 && code <= 0x7A) {
        index = index * 26 + (code - 0x60);
      } else {
        break;
      }
    }
    return index - 1;
  }

  static XmlElement? _firstElement(Iterable<XmlElement> elements, String localName) {
    for (final element in elements) {
      if (element.name.local == localName) return element;
    }
    return null;
  }

  /// 按 local name 取属性，兼容带命名空间前缀的属性（如 `r:id`）。
  static String? _attributeByLocalName(XmlElement element, String localName) {
    for (final attribute in element.attributes) {
      if (attribute.name.local == localName) return attribute.value;
    }
    return null;
  }
}
