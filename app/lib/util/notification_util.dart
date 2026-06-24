import 'dart:math';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:nnbdc/db/db.dart';
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
      final info = await FlutterTimezone.getLocalTimezone();
      String timeZoneInfo = info.toString();
      
      // Handle formatting like: "TimezoneInfo(Asia/Shanghai, (locale:...))" on macOS
      if (timeZoneInfo.startsWith('TimezoneInfo(')) {
        final match = RegExp(r'TimezoneInfo\(([^,]+),').firstMatch(timeZoneInfo);
        if (match != null && match.groupCount >= 1) {
          timeZoneInfo = match.group(1)!.trim();
        }
      }
      
      tz.setLocalLocation(tz.getLocation(timeZoneInfo));

      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('ic_launcher');

      const DarwinInitializationSettings initializationSettingsDarwin =
          DarwinInitializationSettings(
        requestSoundPermission: true,
        requestBadgePermission: true,
        requestAlertPermission: true,
      );

      const InitializationSettings initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsDarwin,
        macOS: initializationSettingsDarwin,
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
      macOS: DarwinNotificationDetails(),
    );

    String messageBody = _getReminderMessage(user);

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
        title: Global.appName,
        body: messageBody,
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

  static String _getReminderMessage(User? user) {
    final random = Random();
    
    // 如果无法获取用户信息，返回通用轻量型文案
    if (user == null) {
      final generalMsgs = [
        '刚开始最关键，3分钟就够了',
        '已经帮你选好单词了，点开就能学',
        '别等明天，现在开始更容易坚持',
      ];
      return generalMsgs[random.nextInt(generalMsgs.length)];
    }
    
    // 优先使用连续打卡天数，如果没有则使用已学习天数
    int currentDay = user.continuousDakaDayCount > 0 
        ? user.continuousDakaDayCount 
        : user.learnedDays;

    if (currentDay == 0) {
      final msgs = [
        '刚开始最关键，3分钟就够了',
        '已经帮你选好单词了，点开就能学',
        '别等明天，现在开始更容易坚持',
      ];
      return msgs[random.nextInt(msgs.length)];
    } else if (currentDay == 1 || currentDay == 2) {
      final msgs = [
        '你已经开始坚持了，别断在第${currentDay + 1}天',
        '很多人都卡在这里，你已经超过他们了',
        '今天完成，你就领先80%的用户',
      ];
      return msgs[random.nextInt(msgs.length)];
    } else if (currentDay >= 3 && currentDay <= 5) {
      final msgs = [
        '再不学，打卡记录就要断了',
        '已经坚持$currentDay天，现在放弃最亏',
        '今天不学 = 前面全白费',
        '你差一点就养成习惯了',
      ];
      return msgs[random.nextInt(msgs.length)];
    } else if (currentDay == 6 || currentDay == 7) {
      final msgs = [
        '再坚持1天，你就进入少数坚持下来的人了',
        '7天习惯马上达成，别在最后放弃',
        '你已经超过90%的用户',
      ];
      return msgs[random.nextInt(msgs.length)];
    } else {
      // 大于7天，三套方案随机转
      // A：损失型（断打卡记录）
      // B：成就型（超过别人）
      // C：轻量型（3分钟就够）
      final msgs = [
        '辛辛苦苦坚持了 $currentDay 天，千万别在这里断了！',
        '今天不学 = 前面全白费，花几分钟保住打卡天数！',
        '你已经坚持$currentDay天，现在放弃最亏！',
        '你已经进入极少数坚持下来的人了，继续保持！',
        '今天完成，继续领先95%的用户！',
        '不积跬步无以至千里，每天3分钟就够了！',
      ];
      return msgs[random.nextInt(msgs.length)];
    }
  }
}
