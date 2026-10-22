import 'package:nnbdc/api/enum.dart';
import 'package:nnbdc/util/platform_util.dart';

/// 答题方式：写（键盘打字）、说（开口）、选（四选一）。
///
/// 三档都摆在答题卡右上角，用户想用哪种就切哪种，切完按设备记住
/// （见 `BdcNotifier.updateAnswerMode`），换词不必再点第二次。
enum AnswerMode {
  write('写'),
  speak('说'),
  choose('选');

  const AnswerMode(this.label);

  /// 答题卡上那个切换按钮上的一个字
  final String label;

  /// 从本地存储里存的名字还原，认不出来返回 null（调用方自行回落默认档）。
  static AnswerMode? fromName(Object? name) {
    if (name is! String) return null;
    for (final AnswerMode mode in AnswerMode.values) {
      if (mode.name == name) return mode;
    }
    return null;
  }
}

/// 每个环节有哪些答题方式 —— 全项目唯一一份判据。
///
/// - 单词环节：写 + 选恒在，平台认这门语言的语音时才有「说」。
/// - 例句环节：只有「说」「选」。例句没有「写」是定死的决定：整句打字要按
///   另一套判分口径（60 分 + 核心词命中）去比，和"按住说出来"不是一杆秤。
/// - 单词列表环节没有答题，档位只为让页面有个合法值。
class AnswerModes {
  /// 这个环节的语音答题能不能用（平台支持 + 环节本身有对应的说模式）。
  static bool asrAvailableFor(String? studyStep) {
    if (!PlatformUtils.isAsrSupported()) return false;
    if (studyStep == StudyStep.ch2En.json ||
        studyStep == StudyStep.chSentence2En.json) {
      return PlatformUtils.isEnglishAsrSupported();
    }
    return studyStep == StudyStep.en2Ch.json ||
        studyStep == StudyStep.enSentence2Ch.json;
  }

  static bool isSentenceStep(String? studyStep) =>
      studyStep == StudyStep.enSentence2Ch.json ||
      studyStep == StudyStep.chSentence2En.json;

  /// 答题卡上有哪几档，顺序就是界面上从左到右的顺序。
  static List<AnswerMode> forStep(String? studyStep) {
    final bool speak = asrAvailableFor(studyStep);
    if (isSentenceStep(studyStep)) {
      return <AnswerMode>[if (speak) AnswerMode.speak, AnswerMode.choose];
    }
    return <AnswerMode>[
      AnswerMode.write,
      if (speak) AnswerMode.speak,
      AnswerMode.choose,
    ];
  }

  /// 第一次进来落在哪一档：能说就说（与老版本一致），说不了就落在第一档。
  static AnswerMode defaultFor(String? studyStep) {
    if (asrAvailableFor(studyStep)) return AnswerMode.speak;
    return forStep(studyStep).first;
  }

  /// 把用户存的偏好夹进这个环节真正有的档里（环节换了、平台变了都不许落到不存在的档）。
  static AnswerMode coerce(String? studyStep, AnswerMode? preferred) {
    final List<AnswerMode> modes = forStep(studyStep);
    if (preferred != null && modes.contains(preferred)) return preferred;
    return defaultFor(studyStep);
  }

  /// 某一档在答题卡上是第几档（TabController 的唯一换算入口）。
  static int indexOf(String? studyStep, AnswerMode mode) {
    final List<AnswerMode> modes = forStep(studyStep);
    final int index = modes.indexOf(mode);
    return index < 0 ? modes.length - 1 : index;
  }
}
