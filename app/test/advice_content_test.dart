import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/util/advice_content.dart';

/// 客服会话消息正文的解析规则：一条消息 = 纯文字 + 可选的图片名列表。
///
/// 这些断言直接对着服务端 MsgBo.appendImageFiles 写出来的格式，
/// 两端任何一边改了写法都会在这里失败。
void main() {
  group('AdviceContent 解析', () {
    test('没有图片时原样返回正文', () {
      const content = '希望单词列表支持乱序播放';
      expect(AdviceContent.text(content), content);
      expect(AdviceContent.imageFiles(content), isEmpty);
      expect(AdviceContent.preview(content), content);
    });

    test('剥掉图片标记只留用户说的话', () {
      const content = '打卡少了一天\n【报错图片】["advice/u_1_1699999999999.jpg"]';
      expect(AdviceContent.text(content), '打卡少了一天');
      expect(AdviceContent.imageFiles(content), ['advice/u_1_1699999999999.jpg']);
    });

    test('多张图片按顺序解析', () {
      const content =
          '看这两个截图\n【报错图片】["advice/a.jpg","advice/b.jpg","advice/c.jpg"]';
      final images = AdviceContent.imageFiles(content);
      expect(images.length, 3);
      expect(images.first, 'advice/a.jpg');
      expect(images.last, 'advice/c.jpg');
    });

    test('只发截图没有正文时，标记前为空', () {
      const content = '【截图】\n【报错图片】["advice/a.jpg"]';
      expect(AdviceContent.text(content), '【截图】');
      expect(AdviceContent.imageFiles(content).length, 1);
    });

    test('标记后面不是合法 JSON 时不吞掉正文，也不抛异常', () {
      const content = '内容\n【报错图片】[坏掉的写法';
      expect(AdviceContent.text(content), '内容');
      expect(AdviceContent.imageFiles(content), isEmpty);
    });

    test('图片地址按目录拼接；历史数据只有文件名时落到 word 目录', () {
      expect(AdviceContent.imageUrl('advice/a.jpg'), contains('/img/advice/a.jpg'));
      expect(AdviceContent.imageUrl('a.jpg'), contains('/img/word/a.jpg'));
    });
  });

  group('AdviceContent 预览文案', () {
    test('有图有字时前缀标注图片', () {
      const content = '这是问题\n【报错图片】["advice/a.jpg"]';
      expect(AdviceContent.preview(content), '[图片] 这是问题');
    });

    test('只有图时显示图片占位', () {
      const content = '【报错图片】["advice/a.jpg"]';
      expect(AdviceContent.preview(content), '[图片]');
    });

    test('长文本被截断且换行压成一行', () {
      final content = '${'很长的一句话' * 12}\n还有第二行';
      final preview = AdviceContent.preview(content, maxLength: 20);
      expect(preview.length, lessThanOrEqualTo(21));
      expect(preview.contains('\n'), isFalse);
      expect(preview.endsWith('…'), isTrue);
    });
  });
}
