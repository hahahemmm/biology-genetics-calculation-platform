// local_secure_store_test.dart —— 本机透明加密读写原语回归测试。
//
// 移植自早期备份仓库（v2.10 拍题入口分离完成版本，该仓 R9-B/R9-E 批次，
// 原 tag R9-1-02 `ai_config.json` 明文 API Key /
// R9-1-03 `ai_chat_history.json` 明文聊天历史）。逐例对照移植，未删减断言。
// 本仓对应债务记录见 `lib/pages/settings_page.dart` 的 `AiSettingsStore.save`
// 注释（v2.11 M4 安全注释，v2.19.30 诚实化修订里点名的「未兑现」项）。
//
// 契约（与 lib/services/local_secure_store.dart 文件头一一对应）：
//   1. writeSecure → readSecure roundtrip 字节级一致，且磁盘字节里
//      **搜不到**明文（casual disclosure 已消除）。
//   2. 向后兼容：旧明文 JSON（对象 / 数组 / 带 `//` 注释头）→ readSecure
//      原样返回；下次 writeSecure 自动升级为 envelope。
//   3. 嗅探：envelope ↔ 明文 两条路径互不误判。
//   4. 损坏密文 / 跨机器文件 / 字段缺失 / 篡改字节 → 抛
//      LocalSecureCorruptException（消息可读，调用方能降级），不静默返回脏数据。
//   5. 文件缺失 → LocalSecureUnreadableException（不返回 null、不崩）。
//   6. 互操作：本文件写出的 envelope 能被 `MistakeBookCrypto`
//      （错题本导出引擎）解开 —— 证明「复用同一加密引擎格式」不是口头声明。
//   7. Web / 无法派生 → 明文透传（拍板：Web 端不加密）。
//   8. 密钥缓存不改变语义：同机两个路径互通、两次写密文不同（IV 随机）。
//   9. 惰性升级 `upgradeIfLegacyPlaintext` 是 **compare-and-swap**：只有当
//      「调用方读到的原始磁盘字节 expectedRaw」在覆盖前仍逐字相同才 rename；
//      期间被别的写者更新过就删 temp 放弃并返回 false——绝不用过期明文覆盖新配置。
//
// 注：本测试刻意把「每安装机器密钥」收进临时目录（debugMachineKeyPath），
// 并且每个 case 前 debugResetHooks()，保证不脏写真实 ~/.biology_app。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:biology/services/local_secure_store.dart';
import 'package:biology/services/mistake_book_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late String path;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('local_secure_store_test');
    LocalSecureStore.debugResetHooks();
    LocalSecureStore.debugMachineKeyPath = '${tmp.path}/.machine.key';
    path = '${tmp.path}/ai_config.json';
  });

  tearDown(() {
    LocalSecureStore.debugResetHooks();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('roundtrip（契约 1）', () {
    test('writeSecure → readSecure 字节级一致，磁盘无明文', () async {
      const plain =
          '{"provider":"deepseek","baseUrl":"https://api.deepseek.com",'
          '"apiKey":"sk-SECRET-abc123","model":"deepseek-flash"}';

      await LocalSecureStore.writeSecure(path, plain);

      final raw = File(path).readAsStringSync();
      expect(raw, isNot(contains('sk-SECRET-abc123')),
          reason: 'API Key 不得以明文出现在磁盘字节里（验收点）');
      expect(raw, isNot(contains('apiKey')), reason: '字段名也不该裸露');
      expect(raw, isNot(contains('deepseek-flash')));
      expect(MistakeBookCrypto.isEncryptedEnvelope(raw), isTrue,
          reason: '落盘内容必须是可识别的 AES-GCM envelope');

      expect(await LocalSecureStore.readSecure(path), plain,
          reason: 'readSecure 必须逐字取回明文');
    });

    test('envelope 字段与错题本导出引擎 v1 对齐（AES-256-GCM / PBKDF2 100k）',
        () async {
      await LocalSecureStore.writeSecure(path, '{"x":1}');
      final env =
          jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
      expect(env['cipher'], 'aes-256-gcm');
      expect(env['kdf'], 'pbkdf2-sha256');
      expect(env['kdfIterations'], 100000,
          reason: '迭代数必须与错题本导出同值，否则 envelope 不互操作');
      expect(env['schemaVersion'], 1);
      for (final k in ['salt', 'iv', 'ciphertext', 'tag']) {
        expect(env[k], isA<String>(), reason: 'envelope 必须自带 $k');
      }
    });

    test('UTF-8 中文 / 人名 / 长文本 roundtrip', () async {
      final plain = jsonEncode([
        {'role': 'user', 'text': '张小明问：减数分裂Ⅰ前期同源染色体联会？'},
        {'role': 'assistant', 'text': '对——${'交叉互换'.padRight(2000, '。）')}'}
      ]);
      await LocalSecureStore.writeSecure(path, plain);
      final raw = File(path).readAsStringSync();
      expect(raw, isNot(contains('张小明')), reason: '人名不得明文落盘');
      expect(await LocalSecureStore.readSecure(path), plain);
    });

    test('两次写同一明文 → 密文字节不同（IV 随机），但都能解回', () async {
      const plain = '{"apiKey":"sk-repeat"}';
      await LocalSecureStore.writeSecure(path, plain);
      final first = File(path).readAsStringSync();
      await LocalSecureStore.writeSecure(path, plain);
      final second = File(path).readAsStringSync();
      expect(first, isNot(equals(second)),
          reason: '每次写都换 IV ⇒ 同明文同密钥密文也不同（盐/IV 随机性）');
      expect(await LocalSecureStore.readSecure(path), plain);
    });

    test('原子写：目标内容正确且目录无 .tmp 残留', () async {
      const plain = '{"apiKey":"sk-atomic"}';
      await LocalSecureStore.writeSecure(path, plain);

      // 目标文件是完整密文、能解回。
      expect(MistakeBookCrypto.isEncryptedEnvelope(File(path).readAsStringSync()),
          isTrue);
      expect(await LocalSecureStore.readSecure(path), plain);
      // 关键：同目录不得留下 *.tmp 半成品。
      final residue = tmp
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.tmp'))
          .toList();
      expect(residue, isEmpty, reason: '原子写完成后不得残留 .tmp');
    });

    test('原子写覆盖旧文件：替换成功、无 .tmp 残留、读回最新值', () async {
      await LocalSecureStore.writeSecure(path, '{"apiKey":"v1"}');
      await LocalSecureStore.writeSecure(path, '{"apiKey":"v2"}');

      expect(await LocalSecureStore.readSecure(path), '{"apiKey":"v2"}',
          reason: 'rename 覆盖旧文件（Windows 需 MOVEFILE_REPLACE_EXISTING 语义）');
      expect(
          tmp.listSync().whereType<File>().where((f) => f.path.endsWith('.tmp')),
          isEmpty,
          reason: '覆盖写后同样不得残留 .tmp');
    });
  });

  group('互操作：错题本导出引擎能解开本文件的 envelope（契约 6）', () {
    test('cross-decrypt：MistakeBookCrypto.decryptJson(envelope, 机器口令) 成功',
        () async {
      const plain = '{"apiKey":"sk-interop"}';
      await LocalSecureStore.writeSecure(path, plain);
      final raw = File(path).readAsStringSync();

      final passphrase = await LocalSecureStore.debugMachinePassphrase();
      expect(passphrase, isNotNull, reason: '本机应能派生出口令');
      // 口令不得进任何断言输出（只断长度/非空）；派生源都在本机，见威胁模型。
      expect(passphrase!.length, greaterThan(8));

      final decrypted = await MistakeBookCrypto.decryptJson(raw, passphrase);
      expect(decrypted, plain,
          reason: 'envelope 格式必须与 MistakeBookCrypto 逐字兼容（复用引擎的实证）');
    });
  });

  group('向后兼容 + 嗅探（契约 2 / 3）', () {
    test('旧明文 object JSON → 原样返回，不判成 envelope', () async {
      // model 用未退役名——本用例只测 readSecure 的明文嗅探保真，
      // 不掺和 AiSettingsStore 的 MiniMax 退役迁移语义。
      const legacy =
          '{"provider":"minimax","baseUrl":"https://api.minimaxi.com/v1",'
          '"apiKey":"sk-legacy","model":"my-model"}';
      File(path).writeAsStringSync(legacy);
      expect(MistakeBookCrypto.isEncryptedEnvelope(legacy), isFalse);
      expect(await LocalSecureStore.readSecure(path), legacy);
    });

    test('旧明文数组（聊天历史形态）→ 原样返回', () async {
      const legacy = '[{"role":"user","text":"旧明文"}]';
      File(path).writeAsStringSync(legacy);
      expect(await LocalSecureStore.readSecure(path), legacy);
    });

    test('旧明文带 `//` 注释头 → 原样返回（错题本导出风格兼容）', () async {
      const legacy = '// Biology 错题本导出 — 包含个人数据\n{"entries":[]}';
      File(path).writeAsStringSync(legacy);
      expect(await LocalSecureStore.readSecure(path), legacy,
          reason: 'readSecure 不得对明文做任何改写（含剥头）');
    });

    test('升级：旧明文读回后 writeSecure → 磁盘变 envelope 且仍可解', () async {
      const legacy = '{"apiKey":"sk-upgrade"}';
      File(path).writeAsStringSync(legacy);
      final asPlain = await LocalSecureStore.readSecure(path);
      expect(asPlain, legacy);

      await LocalSecureStore.writeSecure(path, asPlain);
      final raw = File(path).readAsStringSync();
      expect(MistakeBookCrypto.isEncryptedEnvelope(raw), isTrue,
          reason: '下次 save 自动升级为密文（用户无感迁移）');
      expect(raw, isNot(contains('sk-upgrade')));
      expect(await LocalSecureStore.readSecure(path), legacy);
    });

    test('非 JSON 垃圾（旧实现里的"损坏文件"）→ 原样返回，交给调用方判断',
        () async {
      const junk = '不是JSON{{{';
      File(path).writeAsStringSync(junk);
      expect(await LocalSecureStore.readSecure(path), junk,
          reason: '嗅探为"非 envelope"时不得抛——损坏判定属于调用方的 jsonDecode');
    });

    test('空文件 → 原样返回空串（与改造前语义一致）', () async {
      File(path).writeAsStringSync('');
      expect(await LocalSecureStore.readSecure(path), '');
    });
  });

  group('惰性升级 upgradeIfLegacyPlaintext（CAS 护栏）', () {
    Iterable<String> tmpResidue() => tmp
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.tmp'))
        .map((f) => f.path);

    test('expectedRaw 未变（磁盘仍是那份明文）→ 升级成功，磁盘转 envelope',
        () async {
      const legacy = '{"apiKey":"sk-lazy-upgrade","model":"m"}';
      File(path).writeAsStringSync(legacy);
      expect(File(path).readAsStringSync(), contains('sk-lazy-upgrade'),
          reason: '前置：磁盘上是明文');

      // expectedRaw 省略 = 用 plainJson 当磁盘现状（旧明文路径下二者逐字相同）。
      final upgraded =
          await LocalSecureStore.upgradeIfLegacyPlaintext(path, legacy);
      expect(upgraded, isTrue, reason: 'CAS 成立（磁盘没被人动过）⇒ 真的升级了');

      final raw = File(path).readAsStringSync();
      expect(MistakeBookCrypto.isEncryptedEnvelope(raw), isTrue,
          reason: '升级后磁盘必须是密文');
      expect(raw, isNot(contains('sk-lazy-upgrade')),
          reason: '明文 key 不得再裸露');
      expect(await LocalSecureStore.readSecure(path), legacy,
          reason: '升级后仍能逐字解回原明文（内容不丢）');
      expect(tmpResidue(), isEmpty, reason: 'CAS 成功路径不得残留 .tmp');
    });

    test('内容已变（expectedRaw 与磁盘不符）→ 返回 false 且不覆盖', () async {
      const legacy = '{"apiKey":"sk-cas-stale"}';
      File(path).writeAsStringSync(legacy);

      // 调用方读到的是 legacy，但升级期间别的写者已把磁盘换成**新配置**：
      // 这里直接把 expectedRaw 指定成一份过期内容来钉死 CAS 判定。
      final upgraded = await LocalSecureStore.upgradeIfLegacyPlaintext(
        path,
        legacy,
        expectedRaw: '{"apiKey":"sk-cas-stale","model":"stale-snapshot"}',
      );
      expect(upgraded, isFalse, reason: 'CAS 不成立 ⇒ 放弃覆盖，如实返回 false');
      expect(File(path).readAsStringSync(), legacy,
          reason: '放弃时磁盘必须逐字保持现状（既没回滚成过期内容，也没留半成品）');
      expect(tmpResidue(), isEmpty, reason: 'CAS 失败路径要删掉 .tmp');
    });

    test('竞态回归（确定性编排）：加密窗口内迁移 save 落盘 → 迁移内容胜出',
        () async {
      // 真实事故复现（opencode→DeepSeek 迁移链 save 覆盖后台升级）：
      // load() 读到旧明文 → 后台升级启动（要等一次 PBKDF2）→ 迁移链 save()
      // 写入 DeepSeek 新配置 → 升级若无 CAS 就把过期明文回写，provider 从
      // deepseek 被打回 opencode。
      const legacy =
          '{"provider":"opencode","baseUrl":"https://opencode.ai/zen/go/v1",'
          '"apiKey":"sk-legacy-opencode","model":"mimo-v2.5"}';
      const migrated =
          '{"provider":"deepseek","baseUrl":"https://api.deepseek.com",'
          '"apiKey":"sk-legacy-opencode","model":"deepseek-flash"}';
      File(path).writeAsStringSync(legacy);

      // 把「加密窗口」钉成确定时序：升级算好密文后停在闸门里，此时才让迁移落盘。
      final gate = Completer<void>();
      var parkedOn = '';
      LocalSecureStore.debugGateBeforeAtomicReplace = (p) {
        parkedOn = p;
        return gate.future;
      };
      final upgrading =
          LocalSecureStore.upgradeIfLegacyPlaintext(path, legacy,
              expectedRaw: legacy);
      for (var i = 0; i < 1000 && parkedOn.isEmpty; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(parkedOn, path, reason: '前置：升级已走到「密文就绪、尚未替换」的窗口内');

      await LocalSecureStore.writeSecure(path, migrated); // 迁移写入新配置
      gate.complete(); // 放升级继续 ⇒ 它此刻面对的是「磁盘已被别人更新」

      final upgraded = await upgrading;
      expect(upgraded, isFalse,
          reason: '窗口内磁盘已被更新 ⇒ CAS 必须失败，不得谎报升级成功');
      expect(File(path).readAsStringSync(), isNot(contains('"opencode"')),
          reason: '过期明文绝不能被回写');
      expect(await LocalSecureStore.readSecure(path), migrated,
          reason: '最终磁盘内容 = 迁移写入的新配置');
      expect(tmpResidue(), isEmpty, reason: '放弃覆盖时不得残留 .tmp');
    });

    test('已是 envelope → 幂等 no-op（内容不变）', () async {
      const plain = '{"apiKey":"sk-already-enc"}';
      await LocalSecureStore.writeSecure(path, plain);
      final before = File(path).readAsStringSync();
      expect(MistakeBookCrypto.isEncryptedEnvelope(before), isTrue);

      final upgraded =
          await LocalSecureStore.upgradeIfLegacyPlaintext(path, plain);
      expect(upgraded, isFalse, reason: '已是密文 ⇒ 本次没有升级，如实返回 false');
      expect(File(path).readAsStringSync(), before,
          reason: '已加密时不应再触发写，字节应逐字不变');
    });

    test('文件不存在 → 静默返回 false，不抛', () async {
      final upgraded = await LocalSecureStore.upgradeIfLegacyPlaintext(
          '${tmp.path}/nope.json', '{}');
      expect(upgraded, isFalse);
      expect(File('${tmp.path}/nope.json').existsSync(), isFalse);
    });

    test('透传模式（无法派生机器口令）→ 跳过，不把明文反复重写', () async {
      LocalSecureStore.debugForcePassthrough = true;
      const legacy = '{"apiKey":"sk-passthrough"}';
      File(path).writeAsStringSync(legacy);

      final upgraded =
          await LocalSecureStore.upgradeIfLegacyPlaintext(path, legacy);
      expect(upgraded, isFalse, reason: '透传模式永远不升级');
      expect(File(path).readAsStringSync(), legacy,
          reason: '透传模式升级无意义，应保持原明文不动（避免每次 load 反复重写）');
    });
  });

  group('损坏 / 缺失降级（契约 4 / 5）', () {
    test('文件不存在 → LocalSecureUnreadableException', () async {
      await expectLater(
        LocalSecureStore.readSecure('${tmp.path}/never_created.json'),
        throwsA(isA<LocalSecureUnreadableException>()),
      );
    });

    test('口令不匹配（跨机器拷贝）→ LocalSecureCorruptException 且消息可读',
        () async {
      // 模拟"别的机器写来的文件"：同格式、不同口令。
      final foreign = await MistakeBookCrypto.encryptJson(
          '{"apiKey":"sk-from-other-machine"}', 'another-machine-passphrase');
      File(path).writeAsStringSync(foreign);

      await expectLater(
        LocalSecureStore.readSecure(path),
        throwsA(isA<LocalSecureCorruptException>().having(
          (e) => e.message,
          'message',
          contains('本机密钥与密文不匹配'),
        )),
        reason: 'GCM tag 失败必须报明确消息，调用方据此降级',
      );
    });

    test('密文被篡改（翻一个字符）→ LocalSecureCorruptException', () async {
      await LocalSecureStore.writeSecure(path, '{"apiKey":"sk-tamper"}');
      final raw = File(path).readAsStringSync();
      final ct = (jsonDecode(raw) as Map)['ciphertext'] as String;
      final flipped = ct.startsWith('A') ? 'B${ct.substring(1)}' : 'A${ct.substring(1)}';
      File(path).writeAsStringSync(raw.replaceFirst(ct, flipped));

      await expectLater(
        LocalSecureStore.readSecure(path),
        throwsA(isA<LocalSecureCorruptException>()),
        reason: 'authenticated encryption 必须拒绝被改过一个字节的密文',
      );
    });

    test('envelope 字段缺失 / 算法不匹配 → LocalSecureCorruptException，不崩',
        () async {
      final missing = jsonEncode({
        'schemaVersion': 1,
        'cipher': 'aes-256-gcm',
        'salt': base64Encode(List.filled(16, 1)),
        'iv': base64Encode(List.filled(12, 2)),
        // ciphertext / tag 故意缺失
      });
      File(path).writeAsStringSync(missing);
      await expectLater(
        LocalSecureStore.readSecure(path),
        throwsA(isA<LocalSecureCorruptException>()),
      );

      final wrongCipher = jsonEncode({
        'schemaVersion': 1,
        'cipher': 'aes-256-gcm',
        'salt': 'AAAA',
        'iv': 'AAAA',
        'ciphertext': 'AAAA',
        'tag': 'AAAA',
      });
      File(path).writeAsStringSync(wrongCipher);
      // base64 长度非法 / GCM 失败都归一到 Corrupt，而不是抛裸 FormatException。
      await expectLater(
        LocalSecureStore.readSecure(path),
        throwsA(isA<LocalSecureStoreException>()),
      );
    });

    test('异常类型可被基类 catch 覆盖（调用方只需 try/catch 一个类型）', () async {
      File(path).writeAsStringSync(
          await MistakeBookCrypto.encryptJson('{}', 'someone-else'));
      var fellBack = false;
      try {
        await LocalSecureStore.readSecure(path);
      } on LocalSecureStoreException catch (e) {
        fellBack = true;
        expect(e.message, isNotEmpty, reason: '降级日志要有内容可读');
      }
      expect(fellBack, isTrue);
    });
  });

  group('Web / 不可派生 → 明文透传（契约 7）', () {
    test('debugForcePassthrough：writeSecure 写明文，readSecure 原样读',
        () async {
      LocalSecureStore.debugForcePassthrough = true;
      const plain = '{"apiKey":"sk-web"}';

      await LocalSecureStore.writeSecure(path, plain);
      expect(File(path).readAsStringSync(), plain,
          reason: 'Web 端拍板不加密（理由见实现文件头），必须与改造前逐字一致');

      final raw = await LocalSecureStore.readSecure(path);
      expect(raw, plain);
      expect(MistakeBookCrypto.isEncryptedEnvelope(raw), isFalse);
    });

    test('透传模式下不会把已有的密文写坏成"看起来已加密"', () async {
      const plain = '{"apiKey":"sk-x"}';
      await LocalSecureStore.writeSecure(path, plain); // 加密模式
      LocalSecureStore.debugForcePassthrough = true;
      await LocalSecureStore.writeSecure(path, plain); // 切透传
      expect(File(path).readAsStringSync(), plain,
          reason: '透传模式写出的就是明文（该行为只在平台不可派生时出现）');
    });
  });

  group('密钥稳定与缓存语义（契约 8）', () {
    test('同机跨文件：拷贝到另一路径仍能解开（口令派生与路径无关）', () async {
      const plain = '{"apiKey":"sk-copy"}';
      await LocalSecureStore.writeSecure(path, plain);
      final other = '${tmp.path}/ai_chat_history.json';
      File(other).writeAsStringSync(File(path).readAsStringSync());
      expect(await LocalSecureStore.readSecure(other), plain,
          reason: 'salt 在 envelope 里 ⇒ 同机不同路径自解（跨机才失败）');
    });

    test('反复读同一文件结果稳定（缓存的 key 不会改变解密输出）', () async {
      const plain = '{"n":42,"s":"减数分裂"}';
      await LocalSecureStore.writeSecure(path, plain);
      for (var i = 0; i < 5; i++) {
        expect(await LocalSecureStore.readSecure(path), plain,
            reason: '第 $i 次读必须与前一次逐字相同');
      }
      // 写路径也复用同一份派生密钥（热路径不重复跑 100k PBKDF2）。
      await LocalSecureStore.writeSecure(path, '{"n":43}');
      expect(await LocalSecureStore.readSecure(path), '{"n":43}');
    });

    test('读后紧接写复用同一条派生密钥（salt 继承，不重复跑 100k PBKDF2）',
        () async {
      const plain = '{"apiKey":"sk-a"}';
      await LocalSecureStore.writeSecure(path, plain);
      final salt1 =
          (jsonDecode(File(path).readAsStringSync()) as Map)['salt'] as String;

      // 读一次（解密必须用 envelope 里的 salt 派生 → 记为该路径的"写 salt"）。
      expect(await LocalSecureStore.readSecure(path), plain);
      await LocalSecureStore.writeSecure(path, '{"apiKey":"sk-b"}');
      final salt2 =
          (jsonDecode(File(path).readAsStringSync()) as Map)['salt'] as String;

      expect(salt2, salt1,
          reason: '写应沿用读到的 salt ⇒ 命中密钥缓存；换 salt = 每进程多跑一次 KDF');
      expect(await LocalSecureStore.readSecure(path), '{"apiKey":"sk-b"}');
    });

    test('机器密钥文件落在预期路径（每安装随机盐可复用，不重复生成）',
        () async {
      await LocalSecureStore.writeSecure(path, '{"a":1}');
      final keyFile = File('${tmp.path}/.machine.key');
      expect(keyFile.existsSync(), isTrue,
          reason: '派生材料必须落在注入的 debugMachineKeyPath 上');
      final generated = keyFile.readAsStringSync();
      await LocalSecureStore.writeSecure(path, '{"a":2}');
      expect(File('${tmp.path}/.machine.key').readAsStringSync(), generated,
          reason: '口令一旦派生就不该重新生成（否则重启即丢历史）');
      // 模拟"重启进程"：清缓存后仍可解（口令 + salt 都在磁盘上）。
      final stored = File(path).readAsStringSync();
      final keepPath = '${tmp.path}/.machine.key';
      LocalSecureStore.debugResetHooks();
      LocalSecureStore.debugMachineKeyPath = keepPath;
      expect(await LocalSecureStore.readSecure(path), '{"a":2}');
      final again = await LocalSecureStore.debugMachinePassphrase();
      expect(again, isNotNull);
      expect(
          await MistakeBookCrypto.decryptJson(stored, again!),
          '{"a":2}',
          reason: '换进程重新派生的口令依然解得开（稳定性验收）');
    });

    // ── 本仓增量：闸门不许在测试进程里污染真实用户目录 ──
    // 备份仓把这条闸门放在 lib/storage/platform_storage_io.dart（R9-M 批次，
    // 事故背景：并发跑回归时 8 个用户文件被改写）。本仓那条闸门尚未落地，
    // 移植时随本文件一并携带，避免新引入的 `.machine.key` 被测试写进
    // 真实 ~/.biology_app。
    test('未注入 debugMachineKeyPath + FLUTTER_TEST → 闸门拦住真实用户目录写入',
        () async {
      LocalSecureStore.debugResetHooks();
      LocalSecureStore.debugMachineKeyPath = null; // 模拟「测试没做隔离」
      expect(
        debugSkipUserDirWrite('.machine.key', hasIsolatedPath: false),
        isTrue,
        reason: '测试进程未注入隔离路径时必须拦下真实用户目录写入',
      );
      // 但显式注入了隔离路径的用例照常放行。
      expect(
        debugSkipUserDirWrite('.machine.key', hasIsolatedPath: true),
        isFalse,
        reason: 'hasIsolatedPath 为真 = 调用方自己管好了路径，不拦',
      );
    });
  });

  // ── 契约 9：派生位置（内联 vs 子 isolate）两条路径都必须可用 ──
  // 立此组的原因是一条**实测踩到的挂死**（不是理论担忧）：
  // 最初 KDF 无条件跑 `Isolate.run`，于是
  // `test/ai_assistant_test.dart`「问AI 面板（widget） 历史恢复」在
  // `await AiChatStore.save()` 处永久卡住——`testWidgets` 体内不能 `await`
  // 只能由**真实事件循环**投递的 isolate 回信（FakeAsync 永不跑真实循环）。
  // 修复 = 测试进程内联派生。下面 4 条把这个约束钉死，两条路径都有覆盖。
  group('派生路径与 widget 测试不死锁（契约 9）', () {
    test('探针：flutter test 进程确实注入了 FLUTTER_TEST=true（自动内联的前提）',
        () {
      // 这条断言不是形式主义：`_inlineDeriveRequired` 的判定前提就是这个变量。
      // 若哪天 flutter 改了注入方式，本条先红，而不是让 widget 测试悄悄挂死。
      expect(Platform.environment['FLUTTER_TEST'], 'true',
          reason: 'LocalSecureStore 靠它决定测试内内联派生；变了就要改判定');
    });

    test('生产那条路径（强制 Isolate.run）roundtrip 可用且与内联同解', () async {
      const plain = '{"apiKey":"sk-isolate-path","name":"李明"}';
      LocalSecureStore.debugForceInlineDerive = false; // 强制子 isolate
      await LocalSecureStore.writeSecure(path, plain);
      expect(MistakeBookCrypto.isEncryptedEnvelope(File(path).readAsStringSync()),
          isTrue);
      LocalSecureStore.debugResetHooks();
      LocalSecureStore.debugMachineKeyPath = '${tmp.path}/.machine.key';
      LocalSecureStore.debugForceInlineDerive = true; // 换内联路径去解
      expect(await LocalSecureStore.readSecure(path), plain,
          reason: '两条路径必须派生出同一把 key（同口令 + envelope 内同 salt）');
    });

    testWidgets('testWidgets 体内裸 await writeSecure/readSecure 不挂起',
        (tester) async {
      // 刻意**不用** tester.runAsync 包裹：runAsync 会替我们泵真实事件循环，
      // 那样就测不到 ai_assistant_test 的原始故障形态了。
      const plain = '[{"role":"user","text":"减数分裂是什么"}]';
      await LocalSecureStore.writeSecure(path, plain);
      final back = await LocalSecureStore.readSecure(path);
      expect(back, plain);
      expect(MistakeBookCrypto.isEncryptedEnvelope(File(path).readAsStringSync()),
          isTrue,
          reason: 'widget 测试里也必须真加密，不能因绕开 isolate 而透传降级');
    });

    testWidgets('widget 测试里连续两次 save 只付一次 KDF（缓存生效 → 不拖慢测试）',
        (tester) async {
      await LocalSecureStore.writeSecure(path, '{"n":1}');
      final salt1 =
          (jsonDecode(File(path).readAsStringSync()) as Map)['salt'] as String;
      await LocalSecureStore.writeSecure(path, '{"n":2}');
      final salt2 =
          (jsonDecode(File(path).readAsStringSync()) as Map)['salt'] as String;
      expect(salt2, salt1, reason: '第二次写应命中密钥缓存（同 salt）');
      expect(await LocalSecureStore.readSecure(path), '{"n":2}');
    });
  });
}
