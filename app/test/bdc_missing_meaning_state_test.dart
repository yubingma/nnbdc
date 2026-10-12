import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/bo/word_bo.dart';
import 'package:nnbdc/page/bdc/providers/bdc_state.dart';
import 'package:nnbdc/page/bdc/providers/bdc_state_ui_signature.dart';

/// 学习页要能按错误种类切界面：`loadErrorCause` 必须随 `copyWith` 传递，
/// 刷新签名必须能分辨「通用释义缺失」与其它错误，否则引导面板不会出现。
void main() {
  test('loadErrorCause 随 copyWith 传递与清空', () {
    const s = BdcState();
    final error = MissingCommonMeaningException('word_abcdef', 'apple');

    final failed = s.copyWith(loadError: error.toString(), loadErrorCause: error);
    expect(failed.loadErrorCause, same(error));
    expect(failed.loadError, contains('apple'));

    final recovered = failed.copyWith(loadError: null, loadErrorCause: null);
    expect(recovered.loadErrorCause, isNull);
    expect(recovered.loadError, isNull);
  });

  test('刷新签名能分辨「通用释义缺失」与普通错误', () {
    final error = MissingCommonMeaningException('word_abcdef', 'apple');
    final missing = BdcStateUiSignature(BdcState(loadError: error.toString(), loadErrorCause: error));
    final other = BdcStateUiSignature(const BdcState(loadError: '网络异常，请稍后重试'));

    expect(missing.isMissingCommonMeaningError, isTrue);
    expect(other.isMissingCommonMeaningError, isFalse);
    expect(missing == other, isFalse, reason: '错误页种类不同必须触发学习页重建');
  });
}
