import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import '../api/vo.dart';
import 'word_util.dart';

enum PdfExportMode {
  classic,          // 中英对照
  spellDictation,   // 拼写默写 (隐藏英文)
  meaningDictation, // 释义默写 (隐藏中文)
}

class PdfExporter {
  /// 每页的最大行数 (双栏，所以每页最多展示 maxRowsPerPage * 2 个单词)
  static const int maxRowsPerPage = 32;

  static Future<void> exportToPdf({
    required BuildContext context,
    required String title,
    required List<WordWrapper> words,
    required PdfExportMode exportMode,
    required bool includePronounce,
    required Function(String) onStatusChanged,
  }) async {
    if (words.isEmpty) {
      throw Exception('当前词表没有单词，无法导出');
    }

    try {
      onStatusChanged('正在加载中文字体...');
      // 1. 加载本地中文字体以支持中文渲染 (避免乱码)
      final fontData = await rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf');
      final ttfFont = pw.Font.ttf(fontData);

      onStatusChanged('正在排版 PDF 文档...');
      final pdfDoc = pw.Document(
        theme: pw.ThemeData.withFont(
          base: ttfFont,
        ),
      );

      // 2. 分页处理单词数据
      final int wordsPerPage = maxRowsPerPage * 2;
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
                  // 页眉
                  _buildHeader(title, pageIndex + 1, totalPages, exportMode),
                  pw.SizedBox(height: 12),

                  // 双栏内容区
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
                                  itemIdx + 1, entry.value.word, exportMode, includePronounce);
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
                                  itemIdx + 1, entry.value.word, exportMode, includePronounce);
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 页脚
                  pw.SizedBox(height: 8),
                  _buildFooter(pageIndex + 1, totalPages),
                ],
              );
            },
          ),
        );
      }

      onStatusChanged('正在生成 PDF 文件...');
      // 3. 将 PDF 写入临时文件
      final bytes = await pdfDoc.save();
      final tempDir = await getTemporaryDirectory();
      
      // 处理文件名中的非法字符
      final safeTitle = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final modeSuffix = exportMode == PdfExportMode.classic
          ? '中英对照'
          : (exportMode == PdfExportMode.spellDictation ? '拼写默写' : '释义默写');
      
      final String filePath = '${tempDir.path}/${safeTitle}_$modeSuffix.pdf';
      final file = File(filePath);
      await file.writeAsBytes(bytes);

      onStatusChanged('拉起系统分享...');
      // 4. 调用原生分享
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: '$title - 导出词表',
      );
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
  ) {
    String modeName = '中英对照表';
    if (mode == PdfExportMode.spellDictation) {
      modeName = '拼写默写自测本';
    } else if (mode == PdfExportMode.meaningDictation) {
      modeName = '释义记忆自测本';
    }

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
              modeName,
              style: const pw.TextStyle(
                fontSize: 11,
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
  ) {
    final bool hasPronounce =
        includePronounce && word.mergedPronounce.isNotEmpty;

    // 行高固定在 22 像素左右，保持规整
    return pw.Container(
      height: 22,
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
            width: 20,
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
              width: 75,
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
              width: 75,
              child: pw.Padding(
                padding: const pw.EdgeInsets.only(right: 4),
                child: pw.Text(
                  word.spell,
                  style: pw.TextStyle(
                    fontSize: 9.5,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.grey900,
                  ),
                  maxLines: 1,
                  overflow: pw.TextOverflow.clip,
                ),
              ),
            ),

          // 音标 (可选)
          if (hasPronounce)
            pw.SizedBox(
              width: 50,
              child: pw.Padding(
                padding: const pw.EdgeInsets.only(right: 4),
                child: pw.Text(
                  word.mergedPronounce,
                  style: const pw.TextStyle(
                    fontSize: 7.5,
                    color: PdfColors.grey600,
                  ),
                  maxLines: 1,
                  overflow: pw.TextOverflow.clip,
                ),
              ),
            ),

          // 中文释义 或 填空下划线
          pw.Expanded(
            child: mode == PdfExportMode.meaningDictation
                ? pw.Align(
                    alignment: pw.Alignment.bottomLeft,
                    child: pw.Container(
                      width: 100,
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
                    word.meaningStr ?? '',
                    style: const pw.TextStyle(
                      fontSize: 8.5,
                      color: PdfColors.grey800,
                    ),
                    maxLines: 1,
                    overflow: pw.TextOverflow.clip,
                  ),
          ),
        ],
      ),
    );
  }
}
