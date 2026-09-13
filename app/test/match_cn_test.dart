import 'package:flutter/material.dart';
import 'package:nnbdc/util/pinyin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Test fuzzyChineseContains - 字距超过上限不放过', () {
    // 字距是硬上限：匹配上的字之间最多夹 2 个字。"引的的的的诱" 用 引…诱 跨了 4 个字，
    // 是两段无关语音被 ASR 拼到一起的形态，必须拒绝。
    expect(fuzzyChineseContains("引的的的的诱", "n. 引诱"), isFalse);
  });

  test('Test fuzzyChineseContains - 字距上限内仍容错', () {
    expect(fuzzyChineseContains("引诱", "n. 引诱"), isTrue, reason: '相邻');
    expect(fuzzyChineseContains("引的诱", "n. 引诱"), isTrue, reason: '夹 1 个字');
    expect(fuzzyChineseContains("引的的诱", "n. 引诱"), isTrue, reason: '夹 2 个字');
  });

  test('Test fuzzyChineseContains - 距离越远要求的相似度越高', () {
    // 同一对音：协→习 0.925、调→到 0.800（经 diào 读音），两字平均 0.86。
    // 相邻时阈值 0.72 可过；夹 2 个字时阈值抬到 0.72+2*0.10=0.92，同一个 0.86 就不过了。
    expect(fuzzyChineseContains("习到", "n. 协调"), isTrue, reason: '相邻，0.86 > 0.72');
    expect(fuzzyChineseContains("习模式到", "n. 协调"), isFalse, reason: '夹 2 个字，0.86 < 0.92');
  });

  test('Test fuzzyChineseContains - 相邻近音窗仍算命中（噪声容错）', () {
    // 老用例 "牛以就发奖金右然" 里 以…右 跨了 4 个字，那条路已被字距上限掐断；
    // 但它仍会因相邻子串 "以就"（以→引 0.925 / 就→诱 0.800，平均 0.86）命中——
    // 这是"用户确实发出了相近的音、旁边夹了杂音"的噪声容错，与远距捞字是两件事。
    expect(fuzzyChineseContains("以就", "n. 引诱"), isTrue);
  });

  test('Test fuzzyChineseContains - 引用', () {
    String asrResult = "引用";
    String meaning = "n. 引诱";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });

  test('Test fuzzyChineseContains - phonetic similarity', () {
    String asrResult = "无穷";
    String meaning = "无球"; // Not a real word, but testing the phonetic match
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });

  test('Test fuzzyChineseContains - dissimilar phrases (non-match)', () {
    String asrResult = "有意义的";
    String meaning = "不明白的";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isFalse);
  });
  test('Test fuzzyChineseContains - 没见-媒介', () {
    String asrResult = "没见";
    String meaning = "n. 媒介";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 情况-惊慌', () {
    String asrResult = "情况";
    String meaning = "n. 惊慌";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 这都-战斗', () {
    String asrResult = "这都";
    String meaning = "n. 战斗";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 启禀-曲柄', () {
    String asrResult = "启禀";
    String meaning = "n. 曲柄";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 西-吸引', () {
    String asrResult = "西";
    String meaning = "n. 吸引";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 父也-赋予', () {
    String asrResult = "父也";
    String meaning = "n. 赋予";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 大概-大纲', () {
    String asrResult = "大概";
    String meaning = "n. 大纲";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 博取-夺取', () {
    String asrResult = "博取";
    String meaning = "n. 夺取";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 白本-版本', () {
    String asrResult = "白本";
    String meaning = "n. 版本";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 论论-论文', () {
    String asrResult = "论论";
    String meaning = "n. 论文";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 识别人-使变软', () {
    String asrResult = "识别人";
    String meaning = "n. 使变软";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 美润状-委任状', () {
    String asrResult = "美润状";
    String meaning = "n. 委任状";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 爱尔兰-爱尔兰人', () {
    String asrResult = "爱尔兰";
    String meaning = "爱尔兰人";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 打死-打扫', () {
    String asrResult = "打死";
    String meaning = "v. 打扫";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 巴苦-挖苦', () {
    String asrResult = "巴苦";
    String meaning = "v. 挖苦";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 顺利-视力', () {
    String asrResult = "顺利";
    String meaning = "n. 视力";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 下令-下列', () {
    String asrResult = "下令";
    String meaning = "n. 下列";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 毛型-模型', () {
    String asrResult = "毛型";
    String meaning = "n. 模型";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 此时-四十', () {
    String asrResult = "此时";
    String meaning = "n. 四十";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 毛饭-毛发', () {
    String asrResult = "毛饭";
    String meaning = "n. 毛发";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 大哥-大纲', () {
    String asrResult = "大哥";
    String meaning = "n. 大纲";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 挑衅-挑选', () {
    String asrResult = "挑衅";
    String meaning = "v. 挑选";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 那肉-嫩肉', () {
    String asrResult = "那肉";
    String meaning = "n. 嫩肉";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 树林-数量', () {
    String asrResult = "树林";
    String meaning = "n. 数量";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 粉-吻', () {
    String asrResult = "粉";
    String meaning = "吻";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 哟-药', () {
    String asrResult = "哟";
    String meaning = "药";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 哎哟-哎药', () {
    String asrResult = "哎哟";
    String meaning = "哎药";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 阿姨-牙医', () {
    String asrResult = "阿姨";
    String meaning = "牙医";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 此会-词汇量', () {
    String asrResult = "此会";
    String meaning = "词汇量";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });

  test('Test fuzzyChineseContains - 投放-头发', () {
    String asrResult = "投放";
    String meaning = "n. 头发";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 洋洋-洋葱', () {
    String asrResult = "洋洋";
    String meaning = "n. 洋葱";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 杨-洋葱', () {
    String asrResult = "杨";
    String meaning = "n. 洋葱";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
  test('Test fuzzyChineseContains - 么-幕', () {
    String asrResult = "么";
    String meaning = "幕";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });

  test('Test fuzzyChineseContains - 你-捏', () {
    String asrResult = "你";
    String meaning = "捏";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });

  test('Test fuzzyChineseContains - 脾-引诱 (should not match)', () {
    String asrResult = "脾";
    String meaning = "引诱";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isFalse);
  });

  test('Test fuzzyChineseContains - 有-牛', () {
    String asrResult = "有";
    String meaning = "牛";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });

  test('Test fuzzyChineseContains - 春眠不觉想处处-认出 (should not match)', () {
    String asrResult = "春眠不觉想处处";
    String meaning = "认出";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isFalse);
  });

  test('Test fuzzyChineseContains - 好的那么就加上乘法机-提神 (should not match)', () {
    String asrResult = "好的那么就加上乘法机";
    String meaning = "提神";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isFalse);
  });

  test('Test fuzzyChineseContains - 好的那么就加上乘法机-补充 (should not match)', () {
    String asrResult = "好的那么就加上乘法机";
    String meaning = "补充";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isFalse);
  });

  test('Test fuzzyChineseContains - 春眠不觉晓处处闻其鸟-树枝 (should not match)', () {
    String asrResult = "春眠不觉晓处处闻其鸟";
    String meaning = "树枝";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isFalse);
  });

  test('Test fuzzyChineseContains - sliding window for long accumulated ASR result', () {
    String asrResult = "PS R提示音不用改就用刚才你第一次生成的吧安全的安全的";
    String meaning = "adj. 安全的";
    
    bool match = fuzzyChineseContains(asrResult, meaning);
    debugPrint('~~~~~asrResult: $asrResult, meaning: $meaning, match: $match');
    expect(match, isTrue);
  });
}
