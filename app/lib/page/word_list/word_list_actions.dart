import 'package:nnbdc/util/word_util.dart';

/// 定义词表页面中单词项的交互操作回调接口
mixin WordListActionHandler {
  void onWordTap(WordWrapper word, int index);
  void onWordLongPress(WordWrapper word, int index);
  void onMasterBtnPressed(WordWrapper word, int index);
  void onUnmasterBtnPressed(WordWrapper word, int index);
  void onDelBtnPressed(WordWrapper word, int index);
  void onEditBtnPressed(WordWrapper word, int index);
  void onResetHint(WordWrapper word);
  void onGiveHint(WordWrapper word);
  void onToggleAnswer(WordWrapper word, int index);
  void onHandwritingPressed(WordWrapper word, int index);
  void onSpellChanged(WordWrapper word, int index, String value);
}
