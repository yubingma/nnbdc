import 'dart:math' as math;

/// 导入行在预览阶段的状态。
enum ExcelRowStatus {
  /// 可导入（词库已收录且词表中不存在）
  ready,

  /// 词表中已存在
  alreadyInDict,

  /// 词库未收录
  notInLibrary,

  /// 文件内重复（释义已合并到首次出现的行）
  duplicate,

  /// 格式非法（空单词、含非英文字符等）
  invalid,
}

/// 从 Excel 解析出的一个待导入词条。
class ExcelImportRow {
  final int lineNumber;
  final String spell;
  final String partOfSpeech;
  final int unit;

  /// 释义（多个义项以 `;` 分隔），可能是合并后的结果。
  String meaning;

  ExcelRowStatus status;

  /// 词库命中的词条 ID（仅在词库已收录时有值）。
  String? wordId;

  ExcelImportRow({
    required this.lineNumber,
    required this.spell,
    required this.meaning,
    required this.partOfSpeech,
    required this.unit,
    required this.status,
    this.wordId,
  });

  /// 合并同一拼写的释义项，保持首次出现的顺序。
  void mergeMeaning(String extra) {
    if (extra.isEmpty) return;
    final merged = <String>[];
    for (final part in '${meaning.isEmpty ? '' : '$meaning;'}$extra'.split(';')) {
      final trimmed = part.trim();
      if (trimmed.isNotEmpty && !merged.contains(trimmed)) merged.add(trimmed);
    }
    meaning = merged.join(';');
  }
}

/// 工作表各语义列的位置；列索引为 0 基，null 表示未识别到。
class ExcelColumnMapping {
  final int? spellColumn;
  final int? meaningColumn;
  final int? partOfSpeechColumn;
  final int? unitColumn;

  /// 表头所在行索引；null 表示未识别到表头。
  final int? headerRowIndex;

  const ExcelColumnMapping({
    this.spellColumn,
    this.meaningColumn,
    this.partOfSpeechColumn,
    this.unitColumn,
    this.headerRowIndex,
  });

  bool get hasSpellColumn => spellColumn != null;

  /// 数据起始行：有表头则跳过表头行。
  int get firstDataRowIndex => headerRowIndex == null ? 0 : headerRowIndex! + 1;

  ExcelColumnMapping copyWith({
    int? spellColumn,
    int? meaningColumn,
    int? partOfSpeechColumn,
    int? unitColumn,
    int? headerRowIndex,
    bool clearHeaderRow = false,
  }) {
    return ExcelColumnMapping(
      spellColumn: spellColumn ?? this.spellColumn,
      meaningColumn: meaningColumn ?? this.meaningColumn,
      partOfSpeechColumn: partOfSpeechColumn ?? this.partOfSpeechColumn,
      unitColumn: unitColumn ?? this.unitColumn,
      headerRowIndex: clearHeaderRow ? null : (headerRowIndex ?? this.headerRowIndex),
    );
  }
}

/// 表头别名 → 语义列。
const Map<String, List<String>> _headerAliases = {
  'spell': [
    '单词', '英文', '拼写', '词条', '词汇', '英文单词', '单词拼写',
    'word', 'words', 'spell', 'spelling', 'english', 'term', 'vocabulary', 'entry',
  ],
  'meaning': [
    '释义', '中文', '意思', '含义', '解释', '翻译', '词义', '中文释义', '注释',
    'meaning', 'definition', 'chinese', 'translation', 'def', 'explanation',
  ],
  'pos': [
    '词性', '词类', '词性标注', '属性',
    'pos', 'partofspeech', 'part of speech', 'type',
  ],
  'unit': [
    '单元', '章节', '课', '课时', '模块',
    'unit', 'chapter', 'lesson', 'section', 'module',
  ],
};

final RegExp _englishPattern = RegExp(r"^[A-Za-z][A-Za-z' \-.]*$");
final RegExp _cjkPattern = RegExp(r'[\u4e00-\u9fff]');
final RegExp _spellNoisePattern = RegExp(r'\[[^\]]*\]');

/// 识别工作表的列含义：优先匹配表头别名，其次按列内容特征推断。
class ExcelColumnDetector {
  const ExcelColumnDetector._();

  /// 表头最多向前探测的行数。
  static const int _headerScanLimit = 3;

  /// 内容推断的采样行数。
  static const int _sampleLimit = 30;

  /// 内容推断时，一列被判为「单词列 / 释义列」所需的最低命中率。
  static const double _minHitRatio = 0.5;

  static ExcelColumnMapping detect(List<List<String>> rows) {
    final header = _detectHeader(rows);
    if (header != null) {
      return ExcelColumnMapping(
        spellColumn: header.columns['spell'],
        meaningColumn: header.columns['meaning'],
        partOfSpeechColumn: header.columns['pos'],
        unitColumn: header.columns['unit'],
        headerRowIndex: header.rowIndex,
      );
    }
    return _detectByContent(rows);
  }

  static _HeaderMatch? _detectHeader(List<List<String>> rows) {
    _HeaderMatch? best;
    final limit = math.min(rows.length, _headerScanLimit);
    for (var i = 0; i < limit; i++) {
      final columns = <String, int>{};
      for (var c = 0; c < rows[i].length; c++) {
        final key = _aliasKeyOf(rows[i][c]);
        if (key != null && !columns.containsKey(key)) columns[key] = c;
      }
      // 没有「单词」列的表头不可信，退回内容推断
      if (!columns.containsKey('spell')) continue;
      if (best == null || columns.length > best.columns.length) {
        best = _HeaderMatch(i, columns);
      }
    }
    return best;
  }

  static String? _aliasKeyOf(String cell) {
    final normalized = cell.trim().toLowerCase().replaceAll(RegExp(r'[\s_\-:：*]'), '');
    if (normalized.isEmpty) return null;
    for (final entry in _headerAliases.entries) {
      for (final alias in entry.value) {
        if (normalized == alias.replaceAll(' ', '')) return entry.key;
      }
    }
    return null;
  }

  static ExcelColumnMapping _detectByContent(List<List<String>> rows) {
    final sample = rows.take(_sampleLimit).toList();
    final columnCount = sample.fold<int>(0, (max, row) => math.max(max, row.length));
    if (columnCount == 0) return const ExcelColumnMapping();

    final englishHits = List<int>.filled(columnCount, 0);
    final chineseHits = List<int>.filled(columnCount, 0);
    final nonEmpty = List<int>.filled(columnCount, 0);

    for (final row in sample) {
      for (var c = 0; c < row.length; c++) {
        final value = row[c].trim();
        if (value.isEmpty) continue;
        nonEmpty[c]++;
        if (_englishPattern.hasMatch(value)) englishHits[c]++;
        if (_cjkPattern.hasMatch(value)) chineseHits[c]++;
      }
    }

    final spellColumn = _bestColumn(englishHits, nonEmpty);
    final meaningColumn = _bestColumn(chineseHits, nonEmpty, exclude: spellColumn);
    return ExcelColumnMapping(spellColumn: spellColumn, meaningColumn: meaningColumn);
  }

  static int? _bestColumn(List<int> hits, List<int> nonEmpty, {int? exclude}) {
    int? best;
    var bestHits = 0;
    for (var c = 0; c < hits.length; c++) {
      if (c == exclude || nonEmpty[c] == 0) continue;
      if (hits[c] / nonEmpty[c] < _minHitRatio) continue;
      if (hits[c] > bestHits) {
        bestHits = hits[c];
        best = c;
      }
    }
    return best;
  }
}

/// 按列映射把工作表行转换成待导入词条。
class ExcelRowParser {
  const ExcelRowParser._();

  static List<ExcelImportRow> parse(List<List<String>> rows, ExcelColumnMapping mapping) {
    final spellColumn = mapping.spellColumn;
    if (spellColumn == null) return const [];

    final result = <ExcelImportRow>[];
    final firstIndexBySpell = <String, int>{};

    for (var i = mapping.firstDataRowIndex; i < rows.length; i++) {
      final row = rows[i];
      final rawSpell = _cellAt(row, spellColumn);
      final partOfSpeech = _cellAt(row, mapping.partOfSpeechColumn).trim();
      final meaning = _stripRedundantPartOfSpeech(
        _normalizeMeaning(_cellAt(row, mapping.meaningColumn)),
        partOfSpeech,
      );
      final unit = _parseUnit(_cellAt(row, mapping.unitColumn));
      final lineNumber = i + 1;

      // 整行空白：直接跳过，不进入预览
      if (rawSpell.trim().isEmpty && meaning.isEmpty) continue;

      final spell = _normalizeSpell(rawSpell);
      if (spell == null) {
        result.add(ExcelImportRow(
          lineNumber: lineNumber,
          spell: rawSpell.trim(),
          meaning: meaning,
          partOfSpeech: partOfSpeech,
          unit: unit,
          status: ExcelRowStatus.invalid,
        ));
        continue;
      }

      final key = spell.toLowerCase();
      final firstIndex = firstIndexBySpell[key];
      if (firstIndex != null) {
        result[firstIndex].mergeMeaning(meaning);
        result.add(ExcelImportRow(
          lineNumber: lineNumber,
          spell: spell,
          meaning: meaning,
          partOfSpeech: partOfSpeech,
          unit: unit,
          status: ExcelRowStatus.duplicate,
        ));
        continue;
      }

      firstIndexBySpell[key] = result.length;
      result.add(ExcelImportRow(
        lineNumber: lineNumber,
        spell: spell,
        meaning: meaning,
        partOfSpeech: partOfSpeech,
        unit: unit,
        status: ExcelRowStatus.ready,
      ));
    }

    return result;
  }

  static String _cellAt(List<String> row, int? column) {
    if (column == null || column < 0 || column >= row.length) return '';
    return row[column];
  }

  /// 清洗单元格得到规范拼写；无法得到合法英文拼写时返回 null。
  static String? _normalizeSpell(String raw) {
    var value = raw.replaceAll(_spellNoisePattern, ' ').trim();
    if (value.isEmpty) return null;
    if (!_englishPattern.hasMatch(value)) return null;
    value = value.replaceAll(RegExp(r'\s+'), ' ');
    return value;
  }

  /// 换行与全角分号统一为 `;`，与释义写入规则保持一致。
  static String _normalizeMeaning(String raw) {
    return raw.replaceAll(RegExp(r'[\r\n；;]+'), ';').replaceAll(RegExp(r'^;+|;+$'), '').trim();
  }

  /// 词性列已单独给出词性时，去掉释义开头重复的词性前缀，避免显示成「n. n. 能力」。
  static String _stripRedundantPartOfSpeech(String meaning, String partOfSpeech) {
    if (meaning.isEmpty || partOfSpeech.isEmpty) return meaning;
    final prefix = RegExp.escape(partOfSpeech.replaceAll('.', '').trim());
    if (prefix.isEmpty) return meaning;
    return meaning.replaceFirst(RegExp('^\\s*$prefix\\.?\\s*'), '').trim();
  }

  static int _parseUnit(String raw) {
    final value = int.tryParse(raw.trim());
    return value == null || value < 0 ? 0 : value;
  }
}

class _HeaderMatch {
  final int rowIndex;
  final Map<String, int> columns;

  _HeaderMatch(this.rowIndex, this.columns);
}
