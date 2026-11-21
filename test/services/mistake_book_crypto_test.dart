// mistake_book_crypto_test.dart —— 错题本 AES-GCM 端到端加密单元测试。
//
// v2.13 R8-P1：闭环 R6-P1 路线图 P1 隐私根因 2/4——磁盘明文 JSON。
// 重点验证：
//   1. encrypt → decrypt roundtrip 字节级一致
//   2. 错口令 / 篡改密文 → GCM tag 校验失败 → 抛 FormatException
//   3. envelope 字段缺失 / 损坏 → 抛 FormatException
//   4. isEncryptedEnvelope 启发式正确（明文 / 加密 / 损坏 三种输入）
//   5. 同明文 + 同口令 两次加密 → 密文不同（salt + IV 随机）
//   6. UTF-8 中文 roundtrip（含人名 / 学号 / 考点）
//   7. 边界：空字符串 / 长字符串（10KB）/ 特殊字符

import 'package:biology/services/mistake_book_crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MistakeBookCrypto encrypt/decrypt roundtrip', () {
    test('明文 + 口令 → 加密 → 解密 字节级一致', () async {
      const plain = '{"entries":[{"id":"m1","stem":"今天张三答错"}]}';
      const passphrase = 'correct horse battery staple';

      final envelope = await MistakeBookCrypto.encryptJson(plain, passphrase);
      expect(envelope.startsWith('// Biology 错题本加密导出'),
          isTrue,
          reason: 'envelope 有注释头');
      expect(MistakeBookCrypto.isEncryptedEnvelope(envelope), isTrue);

      final decrypted = await MistakeBookCrypto.decryptJson(envelope, passphrase);
      expect(decrypted, plain, reason: 'decrypt 后字节级一致');
    });

    test('错口令 → 抛 FormatException（GCM tag 校验失败）', () async {
      const plain = '{"x":1}';
      const right = 'right passphrase';
      const wrong = 'wrong passphrase';

      final envelope = await MistakeBookCrypto.encryptJson(plain, right);
      expect(
        () => MistakeBookCrypto.decryptJson(envelope, wrong),
        throwsA(isA<FormatException>()),
        reason: '错口令必须被 GCM tag 拒绝',
      );
    });

    test('密文被篡改 → 抛 FormatException（authenticated encryption）', () async {
      const plain = '{"x":1}';
      const passphrase = 'p';

      final envelope = await MistakeBookCrypto.encryptJson(plain, passphrase);

      // 提取 ciphertext 字段的 base64，翻转其中一个字符模拟篡改
      final lines = envelope.split('\n');
      // 找 "ciphertext": "..." 行
      final ctLine = lines.firstWhere((l) => l.contains('"ciphertext"'));
      final start = ctLine.indexOf('"') + 1;
      final end = ctLine.lastIndexOf('"');
      final b64 = ctLine.substring(start, end);
      // 翻转第 1 个非空字符
      final flipped = b64.substring(0, 1) == 'A'
          ? 'B${b64.substring(1)}'
          : 'A${b64.substring(1)}';
      final tampered = envelope.replaceFirst(b64, flipped);

      expect(
        () => MistakeBookCrypto.decryptJson(tampered, passphrase),
        throwsA(isA<FormatException>()),
        reason: 'GCM authenticated encryption 必须检测密文篡改',
      );
    });

    test('envelope 字段缺失 → 抛 FormatException', () async {
      const incomplete = '''{
  "schemaVersion": 1,
  "kdf": "pbkdf2-sha256",
  "cipher": "aes-256-gcm"
}''';
      expect(
        () => MistakeBookCrypto.decryptJson(incomplete, 'p'),
        throwsA(isA<FormatException>()),
        reason: '缺 salt/iv/ciphertext/tag 必须拒绝',
      );
    });

    test('算法不匹配（cipher=foo）→ 抛 FormatException', () async {
      const wrongCipher = '''{
  "schemaVersion": 1,
  "cipher": "aes-128-cbc",
  "salt": "AAAA",
  "iv": "AAAA",
  "ciphertext": "AAAA",
  "tag": "AAAA"
}''';
      expect(
        () => MistakeBookCrypto.decryptJson(wrongCipher, 'p'),
        throwsA(isA<FormatException>()),
        reason: '未来版本可换算法，旧 v1 解密路径拒绝不匹配',
      );
    });

    test('空 passphrase → ArgumentError', () async {
      expect(
        () => MistakeBookCrypto.encryptJson('plain', ''),
        throwsA(isA<ArgumentError>()),
        reason: 'exportEncryptedJson(passphrase) 不允许空口令',
      );
      expect(
        () => MistakeBookCrypto.decryptJson('envelope', ''),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('MistakeBookCrypto isEncryptedEnvelope 启发式', () {
    test('明文 JSON → 返回 false', () {
      const plain = '{"schemaVersion":1,"entries":[]}';
      expect(MistakeBookCrypto.isEncryptedEnvelope(plain), isFalse);
    });

    test('明文 JSON 带注释头 → 返回 false（脱敏导出的格式）', () {
      const plain =
          '// Biology 错题本导出 — 包含个人数据\n{"schemaVersion":1,"entries":[]}';
      expect(MistakeBookCrypto.isEncryptedEnvelope(plain), isFalse);
    });

    test('加密 envelope → 返回 true', () async {
      final envelope =
          await MistakeBookCrypto.encryptJson('{"x":1}', 'pass');
      expect(MistakeBookCrypto.isEncryptedEnvelope(envelope), isTrue);
    });

    test('损坏 JSON → 返回 false（不抛错）', () {
      const broken = 'not json at all';
      expect(MistakeBookCrypto.isEncryptedEnvelope(broken), isFalse);
    });

    test('空字符串 → 返回 false', () {
      expect(MistakeBookCrypto.isEncryptedEnvelope(''), isFalse);
    });

    test('JSON 根非 object（数组）→ 返回 false', () {
      const arr = '[1,2,3]';
      expect(MistakeBookCrypto.isEncryptedEnvelope(arr), isFalse);
    });
  });

  group('MistakeBookCrypto 安全属性', () {
    test('同明文 + 同口令 两次加密 → 密文不同（salt + IV 随机）', () async {
      const plain = '{"x":1}';
      const passphrase = 'p';

      final e1 = await MistakeBookCrypto.encryptJson(plain, passphrase);
      final e2 = await MistakeBookCrypto.encryptJson(plain, passphrase);
      expect(e1, isNot(equals(e2)),
          reason: 'salt 16 字节 + IV 12 字节随机 → 密文不可预测');

      // 但解密结果一致
      final p1 = await MistakeBookCrypto.decryptJson(e1, passphrase);
      final p2 = await MistakeBookCrypto.decryptJson(e2, passphrase);
      expect(p1, plain);
      expect(p2, plain);
    });

    test('UTF-8 中文 roundtrip（含人名 / 学号 / 考点）', () async {
      const plain =
          '{"stem":"今天张小明被选为班委","id":"20260001","subjectArea":"减数分裂"}';
      const passphrase = '生物学生';

      final envelope = await MistakeBookCrypto.encryptJson(plain, passphrase);
      final decrypted = await MistakeBookCrypto.decryptJson(envelope, passphrase);
      expect(decrypted, plain);
      expect(decrypted, contains('张小明'),
          reason: '中文姓名 byte 完整往返');
      expect(decrypted, contains('20260001'),
          reason: '学号 byte 完整往返');
    });

    test('长字符串 10KB roundtrip', () async {
      final buf = StringBuffer('{"data":"');
      for (var i = 0; i < 10000; i++) {
        buf.write('今天张三答对');
      }
      buf.write('"}');
      final plain = buf.toString();
      const passphrase = 'p';

      final envelope = await MistakeBookCrypto.encryptJson(plain, passphrase);
      final decrypted = await MistakeBookCrypto.decryptJson(envelope, passphrase);
      expect(decrypted, plain);
    });
  });
}
