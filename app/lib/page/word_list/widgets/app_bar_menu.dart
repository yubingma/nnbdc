import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../api/enum.dart';
import '../../../state.dart';

class WordListAppBarMenu extends StatelessWidget {
  final WordListStudyMode studyMode;
  final bool isAsrSupported;
  final bool isEnglishAsrSupported;
  final Function(String) onSelected;

  const WordListAppBarMenu({
    super.key,
    required this.studyMode,
    required this.isAsrSupported,
    required this.isEnglishAsrSupported,
    required this.onSelected,
  });

  static const String menuWordList = '浏览';
  static const String menuWalkman = '随身听';
  static const String menuSpeakChinese = '背中文';
  static const String menuSpeakEnglish = '背英文';
  static const String menuTranslateSentence = '翻译例句';
  static const String menuWriteSpell = '默写';

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.read<DarkMode>().isDarkMode;

    return PopupMenuButton<String>(
      icon: const Icon(
        Icons.more_vert_rounded,
        color: Colors.white,
      ),
      color: isDarkMode ? const Color(0xFF131E1C) : Colors.white,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: isDarkMode ? 0.4 : 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDarkMode ? Colors.white12 : const Color(0xFFE1EFEA),
          width: 1,
        ),
      ),
      constraints: const BoxConstraints(
        minWidth: 148,
        maxWidth: 175,
      ),
      onSelected: onSelected,
      itemBuilder: (BuildContext context) {
        return _buildMenuItems(isDarkMode);
      },
    );
  }

  List<PopupMenuEntry<String>> _buildMenuItems(bool isDarkMode) {
    List<String> menus = [
      menuWordList,
    ];

    if (isAsrSupported) {
      menus.add(menuSpeakChinese);
    }
    if (isEnglishAsrSupported) {
      menus.add(menuSpeakEnglish);
    }
    if (isAsrSupported) {
      menus.add(menuTranslateSentence);
    }
    menus.add(menuWriteSpell);

    menus.add(menuWalkman);

    return menus.map((String choice) {
      final isSelected = _isSelected(choice);
      return PopupMenuItem<String>(
        value: choice,
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Container(
          decoration: BoxDecoration(
            color: isSelected
                ? (isDarkMode
                    ? const Color(0xFF192C27)
                    : const Color(0xFFEDF8F3))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: isSelected
                ? Border.all(
                    color: isDarkMode
                        ? Colors.white12
                        : const Color(0xFFD1EADE),
                    width: 1,
                  )
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            children: [
              Icon(
                _getMenuIcon(choice),
                size: 18,
                color: isSelected
                    ? (isDarkMode
                        ? const Color(0xFF2CD88F)
                        : const Color(0xFF18BA7C))
                    : (isDarkMode
                        ? const Color(0xFF8EA8A3)
                        : const Color(0xFF5B7A75)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  choice,
                  style: TextStyle(
                    fontSize: 13,
                    color: isSelected
                        ? (isDarkMode
                            ? const Color(0xFF2CD88F)
                            : const Color(0xFF18BA7C))
                        : (isDarkMode
                            ? const Color(0xFFEAF7F4)
                            : const Color(0xFF152724)),
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  bool _isSelected(String choice) {
    switch (choice) {
      case menuWordList:
        return studyMode == WordListStudyMode.list;
      case menuSpeakChinese:
        return studyMode == WordListStudyMode.speakChinese;
      case menuSpeakEnglish:
        return studyMode == WordListStudyMode.speakEnglish;
      case menuTranslateSentence:
        return studyMode == WordListStudyMode.translateSentence;
      case menuWriteSpell:
        return studyMode == WordListStudyMode.dictation;
      default:
        return false;
    }
  }

  IconData _getMenuIcon(String choice) {
    switch (choice) {
      case menuWordList:
        return Icons.list_alt;
      case menuWalkman:
        return Icons.headphones;
      case menuSpeakChinese:
      case menuSpeakEnglish:
        return Icons.record_voice_over;
      case menuTranslateSentence:
        return Icons.hearing;
      case menuWriteSpell:
        return Icons.edit;
      default:
        return Icons.help_outline;
    }
  }
}
