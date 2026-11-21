// backup_service.dart —— 整机数据一键打包 / 原地恢复（v2.24）。
//
// 目标：把 `baseAppDir()`（基目录）下的全部内容打进一个口令加密的单文件，
// 换一台机器导入后原地还原（含 AI 配置、聊天历史、错题本、板书、账号档案）。
//
// 注意用 baseAppDir() 而不是 userAppDir()：后者在 v2.24 已指向「当前账号
// 档案目录」(`<基目录>/accounts/<id>`)，拿它当根只会打包当前一个人，
// accounts.json 与其它档案全部漏掉——那不是「整机」。
//
// 包结构（外层文本，用户可直接用编辑器看到这是什么）：
//   // BIOLOGY-BACKUP · 全量数据包（AES-256-GCM 口令加密）
//   // 导入时必须输入同一口令；文件由本机生成，勿手工编辑
//   { "schemaVersion": 1, "cipher": "aes-256-gcm", ... }   <- MistakeBookCrypto envelope
//
// 内层是 MistakeBookCrypto.decryptJson 解出来的明文容器：
//   {"format":"biology-backup","version":1,"createdAt":<ms>,
//    "appVersion":"...","accounts":[{"id","name"}],"fileCount":N,
//    "files":{"相对路径":"<base64 原始字节>"}}
//
// 设计取舍：
//   - 不新写密码学：外层完全复用 MistakeBookCrypto（AES-256-GCM + PBKDF2 100k），
//     与错题本导出共用同一 envelope 格式，口令错误 = GCM tag 校验失败，绝不
//     出现「解了一半」。
//   - 不新写保存对话框 / 下载分流：落盘交给 MistakeBookExporter，桌面写
//     ~/Downloads、Android 写应用目录、Web 触发浏览器下载，三端语义已有。
//   - 文件用 base64 存原始字节而不是字符串：错题本 PNG、板书图片等二进制
//     资产必须逐字节还原，任何 utf8 往返都会毁掉它们。
//
// 平台：桌面 / 安卓（dart:io）。Web 没有文件系统，两个入口都直接返回
// 「当前平台不支持整机打包/恢复」——把 localStorage 拼成 zip 的收益远小于成本，
// 留给后续单独设计。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../state/mistake_book.dart' show MistakeBookExporter;
import '../storage/platform_storage_io.dart'
    if (dart.library.html) '../storage/platform_storage_web.dart';
import 'local_secure_store.dart';
import 'mistake_book_crypto.dart';

/// 一次整机导出的结果。
///
/// 为什么用返回值而不是抛异常：导出由设置页按钮触发，调用方只需要拼一句
/// SnackBar；把异常语义收进返回值，UI 不需要 try/catch，也不会因为一次磁盘
/// 错误崩成红屏（与 MistakeBookExporter「返 null 不抛」的既有契约一致）。
class BackupExportResult {
  const BackupExportResult({
    required this.ok,
    this.path,
    this.fileCount = 0,
    this.bytes = 0,
    this.error,
  });

  /// 是否成功。false 时 [error] 一定非空。
  final bool ok;

  /// 落盘后的用户可见路径；Web / Android 等无公共下载目录的平台由
  /// MistakeBookExporter 给出对应说明（Web 为「已触发浏览器下载」）。
  final String? path;

  /// 入包的文件数（不含目录），用于告知用户「这一次带走了多少东西」。
  final int fileCount;

  /// 最终包体的 UTF-8 字节数（含注释头），用于展示体积。
  final int bytes;

  /// 失败原因，中文、可直接展示给用户。
  final String? error;
}

/// 一次整机导入（原地恢复）的结果。
///
/// [backupDir] 是覆盖前快照的路径：写入中途失败时用户还能据此手工回滚，
/// 所以即使 ok=false 也照样返回，不吞掉这条救命信息。
class BackupImportResult {
  const BackupImportResult({
    required this.ok,
    this.fileCount = 0,
    this.accountCount = 0,
    this.backupDir,
    this.error,
  });

  /// 是否成功。false 时 [error] 一定非空。
  final bool ok;

  /// 数据包里尝试写入的文件数。
  final int fileCount;

  /// 数据包里的档案数（accounts 数组长度），用于 UI 提示「恢复了几个档案」。
  final int accountCount;

  /// 覆盖前的快照目录；导入前没有可快照的内容时为 null。
  final String? backupDir;

  /// 失败原因，中文、可直接展示给用户。
  final String? error;
}

/// 恢复确认框要展示的「包里有什么」。
///
/// 只读结果，解不开就是 ok=false + 中文原因；调用方据此决定是否继续，
/// 绝不因为「只是一次预览」写盘。
class BackupInspectResult {
  const BackupInspectResult({
    required this.ok,
    this.accountNames = const <String>[],
    this.fileCount = 0,
    this.createdAt,
    this.appVersion,
    this.error,
  });

  /// 包是否解开并通过格式校验。false 时 [error] 一定非空。
  final bool ok;

  /// 包内档案名（accounts.json 的顺序）。可能为空（老包 / 清单无名字）。
  final List<String> accountNames;

  /// 包内文件数（含 accounts.json）。
  final int fileCount;

  /// 导出时刻（容器 createdAt，毫秒）。老包缺字段时为 null。
  final DateTime? createdAt;

  /// 导出方 appVersion，仅展示用。
  final String? appVersion;

  /// 失败原因（口令错误或文件已损坏 / 不是本软件的数据包）。
  final String? error;
}

/// 整机数据打包 / 恢复服务（静态类，零状态）。
///
/// 职责只有四件事：收集文件 → 解掉机器绑定加密 → 口令加密成单文件；
/// 以及反向的校验 → 快照 → 覆盖写。不碰 UI、不重启进程（重启由 UI 层做）。
class BackupService {
  BackupService._();

  /// 容器格式标识。写进明文容器第一层，导入时逐字比对，防止把错题本
  /// 导出文件当整机包导入（两者外层 envelope 长得一样）。
  static const String formatId = 'biology-backup';

  /// 容器格式版本。当前只认 <= 本值的包；未来加字段要同步 +1，让旧版
  /// 软件在导入新包时给出「不是本软件的数据包」而不是静默丢字段。
  static const int formatVersion = 1;

  /// 解密失败的唯一说法。口令是区分大小写的长串、又全掩码，单个字符打错
  /// 和文件真损坏在 GCM 上无法区分——先让用户逐个核对，再怀疑文件。
  static const String badPassphraseError =
      '口令不正确（区分大小写，请逐个核对）；若确认无误则文件可能已损坏';

  /// 包文件头标记。写在 envelope 前面（decryptJson 会剥掉所有 `//` 行，
  /// 不影响解析），用户用记事本打开时能一眼确认这是什么文件。
  static const String marker = 'BIOLOGY-BACKUP';

  /// 机器绑定加密落盘的两个文件，导出时必须解成明文（见 export 注释）。
  static const String _aiConfigName = 'ai_config.json';
  static const String _aiChatName = 'ai_chat_history.json';

  /// 包文件头（两行 `//` 注释）。
  static const String _header = '// $marker · 全量数据包（AES-256-GCM 口令加密）\n'
      '// 导入时必须输入同一口令；文件由本机生成，勿手工编辑\n';

  /// 收集 [baseDir]（默认为基目录 baseAppDir()）下全部文件，口令加密后存到下载目录。
  ///
  /// 为什么导出要先把机器绑定的两个文件解成明文：
  ///   `ai_config.json` / `ai_chat_history.json` 的密钥由 hostname + USERNAME
  ///   + `.machine.key` 派生，**换一台机器就解不开**。包里若存密文，恢复后
  ///   目标机的 LocalSecureStore 只会把它判成「损坏」并回退空配置——用户丢的
  ///   恰恰是最重要的 AI 设置与聊天记录。所以这里用 readSecure 取明文再入包，
  ///   导入后由目标机的正常保存路径（writeSecure）重新按新机器加密。
  ///   解不开时保留原字节并 debugPrint：同机导出/导入仍然可用，不因一个文件
  ///   毁掉整包（这是唯一允许「带伤继续」的分支）。
  static Future<BackupExportResult> export({
    required String passphrase,
    String? baseDirOverride,
    String? appVersion,
  }) async {
    try {
      if (passphrase.isEmpty) {
        return const BackupExportResult(ok: false, error: '口令不能为空');
      }
      // Android 首次读盘前 getFilesDir 缓存可能未就绪（baseAppDir 会返 null），
      // 与 MistakeBookExporter 同样的前置 await；桌面 / Web 是 no-op。
      await ensureAppDirReady();
      final base = baseDirOverride ?? baseAppDir();
      if (base == null || isWebStorage) {
        return const BackupExportResult(
            ok: false, error: '当前平台不支持整机打包');
      }
      final baseDir = Directory(base);
      if (!baseDir.existsSync()) {
        return BackupExportResult(ok: false, error: '应用数据目录不存在：$base');
      }
      final baseAbs = baseDir.absolute.path;
      final files = <String, String>{};

      await for (final entity
          in Directory(baseAbs).list(recursive: true, followLinks: false)) {
        if (entity is! File) continue; // 目录 / 符号链接一律不入包
        final rel = _relativeKey(baseAbs, entity.path);
        if (_shouldSkip(rel)) continue;
        // 单个文件读失败直接终止导出：备份「少了一个文件还报成功」比失败更危险。
        final raw = await entity.readAsBytes();
        var bytes = raw;
        final name = _fileName(rel);
        if (name == _aiConfigName || name == _aiChatName) {
          final sniff = utf8.decode(raw, allowMalformed: true);
          if (MistakeBookCrypto.isEncryptedEnvelope(sniff)) {
            // 机器口令由 `userAppDir()/.machine.key` 派生，而 userAppDir() 指的是
            // **当前档案**。这里要读的是任意档案的文件，必须临时把档案指针切到
            // 该文件所在目录，否则非当前档案的配置只能用别人的密钥去解——必然失败。
            final prevDir = accountDataDir;
            try {
              // 每换一个档案目录都要重算口令：口令里含该目录的 .machine.key，
              // 进程级缓存会把上一个档案的口令沿用过来，这里必然解密失败，
              // 而失败分支只 debugPrint——包照样报成功，内容却是密文。
              LocalSecureStore.invalidateMachinePassphraseCache();
              accountDataDir = entity.parent.path;
              final plain = await LocalSecureStore.readSecure(entity.path);
              bytes = Uint8List.fromList(utf8.encode(plain));
            } catch (e) {
              debugPrint('备份：$rel 解密失败，按原始密文入包（换机后该文件不可用）：$e');
            } finally {
              accountDataDir = prevDir;
              LocalSecureStore.invalidateMachinePassphraseCache();
            }
          }
        }
        files[rel] = base64Encode(bytes);
      }

      final accounts = _readAccounts(baseAbs);
      final envelope = await buildEnvelope(
        passphrase: passphrase,
        accounts: accounts,
        files: files,
        appVersion: appVersion ?? '',
      );
      final package = '$_header$envelope';
      final path = await MistakeBookExporter.saveToDownloads(
        package,
        'biology-backup-${_secondStamp(DateTime.now())}',
      );
      if (path == null) {
        return const BackupExportResult(ok: false, error: '保存失败：未找到可写目录');
      }
      return BackupExportResult(
        ok: true,
        path: path,
        fileCount: files.length,
        bytes: utf8.encode(package).length,
      );
    } catch (e) {
      // 只给原文：调用方统一加「导出失败：」前缀，这里再加一次会重复。
      return BackupExportResult(ok: false, error: '$e');
    }
  }

  /// 用口令解开数据包并原地恢复：[baseDir] 下的 accounts 区域先快照再覆盖。
  ///
  /// 为什么先快照再覆盖：导入是全量删除 + 重写 accounts/ 与 accounts.json，
  /// 中途断电、磁盘满、单个文件被占用都会留下半套数据。快照只是复制（体积
  /// 与当前档案数据同量级，桌面几 MB 到几十 MB，可接受），换来的是「任何
  /// 失败都能手工退回导入前」。快照失败只 debugPrint 不中断——用户此刻的
  /// 目的就是恢复，不能因为快照目录建不出来就拒绝服务；但结果里会带
  /// backupDir=null，UI 应据此提示「没有留下回滚点」。
  ///
  /// 失败语义：口令错 / 格式不符 / 路径非法 → 一个字节都不写；只有解开并通过
  /// 校验之后才进入删除与写入阶段，写入阶段的单文件失败会继续写其余文件并
  /// 汇总成一条错误返回。
  static Future<BackupImportResult> restore({
    required String raw,
    required String passphrase,
    String? baseDirOverride,
  }) async {
    try {
      if (passphrase.isEmpty) {
        return const BackupImportResult(ok: false, error: '口令不能为空');
      }
      final String plain;
      try {
        plain = await MistakeBookCrypto.decryptJson(raw, passphrase);
      } on FormatException {
        return const BackupImportResult(ok: false, error: badPassphraseError);
      } catch (e) {
        // 其它异常（如 cryptography 内部错误）保留原文，便于用户回传排查。
        return BackupImportResult(ok: false, error: '$e');
      }

      final Map<String, dynamic> container;
      try {
        container = decodeEnvelope(plain);
      } on FormatException catch (e) {
        return BackupImportResult(ok: false, error: e.message);
      }

      // 路径清洗放在任何写盘动作之前：整包拒绝，绝不「跳过坏路径继续写」，
      // 否则用户以为恢复成功、实际少了几个文件。
      final filesRaw = container['files'] as Map;
      final entries = <String, String>{};
      for (final key in filesRaw.keys) {
        final rel = key.toString();
        if (!_isSafeRelativePath(rel)) {
          return const BackupImportResult(ok: false, error: '数据包内含非法路径');
        }
        final value = filesRaw[key];
        if (value is! String) {
          return const BackupImportResult(ok: false, error: '数据包内容损坏');
        }
        entries[rel] = value;
      }

      // 删除动作之前的两道硬闸：包是空的、或包里没有账号清单，一律拒绝。
      // 没有这两条，一个口令正确但 files 为 {} 的包会把本机数据删干净再报成功。
      if (entries.isEmpty) {
        return const BackupImportResult(
            ok: false, error: '数据包里没有任何文件，已取消恢复');
      }
      if (!entries.containsKey('accounts.json')) {
        return const BackupImportResult(
            ok: false, error: '数据包缺少账号清单 accounts.json，已取消恢复');
      }

      await ensureAppDirReady();
      final base = baseDirOverride ?? baseAppDir();
      if (base == null || isWebStorage) {
        return const BackupImportResult(
            ok: false, error: '当前平台不支持整机恢复');
      }
      final sep = Platform.pathSeparator;
      await Directory(base).create(recursive: true);

      final backupDir = await _snapshotBeforeRestore(base);

      // 清理旧档案区：数据包里的 accounts/ 是权威副本，先删干净再写，
      // 避免旧档案残留文件在恢复后继续被读到。删除失败只记日志（可能被
      // 占用），后续写入会覆盖同名文件。
      await _deleteBestEffort(Directory('$base${sep}accounts'));
      await _deleteBestEffort(File('$base${sep}accounts.json'));

      final failures = <String>[];
      for (final entry in entries.entries) {
        final abs = '$base$sep${entry.key.split('/').join(sep)}';
        try {
          final bytes = base64Decode(entry.value);
          final file = File(abs);
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes, flush: true);
        } catch (e) {
          failures.add(entry.key);
          debugPrint('恢复：写入 ${entry.key} 失败：$e');
        }
      }

      final accounts = container['accounts'];
      return BackupImportResult(
        ok: failures.isEmpty,
        fileCount: entries.length,
        accountCount: accounts is List ? accounts.length : 0,
        backupDir: backupDir,
        error: failures.isEmpty
            ? null
            : '${failures.length} 个文件写入失败：'
                '${failures.take(3).join('、')}',
      );
    } catch (e) {
      // 原文返回：调用方统一加「恢复失败：」前缀。
      return BackupImportResult(ok: false, error: '$e');
    }
  }

  /// 组装并加密容器明文，返回可直接落盘的 envelope 字符串。
  ///
  /// 纯函数（不碰磁盘）供单测：把「容器 schema + 加密」与「文件收集」解耦，
   /// 测试只需给两个内存 Map 就能验证格式/往返，不用建临时目录。
  /// [createdAt] 传毫秒时间戳，测试可固定它做逐字比对。
  /// 口令为空时由 MistakeBookCrypto.encryptJson 抛 ArgumentError（不在这里
  /// 重复校验，密码学门面只有一个入口）。
  static Future<String> buildEnvelope({
    required String passphrase,
    required List<Map<String, dynamic>> accounts,
    required Map<String, String> files,
    required String appVersion,
    int? createdAt,
  }) async {
    final plain = jsonEncode(<String, dynamic>{
      'format': formatId,
      'version': formatVersion,
      'createdAt': createdAt ?? DateTime.now().millisecondsSinceEpoch,
      'appVersion': appVersion,
      'accounts': accounts,
      'fileCount': files.length,
      'files': files,
    });
    return MistakeBookCrypto.encryptJson(plain, passphrase);
  }

  /// 解析并校验容器明文，返回强类型 Map。
  ///
  /// 纯函数供单测。校验三件事（format / version / files）就够挡住「把错题本
  /// 导出文件当整机包」的误操作；更细的字段校验留给 restore 在写盘前做。
  /// 不合格统一抛 FormatException('不是本软件的数据包')，调用方直接展示。
  static Map<String, dynamic> decodeEnvelope(String plainJson) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(plainJson.trim());
    } on FormatException {
      throw const FormatException('不是本软件的数据包');
    }
    if (decoded is! Map) {
      throw const FormatException('不是本软件的数据包');
    }
    final map = Map<String, dynamic>.from(decoded);
    if (map['format'] != formatId) {
      throw const FormatException('不是本软件的数据包');
    }
    final version = map['version'];
    if (version is! int || version < 1 || version > formatVersion) {
      throw const FormatException('不是本软件的数据包');
    }
    if (map['files'] is! Map) {
      throw const FormatException('不是本软件的数据包');
    }
    return map;
  }

  /// 只解密 + 解析，不写盘：给恢复确认框显示「这个包里到底有什么」。
  ///
  /// 为什么单独一个入口：restore 一进去就快照 + 删 accounts/，用户在此之前
  /// 应该能看到「包里有哪些账号、多少个文件、什么时候导的」——这是判断
  /// 「要不要覆盖」的唯一依据。失败原因与 restore 逐字一致，避免用户先在
  /// 预览里看到一种说法、点确定后又看到另一种。
  static Future<BackupInspectResult> inspect({
    required String raw,
    required String passphrase,
  }) async {
    if (passphrase.isEmpty) {
      return const BackupInspectResult(ok: false, error: '口令不能为空');
    }
    final String plain;
    try {
      plain = await MistakeBookCrypto.decryptJson(raw, passphrase);
    } on FormatException {
      return const BackupInspectResult(ok: false, error: badPassphraseError);
    } catch (e) {
      return BackupInspectResult(ok: false, error: '$e');
    }
    final Map<String, dynamic> container;
    try {
      container = decodeEnvelope(plain);
    } on FormatException catch (e) {
      return BackupInspectResult(ok: false, error: e.message);
    }

    final names = <String>[];
    final accounts = container['accounts'];
    if (accounts is List) {
      for (final item in accounts) {
        if (item is! Map) continue;
        final name = item['name']?.toString() ?? '';
        if (name.isNotEmpty) names.add(name);
      }
    }
    final files = container['files'];
    final createdAt = container['createdAt'];
    return BackupInspectResult(
      ok: true,
      accountNames: names,
      fileCount: files is Map ? files.length : 0,
      createdAt: createdAt is int
          ? DateTime.fromMillisecondsSinceEpoch(createdAt)
          : null,
      appVersion: container['appVersion']?.toString(),
    );
  }

  // ───────────────────────────── 内部实现 ─────────────────────────────

  /// 读 accounts.json 的档案清单，只保留 id / name。
  ///
  /// 为什么要裁剪：清单里的 PIN 盐、设置项都属于「本机状态」，进了包反而
  /// 会让跨机恢复带上一份对不上的旧账；这里只要身份信息用于 UI 展示
  /// 「恢复了几个档案」。读不到 / 解析失败一律给空数组——清单只是元数据，
  /// accounts.json 本身仍作为普通文件入包，恢复后由 AccountsStore 自己读。
  static List<Map<String, dynamic>> _readAccounts(String base) {
    final file = File('$base${Platform.pathSeparator}accounts.json');
    if (!file.existsSync()) return const <Map<String, dynamic>>[];
    try {
      final raw = utf8.decode(file.readAsBytesSync(), allowMalformed: true);
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const <Map<String, dynamic>>[];
      final list = decoded['accounts'];
      if (list is! List) return const <Map<String, dynamic>>[];
      final out = <Map<String, dynamic>>[];
      for (final item in list) {
        if (item is! Map) continue;
        final id = item['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        out.add({'id': id, 'name': item['name']?.toString() ?? ''});
      }
      return out;
    } catch (e) {
      debugPrint('备份：accounts.json 解析失败，档案清单留空：$e');
      return const <Map<String, dynamic>>[];
    }
  }

  /// 导出侧过滤规则。
  ///
  /// 为什么 `.machine.key` 不进包：它是本机的机器身份私钥。跨机复制既解不开
  /// 目标机上的密文（密钥仍由目标机特征派生），又等于把源机器的身份材料
  /// 白送出去；导入侧也禁止写它，防止数据包反向覆盖目标机的机器身份。
  ///
  /// 跳过 `_restore_backup_*`（自己的快照，指数增长）、`待删除`（用户已判
  /// 死刑的数据）、`_exports`（历史导出产物）与 `.tmp`（LocalSecureStore
  /// 原子写的中间文件，可能只写了一半）。
  ///
  /// `_trash_accounts` **不跳过**：门禁里「忘记 PIN → 删除档案」只做移动，
  /// 回收站必须跟着包走，换机后删除才真的可逆；恢复侧也只清 accounts/ 与
  /// accounts.json，不会把回收站删掉。
  static bool _shouldSkip(String rel) {
    final segments = rel.split('/');
    final name = segments.last;
    if (name.endsWith('.tmp')) return true;
    // Android 的 MistakeBookExporter 把导出文件写进当前档案目录
    // （_resolveDownloadsDir 走 userAppDir）。不排除的话，第二次打包会把上一份
    // 整包 base64 进新包，体积翻倍且恢复时又落回档案目录，越滚越大。
    if (name.startsWith('biology-backup-') && name.endsWith('.json')) return true;
    for (final segment in segments) {
      if (segment == '.machine.key') return true;
      if (segment.startsWith('_restore_backup_')) return true;
      if (segment == '待删除') return true;
      if (segment == '_exports') return true;
    }
    return false;
  }

  /// 路径清洗（安全关键）：只接受纯相对路径。
  ///
  /// 拒绝规则：空、反斜杠（Windows 分隔符走私）、冒号（盘符 / ADS）、
  /// 前导 `/`、任何 `.` / `..` / 空段。`.machine.key` 同样拒绝，理由见
  /// [_shouldSkip]；`_restore_backup_*` 也拒绝——那是本次导入刚做好的回滚
  /// 快照，数据包要是能往里写，快照就白做了。
  static bool _isSafeRelativePath(String rel) {
    if (rel.isEmpty) return false;
    if (rel.contains('\\') || rel.contains(':')) return false;
    if (rel.startsWith('/')) return false;
    for (final segment in rel.split('/')) {
      if (segment.isEmpty || segment == '.' || segment == '..') return false;
      if (segment == '.machine.key') return false;
      if (segment.startsWith('_restore_backup_')) return false;
    }
    return true;
  }

  /// 覆盖前的快照：把 accounts/（递归）、accounts.json、.machine.key 复制到
  /// `<base>/_restore_backup_<yyyyMMdd_HHmmss>/`。
  ///
  /// 只复制这三项而不是整个基目录：导入只覆盖这三项，多复制没有回滚价值，
  /// 却会把导出产物 / 图片资产再复制一遍。全部 best-effort，任一项失败只
  /// debugPrint——快照是保险，不该成为恢复的阻塞点。
  /// 三项都不存在时返回 null（首次装机没有可回滚的东西，不必留空目录）。
  static Future<String?> _snapshotBeforeRestore(String base) async {
    final sep = Platform.pathSeparator;
    final accountsDir = Directory('$base${sep}accounts');
    final accountsJson = File('$base${sep}accounts.json');
    final machineKey = File('$base$sep.machine.key');
    final hasAccounts = accountsDir.existsSync();
    final hasJson = accountsJson.existsSync();
    final hasKey = machineKey.existsSync();
    if (!hasAccounts && !hasJson && !hasKey) return null;

    final snapshot = Directory(
        '$base${sep}_restore_backup_${_dirStamp(DateTime.now())}');
    try {
      await snapshot.create(recursive: true);
    } catch (e) {
      debugPrint('恢复：快照目录创建失败，未留下回滚点：$e');
      return null;
    }
    var copied = 0;
    if (hasAccounts) {
      try {
        await _copyTree(accountsDir, Directory('${snapshot.path}${sep}accounts'));
        copied++;
      } catch (e) {
        debugPrint('恢复：快照 accounts/ 失败：$e');
      }
    }
    if (hasJson) {
      try {
        await accountsJson.copy('${snapshot.path}${sep}accounts.json');
        copied++;
      } catch (e) {
        debugPrint('恢复：快照 accounts.json 失败：$e');
      }
    }
    if (hasKey) {
      try {
        await machineKey.copy('${snapshot.path}$sep.machine.key');
        copied++;
      } catch (e) {
        debugPrint('恢复：快照 .machine.key 失败：$e');
      }
    }
    // 三项全失败 = 磁盘满/权限不足：空目录不是回滚点，必须报 null，
    // 否则界面会告诉用户「有快照可回滚」而实际什么都没有。
    if (copied == 0) {
      debugPrint('恢复：快照未复制任何内容，回滚点不存在：${snapshot.path}');
      return null;
    }
    return snapshot.path;
  }

  /// 递归复制目录内容（dart:io 的 Directory 没有递归 copy）。
  ///
  /// followLinks: false：符号链接当普通条目跳过，避免顺着链接把基目录外的
  /// 内容复制进快照。
  static Future<void> _copyTree(Directory src, Directory dst) async {
    final sep = Platform.pathSeparator;
    await dst.create(recursive: true);
    await for (final entity in src.list(followLinks: false)) {
      final name = _fileName(entity.path.replaceAll('\\', '/'));
      if (entity is Directory) {
        await _copyTree(entity, Directory('${dst.path}$sep$name'));
      } else if (entity is File) {
        await entity.copy('${dst.path}$sep$name');
      }
    }
  }

  /// 删除文件或目录，失败只 debugPrint（占用 / 权限问题不该让恢复直接崩）。
  static Future<void> _deleteBestEffort(FileSystemEntity entity) async {
    try {
      if (entity is Directory) {
        if (await entity.exists()) await entity.delete(recursive: true);
      } else if (await entity.exists()) {
        await entity.delete();
      }
    } catch (e) {
      debugPrint('恢复：清理 ${entity.path} 失败（可能被占用）：$e');
    }
  }

  /// 文件相对路径（统一 `/` 分隔，不带盘符）。
  ///
  /// list 的根就是 [base]，所以正常一定命中前缀；这里再按大小写不敏感比较
  /// 兜一次底（Windows 盘符 / 路径大小写）。仍不命中说明调用方式异常，此时
  /// 返回原路径——它带盘符，导入侧会按「非法路径」整包拒绝，绝不会写坏磁盘。
  static String _relativeKey(String base, String fullPath) {
    final sep = Platform.pathSeparator;
    var root = base;
    if (!root.endsWith(sep)) root = '$root$sep';
    var rel = fullPath;
    if (rel.startsWith(root)) {
      rel = rel.substring(root.length);
    } else if (rel.toLowerCase().startsWith(root.toLowerCase())) {
      rel = rel.substring(root.length);
    }
    return rel.replaceAll('\\', '/');
  }

  /// 取文件名（`/` 分隔的相对路径）。
  static String _fileName(String rel) =>
      rel.substring(rel.lastIndexOf('/') + 1);

  /// 下载文件名时间戳：yyyyMMdd-HHmmss。
  /// 精确到秒是因为同一分钟内连导两次会静默覆盖上一份包；包里可能是几 GB
  /// 的图片资产，宁可文件名多三位。
  static String _secondStamp(DateTime t) =>
      '${t.year}${_two(t.month)}${_two(t.day)}-'
      '${_two(t.hour)}${_two(t.minute)}${_two(t.second)}';

  /// 快照目录时间戳：yyyyMMdd_HHmmss。
  static String _dirStamp(DateTime t) =>
      '${t.year}${_two(t.month)}${_two(t.day)}_'
      '${_two(t.hour)}${_two(t.minute)}${_two(t.second)}';

  static String _two(int v) => v.toString().padLeft(2, '0');
}
