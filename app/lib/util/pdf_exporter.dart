import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../api/vo.dart';
import 'word_util.dart';

enum PdfExportMode {
  classic,          // 中英对照
  spellDictation,   // 拼写默写 (隐藏英文)
  meaningDictation, // 释义默写 (隐藏中文)
}

class PdfExporter {
  /// 单栏每页的最大行数
  static const int maxRowsPerSinglePage = 28;
  /// 双栏每页的最大行数 (双栏，所以每页最多展示 maxRowsPerDoublePage * 2 个单词)
  static const int maxRowsPerDoublePage = 32;

  /// 生成 PDF 并保存为临时文件，返回 File 实例
  static Future<File> generatePdfFile({
    required String title,
    required List<WordWrapper> words,
    required PdfExportMode exportMode,
    required bool includePronounce,
    required bool isDoubleColumn,
    required Function(String) onStatusChanged,
  }) async {
    if (words.isEmpty) {
      throw Exception('当前词表没有单词，无法导出');
    }

    try {
      onStatusChanged('正在加载字体资源...');
      // 1. 同时加载中文字体和西文字体，防止中文乱码和音标特殊字符乱码
      final fontDataSC = await rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf');
      final fontDataEN = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
      
      final ttfSC = pw.Font.ttf(fontDataSC);
      final ttfEN = pw.Font.ttf(fontDataEN);

      onStatusChanged('正在排版 PDF 文档...');
      final pdfDoc = pw.Document(
        theme: pw.ThemeData.withFont(
          base: ttfSC,
          bold: ttfSC, // 修复 bold 时中文回退到默认英文加粗导致乱码的 Bug
        ),
      );

      if (isDoubleColumn) {
        // 双栏排版
        final int wordsPerPage = maxRowsPerDoublePage * 2;
        final int totalPages = (words.length / wordsPerPage).ceil();

        for (int pageIndex = 0; pageIndex < totalPages; pageIndex++) {
          final int startIdx = pageIndex * wordsPerPage;
          final int endIdx = (startIdx + wordsPerPage < words.length)
              ? startIdx + wordsPerPage
              : words.length;

          final List<WordWrapper> pageWords = words.sublist(startIdx, endIdx);

          // 将这一页的单词分为左右两栏
          final int midPoint = (pageWords.length / 2).ceil();
          final List<WordWrapper> leftColWords = pageWords.sublist(0, midPoint);
          final List<WordWrapper> rightColWords =
              pageWords.sublist(midPoint, pageWords.length);

          pdfDoc.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              build: (pw.Context pwContext) {
                return pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildHeader(title, pageIndex + 1, totalPages, exportMode, true),
                    pw.SizedBox(height: 12),
                    pw.Expanded(
                      child: pw.Row(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          // 左栏
                          pw.Expanded(
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: leftColWords.asMap().entries.map((entry) {
                                final int itemIdx = startIdx + entry.key;
                                return _buildWordRow(
                                  itemIdx + 1,
                                  entry.value.word,
                                  exportMode,
                                  includePronounce,
                                  true,
                                  ttfEN,
                                );
                              }).toList(),
                            ),
                          ),
                          
                          // 中间分割线
                          pw.VerticalDivider(
                            width: 24,
                            thickness: 0.5,
                            color: PdfColors.grey400,
                          ),

                          // 右栏
                          pw.Expanded(
                            child: pw.Column(
                              crossAxisAlignment: pw.CrossAxisAlignment.start,
                              children: rightColWords.asMap().entries.map((entry) {
                                final int itemIdx = startIdx + midPoint + entry.key;
                                return _buildWordRow(
                                  itemIdx + 1,
                                  entry.value.word,
                                  exportMode,
                                  includePronounce,
                                  true,
                                  ttfEN,
                                );
                              }).toList(),
                            ),
                          ),
                        ],
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    _buildFooter(pageIndex + 1, totalPages),
                  ],
                );
              },
            ),
          );
        }
      } else {
        // 单栏排版
        final int wordsPerPage = maxRowsPerSinglePage;
        final int totalPages = (words.length / wordsPerPage).ceil();

        for (int pageIndex = 0; pageIndex < totalPages; pageIndex++) {
          final int startIdx = pageIndex * wordsPerPage;
          final int endIdx = (startIdx + wordsPerPage < words.length)
              ? startIdx + wordsPerPage
              : words.length;

          final List<WordWrapper> pageWords = words.sublist(startIdx, endIdx);

          pdfDoc.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 24),
              build: (pw.Context pwContext) {
                return pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildHeader(title, pageIndex + 1, totalPages, exportMode, false),
                    pw.SizedBox(height: 12),
                    pw.Expanded(
                      child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: pageWords.asMap().entries.map((entry) {
                          final int itemIdx = startIdx + entry.key;
                          return _buildWordRow(
                            itemIdx + 1,
                            entry.value.word,
                            exportMode,
                            includePronounce,
                            false,
                            ttfEN,
                          );
                        }).toList(),
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    _buildFooter(pageIndex + 1, totalPages),
                  ],
                );
              },
            ),
          );
        }
      }

      onStatusChanged('正在生成 PDF 文件...');
      final bytes = await pdfDoc.save();
      final tempDir = await getTemporaryDirectory();
      
      final safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final modeSuffix = exportMode == PdfExportMode.classic
          ? '中英对照'
          : (exportMode == PdfExportMode.spellDictation ? '拼写默写' : '释义默写');
      final colSuffix = isDoubleColumn ? '双栏' : '单栏';
      
      final String filePath = '${tempDir.path}/${safeTitle}_${modeSuffix}_$colSuffix.pdf';
      final file = File(filePath);
      await file.writeAsBytes(bytes);

      return file;
    } catch (e) {
      rethrow;
    }
  }

  /// 构建页眉
  static pw.Widget _buildHeader(
    String title,
    int pageNum,
    int totalPages,
    PdfExportMode mode,
    bool isDoubleColumn,
  ) {
    String modeName = '中英对照表';
    if (mode == PdfExportMode.spellDictation) {
      modeName = '拼写默写自测本';
    } else if (mode == PdfExportMode.meaningDictation) {
      modeName = '释义记忆自测本';
    }

    final colName = isDoubleColumn ? '双列版' : '单列版';

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              '泡泡单词 - $title',
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.cyan800,
              ),
            ),
            pw.Text(
              '$modeName ($colName)',
              style: const pw.TextStyle(
                fontSize: 10,
                color: PdfColors.grey700,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Container(
          height: 1.5,
          color: PdfColors.cyan800,
        ),
      ],
    );
  }

  /// 构建页脚
  static pw.Widget _buildFooter(int pageNum, int totalPages) {
    return pw.Column(
      children: [
        pw.Container(
          height: 0.5,
          color: PdfColors.grey400,
        ),
        pw.SizedBox(height: 4),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              '由泡泡单词 App 智能导出',
              style: const pw.TextStyle(
                fontSize: 8,
                color: PdfColors.grey500,
              ),
            ),
            pw.Text(
              '第 $pageNum 页 / 共 $totalPages 页',
              style: const pw.TextStyle(
                fontSize: 8,
                color: PdfColors.grey500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 构建单个单词的行
  static pw.Widget _buildWordRow(
    int displayNum,
    WordVo word,
    PdfExportMode mode,
    bool includePronounce,
    bool isDoubleColumn,
    pw.Font ttfEN,
  ) {
    final bool hasPronounce =
        includePronounce && word.mergedPronounce.isNotEmpty;

    // 根据是单栏还是双栏，动态分配宽度
    final double indexWidth = isDoubleColumn ? 20 : 25;
    final double spellWidth = isDoubleColumn ? 80 : 140; // 双栏稍窄，增加中文可展示空间
    final double pronounceWidth = isDoubleColumn ? 50 : 90; // 双栏稍窄

    // 双栏固定行高保证左右对称，单栏弹性大小防止释义换行被截断
    final pw.BoxConstraints constraints = isDoubleColumn
        ? const pw.BoxConstraints(minHeight: 22, maxHeight: 22)
        : const pw.BoxConstraints(minHeight: 24);

    return pw.Container(
      constraints: constraints,
      alignment: pw.Alignment.centerLeft,
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(
            width: 0.3,
            color: PdfColors.grey300,
            style: pw.BorderStyle.dashed,
          ),
        ),
      ),
      child: pw.Row(
        children: [
          // 序号
          pw.SizedBox(
            width: indexWidth,
            child: pw.Text(
              '$displayNum.',
              style: const pw.TextStyle(
                fontSize: 9,
                color: PdfColors.grey600,
              ),
            ),
          ),

          // 英文单词 或 填空下划线
          if (mode == PdfExportMode.spellDictation)
            pw.Container(
              width: spellWidth - 6,
              height: 12,
              margin: const pw.EdgeInsets.only(right: 6),
              decoration: const pw.BoxDecoration(
                border: pw.Border(
                  bottom: pw.BorderSide(
                    width: 0.5,
                    color: PdfColors.grey600,
                  ),
                ),
              ),
            )
          else
            pw.SizedBox(
              width: spellWidth,
              child: pw.Padding(
                padding: const pw.EdgeInsets.only(right: 6),
                child: pw.Text(
                  word.spell,
                  style: pw.TextStyle(
                    fontSize: 9.5,
                    fontWeight: pw.FontWeight.bold,
                    font: ttfEN, // 显式指定西文专用 NotoSans 渲染英文，包含完整 IPA 字符集支持
                    color: PdfColors.grey900,
                  ),
                  maxLines: 1,
                ),
              ),
            ),

          // 音标 (可选)
          if (hasPronounce)
            pw.SizedBox(
              width: pronounceWidth,
              child: pw.Padding(
                padding: const pw.EdgeInsets.only(right: 6),
                child: pw.Text(
                  word.mergedPronounce,
                  style: pw.TextStyle(
                    fontSize: 7.5,
                    font: ttfEN, // 显式指定 NotoSans 渲染音标，完美支持音标特殊字符防止乱码
                    color: PdfColors.grey600,
                  ),
                  maxLines: 1,
                ),
              ),
            ),

          // 中文释义 或 填空下划线
          pw.Expanded(
            child: mode == PdfExportMode.meaningDictation
                ? pw.Align(
                    alignment: pw.Alignment.bottomLeft,
                    child: pw.Container(
                      width: isDoubleColumn ? 100 : 150,
                      height: 12,
                      decoration: const pw.BoxDecoration(
                        border: pw.Border(
                          bottom: pw.BorderSide(
                            width: 0.5,
                            color: PdfColors.grey600,
                          ),
                        ),
                      ),
                    ),
                  )
                : pw.Text(
                    _getCleanMeaning(word), // 优化：仅拼接中文释义本身，省去词性前缀，节省约40%的宽度，确保不被截断
                    style: const pw.TextStyle(
                      fontSize: 8.5,
                      color: PdfColors.grey800,
                    ),
                    maxLines: isDoubleColumn ? 1 : 2, // 单栏允许折行展示更多
                  ),
          ),
        ],
      ),
    );
  }

  /// 提取无词性的纯中文释义，优化紧凑排版下的展示效果
  static String _getCleanMeaning(WordVo word) {
    if (word.meaningItems == null || word.meaningItems!.isEmpty) {
      return word.meaningStr ?? '';
    }
    final List<String> parts = [];
    for (var item in word.getMergedMeaningItems()) {
      if (item.meaning != null && item.meaning!.trim().isNotEmpty) {
        String m = item.meaning!.trim();
        while (m.endsWith(';') || m.endsWith('；') || m.endsWith(',') || m.endsWith('，')) {
          m = m.substring(0, m.length - 1);
        }
        if (m.isNotEmpty) {
          parts.add(m);
        }
      }
    }
    return parts.isNotEmpty ? parts.join('；') : (word.meaningStr ?? '');
  }
}
