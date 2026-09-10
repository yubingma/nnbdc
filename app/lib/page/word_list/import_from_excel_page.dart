import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/theme/app_theme.dart';
import 'package:nnbdc/util/excel_import_parser.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:nnbdc/util/xlsx_reader.dart';
import 'package:provider/provider.dart';

import '../../state.dart';
import 'word_list.dart';

/// 从 .xlsx 批量导入单词到可编辑词表（自定义词书 / 生词本 / 已掌握）。
class ImportFromExcelPage extends StatefulWidget {
  final WordModifier wordModifier;

  const ImportFromExcelPage({super.key, required this.wordModifier});

  @override
  State<ImportFromExcelPage> createState() => _ImportFromExcelPageState();
}

class _ImportFromExcelPageState extends State<ImportFromExcelPage> {
  static const int _maxRows = 5000;

  /// 预览列表最多渲染的行数（导入不受此限制）。
  static const int _maxPreviewRows = 300;

  /// 未收录清单在结果页最多列出的单词数。
  static const int _maxMissingPreview = 60;

  String? _fileName;
  String? _sheetName;
  List<List<String>> _worksheetRows = const [];
  ExcelColumnMapping? _mapping;
  List<ExcelImportRow> _rows = const [];
  Set<int> _selectedLines = <int>{};
  bool _isParsing = false;
  bool _isImporting = false;
  bool _updateMeanings = false;
  _ImportOutcome? _outcome;

  bool get _hasFile => _worksheetRows.isNotEmpty;

  bool _isSelectable(ExcelImportRow row) {
    if (row.status == ExcelRowStatus.ready) return true;
    return row.status == ExcelRowStatus.alreadyInDict && _updateMeanings;
  }

  Future<void> _pickFile() async {
    FilePickerResult? picked;
    try {
      picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );
    } catch (e) {
      ToastUtil.error('选择文件失败：$e');
      return;
    }
    if (picked == null || picked.files.isEmpty) return;

    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      ToastUtil.error('无法读取所选文件');
      return;
    }

    // 旧版 .xls 是 OLE2 二进制格式，与 .xlsx 毫无关系。
    // 这里给出明确出路，而不是丢给解析层报一句「无法解压」。
    if (XlsxReader.isLegacyXls(bytes)) {
      ToastUtil.error('这是旧版 .xls 格式，请在 Excel / WPS 中「另存为 .xlsx」后重试');
      return;
    }

    setState(() {
      _isParsing = true;
      _fileName = file.name;
      _outcome = null;
    });

    try {
      final parsed = await compute(_parseXlsxBytes, bytes);
      final rows = parsed['rows'] as List<List<String>>;
      if (rows.length > _maxRows) {
        ToastUtil.info('表格超过 $_maxRows 行，仅解析前 $_maxRows 行');
      }
      _sheetName = parsed['sheet'] as String;
      _worksheetRows = rows.length > _maxRows ? rows.sublist(0, _maxRows) : rows;
      _mapping = null;
      await _rebuildRows();
    } on FormatException catch (e) {
      ToastUtil.error(e.message);
      _resetFile();
    } catch (e) {
      ToastUtil.error('解析失败：$e');
      _resetFile();
    } finally {
      if (mounted) setState(() => _isParsing = false);
    }
  }

  void _resetFile() {
    _worksheetRows = const [];
    _mapping = null;
    _rows = const [];
    _selectedLines = <int>{};
  }

  /// 重新识别列、解析行，并补齐词库匹配与词表去重状态。
  Future<void> _rebuildRows() async {
    final mapping = _mapping ?? ExcelColumnDetector.detect(_worksheetRows);
    final rows = ExcelRowParser.parse(_worksheetRows, mapping);

    final spells = rows
        .where((row) => row.status == ExcelRowStatus.ready)
        .map((row) => row.spell)
        .toList();
    final wordIdsBySpell = await WordBo().matchWordIdsBySpells(spells);
    final existingWordIds = await _loadExistingWordIds();

    for (final row in rows) {
      if (row.status != ExcelRowStatus.ready) continue;
      final wordId = wordIdsBySpell[row.spell.toLowerCase()];
      if (wordId == null) {
        row.status = ExcelRowStatus.notInLibrary;
      } else {
        row.wordId = wordId;
        row.status = existingWordIds.contains(wordId) ? ExcelRowStatus.alreadyInDict : ExcelRowStatus.ready;
      }
    }

    if (!mounted) return;
    setState(() {
      _mapping = mapping;
      _rows = rows;
      _selectedLines = rows
          .where((row) => row.status == ExcelRowStatus.ready)
          .map((row) => row.lineNumber)
          .toSet();
    });
  }

  /// 目标词表中已有的词条 ID；无法确定目标词表时返回空集合，
  /// 与「从词书导入」的处理保持一致（不预判，由写入时的去重兜住）。
  Future<Set<String>> _loadExistingWordIds() async {
    final dictId = await widget.wordModifier.resolveTargetDictId();
    if (dictId == null) return <String>{};
    final db = MyDatabase.instance;
    final entries = await (db.select(db.dictWords)..where((dw) => dw.dictId.equals(dictId))).get();
    return entries.map((entry) => entry.wordId).toSet();
  }

  Future<void> _applyMapping(ExcelColumnMapping mapping) async {
    _mapping = mapping;
    await _rebuildRows();
  }

  Future<void> _import() async {
    final items = <DictWordImportItem>[];
    for (final row in _rows) {
      if (!_selectedLines.contains(row.lineNumber)) continue;
      final wordId = row.wordId;
      if (wordId == null) continue;
      items.add(DictWordImportItem(
        wordId: wordId,
        unit: row.unit,
        meaning: row.meaning,
        partOfSpeech: row.partOfSpeech,
      ));
    }

    if (items.isEmpty) {
      ToastUtil.info('请先选择要导入的单词');
      return;
    }

    setState(() => _isImporting = true);
    try {
      final inserted = await widget.wordModifier.addWords(items, updateMeanings: _updateMeanings);
      if (!mounted) return;
      setState(() {
        _outcome = _ImportOutcome(
          inserted: inserted,
          alreadyInDict: _rows.where((row) => row.status == ExcelRowStatus.alreadyInDict).length,
          notInLibrary: _rows.where((row) => row.status == ExcelRowStatus.notInLibrary).length,
          invalid: _rows.where((row) => row.status == ExcelRowStatus.invalid).length,
          duplicate: _rows.where((row) => row.status == ExcelRowStatus.duplicate).length,
          missingSpells: _rows
              .where((row) => row.status == ExcelRowStatus.notInLibrary)
              .map((row) => row.spell)
              .toList(),
        );
      });
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  void _showMappingSheet() {
    final themeConfig = AppThemeConfig.of(context.read<DarkMode>().themeStyle);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _ColumnMappingSheet(
        options: _columnOptions(),
        mapping: _mapping ?? const ExcelColumnMapping(),
        themeConfig: themeConfig,
        onApply: (mapping) {
          Navigator.of(sheetContext).pop();
          _applyMapping(mapping);
        },
      ),
    );
  }

  List<_ColumnOption> _columnOptions() {
    final columnCount = _worksheetRows.fold<int>(0, (max, row) => math.max(max, row.length));
    final headerIndex = _mapping?.headerRowIndex;
    final firstDataIndex = _mapping?.firstDataRowIndex ?? 0;
    final options = <_ColumnOption>[];

    for (var column = 0; column < columnCount; column++) {
      var header = '';
      if (headerIndex != null && headerIndex < _worksheetRows.length && column < _worksheetRows[headerIndex].length) {
        header = _worksheetRows[headerIndex][column].trim();
      }
      var sample = '';
      for (var i = firstDataIndex; i < _worksheetRows.length; i++) {
        final row = _worksheetRows[i];
        if (column < row.length && row[column].trim().isNotEmpty) {
          sample = row[column].trim();
          break;
        }
      }
      options.add(_ColumnOption(index: column, header: header, sample: sample));
    }
    return options;
  }

  @override
  Widget build(BuildContext context) {
    final themeStyle = context.watch<DarkMode>().themeStyle;
    final themeConfig = AppThemeConfig.of(themeStyle);

    return Scaffold(
      appBar: AppAppBar(
        title: '从 Excel 导入',
        actions: [
          if (_hasFile && _outcome == null)
            TextButton(
              onPressed: _isParsing ? null : _pickFile,
              child: const Text('重选', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _outcome != null
            ? _buildOutcome(themeConfig)
            : (_hasFile ? _buildPreview(themeConfig) : _buildEmpty(themeConfig)),
      ),
    );
  }

  // ---------------------------------------------------------------- 空态

  Widget _buildEmpty(AppThemeConfig themeConfig) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 26),
                  child: Column(
                    children: [
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: themeConfig.primaryColor.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(Icons.table_chart_rounded, size: 28, color: themeConfig.primaryColor),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '选择你的 Excel 词表',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                          color: themeConfig.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '支持 .xlsx，自动识别各列含义，无需调整格式\n旧版 .xls 请先用 Excel / WPS 另存为 .xlsx',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11.5, color: themeConfig.textSecondary, height: 1.7),
                      ),
                    ],
                  ),
                ),
                _buildInfoCard(
                  themeConfig,
                  title: '会自动识别这些列',
                  items: const [
                    ('单词', '必填，英文拼写'),
                    ('释义', '可选，多个义项用分号「;」分隔'),
                    ('词性', '可选，如 n. / v. / adj.'),
                    ('单元', '可选，用于按单元分组'),
                    ('其他', '音标、例句、序号等列会自动忽略'),
                  ],
                  footnote: '列顺序、表头名称都不限，识别不准可在下一步手动指定',
                ),
              ],
            ),
          ),
        ),
        _buildBottomBar(
          themeConfig,
          child: _buildPrimaryButton(
            themeConfig,
            label: _isParsing ? '正在解析…' : '选择 Excel 文件',
            onPressed: _isParsing ? null : _pickFile,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard(
    AppThemeConfig themeConfig, {
    required String title,
    required List<(String, String)> items,
    String? footnote,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: themeConfig.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: themeConfig.cardBorder),
      ),
      padding: const EdgeInsets.fromLTRB(14, 15, 14, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: themeConfig.textPrimary),
          ),
          const SizedBox(height: 4),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  SizedBox(
                    width: 40,
                    child: Text(
                      item.$1,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: themeConfig.primaryColor),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      item.$2,
                      style: TextStyle(fontSize: 11.5, color: themeConfig.textSecondary, height: 1.5),
                    ),
                  ),
                ],
              ),
            ),
          if (footnote != null) ...[
            Divider(height: 1, thickness: 0.5, color: themeConfig.cardBorder),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Text(
                footnote,
                style: TextStyle(fontSize: 11, color: themeConfig.textSecondary, height: 1.6),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- 预览

  Widget _buildPreview(AppThemeConfig themeConfig) {
    final counts = <ExcelRowStatus, int>{};
    for (final row in _rows) {
      counts[row.status] = (counts[row.status] ?? 0) + 1;
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              _buildFileCard(themeConfig),
              const SizedBox(height: 10),
              _buildRecognizeBar(themeConfig),
              _buildStats(themeConfig, counts),
              const SizedBox(height: 10),
              _buildUpdateMeaningsToggle(themeConfig),
              const SizedBox(height: 10),
              _buildRowList(themeConfig),
            ],
          ),
        ),
        _buildBottomBar(
          themeConfig,
          child: Row(
            children: [
              Text.rich(
                TextSpan(
                  text: '已选 ',
                  style: TextStyle(fontSize: 12.5, color: themeConfig.textSecondary),
                  children: [
                    TextSpan(
                      text: '${_selectedLines.length}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: themeConfig.textPrimary,
                        fontFamily: 'Roboto',
                      ),
                    ),
                    const TextSpan(text: ' 个'),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: _buildPrimaryButton(
                  themeConfig,
                  label: _isImporting ? '正在导入…' : '导入 ${_selectedLines.length} 个单词',
                  onPressed: (_isImporting || _selectedLines.isEmpty) ? null : _import,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFileCard(AppThemeConfig themeConfig) {
    return Container(
      decoration: BoxDecoration(
        color: themeConfig.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: themeConfig.cardBorder),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: themeConfig.primaryColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.table_chart_rounded, size: 20, color: themeConfig.primaryColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _fileName ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: themeConfig.textPrimary,
                    letterSpacing: -0.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '工作表「${_sheetName ?? ''}」· ${_worksheetRows.length} 行',
                  style: TextStyle(fontSize: 11, color: themeConfig.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecognizeBar(AppThemeConfig themeConfig) {
    final mapping = _mapping;
    if (mapping == null || !mapping.hasSpellColumn) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '未能识别「单词」列，请手动指定',
                style: TextStyle(fontSize: 11, color: const Color(0xFFE54D3B)),
              ),
            ),
            _buildTextAction(themeConfig, '调整', _showMappingSheet),
          ],
        ),
      );
    }

    final parts = <String>['单词列 ${_columnLabel(mapping.spellColumn!)}'];
    if (mapping.meaningColumn != null) parts.add('释义列 ${_columnLabel(mapping.meaningColumn!)}');
    if (mapping.partOfSpeechColumn != null) parts.add('词性列 ${_columnLabel(mapping.partOfSpeechColumn!)}');
    if (mapping.unitColumn != null) parts.add('单元列 ${_columnLabel(mapping.unitColumn!)}');

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Row(
        children: [
          Icon(Icons.check_rounded, size: 12, color: themeConfig.primaryColor),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              '已识别：${parts.join(' · ')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: themeConfig.textSecondary),
            ),
          ),
          _buildTextAction(themeConfig, '调整', _showMappingSheet),
        ],
      ),
    );
  }

  Widget _buildStats(AppThemeConfig themeConfig, Map<ExcelRowStatus, int> counts) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
      child: Row(
        children: [
          _buildStat(themeConfig, counts[ExcelRowStatus.ready] ?? 0, '可导入', themeConfig.primaryColor),
          const SizedBox(width: 16),
          _buildStat(themeConfig, counts[ExcelRowStatus.alreadyInDict] ?? 0, '已存在', themeConfig.textSecondary),
          const SizedBox(width: 16),
          _buildStat(themeConfig, counts[ExcelRowStatus.notInLibrary] ?? 0, '未收录', const Color(0xFFD97706)),
          const SizedBox(width: 16),
          _buildStat(themeConfig, counts[ExcelRowStatus.invalid] ?? 0, '格式错误', const Color(0xFFE54D3B)),
        ],
      ),
    );
  }

  Widget _buildStat(AppThemeConfig themeConfig, int count, String label, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          '$count',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color, fontFamily: 'Roboto'),
        ),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 11.5, color: themeConfig.textSecondary)),
      ],
    );
  }

  Widget _buildUpdateMeaningsToggle(AppThemeConfig themeConfig) {
    return Container(
      decoration: BoxDecoration(
        color: themeConfig.cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: themeConfig.cardBorder),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '同时更新已有单词的释义',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: themeConfig.textPrimary),
                ),
                const SizedBox(height: 3),
                Text(
                  '默认跳过词表中已存在的单词',
                  style: TextStyle(fontSize: 11, color: themeConfig.textSecondary),
                ),
              ],
            ),
          ),
          Switch(
            value: _updateMeanings,
            onChanged: (value) => setState(() => _updateMeanings = value),
          ),
        ],
      ),
    );
  }

  Widget _buildRowList(AppThemeConfig themeConfig) {
    if (_rows.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: themeConfig.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: themeConfig.cardBorder),
        ),
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: Text('没有解析到可导入的内容', style: TextStyle(fontSize: 12.5, color: themeConfig.textSecondary)),
        ),
      );
    }

    // 预览只渲染前 [_maxPreviewRows] 行：勾选状态与导入均基于全量数据，
    // 避免上千行时一次性构建大量 widget 造成卡顿。
    final previewRows = _rows.length > _maxPreviewRows ? _rows.sublist(0, _maxPreviewRows) : _rows;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: themeConfig.cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: themeConfig.cardBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < previewRows.length; i++) ...[
                if (i > 0)
                  Padding(
                    padding: const EdgeInsets.only(left: 46),
                    child: Divider(height: 1, thickness: 0.5, color: themeConfig.cardBorder),
                  ),
                _buildRowTile(themeConfig, previewRows[i]),
              ],
            ],
          ),
        ),
        if (previewRows.length < _rows.length)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
            child: Text(
              '仅预览前 $_maxPreviewRows 行，共 ${_rows.length} 行；勾选与导入仍基于全部数据',
              style: TextStyle(fontSize: 11, color: themeConfig.textSecondary),
            ),
          ),
      ],
    );
  }

  Widget _buildRowTile(AppThemeConfig themeConfig, ExcelImportRow row) {
    final selectable = _isSelectable(row);
    final selected = _selectedLines.contains(row.lineNumber);
    final status = _statusText(row);
    final muted = !selectable;

    return InkWell(
      onTap: selectable
          ? () => setState(() {
                if (selected) {
                  _selectedLines.remove(row.lineNumber);
                } else {
                  _selectedLines.add(row.lineNumber);
                }
              })
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            _buildCheckbox(themeConfig, selected, selectable),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.spell.isEmpty ? '（空）' : row.spell,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: muted ? FontWeight.w500 : FontWeight.w600,
                      color: muted ? themeConfig.textSecondary : themeConfig.textPrimary,
                      letterSpacing: -0.1,
                    ),
                  ),
                  if (row.meaning.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      row.meaning,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11.5, color: themeConfig.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            if (status != null) ...[
              const SizedBox(width: 10),
              Text(status.$1, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: status.$2)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCheckbox(AppThemeConfig themeConfig, bool selected, bool selectable) {
    final on = selected && selectable;
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: on ? themeConfig.primaryColor : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: on ? themeConfig.primaryColor : themeConfig.cardBorder,
          width: 1.5,
        ),
      ),
      child: on
          ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
          : null,
    );
  }

  (String, Color)? _statusText(ExcelImportRow row) {
    switch (row.status) {
      case ExcelRowStatus.alreadyInDict:
        return ('已存在', const Color(0xFF8A9A96));
      case ExcelRowStatus.notInLibrary:
        return ('未收录', const Color(0xFFD97706));
      case ExcelRowStatus.duplicate:
        return ('重复', const Color(0xFFE54D3B));
      case ExcelRowStatus.invalid:
        return ('格式错误', const Color(0xFFE54D3B));
      case ExcelRowStatus.ready:
        return null;
    }
  }

  // ---------------------------------------------------------------- 结果

  Widget _buildOutcome(AppThemeConfig themeConfig) {
    final outcome = _outcome!;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: themeConfig.primaryColor.withValues(alpha: 0.10),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.check_rounded, size: 26, color: themeConfig.primaryColor),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      '${outcome.inserted}',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        color: themeConfig.textPrimary,
                        fontFamily: 'Roboto',
                        letterSpacing: -1,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text('个单词已加入', style: TextStyle(fontSize: 12.5, color: themeConfig.textSecondary)),
                  ],
                ),
              ),
              Container(
                decoration: BoxDecoration(
                  color: themeConfig.cardBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: themeConfig.cardBorder),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    _buildOutcomeRow(themeConfig, '新增', outcome.inserted, themeConfig.primaryColor),
                    _buildOutcomeDivider(themeConfig),
                    _buildOutcomeRow(themeConfig, '已跳过（词表中已存在）', outcome.alreadyInDict, const Color(0xFF8A9A96)),
                    _buildOutcomeDivider(themeConfig),
                    _buildOutcomeRow(themeConfig, '未收录（词库中暂无）', outcome.notInLibrary, const Color(0xFFD97706)),
                    _buildOutcomeDivider(themeConfig),
                    _buildOutcomeRow(themeConfig, '格式错误（已忽略）', outcome.invalid, const Color(0xFFE54D3B)),
                    if (outcome.duplicate > 0) ...[
                      _buildOutcomeDivider(themeConfig),
                      _buildOutcomeRow(themeConfig, '文件内重复（已合并）', outcome.duplicate, const Color(0xFF8A9A96)),
                    ],
                  ],
                ),
              ),
              if (outcome.missingSpells.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    color: themeConfig.cardBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: themeConfig.cardBorder),
                  ),
                  padding: const EdgeInsets.fromLTRB(14, 15, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '未收录的单词',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: themeConfig.textPrimary),
                            ),
                          ),
                          _buildTextAction(themeConfig, '复制清单', () {
                            Clipboard.setData(ClipboardData(text: outcome.missingSpells.join('\n')));
                            ToastUtil.info('已复制 ${outcome.missingSpells.length} 个单词');
                          }),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _buildMissingPreview(outcome.missingSpells),
                        style: TextStyle(fontSize: 12, color: themeConfig.textSecondary, height: 1.8),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '这些单词暂未收录到词库，本次已跳过。',
                        style: TextStyle(fontSize: 11, color: themeConfig.textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        _buildBottomBar(
          themeConfig,
          child: _buildPrimaryButton(
            themeConfig,
            label: '完成',
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ),
      ],
    );
  }

  String _buildMissingPreview(List<String> spells) {
    if (spells.length <= _maxMissingPreview) return spells.join('、');
    return '${spells.take(_maxMissingPreview).join('、')} 等 ${spells.length} 个';
  }

  Widget _buildOutcomeDivider(AppThemeConfig themeConfig) {
    return Divider(height: 1, thickness: 0.5, color: themeConfig.cardBorder);
  }

  Widget _buildOutcomeRow(AppThemeConfig themeConfig, String label, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 13.5, color: themeConfig.textSecondary)),
          Text(
            '$count',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color, fontFamily: 'Roboto'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- 组件

  Widget _buildTextAction(AppThemeConfig themeConfig, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500, color: themeConfig.primaryColor),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_forward_ios_rounded, size: 9, color: themeConfig.primaryColor.withValues(alpha: 0.8)),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(AppThemeConfig themeConfig, {required Widget child}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: child,
    );
  }

  Widget _buildPrimaryButton(AppThemeConfig themeConfig, {required String label, VoidCallback? onPressed}) {
    return SizedBox(
      height: 48,
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: themeConfig.primaryColor,
          disabledBackgroundColor: themeConfig.primaryColor.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
        ),
      ),
    );
  }

  static String _columnLabel(int index) {
    var value = index;
    final buffer = StringBuffer();
    while (true) {
      buffer.write(String.fromCharCode(65 + value % 26));
      value = value ~/ 26 - 1;
      if (value < 0) break;
    }
    return '${buffer.toString().split('').reversed.join()} 列';
  }
}

/// 后台 isolate 中解析 .xlsx，避免大文件阻塞 UI。
Map<String, dynamic> _parseXlsxBytes(Uint8List bytes) {
  final sheet = XlsxReader.read(bytes);
  return {'sheet': sheet.name, 'rows': sheet.rows};
}

class _ColumnOption {
  final int index;
  final String header;
  final String sample;

  const _ColumnOption({required this.index, required this.header, required this.sample});

  String get label {
    final name = header.isNotEmpty ? header : sample;
    final columnLabel = _ImportFromExcelPageState._columnLabel(index);
    return name.isEmpty ? columnLabel : '$columnLabel · $name';
  }
}

class _ImportOutcome {
  final int inserted;
  final int alreadyInDict;
  final int notInLibrary;
  final int invalid;
  final int duplicate;
  final List<String> missingSpells;

  const _ImportOutcome({
    required this.inserted,
    required this.alreadyInDict,
    required this.notInLibrary,
    required this.invalid,
    required this.duplicate,
    required this.missingSpells,
  });
}

/// 调整列对应关系的底部面板。
class _ColumnMappingSheet extends StatefulWidget {
  final List<_ColumnOption> options;
  final ExcelColumnMapping mapping;
  final AppThemeConfig themeConfig;
  final ValueChanged<ExcelColumnMapping> onApply;

  const _ColumnMappingSheet({
    required this.options,
    required this.mapping,
    required this.themeConfig,
    required this.onApply,
  });

  @override
  State<_ColumnMappingSheet> createState() => _ColumnMappingSheetState();
}

class _ColumnMappingSheetState extends State<_ColumnMappingSheet> {
  late int? _spell;
  late int? _meaning;
  late int? _partOfSpeech;
  late int? _unit;
  String? _expandedField;
  late bool _skipHeader;

  @override
  void initState() {
    super.initState();
    _spell = widget.mapping.spellColumn;
    _meaning = widget.mapping.meaningColumn;
    _partOfSpeech = widget.mapping.partOfSpeechColumn;
    _unit = widget.mapping.unitColumn;
    _skipHeader = widget.mapping.headerRowIndex != null;
  }

  @override
  Widget build(BuildContext context) {
    final themeConfig = widget.themeConfig;
    return Container(
      decoration: BoxDecoration(
        color: themeConfig.cardBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(16, 10, 16, 20 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: themeConfig.textSecondary.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '调整列对应关系',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: themeConfig.textPrimary, letterSpacing: -0.2),
          ),
          const SizedBox(height: 5),
          Text(
            '选择每一列代表的内容，预览会立即更新',
            style: TextStyle(fontSize: 11.5, color: themeConfig.textSecondary),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _buildField(themeConfig, 'spell', '单词', required: true, value: _spell),
                  _buildField(themeConfig, 'meaning', '释义', value: _meaning),
                  _buildField(themeConfig, 'pos', '词性', value: _partOfSpeech),
                  _buildField(themeConfig, 'unit', '单元', value: _unit),
                  const SizedBox(height: 4),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _skipHeader,
                    onChanged: (value) => setState(() => _skipHeader = value),
                    title: Text(
                      '跳过第一行表头',
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: themeConfig.textPrimary),
                    ),
                    subtitle: Text(
                      '表格首行是列名时开启',
                      style: TextStyle(fontSize: 11, color: themeConfig.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 48,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      backgroundColor: themeConfig.subtleBg,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(
                      '取消',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: themeConfig.textSecondary),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: _spell == null
                        ? null
                        : () => widget.onApply(ExcelColumnMapping(
                              spellColumn: _spell,
                              meaningColumn: _meaning,
                              partOfSpeechColumn: _partOfSpeech,
                              unitColumn: _unit,
                              headerRowIndex: _skipHeader ? 0 : null,
                            )),
                    style: FilledButton.styleFrom(
                      backgroundColor: themeConfig.primaryColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text(
                      '应用',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildField(
    AppThemeConfig themeConfig,
    String field,
    String label, {
    required int? value,
    bool required = false,
  }) {
    final expanded = _expandedField == field;
    _ColumnOption? option;
    for (final candidate in widget.options) {
      if (candidate.index == value) {
        option = candidate;
        break;
      }
    }

    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _expandedField = expanded ? null : field),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 13),
            child: Row(
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: themeConfig.textPrimary),
                ),
                if (required)
                  Text(' *', style: TextStyle(fontSize: 12.5, color: const Color(0xFFE54D3B))),
                const Spacer(),
                Text(
                  option == null ? '未指定' : option.label,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: option == null ? themeConfig.textSecondary : themeConfig.textPrimary,
                  ),
                ),
                const SizedBox(width: 5),
                Icon(
                  expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: themeConfig.textSecondary,
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          Container(
            constraints: const BoxConstraints(maxHeight: 240),
            decoration: BoxDecoration(
              color: themeConfig.subtleBg,
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: widget.options.length + (required ? 0 : 1),
              itemBuilder: (context, index) {
                if (!required && index == 0) {
                  return ListTile(
                    dense: true,
                    title: Text('未指定', style: TextStyle(fontSize: 13, color: themeConfig.textSecondary)),
                    onTap: () => setState(() {
                      _assign(field, null);
                      _expandedField = null;
                    }),
                  );
                }
                final optionIndex = required ? index : index - 1;
                if (optionIndex >= widget.options.length) return const SizedBox.shrink();
                final item = widget.options[optionIndex];
                return ListTile(
                  dense: true,
                  title: Text(item.label, style: TextStyle(fontSize: 13, color: themeConfig.textPrimary)),
                  trailing: item.index == value
                      ? Icon(Icons.check_rounded, size: 16, color: themeConfig.primaryColor)
                      : null,
                  onTap: () => setState(() {
                    _assign(field, item.index);
                    _expandedField = null;
                  }),
                );
              },
            ),
          ),
        Divider(height: 1, thickness: 0.5, color: themeConfig.cardBorder),
      ],
    );
  }

  void _assign(String field, int? value) {
    switch (field) {
      case 'spell':
        _spell = value;
        break;
      case 'meaning':
        _meaning = value;
        break;
      case 'pos':
        _partOfSpeech = value;
        break;
      case 'unit':
        _unit = value;
        break;
    }
  }
}
