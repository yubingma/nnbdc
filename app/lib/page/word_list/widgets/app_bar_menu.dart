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
        Icons.more_vert,
        color: Colors.white,
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
      return PopupMenuItem<String>(
        value: choice,
        child: Container(
          decoration: BoxDecoration(
            color: _isSelected(choice) ? const Color(0xFF0097A7).withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Icon(
                _getMenuIcon(choice),
                size: 20,
                color: _isSelected(choice) ? const Color(0xFF0097A7) : (isDarkMode ? Colors.white : Colors.grey[700]),
              ),
              const SizedBox(width: 8),
              Text(
                choice,
                style: TextStyle(
                  color: _isSelected(choice) ? const Color(0xFF0097A7) : (isDarkMode ? Colors.white : Colors.grey[700]),
                  fontWeight: _isSelected(choice) ? FontWeight.w600 : FontWeight.normal,
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
        return Icons.translate;
      case menuWriteSpell:
        return Icons.edit;
      default:
        return Icons.help_outline;
    }
  }
}
