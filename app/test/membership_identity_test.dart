import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/vo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/subscription_util.dart';

/// 会员身份判定测试。
///
/// 关键区分：非 iOS 平台没有会员付费入口，[SubscriptionUtil.isPremium] 对所有人放行（功能不受限），
/// 但「放行」不等于「拥有会员身份」；[SubscriptionUtil.hasMembership] 只看真实的会员字段，
/// 「我的」页面据此决定是否展示会员信息。
User _buildUser({
  bool isAdmin = false,
  bool isSuperAdmin = false,
  bool premiumOverrideEnabled = false,
  String? premiumOverrideDuration,
  DateTime? premiumOverrideUpdateTime,
  DateTime? vipExpireDate,
}) {
  final now = AppClock.now();
  return User(
    id: 'u1',
    userName: 'tester',
    wordsPerDay: 20,
    gameScore: 0,
    dakaScore: 0,
    learnedDays: 0,
    dakaDayCount: 0,
    continuousDakaDayCount: 0,
    maxContinuousDakaDayCount: 0,
    masteredWordsCount: 0,
    cowDung: 0,
    throwDiceChance: 0,
    todayStudyStarted: false,
    learningFinished: false,
    isAdmin: isAdmin,
    isSuperAdmin: isSuperAdmin,
    vipExpireDate: vipExpireDate,
    premiumOverrideEnabled: premiumOverrideEnabled,
    premiumOverrideDuration: premiumOverrideDuration,
    premiumOverrideUpdateTime: premiumOverrideUpdateTime,
    createTime: now,
    updateTime: now,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final fixedNow = DateTime(2026, 10, 21, 12);

  setUp(() {
    AppClock.setClock(FakeClock(fixedNow));
    Global.clearUserCache();
  });

  tearDown(() {
    AppClock.reset();
    Global.clearUserCache();
  });

  group('会员身份判定', () {
    test('未登录时没有会员身份', () {
      expect(SubscriptionUtil.hasMembership(), isFalse);
    });

    test('普通用户没有会员身份，但非 iOS 平台仍享有会员能力', () {
      Global.updateUserCache(_buildUser());

      expect(SubscriptionUtil.hasMembership(), isFalse);
      // 测试机为 macOS（非 iOS），验证「功能放行」与「会员身份」确实是两件事
      expect(SubscriptionUtil.isPremium(), isTrue);
    });

    test('管理员视为拥有会员身份', () {
      Global.updateUserCache(_buildUser(isAdmin: true));
      expect(SubscriptionUtil.hasMembership(), isTrue);

      Global.updateUserCache(_buildUser(isSuperAdmin: true));
      expect(SubscriptionUtil.hasMembership(), isTrue);
    });

    test('活动码兑换的限时会员在有效期内拥有会员身份', () {
      Global.updateUserCache(_buildUser(
        premiumOverrideEnabled: true,
        premiumOverrideDuration: '30天',
        premiumOverrideUpdateTime: fixedNow.subtract(const Duration(days: 29)),
      ));

      expect(SubscriptionUtil.hasMembership(), isTrue);
    });

    test('活动码兑换的限时会员过期后不再拥有会员身份', () {
      Global.updateUserCache(_buildUser(
        premiumOverrideEnabled: true,
        premiumOverrideDuration: '30天',
        premiumOverrideUpdateTime: fixedNow.subtract(const Duration(days: 31)),
      ));

      expect(SubscriptionUtil.hasMembership(), isFalse);
    });

    test('永久会员（未设置时长）拥有会员身份', () {
      Global.updateUserCache(_buildUser(
        premiumOverrideEnabled: true,
        premiumOverrideUpdateTime: fixedNow.subtract(const Duration(days: 365)),
      ));

      expect(SubscriptionUtil.hasMembership(), isTrue);
    });

    test('通用会员有效期内拥有会员身份', () {
      Global.updateUserCache(_buildUser(
        vipExpireDate: fixedNow.add(const Duration(days: 10)),
      ));
      expect(SubscriptionUtil.hasMembership(), isTrue);

      Global.updateUserCache(_buildUser(
        vipExpireDate: fixedNow.subtract(const Duration(days: 1)),
      ));
      expect(SubscriptionUtil.hasMembership(), isFalse);
    });

    test('活动码兑换的强制会员走完整链路后仍被识别，页面展示字段齐全', () {
      // 与生产数据一致：premium_override_enabled=true、duration 为空（永久）、update_time 有值
      final redeemTime = fixedNow.subtract(const Duration(days: 10));
      final vo = UserVo('u1', 'tester')
        ..continuousDakaDayCount = 0
        ..cowDung = 0
        ..dakaDayCount = 0
        ..dakaScore = 0
        ..gameScore = 0
        ..inviteAwardTaken = false
        ..isAdmin = false
        ..isInputor = false
        ..isSuperAdmin = false
        ..learnedDays = 0
        ..learningFinished = false
        ..masteredWordsCount = 0
        ..maxContinuousDakaDayCount = 0
        ..throwDiceChance = 0
        ..wordsPerDay = 20
        ..isPremiumIos = false
        ..premiumOverrideEnabled = true
        ..premiumOverrideUpdateTime = redeemTime
        ..premiumOverrideReason = '兑换活动码: 我是小可爱';

      final user = userVo2User(vo);
      expect(user.premiumOverrideEnabled, isTrue);
      expect(user.premiumOverrideDuration, isNull);
      expect(user.premiumOverrideUpdateTime, redeemTime);

      Global.updateUserCache(user);
      expect(SubscriptionUtil.hasMembership(), isTrue);

      // 「我的」页面的账户类型状态条读的是 UserVo.fromUser 的结果
      final displayVo = UserVo.fromUser(user);
      expect(displayVo.premiumOverrideEnabled, isTrue);
      expect(displayVo.premiumOverrideDuration, isNull);
      expect(displayVo.premiumOverrideUpdateTime, redeemTime);
    });
  });

  // 会员能力判定与「我的」页面状态条共用这套算法，这里锁住两侧共同依赖的结果
  group('强制会员有效期计算', () {
    test('未启用时无效', () {
      final result = SubscriptionUtil.resolveForcedMembership(
        enabled: false,
        duration: null,
        updateTime: fixedNow,
      );
      expect(result.active, isFalse);
      expect(result.expireTime, isNull);
    });

    test('时长为空（活动码兑换的永久会员）时永久有效', () {
      final result = SubscriptionUtil.resolveForcedMembership(
        enabled: true,
        duration: null,
        updateTime: fixedNow.subtract(const Duration(days: 365)),
      );
      expect(result.active, isTrue);
      expect(result.expireTime, isNull);
    });

    test('限时时长在有效期内', () {
      final redeemTime = fixedNow.subtract(const Duration(days: 10));
      final result = SubscriptionUtil.resolveForcedMembership(
        enabled: true,
        duration: '30天',
        updateTime: redeemTime,
      );
      expect(result.active, isTrue);
      expect(result.expireTime, redeemTime.add(const Duration(days: 30)));
    });

    test('限时时长过期后无效', () {
      final result = SubscriptionUtil.resolveForcedMembership(
        enabled: true,
        duration: '30天',
        updateTime: fixedNow.subtract(const Duration(days: 31)),
      );
      expect(result.active, isFalse);
      expect(result.expireTime, isNotNull);
    });

    test('时长无法解析或缺少起算时间时按永久放行（与会员能力判定一致）', () {
      for (final result in [
        SubscriptionUtil.resolveForcedMembership(
          enabled: true,
          duration: '1个月',
          updateTime: fixedNow.subtract(const Duration(days: 90)),
        ),
        SubscriptionUtil.resolveForcedMembership(
          enabled: true,
          duration: '30天',
          updateTime: null,
        ),
      ]) {
        expect(result.active, isTrue);
        expect(result.expireTime, isNull);
      }
    });

    test('0 天时长立即过期', () {
      final result = SubscriptionUtil.resolveForcedMembership(
        enabled: true,
        duration: '0天',
        updateTime: fixedNow,
      );
      expect(result.active, isFalse);
    });
  });
}
