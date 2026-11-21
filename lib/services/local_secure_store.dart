// local_secure_store.dart —— 本机配置文件「透明加密读写」原语。
//
// 移植自早期备份仓库（v2.10 拍题入口分离完成版本，该仓 R9-B / R9-E 批次）。本仓对应债务记录见
// `lib/pages/settings_page.dart` 的 `AiSettingsStore.save` 注释——
// v2.11 M4 安全注释（v2.19.30 诚实化修订）点名的「v2.12 引入 cryptography
// 做 AES-GCM 加密」未兑现项。本文件把它兑现。
//
// 闭环找茬报告实证的两块残留明文落盘（目录 `~/.biology_app/`）：
//   - `ai_config.json`：设置页填入的 API Key 明文可被任何本机使用者打开直读；
//   - `ai_chat_history.json`：AI 聊天历史明文（含题目图片描述、
//     可能含学生 / 家长 / 老师姓名）。
// 错题本**导出文件**早已是端到端加密（MistakeBookCrypto），但日常落盘的
// 两个配置文件仍是明文——导出加密只保护「离开设备的那份拷贝」。
//
// ───────────────────────── API 契约（冻结）─────────────────────────
//   Future<void>   writeSecure(String path, String plainJson)  // 明文→密文落盘
//   Future<String> readSecure(String path)                     // 密文/旧明文自动识别
// 其余成员全部 private 或 @visibleForTesting，不构成生产 API。
//
// 向后兼容（硬要求）：
//   1. `readSecure` 先嗅探：envelope → 解密；旧明文 JSON（含 `//` 注释头）→
//      **原样返回**，下一次 `writeSecure` 自动升级为密文（用户无感迁移）。
//   2. 文件缺失 / 损坏密文 / 口令不匹配 → 抛 [LocalSecureStoreException]
//      子类，由调用方 try/catch 降级到既有 fallback（`AiConfig.fromEnv()` /
//      空历史）——**绝不**把异常冒到 App 启动链上造成白屏。
//      （本仓实测事故：`ai_chat_controller.dart:278` 注释记载的 9/25 机器
//      key 轮换 → 解密失败 → 测试被打成「未配置」分支，v215_r6 全量红。）
//   3. 文件路径不变（envelope 内嵌在原文件里，不新增 sidecar 密文文件）。
//
// ─────────────────────── 威胁模型（诚实边界）───────────────────────
// 防：casual disclosure——讲台机上任何人用记事本打开 `ai_config.json`
//     就看见 `sk-...` 明文 key / 打开 `ai_chat_history.json` 就看见学生姓名。
// 不防：取证级 / 同权限攻击——passphrase 的三个派生源（hostname、
//     `USERNAME`、`.machine.key`）**全部落在同一台机器上**，能读密文的进程
//     同样能读到派生材料并跑同一段代码。`.machine.key` 与密文同目录同权限，
//     是「锁和钥匙放同一间屋」——这是**本机透明加密的天花板**，不是实现缺陷。
//     越过它必须引入用户口令或系统级密钥库（flutter_secure_storage /
//     Windows DPAPI），属另一轮范围（pubspec 的注释已记该 TODO）。
// 仍成立：跨机器拷贝这两个文件 → 本机解不开 → 走降级路径（不崩，丢配置）。
//
// ───────────────────────── web 端策略（明确不加密）─────────────────
// `kIsWeb == true` ⇒ 两个方法都**明文透传**（与改造前行为逐字一致）。三条理由：
//   1. Web 端根本不走 File 分支：`settings_page.dart` 的 `_isWebStorage` 走
//      localStorage（`storageGet/storageSet`），本改造点只覆盖 File 分支。
//   2. dart2js 的 `dart:io` 是 stub：`Platform.environment` /
//      `Platform.localHostname` 在 Web 端抛 UnimplementedError，本工程
//      v2.12 R1 C P0 #7 就是被「Web 端 File 构造抛 UnimplementedError 被
//      catch 吞掉」坑过），拿不到任何**重装后仍稳定**的机器特征 ⇒ 派生不出口令。
//   3. 浏览器里唯一能存口令的地方就是 localStorage / IndexedDB——与密文同源
//      同权限，等于把「明文」换成「明文密钥 + 密文」，攻击面没缩小，自欺。
//      真正的 Web 端方案要服务端下发或用户口令（另一条产品决策）。
// 因此 Web 端「保持现状」不是遗漏，而是本轮拍板；代码里的对应分支带
// `WEB-PASSTHROUGH` 标记，便于复审定位。
//
// ───────────── 为什么复用「引擎格式」而非逐字调用 MistakeBookCrypto ─────────────
// 加密引擎 = `cryptography` 2.9 的 AES-256-GCM + PBKDF2-HMAC-SHA256 × 100k，
// envelope 字段与 `MistakeBookCrypto` v1 逐字对齐（`isEncryptedEnvelope` 能嗅探、
// `decryptJson(env, 机器口令)` 能解开——测试 `test/services/local_secure_store_test.dart`
// 有一条 cross-decrypt 断言专门钉死这个互操作性）。
// 但**不能**直接调 `MistakeBookCrypto.encryptJson/decryptJson`：它的 API 把
// 「随机 salt + 100k PBKDF2 + AES-GCM」焊死在一次调用里，每次调用必重跑 KDF。
// 源仓实测（`cryptography` 纯 Dart）：
//     AOT（dart compile exe，真实发行形态）：4 轮 763 / 770 / 772 / 774 ms
//     JIT（flutter test）：enc 385 ms / dec 411 ms
// 而这两个 store 都在热路径上（grep 实证）：`AiSettingsStore.load()` 被
//     `ai_chat_controller.dart:184/:276/:391`、`ai_fill_params.dart:55`、
//     `mistake_book_ai.dart:234` 调用——**每次向 AI 发问都要读一次**；
//     `AiChatStore.save()` 被 `ai_chat_controller.dart:148 _persist()` 在**每条消息**
//     后调用。逐字套用 = 每条消息 / 每次发问固定多 ~770ms 且发生在 UI isolate 上。
// ⇒ 本文件的实现选择：**同算法 + 同 envelope 格式**，KDF 结果按 salt 缓存
//   （每进程每文件 ≤1 次）且跑在 `Isolate.run` 里（UI 不冻结），
//   之后 AES-GCM 是纯内存运算（<1ms），磁盘写是**同步且原子**（临时文件
//   writeAsStringSync + rename 覆盖，见 writeSecure）——读方永远看不到半截文件。
//   **但要如实说明**：正因为 KDF 在子 isolate，
//   `writeSecure` 是异步的——真正的 `writeAsStringSync` 要等 `_protect()`
//   resolve 之后才跑。所以调用方**必须 await** 这个 Future，否则应用在被杀掉时
//   这次写入可能永远没落盘。
//   ⚠️ **本仓遗留（移植时如实记账，未纳入本轮修复）**：
//   源仓后来把 `ai_chat_controller` 的 `_persist()` / `clearHistory()` 全改成
//   await 收口（还加了串行落盘队列），本仓**仍是 fire-and-forget**
//   （`ai_chat_controller.dart:147-156`）。即：聊天历史存在「进程被杀的那一瞬
//   丢掉本次写入」的窗口——这是相对改造前（同步明文写）新增的弱化。
//   修法是 await 收口（+ 队列），属 ai_chat_controller 的独立一轮。
// 派生跑在哪：**生产 = 子 isolate；flutter test = 本 isolate 内联**
//   （`_inlineDeriveRequired`，判据是 `FLUTTER_TEST=true`）。原因见
//   `_deriveOffUi` / `_pbkdf2Derive` 两处注释——`testWidgets` 的 FakeAsync
//   既不兑现 isolate 回信，也不兑现 `Future.delayed`，任一条都会让
//   `await AiChatStore.save()` 永久挂起（源仓实测各卡满 10 分钟超时）。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart' show DartPbkdf2;
import 'package:flutter/foundation.dart';

import '../storage/platform_storage_io.dart'
    if (dart.library.html) '../storage/platform_storage_web.dart';
import 'mistake_book_crypto.dart';

// ── envelope 参数：与 MistakeBookCrypto v1 逐字对齐（跨实现互操作的前提）──
const int _envelopeSchemaVersion = 1;
const int _kdfIterations = 100000; // OWASP 2023 推荐 ≥100k，与导出引擎同值
const int _saltLength = 16;
const int _ivLength = 12;
const int _keyLength = 32;
const String _kdfId = 'pbkdf2-sha256';
const String _cipherId = 'aes-256-gcm';

/// 应用内固定盐：写进 passphrase，保证「同样的 hostname + 用户名」在不同应用
/// 之间派生出不同密钥（域分离）。
const String _appId = 'biology.local_secure_store.v1';

/// 每安装随机机器密钥的文件名（放在 `userAppDir()` 下）。
const String _machineKeyFileName = '.machine.key';

/// 派生密钥缓存条数上限（本机只有 2 个受保护文件，8 已经非常宽松；
/// 超限时整体清空，防长会话里 salt 无限累积）。
const int _maxCachedKeys = 8;

final math.Random _secureRandom = math.Random.secure();

/// 测试写盘闸门：`flutter test` 未注入隔离路径时，**禁止**往真实用户目录
/// （`~/.biology_app`）写任何文件。
///
/// ⚠️ 与源仓的差异（如实记账）：源仓把这条闸门放在
/// `lib/storage/platform_storage_io.dart` / `_web.dart`（条件导入同名签名），
/// 由 8 个 store 逐个 opt-in 调用。本仓那一层**没有**这个函数，本轮也不去
/// 改共享存储层（超范围），因此随本文件携带一份实现，供 `settings_page.dart`
/// 的两个 store 复用。签名与语义与源仓一致，未来与源仓对齐时只需改 import。
///
/// 事故背景（源仓 R9-M 🔴）：load() 侧的 FLUTTER_TEST 守卫在写盘侧漏掉时，
/// 跑一遍回归就把用户真实 `ai_config.json` / `ai_chat_history.json` 覆盖成
/// 用例数据；并发跑测试的那次实测有 8 个用户文件在 3 分钟内被改写。
/// 语义：`hasIsolatedPath` 为调用方自己的 `debugFilePath` 类注入是否非空。
/// 返 true = 本次写盘必须跳过（调用方直接 return，不抛错、不静默丢正常链路）。
bool debugSkipUserDirWrite(String target, {required bool hasIsolatedPath}) {
  if (hasIsolatedPath) return false;
  try {
    if (Platform.environment['FLUTTER_TEST'] == 'true') {
      debugPrint('FLUTTER_TEST 写盘闸门：跳过真实用户目录写入 $target');
      return true;
    }
  } catch (_) {
    // Web 的 dart:io 是 stub：拿不到环境变量就按「非测试」处理。
  }
  return false;
}

/// PBKDF2-HMAC-SHA256 派生（**顶层纯函数**：`Isolate.run` 闭包只捕获
/// sendable 的 `List<String>`，不读任何 root isolate 的可变状态）。
///
/// args = [passphrase, salt(base64)]，返回 32 字节 key。
///
/// 为什么用 `DartPbkdf2` 而不是 `Pbkdf2(...)` 工厂：两者在 VM 上是**同一个类、
/// 同一套参数**（`Cryptography.instance.pbkdf2()` 内部就是
/// `DartPbkdf2(macAlgorithm:, iterations:, bits:)`，见
/// `cryptography-2.9.0/lib/src/dart/cryptography.dart:233`），派生结果逐字节相同
/// ⇒ 与 `MistakeBookCrypto` 的互操作性不受影响（有 cross-decrypt 断言钉死）。
/// 区别只在我显式传了 `pausePeriod: Duration.zero`：
/// 默认实现每 2000 轮 `await Future.delayed(1ms)` 让出主事件循环
/// （`src/dart/pbkdf2.dart:101-105`），100k 轮 = 50 次真实定时器。
///   * 生产路径：KDF 跑在子 isolate，让不让出都不影响 UI ⇒ 收益为零。
///   * 测试路径：`Future.delayed` 只能由**真实事件循环**兑现，
///     `testWidgets` 的 FakeAsync 永不跑真实循环 ⇒ 裸 `await` 直接死锁
///     （源仓实测：`test/ai_assistant_test.dart`「历史恢复」在
///     `await AiChatStore.save()` 处卡满 10 分钟超时，见 `_deriveOffUi` 注释）。
/// 关掉暂停 = 一次性算完（JIT 实测 ~385–411ms，AOT ~770ms，都在子 isolate
/// 或测试进程里），既保住 UI 又保住可测试性。
Future<List<int>> _pbkdf2Derive(List<String> args) async {
  final pbkdf2 = DartPbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: _kdfIterations,
    bits: _keyLength * 8,
    pausePeriod: Duration.zero,
  );
  final key = await pbkdf2.deriveKey(
    secretKey: SecretKey(utf8.encode(args[0])),
    nonce: base64Decode(args[1]),
  );
  return key.extractBytes();
}

/// 剥掉前导 BOM / 空行 / `//` 注释行。
///
/// 为什么要有：本文件自己写的 envelope 是无头的纯 JSON，但
/// `MistakeBookCrypto.encryptJson`（错题本导出）写出来的是**带 3 行 `//` 头**
/// 的——用户把导出文件误当配置文件放回原位、或跨机器拷贝时，`readSecure`
/// 必须先剥头再 parse，才能把「口令不匹配」报成明确消息而不是
/// 「JSON 解析失败」这种误导性降级理由。
/// （与 `MistakeBookCrypto._stripCommentHeader` 同款实现——那份是 private，
/// 不能跨文件复用，故此处独立复刻；行为差异由测试钉住。）
String _stripCommentHeader(String raw) {
  var s = raw;
  if (s.startsWith('﻿')) s = s.substring(1);
  final lines = s.split('\n');
  var i = 0;
  while (i < lines.length) {
    final line = lines[i].trim();
    if (line.isEmpty || line.startsWith('//')) {
      i++;
      continue;
    }
    break;
  }
  return lines.sublist(i).join('\n');
}

/// [LocalSecureStore] 读写失败基类。调用方 catch 这个基类即可覆盖全部
/// 降级场景（设计成异常而不是返回 null，是为了让「文件不存在」与
/// 「密文损坏」在日志里可区分，同时不污染 `readSecure` 的返回类型）。
class LocalSecureStoreException implements Exception {
  const LocalSecureStoreException(this.message, [this.path]);

  final String message;

  /// 出问题的文件路径（可能为 null）。
  final String? path;

  @override
  String toString() =>
      '$runtimeType: $message${path == null ? '' : ' [$path]'}';
}

/// 文件不可读（不存在 / 无权限 / 平台不支持 File）。
class LocalSecureUnreadableException extends LocalSecureStoreException {
  const LocalSecureUnreadableException(super.message, [super.path]);
}

/// 密文损坏 / 本机密钥不匹配（含跨机器拷贝、手工改过字节、字段缺失）。
class LocalSecureCorruptException extends LocalSecureStoreException {
  const LocalSecureCorruptException(super.message, [super.path]);
}

/// 本机自动加密读写原语（AES-256-GCM + 机器派生口令）。见文件头契约。
class LocalSecureStore {
  LocalSecureStore._();

  // ── 进程内缓存（全部只在 root isolate 读写；派生本身在子 isolate）──
  static final Map<String, List<int>> _derivedKeys = <String, List<int>>{};
  static final Map<String, Future<List<int>>> _deriving =
      <String, Future<List<int>>>{};
  static final Map<String, String> _pathSalt = <String, String>{};
  static String? _passphrase;
  static bool _passphraseResolved = false;
  static String _deviceSecret = '';
  static bool _deviceSecretResolved = false;

  // ── 测试 hook（生产代码不得依赖）──

  /// 测试注入：机器密钥文件路径（默认 `<userAppDir>/.machine.key`）。
  /// 让 `flutter_test` 能把密钥文件收进临时目录，不脏写真实用户目录。
  @visibleForTesting
  static String? debugMachineKeyPath;

  /// 测试注入：强制走「Web / 无法派生」的明文透传分支，验证降级语义。
  @visibleForTesting
  static bool? debugForcePassthrough;

  /// 测试注入（三态）：强制选择 PBKDF2 的执行位置。
  /// `true` = 强制内联；`false` = 强制走 `Isolate.run`（用来在 `flutter test`
  /// 里覆盖**生产那条**派生路径）；`null` = 自动（测试进程内联、生产 isolate）。
  @visibleForTesting
  static bool? debugForceInlineDerive;

  /// 测试注入：读回当前生效的机器口令（null = 透传模式）。
  /// 只用于验证「LocalSecureStore 写的 envelope 能用 MistakeBookCrypto
  /// 解开」这一互操作契约；口令本身对本机任何代码都是可派生的（见威胁模型），
  /// 暴露它不新增攻击面。
  @visibleForTesting
  static Future<String?> debugMachinePassphrase() => _resolvePassphrase();

  /// 测试注入：在惰性升级「密文已算好、尚未原子替换」的那一刻被调用，
  /// 返回的 Future 决定升级何时继续。用途是把 CAS 竞态排成**确定时序**
  /// （不加这个接缝，两条写链的先后取决于 PBKDF2 让出几次 ⇒ 用例只能在
  /// 「碰巧谁赢」上断言，是假绿）。生产恒为 null（不调用、不 await）。
  @visibleForTesting
  static Future<void> Function(String path)? debugGateBeforeAtomicReplace;

  /// v2.24：切换档案目录后必须重算机器口令——口令里含 .machine.key，
  /// 而 .machine.key 是按档案目录放的；进程级缓存会把 A 档的口令一直
  /// 用在 B 档上，导出其它档案时解密必然失败。
  static void invalidateMachinePassphraseCache() {
    _passphrase = null;
    _passphraseResolved = false;
    _deviceSecret = '';
    _deviceSecretResolved = false;
    _derivedKeys.clear();
    _deriving.clear();
    _pathSalt.clear();
  }

  /// 测试专用：清 hook + 进程内缓存（口令 / 派生密钥 / 路径 salt）。
  @visibleForTesting
  static void debugResetHooks() {
    debugMachineKeyPath = null;
    debugForcePassthrough = null;
    debugForceInlineDerive = null;
    debugGateBeforeAtomicReplace = null;
    invalidateMachinePassphraseCache();
  }

  // ───────────────────────────── 对外两个方法 ─────────────────────────────

  /// 把 [plainJson] 加密后写入 [path]（加密不可用时原样写，见文件头 web 策略）。
  ///
  /// 抛错：底层文件写入失败（磁盘只读 / 路径非法）→ 原始 `FileSystemException`
  /// 等，由调用方决定降级；**加解密本身失败不落盘**（宁可丢一次保存，
  /// 也不把明文偷偷写到磁盘上——那正是本轮要消除的资产）。
  static Future<void> writeSecure(String path, String plainJson) async {
    final content = await _protect(path, plainJson);
    // 原子写——先写同目录临时文件（flush 落盘），再 rename 覆盖目标。
    // rename 是原子替换（POSIX rename(2)；Windows File.rename 走
    // MOVEFILE_REPLACE_EXISTING，已带替换语义），因此读方 `readSecure` 永远只
    // 会看到「旧完整文件」或「新完整文件」，绝不会读到写了一半的损坏内容。
    // 失败时删掉半成品再原样抛出，交调用方决定降级（不留 .tmp 残留）。
    // `expectedRaw == null` = 无条件覆盖（writeSecure 的既有语义）。
    _atomicReplace(path, content, null);
  }

  /// 读 [path] 并按需解密，返回明文 JSON 字符串。
  ///
  /// 抛错（调用方 try/catch 降级，不要让异常冒到启动链）：
  ///   - 文件缺失 / 不可读 → [LocalSecureUnreadableException]
  ///   - envelope 损坏 / 本机口令解不开 → [LocalSecureCorruptException]
  static Future<String> readSecure(String path) async {
    final String raw;
    try {
      raw = File(path).readAsStringSync();
    } catch (e) {
      // 首次装机 / 测试临时目录：预热密钥，让紧接着的首次写入是同步快的
      // （fire-and-forget，失败已在内部吞掉）。
      _warmInBackground(path);
      throw LocalSecureUnreadableException('本机文件不可读（可能尚未生成）：$e',
          path);
    }
    if (!MistakeBookCrypto.isEncryptedEnvelope(raw)) {
      // 旧明文（加密改造之前的存量配置 / 聊天历史）：原样返回，下次 writeSecure
      // 顺带升级为密文——用户不需要导出导入任何东西。
      _warmInBackground(path);
      return raw;
    }
    return _unprotect(path, raw);
  }

  /// 惰性升级磁盘上残留的**旧明文**（加密改造之前的
  /// `ai_config.json` / 聊天历史）为密文。调用方（load 链）fire-and-forget，
  /// 不 await、不影响返回。
  ///
  /// 语义（幂等、尽力而为）：重读 [path] 判当前落盘形态——
  ///   - 读不到 / 空 / 已是 envelope → 什么都不做（已升级过或无需升级）；
  ///   - 透传模式（Web / 本机特征不可得，`_resolvePassphrase() == null`）→ 跳过
  ///     （升级无意义，写回去还是明文）；
  ///   - 仍是明文 → 用调用方解析出的 [plainJson] 经原子写覆写为密文。
  /// 返回 true = **本次真的把明文换成了密文**；false = 未写（含下面 CAS 放弃）。
  /// 任何异常都在内部吞掉并 `debugPrint`，绝不向外抛。返回 [Future] 只为让
  /// 测试可 await 验证落盘；生产调用点用 `unawaited(...)` 显式丢弃。
  ///
  /// ─────── CAS 护栏（竞态修复，二修）───────
  /// [expectedRaw] 是调用方在 `readSecure` 里读到的**原始磁盘字节**
  /// （旧明文路径下 readSecure 逐字返回磁盘内容，所以它就是 expectedRaw；
  /// 省略时按 [plainJson] 处理，二者在唯一的生产调用点上一致）。
  /// 加密不是免费的：`_protect` 要先跑一次 100k 轮 PBKDF2（AOT ~770ms）才
  /// 落盘。这段**异步等待窗口**里，同 isolate 的其它写者完全可能已经把同一
  /// 文件更新成更好的内容——源仓实测打到的就是 v2.15 的 opencode→DeepSeek 迁移：
  /// `load()` 读到旧明文 ⇒ 后台起升级 ⇒ 迁移链紧接着 `save()` 写入 DeepSeek
  /// 新配置 ⇒ 升级把 load 时刻的**过期明文**回写覆盖 ⇒ 磁盘 provider 从
  /// 'deepseek' 被打回 'opencode'。
  /// 修法不是 `await` 阻塞 `load()`（那等于把 ~770ms KDF 塞进每次发问的
  /// 热路径），而是 compare-and-swap：temp 落盘后、`renameSync` 覆盖前，
  /// 在**同一个同步段**内重读磁盘字节，与 [expectedRaw] 不逐字相同即放弃
  /// （删 temp、返回 false）。Dart 单 isolate 内代码 run-to-completion，
  /// 同步段里不可能插入别的写者 ⇒ 「比较 + rename」是原子对，判定不会
  /// 被撕裂；比 expectedRaw 新的任何写入（envelope / 迁移后 JSON）都赢。
  static Future<bool> upgradeIfLegacyPlaintext(
      String path, String plainJson, {String? expectedRaw}) async {
    final expected = expectedRaw ?? plainJson;
    try {
      final String disk;
      try {
        disk = File(path).readAsStringSync();
      } catch (_) {
        return false; // 文件不可读：无可升级
      }
      if (disk.isEmpty) return false;
      if (MistakeBookCrypto.isEncryptedEnvelope(disk)) return false; // 已是密文
      if (await _resolvePassphrase() == null) return false; // 透传模式：跳过
      final content = await _protect(path, plainJson); // 密文（或透传原文）
      // 测试注入点：只用于把「加密窗口内别的写者落盘」这一竞态排成确定时序
      // （见 test/services/local_secure_store_test.dart 的 CAS 竞态用例）。
      // 生产为 null；停在闸门前后都不影响 CAS 的原子性——重读比较与 rename
      // 都在 `_atomicReplace` 的**同一个同步段**内完成。
      final gate = debugGateBeforeAtomicReplace;
      if (gate != null) await gate(path);
      return _atomicReplace(path, content, expected);
    } catch (e) {
      debugPrint('LocalSecureStore.upgradeIfLegacyPlaintext: 惰性升级失败（忽略）：$e');
      return false;
    }
  }

  // ───────────────────────── 内部：原子落盘（CAS 可选项） ─────────────────────────

  /// 同步原子落盘段（[writeSecure] 与 [upgradeIfLegacyPlaintext] 共用）。
  ///
  /// 三个动作——写同目录 temp（flush 落盘）→ 重读目标比较（仅当
  /// [expectedRaw] 非空）→ `renameSync` 覆盖——全在**同一个同步段**里跑完，
  /// 中间没有任何 `await`，因此同 isolate 的其它代码无法插进来：
  ///   * [expectedRaw] == null：无条件替换（普通保存的既有语义）。
  ///   * [expectedRaw] != null：仅当目标当前字节与它逐字相同才替换；不同
  ///     （= 我们读盘之后又有别人写过）就删 temp、返回 false，**绝不**用
  ///     过期内容覆盖新数据。
  /// rename 走原子替换（POSIX rename(2)；Windows 的 `File.rename` 带
  /// MOVEFILE_REPLACE_EXISTING），读方永远看不到半截文件。
  /// 失败（磁盘只读 / rename 被拒等）删掉半成品后原样抛出，交调用方降级。
  static bool _atomicReplace(
      String path, String content, String? expectedRaw) {
    final target = File(path);
    final tmp = File('$path.tmp');
    void dropTmp() {
      try {
        if (tmp.existsSync()) tmp.deleteSync();
      } catch (_) {}
    }

    try {
      if (!target.parent.existsSync()) target.parent.createSync(recursive: true);
      tmp.writeAsStringSync(content, flush: true, mode: FileMode.write);
      if (expectedRaw != null) {
        final String current;
        try {
          current = target.readAsStringSync();
        } catch (_) {
          dropTmp();
          return false; // 目标此刻读不到（被删）⇒ 已不是 expectedRaw，放弃
        }
        if (current != expectedRaw) {
          dropTmp();
          return false; // CAS 失败：期间有更新的写者，让它的内容留下
        }
      }
      tmp.renameSync(path);
      return true;
    } catch (e) {
      dropTmp();
      rethrow;
    }
  }

  // ───────────────────────────── 内部：加解密 ─────────────────────────────

  static Future<String> _protect(String path, String plainJson) async {
    final passphrase = await _resolvePassphrase();
    if (passphrase == null) {
      // WEB-PASSTHROUGH / 本机特征不可得：与改造前逐字一致的明文写。
      return plainJson;
    }
    // 每个路径首次写时取一个随机 salt，之后复用（KDF 可缓存 = 写路径不卡 UI）。
    final saltB64 = _pathSalt.putIfAbsent(_norm(path), _randomSaltB64);
    final key = await _deriveKey(passphrase, saltB64);
    final iv = _randomBytes(_ivLength);
    final box = await AesGcm.with256bits().encrypt(
      utf8.encode(plainJson),
      secretKey: SecretKey(key),
      nonce: iv,
    );
    final envelope = <String, dynamic>{
      'schemaVersion': _envelopeSchemaVersion,
      'kdf': _kdfId,
      'cipher': _cipherId,
      'kdfIterations': _kdfIterations,
      'salt': saltB64,
      'iv': base64Encode(iv),
      'ciphertext': base64Encode(box.cipherText),
      'tag': base64Encode(box.mac.bytes),
      // 诊断字段：MistakeBookCrypto.decryptJson 只读它认识的 key，多这一个
      // 不影响互操作（测试里 cross-decrypt 会证明这点）。
      'wrappedBy': 'local_secure_store',
    };
    return jsonEncode(envelope);
  }

  static Future<String> _unprotect(String path, String raw) async {
    Map<String, dynamic> j;
    try {
      final decoded = jsonDecode(_stripCommentHeader(raw));
      if (decoded is! Map) {
        throw const FormatException('根不是 object');
      }
      j = decoded.cast<String, dynamic>();
    } on FormatException catch (e) {
      throw LocalSecureCorruptException('加密包 JSON 解析失败：${e.message}',
          path);
    }
    final saltB64 = j['salt']?.toString();
    final ivB64 = j['iv']?.toString();
    final ctB64 = j['ciphertext']?.toString();
    final tagB64 = j['tag']?.toString();
    if (j['cipher'] != _cipherId ||
        saltB64 == null ||
        ivB64 == null ||
        ctB64 == null ||
        tagB64 == null) {
      throw LocalSecureCorruptException(
          '加密包字段缺失或算法不匹配（cipher=${j['cipher']}）', path);
    }
    final passphrase = await _resolvePassphrase();
    if (passphrase == null) {
      throw LocalSecureCorruptException('文件已加密，但本机无法派生密钥', path);
    }
    final key = await _deriveKey(passphrase, saltB64);
    try {
      final clear = await AesGcm.with256bits().decrypt(
        SecretBox(
          base64Decode(ctB64),
          nonce: base64Decode(ivB64),
          mac: Mac(base64Decode(tagB64)),
        ),
        secretKey: SecretKey(key),
      );
      // 记成该路径的"写 salt"：读之后紧跟的 save 复用同一条派生密钥，
      // 每进程每文件就只跑一次 100k PBKDF2（否则读+写各跑一次）。
      _pathSalt[_norm(path)] = saltB64;
      return utf8.decode(clear);
    } on SecretBoxAuthenticationError {
      // GCM tag 校验失败：文件来自别的机器（口令派生源不同）或被手工改过字节。
      throw LocalSecureCorruptException(
          '本机密钥与密文不匹配（文件可能来自其它机器或被篡改），按「无存量数据」处理',
          path);
    } on FormatException catch (e) {
      throw LocalSecureCorruptException('密文 base64 / UTF-8 损坏：${e.message}',
          path);
    } catch (e) {
      throw LocalSecureCorruptException('解密失败：$e', path);
    }
  }

  /// 派生（或复用缓存的）AES key。single-flight：并发读写同一 salt 只跑一次 KDF。
  static Future<List<int>> _deriveKey(String passphrase, String saltB64) async {
    final cached = _derivedKeys[saltB64];
    if (cached != null) return cached;
    final inflight = _deriving[saltB64];
    if (inflight != null) return inflight;
    late final Future<List<int>> future;
    future = _deriveOffUi(passphrase, saltB64).whenComplete(() {
      if (identical(_deriving[saltB64], future)) _deriving.remove(saltB64);
    });
    _deriving[saltB64] = future;
    final key = await future;
    if (_derivedKeys.length >= _maxCachedKeys) _derivedKeys.clear();
    _derivedKeys[saltB64] = key;
    return key;
  }

  /// KDF 跑在子 isolate：AOT 实测 ~770ms，放 UI isolate 上就是硬冻结。
  /// 子 isolate 起不来（Web stub / 受限环境）时退回本 isolate 计算——
  /// 慢但不丢功能。
  ///
  /// **测试环境必须内联派生**（探针实证过的坑，别改回去）：`testWidgets` 的
  /// 函数体跑在 FakeAsync 区域里，`await Isolate.run(...)` 的回信只能由**真实
  /// 事件循环**投递，而 FakeAsync 在被 `await` 挂起时永远不跑真实循环
  /// ⇒ 永久挂起。源仓实测症状：`test/ai_assistant_test.dart`
  /// 「问AI 面板（widget） 历史恢复」在 `AiChatStore.save()` 处卡死
  /// （日志停在 `+26` 不动）。`AiChatStore.save` / `AiSettingsStore.save`
  /// 都是 `await` 到底的，所以只能让派生本身同步完成。
  /// 代价实测可控：JIT 内联派生 ~385–411ms/首 salt（见文件头《性能实测》），
  /// 且密钥按 salt 缓存，每个测试进程最多付一次。
  static Future<List<int>> _deriveOffUi(String passphrase, String saltB64) async {
    final args = <String>[passphrase, saltB64];
    if (_inlineDeriveRequired) return _pbkdf2Derive(args);
    try {
      return await Isolate.run(() => _pbkdf2Derive(args));
    } catch (e) {
      debugPrint('LocalSecureStore: isolate 派生不可用（$e），退回本 isolate 计算');
      return _pbkdf2Derive(args);
    }
  }

  /// 是否必须内联（本 isolate）派生。
  ///
  /// `flutter test` 会向被测进程注入 `FLUTTER_TEST=true`（探针见
  /// `test/services/local_secure_store_test.dart` 的「派生路径与 widget 测试
  /// 不死锁」组），生产构建里该变量不存在 ⇒ 走 isolate。Web 的 `dart:io` 是
  /// stub，`Platform.environment` 直接抛 UnimplementedError，故整体 try/catch。
  static bool get _inlineDeriveRequired {
    if (kIsWeb) return true;
    final forced = debugForceInlineDerive;
    if (forced != null) return forced; // 测试显式指定路径（含强制走 isolate）
    try {
      return Platform.environment['FLUTTER_TEST'] == 'true';
    } catch (_) {
      return false;
    }
  }

  // ───────────────────────────── 内部：口令派生 ─────────────────────────────

  static Future<String?> _resolvePassphrase() async {
    // 测试 hook 优先级高于进程内缓存：透传模拟必须能中途生效。
    if (debugForcePassthrough == true) return null;
    if (_passphraseResolved) return _passphrase;
    final p = await _derivePassphrase();
    _passphrase = p;
    _passphraseResolved = true;
    if (p == null) {
      debugPrint('LocalSecureStore: 本机特征不可得（Web / 受限平台）→ 明文透传');
    }
    return p;
  }

  static Future<String?> _derivePassphrase() async {
    if (debugForcePassthrough == true) return null;
    // WEB-PASSTHROUGH：见文件头「web 端策略」三条理由。
    if (kIsWeb) return null;
    final hostname = _safeHostname();
    final user = _safeUserName();
    final secret = _machineSecret();
    if (hostname.isEmpty && user.isEmpty && secret.isEmpty) {
      // 三个派生源全空 = 平台连本机特征都不给 → 只能透传（不抛、不崩）。
      return null;
    }
    return '$hostname|$user|$secret|$_appId';
  }

  static String _safeHostname() {
    try {
      return Platform.localHostname;
    } catch (e) {
      debugPrint('LocalSecureStore: Platform.localHostname 不可用（$e）');
      return '';
    }
  }

  static String _safeUserName() {
    try {
      final env = Platform.environment;
      return env['USERNAME'] ?? env['USER'] ?? env['COMPUTERNAME'] ?? '';
    } catch (e) {
      // Android 上 Platform.environment 恒为 {}（返回空串），Web 上直接抛。
      debugPrint('LocalSecureStore: Platform.environment 不可用（$e）');
      return '';
    }
  }

  /// 每安装随机密钥（`.machine.key`）。拿不到就退化成空串（口令仍有稳定性，
  /// 只是少了「同 hostname 机器之间的区分度」——见文件头威胁模型）。
  static String _machineSecret() {
    if (_deviceSecretResolved) return _deviceSecret;
    _deviceSecretResolved = true;
    try {
      var path = debugMachineKeyPath;
      if (path == null) {
        // Android 缓存未就绪 / 平台不支持时 userAppDir() 返 null——
        // 必须显式退出，否则会拼出 'null/.machine.key' 这种在 cwd 下建目录的脏路径。
        final dir = userAppDir();
        if (dir == null || dir.isEmpty) {
          _deviceSecret = '';
          return _deviceSecret;
        }
        path = '$dir/$_machineKeyFileName';
      }
      final f = File(path);
      if (f.existsSync()) {
        final stored = f.readAsStringSync().trim();
        if (stored.isNotEmpty) {
          _deviceSecret = stored.length > 128 ? stored.substring(0, 128) : stored;
          return _deviceSecret;
        }
      }
      // 测试未注入 debugMachineKeyPath 时不在真实用户目录建 .machine.key
      // （落空走 hostname+用户名兜底，口令仍稳定）。
      if (debugSkipUserDirWrite('.machine.key',
          hasIsolatedPath: debugMachineKeyPath != null)) {
        _deviceSecret = '';
        return _deviceSecret;
      }
      final fresh = _hexOf(16); // 16 字节 = 32 hex 字符
      if (!f.parent.existsSync()) f.parent.createSync(recursive: true);
      f.writeAsStringSync(fresh);
      _deviceSecret = fresh;
    } catch (e) {
      debugPrint('LocalSecureStore: 机器密钥文件不可用（$e）→ 仅用 hostname + 用户名');
      _deviceSecret = '';
    }
    return _deviceSecret;
  }

  // ───────────────────────────── 内部：小工具 ─────────────────────────────

  /// 后台预热某路径的写密钥（首装 / 旧明文场景下，让紧随其后的 save
  /// 不必在调用链上现等 ~770ms KDF）。失败静默——写路径自己会再派生。
  static void _warmInBackground(String path) {
    unawaited(() async {
      final passphrase = await _resolvePassphrase();
      if (passphrase == null) return;
      await _deriveKey(passphrase, _pathSalt.putIfAbsent(_norm(path), _randomSaltB64));
    }().catchError((Object e) {
      debugPrint('LocalSecureStore: 密钥预热失败（$e）');
    }));
  }

  static String _norm(String path) => path.replaceAll(r'\', '/');

  static String _randomSaltB64() =>
      base64Encode(_randomBytes(_saltLength));

  static List<int> _randomBytes(int n) {
    final out = List<int>.filled(n, 0);
    for (var i = 0; i < n; i++) {
      out[i] = _secureRandom.nextInt(256);
    }
    return out;
  }

  static String _hexOf(int n) {
    final b = _randomBytes(n);
    final s = StringBuffer();
    for (final x in b) {
      s.write(x.toRadixString(16).padLeft(2, '0'));
    }
    return s.toString();
  }
}
