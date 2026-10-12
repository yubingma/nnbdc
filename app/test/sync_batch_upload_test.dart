import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nnbdc/api/dto.dart';
import 'package:nnbdc/api/result.dart';
import 'package:nnbdc/util/sync.dart';

/// 分批上传的切批与编排测试。
///
/// 目标（对应"导入大词表后云端同步永远卡住"的问题）：
/// - 切批只按真实报文字节数（UTF-8）与条数切，顺序一条不动；
/// - 批次串行发送，版本号逐批接力；
/// - 每批成功后只回调该批，失败即停，剩余批次留待下次同步。
void main() {
  final baseTime = DateTime.utc(2026, 10, 11, 9, 0, 0);

  UserDbLogDto buildLog(
    String id, {
    String tblName = 'dict_word',
    String? recordId,
    String? record,
  }) {
    return UserDbLogDto(
      id,
      'user-1',
      0,
      'INSERT',
      tblName,
      recordId ?? id,
      record ?? '{"dictId":"dict-1","wordId":"$id","seq":1,"unit":0}',
      baseTime,
      baseTime,
    );
  }

  /// 一批日志真实上传时的请求体字节数（与 dio 序列化口径一致）
  int bodyBytes(List<UserDbLogDto> batch) =>
      utf8.encode(jsonEncode(batch.map((log) => log.toJson()).toList())).length;

  group('splitLogsForUpload - 切批', () {
    test('空清单切成 0 批', () {
      expect(splitLogsForUpload(const []), isEmpty);
    });

    test('每批不超过条数上限，且顺序一条不动', () {
      final logs = List.generate(10, (i) => buildLog('log-$i'));
      final batches = splitLogsForUpload(logs, maxCount: 4);

      expect(batches.map((b) => b.length).toList(), [4, 4, 2]);
      expect(
        batches.expand((b) => b).map((log) => log.id).toList(),
        logs.map((log) => log.id).toList(),
      );
    });

    test('每批真实报文字节数不超过预算（含中文释义）', () {
      final logs = List.generate(
        20,
        (i) => buildLog('log-$i', record: '{"meaning":"n. 释义内容$i; v. 第二义项$i"}'),
      );
      final single = bodyBytes([logs.first]);
      final maxBytes = single * 3 + 2;

      final batches = splitLogsForUpload(logs, maxBytes: maxBytes, maxCount: 1000);

      expect(batches.length, greaterThan(1), reason: '预算只够装下约 3 条，应该被切成多批');
      for (final batch in batches) {
        if (batch.length == 1) continue; // 单条超预算时只能单独成批
        expect(bodyBytes(batch), lessThanOrEqualTo(maxBytes));
      }
      expect(
        batches.expand((b) => b).map((log) => log.id).toList(),
        logs.map((log) => log.id).toList(),
      );
    });

    test('单条日志本身超过预算时单独成批，不丢也不死循环', () {
      final big = buildLog('big', record: '{"meaning":"${'很长的释义' * 50}"}');
      final batches = splitLogsForUpload([big], maxBytes: 10);

      expect(batches.length, 1);
      expect(batches.single.single.id, 'big');
    });

    test('默认预算下 6000 条带释义日志会被切成多批，且每批都远低于 5MB', () {
      // 与真实导入场景同量级：6000 个词条日志 + 每词 1 个释义项日志
      final logs = <UserDbLogDto>[];
      for (var i = 0; i < 6000; i++) {
        logs.add(buildLog('word-$i', record: '{"dictId":"dict-1","wordId":"word-$i","seq":$i,"unit":0}'));
        logs.add(buildLog('meaning-$i',
            tblName: 'meaning_item',
            record: '{"wordId":"word-$i","dictId":"dict-1","meaning":"n. 释义$i"}'));
      }

      final batches = splitLogsForUpload(logs);

      expect(batches.length, greaterThan(1));
      for (final batch in batches) {
        expect(bodyBytes(batch), lessThanOrEqualTo(2 * 1024 * 1024));
      }
      expect(
        batches.expand((b) => b).map((log) => log.id).toList(),
        logs.map((log) => log.id).toList(),
      );
    });
  });

  group('uploadLogsInBatches - 编排', () {
    test('空清单不上传', () async {
      var called = 0;
      final allUploaded = await uploadLogsInBatches(
        logs: const [],
        startVersion: 7,
        upload: (expectedVersion, batch) async {
          called++;
          return Result<int>('SUCCESS', null, true)..data = expectedVersion + 1;
        },
        onBatchUploaded: (newVersion, batch) async {},
      );

      expect(allUploaded, isTrue);
      expect(called, 0);
    });

    test('版本号逐批接力，每批成功后立刻回调该批', () async {
      final logs = List.generate(5, (i) => buildLog('log-$i'));
      final expectedVersions = <int>[];
      final uploadedBatches = <List<String>>[];
      final callbackVersions = <int>[];

      final allUploaded = await uploadLogsInBatches(
        logs: logs,
        startVersion: 100,
        maxCount: 2,
        upload: (expectedVersion, batch) async {
          expectedVersions.add(expectedVersion);
          return Result<int>('SUCCESS', null, true)..data = expectedVersion + 1;
        },
        onBatchUploaded: (newVersion, batch) async {
          callbackVersions.add(newVersion);
          uploadedBatches.add(batch.map((log) => log.id).toList());
        },
      );

      expect(allUploaded, isTrue);
      expect(expectedVersions, [100, 101, 102], reason: '下一批必须带上上一批返回的新版本号');
      expect(uploadedBatches, [
        ['log-0', 'log-1'],
        ['log-2', 'log-3'],
        ['log-4'],
      ]);
      expect(callbackVersions, [101, 102, 103]);
    });

    test('某批失败即停止：后续批次不再发送，失败批不回调', () async {
      final logs = List.generate(6, (i) => buildLog('log-$i'));
      final attempted = <List<String>>[];
      final uploaded = <List<String>>[];

      final allUploaded = await uploadLogsInBatches(
        logs: logs,
        startVersion: 10,
        maxCount: 2,
        upload: (expectedVersion, batch) async {
          attempted.add(batch.map((log) => log.id).toList());
          if (attempted.length == 2) {
            return Result<int>('ERROR', '服务端拒收', false);
          }
          return Result<int>('SUCCESS', null, true)..data = expectedVersion + 1;
        },
        onBatchUploaded: (newVersion, batch) async {
          uploaded.add(batch.map((log) => log.id).toList());
        },
      );

      expect(allUploaded, isFalse);
      expect(attempted, [
        ['log-0', 'log-1'],
        ['log-2', 'log-3'],
      ], reason: '第 2 批失败后不能再发第 3 批');
      expect(uploaded, [
        ['log-0', 'log-1'],
      ], reason: '只有成功的那一批才允许删本地日志');
    });

    test('上传抛异常时不吞掉，后续批次不再发送', () async {
      final logs = List.generate(4, (i) => buildLog('log-$i'));
      final attempted = <List<String>>[];

      await expectLater(
        uploadLogsInBatches(
          logs: logs,
          startVersion: 10,
          maxCount: 2,
          upload: (expectedVersion, batch) async {
            attempted.add(batch.map((log) => log.id).toList());
            throw Exception('网络中断');
          },
          onBatchUploaded: (newVersion, batch) async {},
        ),
        throwsA(isA<Exception>()),
      );

      expect(attempted, [
        ['log-0', 'log-1'],
      ]);
    });

    test('成功后的版本号会写回调用方（供本地保存）', () async {
      final logs = List.generate(3, (i) => buildLog('log-$i'));
      var localVersion = 50;

      await uploadLogsInBatches(
        logs: logs,
        startVersion: localVersion,
        maxCount: 1,
        upload: (expectedVersion, batch) async =>
            Result<int>('SUCCESS', null, true)..data = expectedVersion + 1,
        onBatchUploaded: (newVersion, batch) async {
          localVersion = newVersion;
        },
      );

      expect(localVersion, 53);
    });
  });

  group('版本号不匹配（DB_VERSION_NOT_MATCH）', () {
    /// 与 sync.dart 里 doSyncUserDb 的 upload 闭包同构：
    /// 命中「版本号不匹配」抛异常，其余结果原样返回交由 uploadLogsInBatches 按失败处理。
    Future<Result<int>> uploadOnce(Result<int> serverResult) async {
      if (isDbVersionNotMatch(serverResult)) {
        throw DbVersionNotMatchException(serverResult.msg ?? '版本号已变化');
      }
      return serverResult;
    }

    test('服务端返回该错误码时识别为版本号不匹配', () {
      expect(isDbVersionNotMatch(Result<int>('DB_VERSION_NOT_MATCH', '期望版本[1]，当前版本[2]', false)), isTrue);
    });

    test('成功应答与其它业务错误码都不算版本号不匹配', () {
      expect(isDbVersionNotMatch(Result<int>('0000', null, true)), isFalse);
      expect(isDbVersionNotMatch(Result<int>('DICT_WORD_ORDER_INVALID', '词书顺序异常', false)), isFalse);
      expect(isDbVersionNotMatch(Result<int>('0001', '普通失败', false)), isFalse);
    });

    test('命中版本号不匹配时抛出异常，中断本次上传', () async {
      await expectLater(
        uploadOnce(Result<int>('DB_VERSION_NOT_MATCH', '期望版本[1]，当前版本[2]', false)),
        throwsA(isA<DbVersionNotMatchException>()),
      );
    });

    test('其它失败不抛异常，仍按普通失败返回给 uploadLogsInBatches', () async {
      final result = await uploadOnce(Result<int>('0001', '服务端拒收', false));
      expect(result.success, isFalse);
      expect(result.code, '0001');
    });
  });
}
