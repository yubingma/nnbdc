import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/util/notification_util.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => '.',
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
  });

  group('NotificationUtil 提醒设置测试', () {
    test('默认配置值应为开启，时间 20:00', () {
      expect(NotificationUtil.isReminderEnabled(), isTrue);
      expect(NotificationUtil.getReminderHour(), equals(20));
      expect(NotificationUtil.getReminderMinute(), equals(0));
      expect(NotificationUtil.getReminderTime(), equals(const TimeOfDay(hour: 20, minute: 0)));
    });

    test('更新设置后能够正确保存并读取', () async {
      await NotificationUtil.updateReminderSettings(
        enabled: false,
        hour: 8,
        minute: 30,
      );

      expect(NotificationUtil.isReminderEnabled(), isFalse);
      expect(NotificationUtil.getReminderHour(), equals(8));
      expect(NotificationUtil.getReminderMinute(), equals(30));
      expect(NotificationUtil.getReminderTime(), equals(const TimeOfDay(hour: 8, minute: 30)));
    });

    test('开启设置后能够保存新时间', () async {
      await NotificationUtil.updateReminderSettings(
        enabled: true,
        hour: 21,
        minute: 45,
      );

      expect(NotificationUtil.isReminderEnabled(), isTrue);
      expect(NotificationUtil.getReminderHour(), equals(21));
      expect(NotificationUtil.getReminderMinute(), equals(45));
      expect(NotificationUtil.getReminderTime(), equals(const TimeOfDay(hour: 21, minute: 45)));
    });
  });
}
