// accounts_store_test.dart —— v2.24 本机多账号档案测试
//
// 覆盖：首次迁移（老数据搬进 accounts/local 且排除基础设施）、
// 新建/校验/取消 PIN、select 落盘后可跨"重启"读回、删除档案进回收站
// 且拒绝删最后一个。

import 'dart:io';

import 'package:biology/state/accounts_store.dart';
import 'package:biology/storage/platform_storage_io.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final String sep = Platform.pathSeparator;
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('accounts_store_test');
    AccountsStore.debugBaseDir = tmp.path;
    AccountsStore.debugForceWeb = false;
    AccountsStore.instance.debugReset();
  });

  tearDown(() {
    AccountsStore.instance.debugReset();
    AccountsStore.debugBaseDir = null;
    AccountsStore.debugForceWeb = null;
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('首次启动：建默认档案，老数据搬进 accounts/local，基础设施留在原地', () async {
    File('${tmp.path}${sep}first_run.json').writeAsStringSync('{"role":"student"}');
    Directory('${tmp.path}${sep}board_history').createSync();
    Directory('${tmp.path}${sep}待删除').createSync();

    await AccountsStore.instance.load();

    final base = AccountsStore.instance.baseDir;
    expect(base, tmp.path);
    expect(AccountsStore.instance.accounts.length, 1);
    expect(AccountsStore.instance.accounts.first.id, 'local');
    expect(AccountsStore.instance.accounts.first.name, '本机用户');
    expect(AccountsStore.instance.activeId, 'local');
    expect(accountDataDir, '$base${sep}accounts${sep}local');
    expect(File('$base${sep}accounts.json').existsSync(), isTrue);

    final local = '$base${sep}accounts${sep}local';
    expect(File('$local${sep}first_run.json').existsSync(), isTrue);
    expect(Directory('$local${sep}board_history').existsSync(), isTrue);
    // 排除项不动：回收站目录不是任何档案的数据。
    expect(Directory('$base${sep}待删除').existsSync(), isTrue);
  });

  test('单档案无 PIN 直接放行；有 PIN 或多样本才需要门禁', () async {
    await AccountsStore.instance.load();
    expect(AccountsStore.instance.unlocked, isTrue);
    expect(AccountsStore.instance.needsGate, isFalse);

    AccountsStore.instance.debugReset();
    await AccountsStore.instance.load();
    final p = await AccountsStore.instance.create('学生', '1234');

    AccountsStore.instance.debugReset();
    await AccountsStore.instance.load();
    expect(AccountsStore.instance.accounts.length, 2);
    expect(AccountsStore.instance.activeId, 'local');
    expect(AccountsStore.instance.unlocked, isFalse);
    expect(AccountsStore.instance.needsGate, isTrue);
    expect(p.hasPin, isTrue);
  });

  test('PIN：建号即算哈希，改错即失败，置空即取消', () async {
    await AccountsStore.instance.load();
    final p = await AccountsStore.instance.create('学生', '1234');
    expect(p.pinSalt.length, 32); // 16 字节 hex
    expect(await AccountsStore.instance.verifyPin(p.id, '1234'), isTrue);
    expect(await AccountsStore.instance.verifyPin(p.id, '0000'), isFalse);

    await AccountsStore.instance.setPin(p.id, '');
    final reloaded =
        AccountsStore.instance.accounts.firstWhere((a) => a.id == p.id);
    expect(reloaded.hasPin, isFalse);
    expect(reloaded.pinSalt, '');
    // 无 PIN 恒 true。
    expect(await AccountsStore.instance.verifyPin(p.id, '0000'), isTrue);
  });

  test('select 落盘：重开仍指向该档案目录', () async {
    await AccountsStore.instance.load();
    final p = await AccountsStore.instance.create('老师', '');
    await AccountsStore.instance.select(p.id);
    expect(AccountsStore.instance.activeId, p.id);
    expect(accountDataDir, endsWith('$sep${p.id}'));

    // 模拟重启：清内存后重读同一个 base。
    AccountsStore.instance.debugReset();
    await AccountsStore.instance.load();
    expect(AccountsStore.instance.activeId, p.id);
    expect(accountDataDir, endsWith('$sep${p.id}'));
  });

  test('lock()：重新上锁后回到选人页', () async {
    await AccountsStore.instance.load();
    expect(AccountsStore.instance.unlocked, isTrue);
    AccountsStore.instance.lock();
    expect(AccountsStore.instance.unlocked, isFalse);
    expect(AccountsStore.instance.needsGate, isTrue);
  });

  test('删除：目录移入 _trash_accounts，且拒绝删最后一个', () async {
    await AccountsStore.instance.load();
    final p = await AccountsStore.instance.create('临时', '');
    await AccountsStore.instance.select(p.id);

    // 删当前档案会把旧账号的内存数据写进新目录（串档），必须先切走。
    await expectLater(
        AccountsStore.instance.remove(p.id), throwsStateError);
    await AccountsStore.instance.select('local');
    await AccountsStore.instance.remove(p.id);
    expect(AccountsStore.instance.accounts.any((a) => a.id == p.id), isFalse);
    expect(AccountsStore.instance.activeId, 'local');

    final trash = Directory('${tmp.path}${sep}_trash_accounts');
    expect(trash.existsSync(), isTrue);
    expect(trash.listSync().length, 1);
    expect(Directory('${tmp.path}${sep}accounts${sep}${p.id}').existsSync(), isFalse);

    await expectLater(
        AccountsStore.instance.remove('local'), throwsStateError);
  });

  test('清单损坏：先备份再重建，不把用户档案列表覆盖掉', () async {
    final manifest = File('${tmp.path}${sep}accounts.json');
    manifest.writeAsStringSync('{ 这不是 json');

    await AccountsStore.instance.load();

    expect(AccountsStore.instance.accounts.length, 1);
    expect(manifest.existsSync(), isTrue); // 重建后的新清单
    final backups = tmp
        .listSync()
        .whereType<File>()
        .where((f) => f.path.contains('accounts.json.bak-'))
        .toList();
    expect(backups.length, 1);
  });
  test('迁移补跑：上次没搬进档案目录的遗留文件，下次启动补搬', () async {
    // 造一个「已经分过档」的现场：清单 + accounts/local 都在，
    // 但基目录顶层还剩一个上次 rename 失败的历史文件。
    final base = tmp.path;
    Directory('$base${sep}accounts${sep}local').createSync(recursive: true);
    File('$base${sep}accounts.json').writeAsStringSync(
        '{"version":1,"activeId":"local","accounts":[{"id":"local","name":"本机用户","pinSalt":"","pinHash":"","createdAt":1}]}');
    File('$base${sep}history.json').writeAsStringSync('[]');

    await AccountsStore.instance.load();

    expect(File('$base${sep}accounts${sep}local${sep}history.json').existsSync(), isTrue);
    expect(File('$base${sep}history.json').existsSync(), isFalse);
  });

  test('门禁选人标记：selectAndUnlock 后重启直接放行，且标记只用一次', () async {
    await AccountsStore.instance.load();
    final p = await AccountsStore.instance.create('学生', '1234');
    await AccountsStore.instance.selectAndUnlock(p.id);

    AccountsStore.instance.debugReset();
    await AccountsStore.instance.load();
    expect(AccountsStore.instance.activeId, p.id);
    expect(AccountsStore.instance.unlocked, isTrue);

    // 标记是一次性的：再重启一次就要重新选人（多档案 + 有 PIN）。
    AccountsStore.instance.debugReset();
    await AccountsStore.instance.load();
    expect(AccountsStore.instance.unlocked, isFalse);
  });
  test('整机重置：全部档案进回收站，回到无 PIN 的默认档案', () async {
    await AccountsStore.instance.load();
    final p = await AccountsStore.instance.create('学生', '1234');
    Directory('${tmp.path}${sep}accounts${sep}${p.id}')
        .createSync(recursive: true);
    File('${tmp.path}${sep}accounts${sep}${p.id}${sep}note.json')
        .writeAsStringSync('1');

    await AccountsStore.instance.resetAllProfiles();

    expect(AccountsStore.instance.accounts.length, 1);
    expect(AccountsStore.instance.accounts.first.id, 'local');
    expect(AccountsStore.instance.accounts.first.hasPin, isFalse);
    expect(AccountsStore.instance.activeId, 'local');
    expect(AccountsStore.instance.unlocked, isTrue);
    expect(Directory('${tmp.path}${sep}accounts${sep}${p.id}').existsSync(),
        isFalse);
    // 目录只搬家不物理删除：两个档案各一份，反悔能手工捞回来。
    expect(
        Directory('${tmp.path}${sep}_trash_accounts').listSync().length, 2);

    // 重启后仍是干净的默认档案（清单已落盘）。
    AccountsStore.instance.debugReset();
    await AccountsStore.instance.load();
    expect(AccountsStore.instance.accounts.length, 1);
    expect(AccountsStore.instance.activeId, 'local');
    expect(AccountsStore.instance.unlocked, isTrue);
  });

  test('选人页（未解锁）可以删除当前档案；已解锁则不行', () async {
    await AccountsStore.instance.load();
    final p = await AccountsStore.instance.create('学生B', '1234');
    await AccountsStore.instance.select(p.id);

    // 模拟重启：两档 + 有 PIN → 门禁拦下，unlocked = false。
    AccountsStore.instance.debugReset();
    await AccountsStore.instance.load();
    expect(AccountsStore.instance.unlocked, isFalse);
    expect(AccountsStore.instance.activeId, p.id);

    // 还没进任何档案：允许删（否则无 PIN 的档永远删不掉）。
    await AccountsStore.instance.remove(p.id);
    expect(AccountsStore.instance.accounts.any((a) => a.id == p.id), isFalse);
  });
}
