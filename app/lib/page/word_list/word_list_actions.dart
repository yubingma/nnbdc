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

  /// 某行左滑露出的操作面板变化：内容区右侧需要让出的宽度（0 = 收起）。
  ///
  /// 手写面板打开时画布铺满内容区，露出的「掌握 / 详情」等按钮大半压在画布下面点不到；
  /// 页面据此把画布和蒙版一起收窄，让整块面板露出来。[token] 区分是哪一行
  /// （同一时刻可能不止一行处于打开状态，页面按最大宽度让位）。
  void onSlideActionsExposed(Object token, double exposedWidth) {}
}
