import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/global.dart';
import 'package:nnbdc/util/app_clock.dart';
import 'package:nnbdc/util/utils.dart';

/// 记忆守护兽的养成规则与投喂动作。
///
/// 泡泡（魔法泡泡，即 `user.cowDung`）的**发放**由打卡掷骰子负责，本类只负责**消耗**。
/// 投喂写两张表：`user_pet_state`（养成状态，端云同步）与 `user_cow_dung_log`
/// （泡泡收支流水，端云同步），后者同时充当投喂流水，不再另设投喂日志表。
class PetGameBo {
  /// 每次投喂消耗的魔法泡泡数。
  static const int feedCost = 1;

  /// 进化阶段：下标即 `user_pet_state.stage_index`，阈值是累计投喂次数。
  static const List<({String name, String asset, int threshold})> stages = [
    (name: '泡芽', asset: 'stage1_baoya_泡芽', threshold: 0),
    (name: '幼兽', asset: 'stage2_youshou_幼兽', threshold: 8),
    (name: '灵兽', asset: 'stage3_lingshou_灵兽', threshold: 30),
    (name: '守护兽', asset: 'stage4_shouhushou_守护兽', threshold: 70),
    (name: '记忆巨兽', asset: 'stage5_jiyijushou_记忆巨兽', threshold: 140),
  ];

  /// 由累计投喂次数换算进化阶段下标。
  static int stageIndexOf(int totalFeedings) {
    var index = 0;
    for (var i = 0; i < stages.length; i++) {
      if (totalFeedings >= stages[i].threshold) index = i;
    }
    return index;
  }

  /// 距离下一次进化还差多少次投喂；已满阶返回 null。
  static int? feedingsToNextStage(int totalFeedings) {
    for (final stage in stages) {
      if (totalFeedings < stage.threshold) return stage.threshold - totalFeedings;
    }
    return null;
  }

  /// 读取养成状态；从未投喂过时按初始状态返回，不写库。
  Future<UserPetState> loadState(String userId) async {
    final existing = await MyDatabase.instance.userPetStatesDao.getEntity(userId);
    if (existing != null) return existing;

    final now = AppClock.now();
    return UserPetState(
      id: Util.uuid(),
      userId: userId,
      stageIndex: 0,
      totalFeedings: 0,
      form: 'neutral',
      createTime: now,
      updateTime: now,
    );
  }

  /// 投喂一次：扣泡泡、累加进化值、必要时升阶。
  ///
  /// 返回 null 表示泡泡不足；否则返回投喂后的状态与是否发生了升阶。
  Future<({UserPetState state, bool leveledUp})?> feed() async {
    final user = Global.getLoggedInUser();
    if (user == null) return null;
    if (user.cowDung < feedCost) return null;

    final db = MyDatabase.instance;
    final before = await loadState(user.id);
    final now = AppClock.now();

    final totalFeedings = before.totalFeedings + 1;
    final stageIndex = stageIndexOf(totalFeedings);
    final after = before.copyWith(
      totalFeedings: totalFeedings,
      stageIndex: stageIndex,
      updateTime: now,
    );

    // 先扣泡泡再落养成状态：两步都在同一轮同步里，失败时以泡泡账为准更容易发现。
    await db.usersDao.saveUser(
      user.copyWith(cowDung: user.cowDung - feedCost),
      true,
    );
    await db.userPetStatesDao.saveEntity(after, true);
    await db.userCowDungLogsDao.insertEntity(
      UserCowDungLog(
        id: Util.uuid(),
        userId: user.id,
        delta: -feedCost,
        cowDung: user.cowDung - feedCost,
        theTime: now,
        reason: 'feed guardian',
        createTime: now,
        updateTime: now,
      ),
      true,
    );
    // 不写 user_oper：服务端 oper_type 是 VARCHAR(20) 的受控取值（LOGIN/START_LEARN/DAKA…），
    // 新增类型要两端同时改；而泡泡收支已由 user_cow_dung_log 完整记录，投喂不需要第二份流水。
    //
    // 重新加载内存用户，否则完成页上的泡泡数会滞后一轮。
    await Global.loadUserFromDb();

    return (state: after, leveledUp: stageIndex > before.stageIndex);
  }
}
