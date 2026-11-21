// backup_service_test.dart —— 整机打包 / 恢复的回归测试（v2.24）。
//
// 覆盖三条最危险的路径：口令错不能部分写入、非法路径必须整包拒绝、
// 导出→恢复全链路要逐字节还原。

import 'dart:convert';
import 'dart:io';

import 'package:biology/services/backup_service.dart';
import 'package:biology/services/local_secure_store.dart';
import 'package:biology/services/mistake_book_crypto.dart';
import 'package:biology/state/mistake_book.dart' show MistakeBookExporter;
import 'package:biology/storage/platform_storage_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('bio_backup_test_');
    // 导出统一落临时下载目录，绝不碰真实 ~/Downloads。
    MistakeBookExporter.debugDownloadsDir = '${tmp.path}/downloads';
    MistakeBookExporter.debugForceIsAndroid = null;
    // 机器口令是按档案目录缓存的：用例之间必须清掉，否则上一个用例
    // 留下的口令会把下一个用例的解密打偏。
    accountDataDir = null;
    LocalSecureStore.invalidateMachinePassphraseCache();
  });

  tearDown(() {
    MistakeBookExporter.debugDownloadsDir = null;
    accountDataDir = null;
    LocalSecureStore.invalidateMachinePassphraseCache();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  Directory makeBase(String name) {
    final d = Directory('${tmp.path}/$name')..createSync(recursive: true);
    return d;
  }

  void writeAccount(Directory base) {
    File('${base.path}/accounts.json').writeAsStringSync(
      '{"version":1,"activeId":"a1","accounts":[{"id":"a1","name":"甲","pinSalt":"","pinHash":"","createdAt":1}]}',
    );
    final dir = Directory('${base.path}/accounts/a1')..createSync(recursive: true);
    File('${dir.path}/mistake_book.json').writeAsStringSync('{"entries":[1,2,3]}');
    File('${dir.path}/ai_config.json')
        .writeAsStringSync('{"provider":"deepseek","apiKey":"sk-local"}');
  }

  test('buildEnvelope → decodeEnvelope 往返结构完整', () async {
    final env = await BackupService.buildEnvelope(
      passphrase: 'secret123',
      accounts: [
        {'id': 'a1', 'name': '张老师'},
      ],
      files: {
        'accounts/a1/mistake_book.json': base64Encode(utf8.encode('{"x":1}')),
      },
      appVersion: 'test',
      createdAt: 1700000000000,
    );
    final plain = await MistakeBookCrypto.decryptJson(env, 'secret123');
    final m = BackupService.decodeEnvelope(plain);
    expect(m['format'], BackupService.formatId);
    expect(m['version'], BackupService.formatVersion);
    expect((m['files'] as Map).length, 1);
  });

  test('口令错误返回失败，不抛异常，不动磁盘', () async {
    final base = makeBase('src');
    writeAccount(base);
    final exp = await BackupService.export(
      passphrase: 'correct-horse',
      baseDirOverride: base.path,
      appVersion: 'test',
    );
    expect(exp.ok, isTrue, reason: exp.error);
    final raw = File(exp.path!).readAsStringSync();

    final target = makeBase('dst');
    final r = await BackupService.restore(
      raw: raw,
      passphrase: 'wrong-pass',
      baseDirOverride: target.path,
    );
    expect(r.ok, isFalse);
    expect(r.error, contains('口令'));
    // 目标目录没被写入任何东西。
    expect(File('${target.path}/accounts.json').existsSync(), isFalse);
  });

  test('非法路径整包拒绝（路径穿越）', () async {
    final env = await BackupService.buildEnvelope(
      passphrase: 'secret123',
      accounts: const [],
      files: {'../evil.txt': base64Encode(utf8.encode('pwn'))},
      appVersion: 'test',
    );
    final target = makeBase('dst2');
    final r = await BackupService.restore(
      raw: env,
      passphrase: 'secret123',
      baseDirOverride: target.path,
    );
    expect(r.ok, isFalse);
    expect(r.error, contains('非法路径'));
    expect(File('${tmp.path}/evil.txt').existsSync(), isFalse);
  });

  test('导出 → 恢复：数据逐字节还原', () async {
    final src = makeBase('src2');
    writeAccount(src);
    final exp = await BackupService.export(
      passphrase: 'secret123',
      baseDirOverride: src.path,
      appVersion: 'test',
    );
    expect(exp.ok, isTrue, reason: exp.error);
    expect(exp.fileCount, greaterThanOrEqualTo(3));

    final dst = makeBase('dst3');
    final raw = File(exp.path!).readAsStringSync();
    final r = await BackupService.restore(
      raw: raw,
      passphrase: 'secret123',
      baseDirOverride: dst.path,
    );
    expect(r.ok, isTrue, reason: r.error);
    expect(r.accountCount, 1);
    expect(
      File('${dst.path}/accounts/a1/mistake_book.json').readAsStringSync(),
      '{"entries":[1,2,3]}',
    );
    expect(
      File('${dst.path}/accounts/a1/ai_config.json').readAsStringSync(),
      contains('sk-local'),
    );
    expect(File('${dst.path}/accounts.json').existsSync(), isTrue);
  });

  test('上一份数据包不会再被打进新包（包套包）', () async {
    final base = makeBase('nest');
    writeAccount(base);
    // Android 的导出落在档案目录，模拟上一次打包留下的包。
    final prev = File(
        '${base.path}/accounts/a1/biology-backup-20260101-000000.json')
      ..writeAsStringSync('{"previous":"package"}');

    final exp = await BackupService.export(
      passphrase: 'secret123',
      baseDirOverride: base.path,
      appVersion: 'test',
    );
    expect(exp.ok, isTrue, reason: exp.error);
    final plain = await MistakeBookCrypto.decryptJson(
        File(exp.path!).readAsStringSync(), 'secret123');
    final files = BackupService.decodeEnvelope(plain)['files'] as Map;
    expect(files.keys.any((k) => '$k'.contains('biology-backup-')), isFalse);
    expect(prev.existsSync(), isTrue, reason: '旧包只跳过入包，不能被删');
  });

  test('导出不含 .machine.key', () async {
    final src = makeBase('src3');
    writeAccount(src);
    File('${src.path}/.machine.key').writeAsStringSync('deadbeef');
    final exp = await BackupService.export(
      passphrase: 'secret123',
      baseDirOverride: src.path,
      appVersion: 'test',
    );
    expect(exp.ok, isTrue, reason: exp.error);
    final plain = await MistakeBookCrypto.decryptJson(
      File(exp.path!).readAsStringSync(),
      'secret123',
    );
    final files = BackupService.decodeEnvelope(plain)['files'] as Map;
    expect(files.keys.any((k) => '$k'.endsWith('.machine.key')), isFalse);
  });
  test('空包或缺账号清单：拒绝恢复，且一个文件都不删', () async {
    final dst = makeBase('dst4');
    File('${dst.path}/accounts.json')
        .writeAsStringSync('{"version":1,"activeId":"a1","accounts":[]}');

    // 口令正确、格式合法，但 files 为空。
    final emptyEnv = await BackupService.buildEnvelope(
      passphrase: 'secret123',
      accounts: const [],
      files: const {},
      appVersion: 'test',
    );
    final r = await BackupService.restore(
        raw: emptyEnv, passphrase: 'secret123', baseDirOverride: dst.path);
    expect(r.ok, isFalse);
    expect(r.error, contains('没有任何文件'));
    expect(File('${dst.path}/accounts.json').existsSync(), isTrue);

    // 有文件，但没有 accounts.json。
    final noManifest = await BackupService.buildEnvelope(
      passphrase: 'secret123',
      accounts: const [],
      files: {
        'accounts/a1/x.json': base64Encode(utf8.encode('{}')),
      },
      appVersion: 'test',
    );
    final r2 = await BackupService.restore(
        raw: noManifest, passphrase: 'secret123', baseDirOverride: dst.path);
    expect(r2.ok, isFalse);
    expect(r2.error, contains('账号清单'));
    expect(File('${dst.path}/accounts.json').existsSync(), isTrue);
  });

  test('多档案导出：每个档案用自己的 .machine.key 解成明文', () async {
    final base = makeBase('multi');
    final sep = Platform.pathSeparator;

    Future<void> writeProfile(
        String id, String machineKey, String apiKey) async {
      final dir = Directory('${base.path}${sep}accounts$sep$id')
        ..createSync(recursive: true);
      File('${dir.path}$sep.machine.key').writeAsStringSync(machineKey);
      // writeSecure 的口令里含 userAppDir()/.machine.key，必须先切指针再写；
      // 共用一把钥匙的话，这条用例就测不出「导出串档」了。
      accountDataDir = dir.path;
      LocalSecureStore.invalidateMachinePassphraseCache();
      await LocalSecureStore.writeSecure(
        '${dir.path}${sep}ai_config.json',
        '{"provider":"deepseek","apiKey":"$apiKey"}',
      );
    }

    await writeProfile('a1', 'machine-key-a', 'sk-aaa');
    await writeProfile('a2', 'machine-key-b', 'sk-bbb');
    accountDataDir = null;
    LocalSecureStore.invalidateMachinePassphraseCache();

    File('${base.path}${sep}accounts.json').writeAsStringSync(
        '{"version":1,"activeId":"a1","accounts":['
        '{"id":"a1","name":"甲","pinSalt":"","pinHash":"","createdAt":1},'
        '{"id":"a2","name":"乙","pinSalt":"","pinHash":"","createdAt":2}]}');

    final exp = await BackupService.export(
      passphrase: 'secret123',
      baseDirOverride: base.path,
      appVersion: 'test',
    );
    expect(exp.ok, isTrue, reason: exp.error);

    final plain = await MistakeBookCrypto.decryptJson(
        File(exp.path!).readAsStringSync(), 'secret123');
    final files = BackupService.decodeEnvelope(plain)['files'] as Map;
    String contentOf(String key) =>
        utf8.decode(base64Decode(files[key] as String));

    // 进程级口令缓存串档时，第二个档案会解密失败、包内留着密文。
    expect(contentOf('accounts/a1/ai_config.json'), contains('sk-aaa'));
    expect(contentOf('accounts/a2/ai_config.json'), contains('sk-bbb'));
    expect(contentOf('accounts/a1/ai_config.json'), isNot(contains('ciphertext')));
    expect(contentOf('accounts/a2/ai_config.json'), isNot(contains('ciphertext')));
  });

  test('inspect：只读预览账号 / 文件数 / 时间，口令错给明确原因', () async {
    final env = await BackupService.buildEnvelope(
      passphrase: 'secret123',
      accounts: [
        {'id': 'a1', 'name': '甲'},
        {'id': 'a2', 'name': '乙'},
      ],
      files: {
        'accounts.json': base64Encode(utf8.encode('{}')),
        'accounts/a1/mistake_book.json': base64Encode(utf8.encode('{}')),
      },
      appVersion: 'test',
      createdAt: 1700000000000,
    );
    final ok = await BackupService.inspect(raw: env, passphrase: 'secret123');
    expect(ok.ok, isTrue, reason: ok.error);
    expect(ok.accountNames, ['甲', '乙']);
    expect(ok.fileCount, 2);
    expect(ok.createdAt?.millisecondsSinceEpoch, 1700000000000);
    expect(ok.appVersion, 'test');

    final bad = await BackupService.inspect(raw: env, passphrase: 'wrong-pass');
    expect(bad.ok, isFalse);
    expect(bad.error, BackupService.badPassphraseError);
    expect(bad.accountNames, isEmpty);
  });
}
