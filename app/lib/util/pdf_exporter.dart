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

  /// 估算单个单词在指定排版下的物理高度，支持多词性换行符(\n)切割与加权长度折行预测
  static double _estimateWordHeight(WordVo word, bool isDoubleColumn, bool includePronounce) {
    // 基础高度 (单行最小高度 constraints)
    // 经过高精度排版测算，由于字体 Bounding Box 及 Baseline 对齐等物理占用，双栏单行物理基准高度约为 28pt，单栏约为 32pt
    final double baseHeight = isDoubleColumn ? 28.0 : 32.0;
    // 多行文字的增量行高 (8.5号字在 leading 约束下折行后，实际只增大约 8 像素高度)
    final double lineIncrement = 8.0;

    final String meaningText = _formatMeaningForPdf(word.getMeaningStr());
    if (meaningText.isEmpty) {
      return baseHeight;
    }

    // 1. 先用换行符拆分出所有的独立释义行，并在数据源级别硬截断，确保高度预测与渲染 100% 对齐
    List<String> lines = meaningText.split('\n');
    final int maxAllowedLines = isDoubleColumn ? 6 : 6; // 双栏也放宽至 6 行，与单栏完全一致，确保词性不丢失！
    if (lines.length > maxAllowedLines) {
      lines = lines.sublist(0, maxAllowedLines);
    }
    int totalEstimatedLines = 0;

    for (final line in lines) {
      if (line.trim().isEmpty) continue;

      // 2. 对每个独立子行单独计算中英文加权长度，精准估算是否会发生容器边界折行
      double weightedLength = 0.0;
      for (int i = 0; i < line.length; i++) {
        int charCode = line.codeUnitAt(i);
        if (charCode > 127) {
          weightedLength += 1.0;
        } else {
          weightedLength += 0.5;
        }
      }

      int lineEstimatedLines = 1;
      if (isDoubleColumn) {
        // 双栏下可用中文宽度约 91.6px，8.5号中文字体下能容纳的加权字符长度临界值为 10.5
        if (weightedLength > 10.5) {
          lineEstimatedLines = (weightedLength / 10.5).ceil(); // 动态计算双栏折行数，彻底消除写死最多 2 行的高度误差
        }
      } else {
        // 单栏下可用中文宽度约 248px，能容纳的加权字符长度大约为 29.0
        if (weightedLength > 29.0) {
          lineEstimatedLines = (weightedLength / 29.0).ceil();
        }
      }
      totalEstimatedLines += lineEstimatedLines;
    }

    // 3. 对应排版渲染引擎的限制进行物理封顶
    if (isDoubleColumn) {
      if (totalEstimatedLines > 6) totalEstimatedLines = 6; // 双栏最大限制放宽至 6 行，完美容纳 3 个词性折行后的极限高度
    } else {
      if (totalEstimatedLines > 12) totalEstimatedLines = 12; // 单栏最大限制放宽至 12 行，完美容纳 6 个词性折行后的极限高度
    }

    return baseHeight + (totalEstimatedLines - 1) * lineIncrement;
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
      // 1. 同时加载中文字体 and 西文字体，防止中文乱码 and 音标特殊字符乱码
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
      // 不管是 classic 还是 meaningDictation 模式，由于我们采用了同等中文高度隐形占位，两者高度与切页结果 100% 对齐一致
      final List<List<WordWrapper>> pagesData = [];
      int currentWordIdx = 0;

      if (isDoubleColumn) {
        // 双栏最大安全可用主体高度：812px物理总高，扣除页眉页脚等非主体部分固定开销(51px)，直接顶满至 761px 极限空间
        const double maxPageHeight = 761.0; 

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
        // 单栏最大安全可用主体高度：802px物理总高，扣除页眉页脚等固定开销(51px)，直接顶满至 751px 极限空间
        const double maxPageHeight = 751.0; 

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
          // 将当前页 of 单词均分为左右两列
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

  /// 智能构建中文释义区域的富文本渲染（自测模式下只保留词性，且后面的释义生成精准下划线）
  static pw.Widget _buildMeaningTextWithPos(
    String meaningStr,
    PdfExportMode mode,
    PdfColor rowBgColor,
    bool isDoubleColumn,
  ) {
    final String formatted = _formatMeaningForPdf(meaningStr);
    List<String> lines = formatted.split('\n');

    // 在数据源级别限制词性行数，避免在 PDF 库中使用 maxLines 触发排版截断渲染 Bug
    final int maxAllowedLines = isDoubleColumn ? 6 : 6; // 双栏也放宽至 6 行，与单栏完全一致
    if (lines.length > maxAllowedLines) {
      lines = lines.sublist(0, maxAllowedLines);
    }

    final List<pw.InlineSpan> lineSpans = [];

    // 正则匹配句首的词性缩写（如 n., vt., vi., adj. 等，包含可选空格）
    final RegExp posRegExp = RegExp(r'^([a-zA-Z]+\.\s*)');

    for (int i = 0; i < lines.length; i++) {
      final String line = lines[i];
      if (line.trim().isEmpty) continue;

      final Match? match = posRegExp.firstMatch(line);
      String pos = '';
      String meaning = line;

      if (match != null) {
        pos = match.group(1) ?? '';
        meaning = line.substring(pos.length);
      }

      if (mode == PdfExportMode.meaningDictation) {
        // 释义自测模式：词性以灰色常规字体正常显示，中文释义以背景色完美物理隐藏并带下划线
        if (pos.isNotEmpty) {
          lineSpans.add(
            pw.TextSpan(
              text: pos,
              style: const pw.TextStyle(
                fontSize: 8.5,
                color: PdfColors.grey700,
              ),
            ),
          );
        }
        lineSpans.add(
          pw.TextSpan(
            text: meaning,
            style: pw.TextStyle(
              fontSize: 8.5,
              color: rowBgColor, // 100% 与背景融为一体
              decoration: pw.TextDecoration.underline,
              decorationColor: PdfColors.grey400,
              decorationStyle: pw.TextDecorationStyle.solid,
            ),
          ),
        );
      } else {
        // 中英对照经典模式：全文显示
        lineSpans.add(
          pw.TextSpan(
            text: line,
            style: const pw.TextStyle(
              fontSize: 8.5,
              color: PdfColors.grey800,
            ),
          ),
        );
      }

      if (i < lines.length - 1) {
        lineSpans.add(const pw.TextSpan(text: '\n'));
      }
    }

    return pw.RichText(
      text: pw.TextSpan(children: lineSpans),
      maxLines: null, // 废弃 maxLines 限制，改用上述 lines 截断，避开 pdf 库的 layout Bug
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

    final double estimatedHeight = _estimateWordHeight(word, isDoubleColumn, includePronounce);

    final bool isOdd = displayNum % 2 == 1;
    final PdfColor rowBgColor = isOdd ? PdfColors.cyan50 : PdfColors.white;

    return pw.Container(
      height: estimatedHeight, // 显式指定行高，彻底避开 flex 多层嵌套下的高度塌陷与重叠 Bug
      alignment: pw.Alignment.centerLeft,
      padding: const pw.EdgeInsets.symmetric(horizontal: 4), // 加上水平内边距让斑马线效果左右收缩更美观
      decoration: pw.BoxDecoration(
        // 斑马线：奇数行渲染极其浅雅的青蓝色，与页眉深青色呼应
        color: isOdd ? PdfColors.cyan50 : null,
        border: const pw.Border(
          bottom: pw.BorderSide(
            width: 0.3,
            color: PdfColors.grey300,
            style: pw.BorderStyle.dashed,
          ),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
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

          // 中文释义 或 填空手写下划线
          pw.Expanded(
            child: _buildMeaningTextWithPos(
              word.getMeaningStr(),
              mode,
              rowBgColor,
              isDoubleColumn,
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
