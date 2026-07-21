import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/util/pay_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PayManager Unit Tests', () {
    test('PaymentChannelEnum properties test', () {
      expect(PaymentChannelEnum.wechat.code, equals('WECHAT'));
      expect(PaymentChannelEnum.alipay.code, equals('ALIPAY'));
      expect(PaymentChannelEnum.appleIap.code, equals('APPLE_IAP'));
      expect(PaymentChannelEnum.huaweiIap.code, equals('HUAWEI_IAP'));
    });

    test('getAvailableChannels returns a list of channels', () async {
      final channels = await PayManager.getAvailableChannels();
      expect(channels, isA<List<PaymentChannelEnum>>());
    });
  });
}
