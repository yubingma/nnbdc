// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/util/phoneme_util.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('similarity check', () async {
    print('gulty vs Good: ${await PhonemeUtil.similarity('gulty', 'Good')}');
    print('gulty seaplane vs discipline: ${await PhonemeUtil.similarity('gulty seaplane', 'discipline')}');
    print('seaplane vs discipline: ${await PhonemeUtil.similarity('seaplane', 'discipline')}');
    print('gulti vs Good: ${await PhonemeUtil.similarity('gulti', 'Good')}');
    print('gulti se vs Good: ${await PhonemeUtil.similarity('gulti se', 'Good')}');
    print('the seaplan vs discipline: ${await PhonemeUtil.similarity('the seaplan', 'discipline')}');
  });
}
