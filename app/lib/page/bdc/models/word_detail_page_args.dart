import 'package:nnbdc/api/vo.dart';

class WordDetailPageArgs {
  final WordVo word;
  final String? soundPath;
  final bool showAddButton;

  WordDetailPageArgs({
    required this.word,
    this.soundPath,
    this.showAddButton = true,
  });
}
