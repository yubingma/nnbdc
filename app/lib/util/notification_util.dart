import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/user_helper.dart';

class NotificationUtil {
  static final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    try {
      tz.initializeTimeZones();
      final timeZoneInfo = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timeZoneInfo.toString()));

      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      const DarwinInitializationSettings initializationSettingsIOS =
          DarwinInitializationSettings(
        requestSoundPermission: true,
        requestBadgePermission: true,
        requestAlertPermission: true,
      );

      const InitializationSettings initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsIOS,
      );

      await flutterLocalNotificationsPlugin.initialize(
        settings: initializationSettings,
      );

      Global.logger.i('NotificationUtil initialized');
    } catch (e) {
      Global.logger.e('NotificationUtil init failed: $e');
    }
  }

  static Future<void> scheduleDailyReminder() async {
    if (Global.isGuest) return;

    final user = Global.getLoggedInUser();

    const AndroidNotificationDetails androidPlatformChannelSpecifics =
        AndroidNotificationDetails(
      'daily_study_reminder_channel',
      '学习提醒',
      channelDescription: '每天定时提醒背单词',
      importance: Importance.max,
      priority: Priority.high,
    );

    const NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidPlatformChannelSpecifics,
      iOS: DarwinNotificationDetails(),
    );

    try {
      await flutterLocalNotificationsPlugin.cancel(id: 0);

      // 设置在每天晚上20:00提醒
      var now = tz.TZDateTime.now(tz.local);
      var scheduledDate = tz.TZDateTime(tz.local, now.year, now.month, now.day, 20);
      
      // 精确打击：如果用户今天已经完成了打卡学习，就直接将提醒顺延到明天
      if (user != null && UserHelper.isTodayLearningFinishedFromUser(user)) {
        Global.logger.i('NotificationUtil: 用户今日已完成学习，提醒顺延至明天20:00');
        var tomorrow = now.add(const Duration(days: 1));
        scheduledDate = tz.TZDateTime(tz.local, tomorrow.year, tomorrow.month, tomorrow.day, 20);
      } else if (scheduledDate.isBefore(now)) {
        scheduledDate = scheduledDate.add(const Duration(days: 1));
      }

      await flutterLocalNotificationsPlugin.zonedSchedule(
        id: 0,
        title: '泡泡单词',
        body: '今天的单词背了吗？快来完成今天的打卡吧！保持连胜！',
        scheduledDate: scheduledDate,
        notificationDetails: platformChannelSpecifics,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      Global.logger.i('Daily reminder scheduled at 20:00');
    } catch (e) {
      Global.logger.e('Failed to schedule daily reminder: $e');
    }
  }
}
