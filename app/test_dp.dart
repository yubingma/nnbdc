import 'package:nnbdc/util/pinyin.dart';

void main() {
  String target = '女人';
  String uInput = '欺负女野蛮人的';
  
  bool result = fuzzyChineseContains(uInput, target);
  print('Result: $result');
}
