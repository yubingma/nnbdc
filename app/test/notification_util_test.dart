import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/util/notification_util.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockNotificationsPlatform extends FlutterLocalNotificationsPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<bool?> initialize(
    InitializationSettings? settings, {
    dynamic onDidReceiveNotificationResponse,
    dynamic onDidReceiveBackgroundNotificationResponse,
  }) async =>
      true;

  @override
  Future<void> cancel({required int id, String? tag}) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails,
    String? payload,
  }) async {}

  @override
  Future<void> zonedSchedule({
    required int id,
    String? title,
    String? body,
    required tz.TZDateTime scheduledDate,
    required NotificationDetails notificationDetails,
    AndroidScheduleMode? androidScheduleMode,
    DateTimeComponents? matchDateTimeComponents,
    String? payload,
  }) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    tz.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    FlutterLocalNotificationsPlatform.instance = MockNotificationsPlatform();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async => '.',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter_timezone'),
      (MethodCall methodCall) async => 'Asia/Shanghai',
    );
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    await NotificationUtil.init();
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
