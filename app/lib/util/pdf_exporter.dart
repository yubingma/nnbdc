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
  /// 单栏每页的最大行数 (用于动态算法的安全边界参考)
  static const int maxRowsPerSinglePage = 20;
  /// 双栏每页的最大行数 (用于动态算法的安全边界参考)
  static const int maxRowsPerDoublePage = 22;

  /// 估算单个单词在指定排版下的物理高度，校准折行增量高度，实现像素级精准切页
  static double _estimateWordHeight(WordVo word, bool isDoubleColumn, bool includePronounce) {
    // 基础高度 (单行最小高度 constraints)
    final double baseHeight = isDoubleColumn ? 22.0 : 24.0;
    // 多行文字的增量行高 (8.5号字在 leading 约束下折行后，实际只增大约 7~8 像素高度)
    final double lineIncrement = isDoubleColumn ? 7.0 : 8.0;

    final String meaningText = _formatMeaningForPdf(word.getMeaningStr());
    if (meaningText.isEmpty) {
      return baseHeight;
    }

    int estimatedLines = 1;
    if (isDoubleColumn) {
      // 双栏下，可用中文宽度约 110px，在 8.5 号字下大约容纳 13 个字符
      if (meaningText.length > 13) {
        estimatedLines = 2; // 双栏最大限制在 2 行
      }
    } else {
      // 单栏下，可用中文宽度约 270px，在 8.5 号字下大约容纳 32 个字符
      if (meaningText.length > 32) {
        estimatedLines = (meaningText.length / 32).ceil();
        if (estimatedLines > 4) estimatedLines = 4; // 单栏限制最大换行 4 行
      }
    }

    return baseHeight + (estimatedLines - 1) * lineIncrement;
  }

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

      // 2. 根据动态高度累加预测算法进行切页，实现 A4 页面空间利用率最大化且绝对不溢出截断
      final List<List<WordWrapper>> pagesData = [];
      int currentWordIdx = 0;

      if (isDoubleColumn) {
        // 双栏最大安全可用主体高度：812px可用，扣除页眉页脚等非主体部分(51px)，设为精准的 755px
        const double maxPageHeight = 755.0; 

        while (currentWordIdx < words.length) {
          int count = 1;
          while (currentWordIdx + count <= words.length) {
            final List<WordWrapper> candidateWords =
                words.sublist(currentWordIdx, currentWordIdx + count);

            // 模拟左右均分
            final int mid = (candidateWords.length / 2).ceil();
            final List<WordWrapper> left = candidateWords.sublist(0, mid);
            final List<WordWrapper> right = candidateWords.sublist(mid);

            // 计算左右两栏高度
            double leftHeight = 0;
            for (var w in left) {
              leftHeight += _estimateWordHeight(w.word, true, includePronounce);
            }
            double rightHeight = 0;
            for (var w in right) {
              rightHeight += _estimateWordHeight(w.word, true, includePronounce);
            }

            final double pageHeight = leftHeight > rightHeight ? leftHeight : rightHeight;

            if (pageHeight <= maxPageHeight) {
              count++;
            } else {
              break;
            }
          }

          final int finalCount = count > 1 ? count - 1 : 1;
          pagesData.add(words.sublist(currentWordIdx, currentWordIdx + finalCount));
          currentWordIdx += finalCount;
        }
      } else {
        // 单栏最大安全可用主体高度：802px可用，扣除页眉页脚等(51px)，设为精准的 745px
        const double maxPageHeight = 745.0; 

        while (currentWordIdx < words.length) {
          int count = 1;
          while (currentWordIdx + count <= words.length) {
            final List<WordWrapper> candidateWords =
                words.sublist(currentWordIdx, currentWordIdx + count);

            double totalHeight = 0;
            for (var w in candidateWords) {
              totalHeight += _estimateWordHeight(w.word, false, includePronounce);
            }

            if (totalHeight <= maxPageHeight) {
              count++;
            } else {
              break;
            }
          }

          final int finalCount = count > 1 ? count - 1 : 1;
          pagesData.add(words.sublist(currentWordIdx, currentWordIdx + finalCount));
          currentWordIdx += finalCount;
        }
      }

      // 3. 构建排版渲染页面
      final int totalPages = pagesData.length;
      int pageStartGlobalIdx = 0; // 全局绝对序列计数器

      for (int pageIndex = 0; pageIndex < totalPages; pageIndex++) {
        final List<WordWrapper> pageWords = pagesData[pageIndex];
        final int startIdx = pageStartGlobalIdx;

        if (isDoubleColumn) {
          // 将当前页的单词均分为左右两列
          final int midPoint = (pageWords.length / 2).ceil();
          final List<WordWrapper> leftColWords = pageWords.sublist(0, midPoint);
          final List<WordWrapper> rightColWords = pageWords.sublist(midPoint);

          pdfDoc.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 15),
              build: (pw.Context pwContext) {
                return pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildHeader(title, pageIndex + 1, totalPages, exportMode, true),
                    pw.SizedBox(height: 10),
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
                    pw.SizedBox(height: 6),
                    _buildFooter(pageIndex + 1, totalPages),
                  ],
                );
              },
            ),
          );
        } else {
          // 单栏排版
          pdfDoc.addPage(
            pw.Page(
              pageFormat: PdfPageFormat.a4,
              margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 20),
              build: (pw.Context pwContext) {
                return pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _buildHeader(title, pageIndex + 1, totalPages, exportMode, false),
                    pw.SizedBox(height: 10),
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
                    pw.SizedBox(height: 6),
                    _buildFooter(pageIndex + 1, totalPages),
                  ],
                );
              },
            ),
          );
        }

        pageStartGlobalIdx += pageWords.length;
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

  /// 构建单个单词的行 (引入斑马线效果提升视线追踪体验)
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

    // 不再使用固定高度限制（maxHeight），让高度可以自适应折行撑开，防止折行重叠
    final pw.BoxConstraints constraints = isDoubleColumn
        ? const pw.BoxConstraints(minHeight: 22)
        : const pw.BoxConstraints(minHeight: 24);

    return pw.Container(
      constraints: constraints,
      alignment: pw.Alignment.centerLeft,
      padding: const pw.EdgeInsets.symmetric(horizontal: 4), // 加上水平内边距让斑马线效果左右收缩更美观
      decoration: pw.BoxDecoration(
        // 斑马线：奇数行渲染极其浅雅的青蓝色，与页眉深青色呼应
        color: displayNum % 2 == 1 ? PdfColors.cyan50 : null,
        border: const pw.Border(
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
                    _formatMeaningForPdf(word.getMeaningStr()), // 格式化并在分号、逗号后强制加上空格，让 PDF 原生引擎自由换行折行
                    style: const pw.TextStyle(
                      fontSize: 8.5,
                      color: PdfColors.grey800,
                    ),
                    maxLines: isDoubleColumn ? 2 : null, // 关键：双栏模式最多只支持折行 2 行，彻底防止无限折行抢占空间挤掉后面单词；单栏无限折行
                  ),
          ),
        ],
      ),
    );
  }

  /// 格式化中文释义字串，通过在标点（分号、逗号）后面补足半角空格来提供 PDF 引擎的原生分词折行依据
  /// 彻底废弃 \u200B (零宽空格)，避开了中文字体库不支持该 glyph 导致的渲染乱码
  static String _formatMeaningForPdf(String text) {
    if (text.isEmpty) return text;
    return text
        .replaceAll(RegExp(r'[;；]+'), '； ')
        .replaceAll(RegExp(r'[,，]+'), '， ')
        .trim();
  }
}
