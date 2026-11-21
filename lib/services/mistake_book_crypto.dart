// mistake_book_crypto.dart —— 错题本 AES-GCM 端到端加密服务。
//
// v2.13 R8-P1：闭环 R6-P1 路线图 P1 隐私根因 2/4——磁盘明文 JSON。
// R6-P1 已做「默认 desensitize=true + 引导文案 + 5s 长 SnackBar」，但
// 浅脱敏是 token 级正则，无法 100% 覆盖罕见姓氏 / 学号变体；落到下载
// 目录 / 公共存储后其他 app 可读全文——剩余 3 个 P1 风险场景（设备失控
// / 跨设备分享 / 漏网人名）必须靠端到端加密消除。
//
// 设计选择：
//   - AES-256-GCM（authenticated encryption）：同时保证机密性 + 完整性
//     篡改密文 → GCM tag 校验失败 → 抛错（不会"半解出"明文）
//   - PBKDF2-HMAC-SHA256 + 100k iterations：从口令派生 32 字节 key
//     100k 是 OWASP 2023 推荐值，桌面耗时 ~50-200ms（防暴力破解）
//   - 随机 salt（16 字节）+ 随机 IV（12 字节）：同一口令加密两次
//     同一明文 → 密文不同；彩虹表无效
//   - 包格式：文本（`//` 注释头 + JSON），用户可手工 copy/paste 备份
//
// 不写三端 facade（io.dart / web.dart / stub.dart）：
//   - cryptography 2.9 是纯 Dart 实现，跨端同代码，无 platform channel
//   - 不需要 browser-specific API（SubtleCrypto / Web Crypto）
//   - Dart VM 性能足够（PBKDF2 100k 在桌面 ~80ms，Web 端 dart2js 后
//     ~300ms，导出流程本来就 1s+，不感知）
//   - 引入三端 facade 反而增加目录 + 调试成本
//
// 注：cryptography 2.9 只提供 async API（deriveKey/encrypt/decrypt 都是
// Future），所以 encryptJson/decryptJson 必须是 async，调用方 await。

import 'dart:convert';
import 'dart:math' as math;

import 'package:cryptography/cryptography.dart';

/// 加密 envelope 的 schema 版本号（与 MistakeBook JSON schemaVersion 平行）。
///
/// 演进策略：
///   - v1（当前）：AES-256-GCM + PBKDF2-HMAC-SHA256 100k
///   - v2+：可换 Argon2 / 加版本字段 / 改 KDF 参数
const int _envelopeSchemaVersion = 1;

/// PBKDF2 迭代次数（OWASP 2023 推荐 ≥ 100k）。
const int _kdfIterations = 100000;

/// Salt 长度（字节）。
const int _saltLength = 16;

/// AES-GCM nonce 长度（字节），GCM 标准 = 12。
const int _ivLength = 12;

/// 派生 key 长度（字节），AES-256 = 32。
const int _keyLength = 32;

/// 算法标识符（写入 envelope，方便未来 v2+ 改算法时路由）。
const String _kdfId = 'pbkdf2-sha256';
const String _cipherId = 'aes-256-gcm';

/// 错题本 AES-GCM 端到端加密门面。
///
/// 静态类 + 纯函数，零状态（便于测试 + 多窗口共享）。
/// 依赖包：cryptography 2.9.0（pubspec 已加）。
class MistakeBookCrypto {
  MistakeBookCrypto._();

  /// 加密学安全随机数源（dart:math.Random.secure() 包成统一接口，
  /// 方便测试时换 deterministic source 验证 salt/IV 唯一性）。
  static final math.Random _secure = math.Random.secure();

  /// 检测 [raw] 是否为加密 envelope。
  ///
  /// 启发式：剥离前导 `//` 注释 + BOM + 空白行后，jsonDecode 出来的
  /// object 含 `cipher == 'aes-256-gcm'` 字段即视为加密包。
  ///
  /// 失败返回 false（让 importJson 走老明文路径）；**不**抛错。
  static bool isEncryptedEnvelope(String raw) {
    if (raw.isEmpty) return false;
    final cleaned = _stripCommentHeader(raw);
    if (cleaned.isEmpty) return false;
    try {
      final decoded = jsonDecode(cleaned);
      if (decoded is! Map) return false;
      return decoded['cipher'] == _cipherId;
    } catch (_) {
      return false;
    }
  }

  /// 加密明文 JSON，返回 envelope 字符串。
  ///
  /// [plaintext]：明文 JSON（已含 desensitize 处理与否无关，加密层只
  /// 看字节；调用方决定是否先脱敏再加密——本方法推荐直接传「未脱敏」
  /// 明文，因为加密后全文不可读，没必要再脱敏）。
  /// [passphrase]：用户口令。**不**做格式校验（"123" 也接受，因为
  /// 长口令由用户自觉负责；弱口令的风险教育应在 dialog 文案层做）。
  ///
  /// 抛错：
  ///   - [passphrase] 为空 → [ArgumentError]
  ///   - 加密失败（理论上不发生）→ [FormatException]
  static Future<String> encryptJson(String plaintext, String passphrase) async {
    if (passphrase.isEmpty) {
      throw ArgumentError('passphrase 不能为空');
    }
    final salt = _randomBytes(_saltLength);
    final iv = _randomBytes(_ivLength);

    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _kdfIterations,
      bits: _keyLength * 8,
    );
    final aesGcm = AesGcm.with256bits();

    // cryptography 2.9 只暴露 async API（100k iterations 在桌面 ~80ms，
    // await 期间 UI 仍可响应——导出流程本来就 1s+，用户感知不到）。
    final secretKey = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
    final clearBytes = utf8.encode(plaintext);
    final secretBox = await aesGcm.encrypt(
      clearBytes,
      secretKey: secretKey,
      nonce: iv,
    );

    final envelope = <String, dynamic>{
      'schemaVersion': _envelopeSchemaVersion,
      'kdf': _kdfId,
      'cipher': _cipherId,
      'kdfIterations': _kdfIterations,
      'salt': base64Encode(salt),
      'iv': base64Encode(iv),
      'ciphertext': base64Encode(secretBox.cipherText),
      'tag': base64Encode(secretBox.mac.bytes),
    };
    final body = const JsonEncoder.withIndent('  ').convert(envelope);
    // 加 `//` 注释头，与明文 exportJson 风格对齐（导入侧统一剥）。
    final header = StringBuffer()
      ..writeln('// Biology 错题本加密导出（AES-256-GCM，PBKDF2 100k）')
      ..writeln('// 警告：此文件已加密，分享时请通过安全渠道告知口令')
      ..writeln('// 算法：$_cipherId + $_kdfId × $_kdfIterations');
    return '$header$body';
  }

  /// 解密 envelope，返回明文 JSON 字符串。
  ///
  /// 抛错：
  ///   - [passphrase] 为空 → [ArgumentError]
  ///   - [envelope] 不是加密包（无 cipher 字段 / 损坏 JSON）→ [FormatException]
  ///   - [passphrase] 错（GCM tag 校验失败）→ [FormatException]
  ///   - envelope 字段缺失（salt / iv / tag / ciphertext）→ [FormatException]
  static Future<String> decryptJson(String envelope, String passphrase) async {
    if (passphrase.isEmpty) {
      throw ArgumentError('passphrase 不能为空');
    }
    final cleaned = _stripCommentHeader(envelope);
    final dynamic decoded;
    try {
      decoded = jsonDecode(cleaned);
    } on FormatException catch (e) {
      throw FormatException('加密包 JSON 解析失败：${e.message}');
    }
    if (decoded is! Map) {
      throw const FormatException('加密包根必须是 object');
    }
    final cipher = decoded['cipher']?.toString();
    final saltB64 = decoded['salt']?.toString();
    final ivB64 = decoded['iv']?.toString();
    final ctB64 = decoded['ciphertext']?.toString();
    final tagB64 = decoded['tag']?.toString();
    if (cipher != _cipherId ||
        saltB64 == null ||
        ivB64 == null ||
        ctB64 == null ||
        tagB64 == null) {
      throw const FormatException('加密包字段缺失或算法不匹配');
    }
    final salt = base64Decode(saltB64);
    final iv = base64Decode(ivB64);
    final ciphertext = base64Decode(ctB64);
    final tag = base64Decode(tagB64);

    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _kdfIterations,
      bits: _keyLength * 8,
    );
    final aesGcm = AesGcm.with256bits();
    final secretKey = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(passphrase)),
      nonce: salt,
    );
    final secretBox = SecretBox(ciphertext, nonce: iv, mac: Mac(tag));
    try {
      final clearBytes =
          await aesGcm.decrypt(secretBox, secretKey: secretKey);
      return utf8.decode(clearBytes);
    } on SecretBoxAuthenticationError {
      // GCM tag 校验失败 = 口令错 或 密文被篡改
      throw const FormatException('口令错误或密文被篡改（解密失败）');
    } catch (e) {
      throw FormatException('解密失败：$e');
    }
  }

  /// 剥离前导 `//` 注释行 + BOM + 空白行（与 MistakeBook._stripExportHeader
  /// 同款；独立复刻避免跨文件 import 依赖）。
  static String _stripCommentHeader(String raw) {
    var s = raw;
    if (s.startsWith('﻿')) s = s.substring(1);
    final lines = s.split('\n');
    var i = 0;
    while (i < lines.length) {
      final line = lines[i].trim();
      if (line.isEmpty) {
        i++;
        continue;
      }
      if (line.startsWith('//')) {
        i++;
        continue;
      }
      break;
    }
    return lines.sublist(i).join('\n');
  }

  /// 加密学安全随机字节（[n] 字节）。
  ///
  /// 用 dart:math.Random.secure() 作为 CSPRNG（Windows 走 BCryptGenRandom），
  /// 与 cryptography 2.9 内部默认同源——保证 salt / IV 不可预测。
  static List<int> _randomBytes(int n) {
    final out = List<int>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      out[i] = _secure.nextInt(256);
    }
    return out;
  }
}
