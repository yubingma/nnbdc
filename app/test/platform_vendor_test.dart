import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/util/platform_util.dart';

void main() {
  group('Android 厂商归并', () {
    test('华为与荣耀各自独立', () {
      expect(
          PlatformUtils.normalizeAndroidVendor('HUAWEI', 'HUAWEI'), 'Huawei');
      expect(PlatformUtils.normalizeAndroidVendor('HONOR', 'HUAWEI'), 'Honor');
    });

    test('小米子品牌归并到 Xiaomi', () {
      expect(
          PlatformUtils.normalizeAndroidVendor('Xiaomi', 'Xiaomi'), 'Xiaomi');
      expect(PlatformUtils.normalizeAndroidVendor('Redmi', 'Xiaomi'), 'Xiaomi');
      expect(PlatformUtils.normalizeAndroidVendor('POCO', 'Xiaomi'), 'Xiaomi');
    });

    test('OPPO 与 vivo 子品牌归并', () {
      expect(PlatformUtils.normalizeAndroidVendor('OPPO', 'OPPO'), 'OPPO');
      expect(PlatformUtils.normalizeAndroidVendor('OnePlus', 'OPPO'), 'OPPO');
      expect(PlatformUtils.normalizeAndroidVendor('realme', 'OPPO'), 'OPPO');
      expect(PlatformUtils.normalizeAndroidVendor('vivo', 'vivo'), 'vivo');
      expect(PlatformUtils.normalizeAndroidVendor('iQOO', 'vivo'), 'vivo');
    });

    test('未登记的厂商保留原名并统一首字母大写', () {
      expect(PlatformUtils.normalizeAndroidVendor('samsung', 'samsung'),
          'Samsung');
      expect(
          PlatformUtils.normalizeAndroidVendor('google', 'Google'), 'Google');
    });

    test('品牌缺失时按厂商回退，两者都缺失返回 null', () {
      expect(PlatformUtils.normalizeAndroidVendor(null, 'HONOR'), 'Honor');
      expect(PlatformUtils.normalizeAndroidVendor('', '  '), isNull);
    });
  });
}
