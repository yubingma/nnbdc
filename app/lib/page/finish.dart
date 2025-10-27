import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:get/get.dart';
import 'package:nnbdc/api/bo/user_bo.dart';
import 'package:nnbdc/api/bo/study_bo.dart';
import 'package:nnbdc/db/db.dart';
import 'package:nnbdc/util/toast_util.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:appcheck/appcheck.dart';

import '../api/result.dart';
import '../global.dart';
import '../util/platform_util.dart';
import 'index.dart';

class FinishPage extends StatefulWidget {
  const FinishPage({super.key});

  @override
  FinishPageState createState() {
    return FinishPageState();
  }
}

class FinishPageState extends State<FinishPage> {
  bool dataLoaded = false;
  late int cowDung;
  late Result<int> dakaResult;
  late int todayDakaScore; // 今日打卡积分（含加成）
  late int extraScore; // 打卡积分加成

  String? marketAppUrl; // 应用市场的对应Url

  static const double leftPadding = 16;
  static const double rightPadding = 16;

  @override
  void initState() {
    super.initState();

    loadData();
  }

  Future<void> loadData() async {
    // 检测手机上安装的应用市场
    if (PlatformUtils.isAndroid) {
      if (await AppCheck().isAppInstalled('com.huawei.appmarket')) {
        marketAppUrl = "appmarket://details?id=com.nn.nnbdc.android";
      } /*else if (await DeviceApps.isAppInstalled('com.xiaomi.market')) {
        marketAppUrl = "mimarket://details?id=com.nn.nnbdc.android";
      } else if (await DeviceApps.isAppInstalled('com.sec.android.app.samsungapps')) {
        marketAppUrl = "samsungapps://ProductDetail/com.nn.nnbdc.android";
      } else if (await DeviceApps.isAppInstalled('com.oppo.market')) {
        marketAppUrl = "oppomarket://details?packagename=com.nn.nnbdc.android";
      } else if (await DeviceApps.isAppInstalled('com.bbk.appstore')) {
        marketAppUrl = "vivomarket://details?id=com.nn.nnbdc.android";
      }*/
    }

    dakaResult = await StudyBo().saveDakaRecord("好好学习，天天向上");
    if (dakaResult.success) {
      var user = await UserBo().getLoggedInUser();
      await Global.setLoggedInUser(user.data!);

      // 记录用户打卡操作
      await MyDatabase.instance.userOpersDao.recordDaka(user.data!.id!, remark: "用户完成打卡，获得${dakaResult.data}积分");

      todayDakaScore = dakaResult.data!;
      extraScore = Global.getLoggedInUser()!.continuousDakaDayCount;

      var result = await StudyBo().throwDiceAndSave();
      if (result.success) {
        cowDung = result.data!;
        // 不再播放特殊声音，因为不再有翻倍机制
      } else {
        ToastUtil.error(result.msg!);
      }
    }

    setState(() {
      dataLoaded = true;
    });
  }

  Widget renderPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 200,
          child: Stack(
            children: [
              Container(
                color: Colors.green,
                width: double.infinity,
                height: double.infinity,
                child: SvgPicture.asset(
                  "assets/images/wave8.svg",
                  fit: BoxFit.fill,
                  colorFilter: const ColorFilter.mode(Colors.blue, BlendMode.srcIn),
                ),
              ),
              const Positioned(
                  top: 84,
                  right: 120,
                  child: Image(
                    image: AssetImage("assets/images/cow.png"),
                    height: 40,
                  )),

              const Positioned(
                top: 150,
                right: 10,
                child: RotationTransition(
                    turns: AlwaysStoppedAnimation(30 / 360),
                    child: Image(
                      image: AssetImage("assets/images/snails.png"),
                      height: 30,
                    )),
              ),
              // ! 0x00FFFFFF
              const Text("Assess"),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(leftPadding, 16, rightPadding, 0),
          child: dakaResult.success
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('打卡成功！\n获得积分：${todayDakaScore - extraScore} + $extraScore(连续打卡)'),
                    Text('恭喜！你得到$cowDung颗泡泡糖')
                  ],
                )
              : Text(dakaResult.msg!),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(leftPadding, 16, rightPadding, 0),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('若要复习，可前往 '),
                  ElevatedButton.icon(
                    icon: const Icon(
                      Icons.wysiwyg,
                      size: 24.0,
                      color: Colors.white,
                    ),
                    style: ElevatedButton.styleFrom(
                      foregroundColor: Colors.white, backgroundColor: Global.highlight, // foreground
                    ),
                    key: const Key('finish_word_list_btn'),
                    label: const Text('词表'),
                    onPressed: () {
                      Get.toNamed('/index', arguments: IndexPageArgs(1));
                    },
                  ),
                ],
              ),
              if (marketAppUrl != null)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('如果喜欢牛牛，那就 '),
                    ElevatedButton.icon(
                      icon: const Icon(
                        Icons.favorite_outline,
                        size: 24.0,
                        color: Colors.white,
                      ),
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.white, backgroundColor: Global.highlight, // foreground
                      ),
                      label: const Text('给个好评吧'),
                      onPressed: () {
                        launchUrl(Uri.parse(marketAppUrl!));
                      },
                    ),
                  ],
                ),
            ],
          ),
        )
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        padding: const EdgeInsets.fromLTRB(0, 0, 0, 0),
        child: (!dataLoaded) ? const Center(child: Text('')) : renderPage(),
      ),
    );
  }
}
