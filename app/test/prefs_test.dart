import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/util/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Prefs 读写与类型兼容性测试', () {
    test('模拟平台通道返回 List<Object?> 时，Prefs.read<List<String>> 与 getStringList 不应抛类型转换异常', () async {
      // 模拟底层通道返回的 List<Object?>
      SharedPreferences.setMockInitialValues({
        'test_dynamic_list': <Object?>['req_1', 'req_2', 'req_3'],
      });
      await Prefs.init();

      // 验证 Prefs.read<List<String>> 不会抛出 type 'List<Object?>' is not a subtype of type 'List<String>?' 异常
      final listFromRead = Prefs.read<List<String>>('test_dynamic_list');
      expect(listFromRead, isA<List<String>>());
      expect(listFromRead, ['req_1', 'req_2', 'req_3']);

      // 验证 Prefs.getStringList 同样正常
      final listFromGetStringList = Prefs.getStringList('test_dynamic_list');
      expect(listFromGetStringList, isA<List<String>>());
      expect(listFromGetStringList, ['req_1', 'req_2', 'req_3']);
    });

    test('正常 write 和 read<List<String>> 及 getStringList 测试', () async {
      SharedPreferences.setMockInitialValues({});
      await Prefs.init();

      await Prefs.write('voted_ids', ['id_a', 'id_b']);

      final readList = Prefs.read<List<String>>('voted_ids');
      expect(readList, ['id_a', 'id_b']);

      final stringList = Prefs.getStringList('voted_ids');
      expect(stringList, ['id_a', 'id_b']);
    });

    test('常规标量类型读写测试', () async {
      SharedPreferences.setMockInitialValues({});
      await Prefs.init();

      await Prefs.write('str_key', 'hello');
      await Prefs.write('int_key', 42);
      await Prefs.write('double_key', 3.14);
      await Prefs.write('bool_key', true);

      expect(Prefs.read<String>('str_key'), 'hello');
      expect(Prefs.read<int>('int_key'), 42);
      expect(Prefs.read<double>('double_key'), 3.14);
      expect(Prefs.read<bool>('bool_key'), true);
    });
  });
}
