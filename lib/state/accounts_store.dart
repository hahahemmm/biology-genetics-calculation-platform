// accounts_store.dart —— 本机多账号档案（v2.24）。
//
// 为什么存在：14 个持久化 store 全部经 userAppDir() 定位文件，之前是
// 「一个进程一个目录」——同一台机器上老师/学生轮流用，错题本、会话历史、
// AI Key 全糊在一起。现在由本 store 在启动最开始决定「当前档案目录」，
// 各 store 原样调用 userAppDir() 就落到各自档案里，14 个 store 零改动。
//
// 落盘形态：
//   桌面 / 安卓：档案目录 `<基目录>/accounts/<id>/`，清单 `<基目录>/accounts.json`；
//   Web：localStorage key 前缀（local 档案用空前缀，保持老数据可读）。
//
// 边界（诚实）：
//   - PIN 只是门禁，**不加密**任何文件：能碰到磁盘的人仍能读全部数据；
//   - 删档案不物理删除：目录移到 `<基目录>/_trash_accounts/<id>_<时间戳>/`；
//   - 所有 IO 都兜住异常只 debugPrint——这里抛出去等于学生打不开软件。

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../storage/platform_storage_io.dart'
    if (dart.library.html) '../storage/platform_storage_web.dart';

/// 一个本机档案（不含任何业务数据——数据都在它自己的目录里）。
class AccountProfile {
  final String id;
  final String name;
  final String pinSalt; // hex，空串 = 无 PIN
  final String pinHash; // hex
  final int createdAt; // epoch ms

  const AccountProfile({
    required this.id,
    required this.name,
    required this.pinSalt,
    required this.pinHash,
    required this.createdAt,
  });

  bool get hasPin => pinHash.isNotEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'pinSalt': pinSalt,
        'pinHash': pinHash,
        'createdAt': createdAt,
      };

  /// 非法条目返回 null 而不是抛错：清单里一条脏数据不该让整个列表读崩。
  static AccountProfile? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'];
    if (id is! String || id.isEmpty) return null;
    final name = j['name'];
    final createdAt = j['createdAt'];
    final salt = j['pinSalt'];
    final hash = j['pinHash'];
    return AccountProfile(
      id: id,
      name: (name is String && name.isNotEmpty) ? name : id,
      pinSalt: salt is String ? salt : '',
      pinHash: hash is String ? hash : '',
      createdAt: createdAt is int ? createdAt : 0,
    );
  }
}

/// 本机档案清单 + 当前档案（单例，ChangeNotifier）。
///
/// 唯一必须遵守的时序：load() 要在别的 store 读盘之前完成——它负责把
/// accountDataDir / accountKeyPrefix 指向当前档案，晚一步就全落基目录。
class AccountsStore extends ChangeNotifier {
  AccountsStore._();
  static final AccountsStore instance = AccountsStore._();

  /// 测试注入基目录（非空时不碰真实用户目录）。
  @visibleForTesting
  static String? debugBaseDir;

  /// 测试注入：强制走 Web 分支（桌面 VM 上跑 Web 路径断言用）。
  @visibleForTesting
  static bool? debugForceWeb;

  /// 跑在 flutter test 进程里（判据同 first_run_store）。
  /// ⚠ 只在非 Web 分支求值——浏览器里没有 Platform.environment。
  static bool get _isFlutterTest =>
      !kIsWeb && Platform.environment['FLUTTER_TEST'] == 'true';

  /// 老版本的全部数据都躺在基目录顶层，迁移目标就是它的主人。
  static const String _defaultId = 'local';
  static const String _accountsKey = 'accounts_json';
  static const String _manifestName = 'accounts.json';
  /// 一次性解锁标记：门禁里选人 + 重启后直接放行（见 selectAndUnlock）。
  static const String _unlockMarkerName = '_unlock_pending';
  static const String _unlockMarkerKey = 'unlock_pending';

  /// 与错题本加密导出同一档（cryptography 2.9 纯 Dart，桌面约 80ms/次）。
  static const int _pinIterations = 100000;

  final List<AccountProfile> _accounts = <AccountProfile>[];
  String? _activeId;
  String? _baseDir;
  bool _web = false;
  bool _loaded = false;

  // 默认放行：load() 之前还没有「档案」概念（各 store 直接落基目录），拦门禁
  // 没有意义；真实启动必定先 await load()。也让既有直接 pump BiologyApp、
  // 不跑 main() 的 widget 测试保持原行为。
  bool _unlocked = true;

  /// 基目录；Web 端没有文件系统，返 null。
  String? get baseDir => _baseDir;

  /// 不可变副本——调用方拿不到内部 List，避免绕过 _save 改档。
  List<AccountProfile> get accounts => List<AccountProfile>.unmodifiable(_accounts);

  AccountProfile? get active {
    for (final a in _accounts) {
      if (a.id == _activeId) return a;
    }
    return _accounts.isEmpty ? null : _accounts.first;
  }

  String? get activeId => _activeId;

  /// 启动是否需要显示门禁：load() 已算出 unlocked，门禁只是它的反面。
  bool get needsGate => !_unlocked;

  /// 已通过门禁（单档案无 PIN 时 load() 直接置 true）。
  bool get unlocked => _unlocked;

  /// 读清单 / 首次迁移 / 定当前档案。重复调用幂等（_loaded 守护）。
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    _web = debugForceWeb ?? isWebStorage;
    // Android：先等 getFilesDir 缓存，否则 baseAppDir() 返 null（桌面/Web no-op）。
    try {
      await ensureAppDirReady();
    } catch (e) {
      debugPrint('[biology] AccountsStore ensureAppDirReady 失败: $e');
    }
    _baseDir = _web ? null : (debugBaseDir ?? baseAppDir());
    // flutter test + 默认真实路径：只跑内存态。迁移会 rename 用户的真文件，
    // 测试一旦碰真盘就是数据事故；_baseDir=null 让下面所有 IO 自然短路。
    if (!_web && debugBaseDir == null && _isFlutterTest) _baseDir = null;

    final doc = await _readDoc();
    if (doc == null) {
      // 首次启动，或清单损坏：坏清单先改名留档，再按新装流程重建，
      // 绝不直接覆盖用户已有的账号列表。
      await _backupBrokenManifest();
      _accounts
        ..clear()
        ..add(_defaultProfile());
      await _save();
    } else {
      _accounts
        ..clear()
        ..addAll(doc.accounts);
      _activeId = doc.activeId;
    }

    await _ensureAccountDirs();

    // activeId 失效（手改过清单 / 删过目录）→ 回落到第 0 个。
    var active = _activeId;
    var known = false;
    for (final a in _accounts) {
      if (a.id == active) {
        known = true;
        break;
      }
    }
    if (!known) active = _accounts.isEmpty ? null : _accounts.first.id;
    _applyActive(active);

    // 每次都跑一次迁移（幂等：目标已存在就跳过）。上一次有一条 rename
    // 失败（文件被占用等）时，那些文件会留在基目录顶层，而各 store 此后
    // 只读 accounts/<id>/——用户会觉得错题本凭空清空。每次启动补一次，
    // 下一次就能把落下的搬进去。
    if (!_web) await _migrateLegacyEntries();

    // v2.24：门禁里选人后重启进入——上次已通过 PIN 校验的档案直接放行。
    // 没有这个标记，多档案用户每次重启都要重新选人 + 输 PIN。
    final pending = await _takeUnlockMarker();
    _unlocked = (pending != null && pending == active) ||
        (_accounts.length == 1 && !_accounts.first.hasPin);
    notifyListeners();
  }

  /// 新建档案。不自动切换：切不切由 UI 决定（创建后多半要 select）。
  Future<AccountProfile> create(String name, String pin) async {
    final id = 'a${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    final trimmed = name.trim();
    final salt = pin.isEmpty ? '' : randomSaltHex();
    final hash = pin.isEmpty ? '' : await hashPin(pin, salt);
    final p = AccountProfile(
      id: id,
      name: trimmed.isEmpty ? '账号' : trimmed,
      pinSalt: salt,
      pinHash: hash,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    _accounts.add(p);
    await _ensureDir(id);
    await _save();
    notifyListeners();
    return p;
  }

  /// 无 PIN 档案恒 true（门禁上是「点一下就进」）；id 不存在返 false。
  Future<bool> verifyPin(String id, String pin) async {
    AccountProfile? p;
    for (final a in _accounts) {
      if (a.id == id) {
        p = a;
        break;
      }
    }
    if (p == null) return false;
    if (!p.hasPin) return true;
    try {
      return await hashPin(pin, p.pinSalt) == p.pinHash;
    } catch (e) {
      debugPrint('[biology] AccountsStore 校验 PIN 失败: $e');
      return false;
    }
  }

  /// pin 传空串 = 取消 PIN（salt/hash 一起清，不留半套凭据）。
  Future<void> setPin(String id, String pin) async {
    final i = _accounts.indexWhere((a) => a.id == id);
    if (i < 0) return;
    final salt = pin.isEmpty ? '' : randomSaltHex();
    final hash = pin.isEmpty ? '' : await hashPin(pin, salt);
    final old = _accounts[i];
    _accounts[i] = AccountProfile(
      id: old.id,
      name: old.name,
      pinSalt: salt,
      pinHash: hash,
      createdAt: old.createdAt,
    );
    await _save();
    notifyListeners();
  }

  Future<void> rename(String id, String name) async {
    final i = _accounts.indexWhere((a) => a.id == id);
    final trimmed = name.trim();
    if (i < 0 || trimmed.isEmpty) return;
    final old = _accounts[i];
    _accounts[i] = AccountProfile(
      id: old.id,
      name: trimmed,
      pinSalt: old.pinSalt,
      pinHash: old.pinHash,
      createdAt: old.createdAt,
    );
    await _save();
    notifyListeners();
  }

  /// 删档案：目录移进 `_trash_accounts/`（可人工找回），Web 端清该前缀的 key。
  Future<void> remove(String id) async {
    if (_accounts.length <= 1) {
      throw StateError('至少要保留一个账号');
    }
    // 已解锁时删「当前档案」会把数据目录搬走，而进程里各 store 仍握着它的
    // 内存副本，之后任何一次保存都会写进剩下的档案（串档）。这条硬挡。
    //
    // 未解锁（选人页）时允许删当前档案——否则门禁上永远删不掉它。但**不能**
    // 因此假设「选人页没有内存副本」：main() 在门禁之前就 load() 了各 store，
    // ThemeController / PresentModeController 也在 initState 读过盘，lock()
    // 只翻了一个 bool，单例缓存原封不动。所以删掉 active 之后调用方必须重启
    // 进程，重启责任在 UI（见 account_gate 的删除流程）。
    if (id == _activeId && _unlocked) {
      throw StateError('不能删除当前账号，请先切换到其它账号');
    }
    final i = _accounts.indexWhere((a) => a.id == id);
    if (i < 0) return;
    final removed = _accounts.removeAt(i);

    if (_web) {
      // 临时把前缀指向被删档案，清完再由 _applyActive 写回当前档案。
      final prefix = _prefixFor(removed.id);
      // ⚠ local 档案用空前缀，而 storageRemoveByPrefix('') 的 startsWith('')
      // 恒真——那会把其它档案连同账号清单一起删光。遗留 key 留着不影响
      // 新档案，比误删安全得多。
      if (prefix.isNotEmpty) {
        accountKeyPrefix = prefix;
        try {
          await storageRemoveByPrefix(prefix);
        } catch (e) {
          debugPrint('[biology] AccountsStore 清 localStorage 失败: $e');
        }
      } else {
        debugPrint('[biology] 删除 local 档案：跳过清 key（空前缀会误删全部档案）');
      }
    } else {
      await _trashDir(removed.id);
    }

    _applyActive(_activeId == id ? _accounts.first.id : _activeId);
    await _save();
    notifyListeners();
  }

  /// 整机重置：把每个档案目录整体移进 _trash_accounts，重建一个无 PIN 的
  /// 默认档案。等价于「重装但保留回收站」，是忘记 PIN 时的唯一出路。
  ///
  /// 为什么不留「重置某个档案的 PIN」：PIN 是门禁不是密钥，能重置别人的 PIN
  /// 等于任何人拿到设备就能接管对方档案——那 PIN 就毫无意义。
  Future<void> resetAllProfiles() async {
    for (final a in List<AccountProfile>.of(_accounts)) {
      if (_web) {
        final prefix = _prefixFor(a.id);
        try {
          // local 用空前缀：不能按前缀清（startsWith('') 恒真会删光全部），
          // 改用「删掉所有不带 acct. 的 key」——那正好是 local 的数据域。
          // 不清理的话，重置后旧数据原样回来且不再要 PIN，等于绕过门禁。
          if (prefix.isEmpty) {
            await storageRemoveLocalKeys();
          } else {
            accountKeyPrefix = prefix;
            await storageRemoveByPrefix(prefix);
          }
        } catch (e) {
          debugPrint('[biology] AccountsStore 重置清 key 失败 $prefix: $e');
        }
      } else {
        await _trashDir(a.id);
      }
    }
    _accounts
      ..clear()
      ..add(_defaultProfile());
    _applyActive(_defaultId);
    await _ensureDir(_defaultId);
    _unlocked = true;
    await _save();
    notifyListeners();
  }

  /// 切当前档案：写 activeId + 把 accountDataDir / 前缀指过去。不负责重启。
  Future<void> select(String id) async {
    var exists = false;
    for (final a in _accounts) {
      if (a.id == id) {
        exists = true;
        break;
      }
    }
    if (!exists) return;
    _applyActive(id);
    await _ensureDir(id);
    await _save();
    notifyListeners();
  }

  /// 选人 + 记住「本档案已通过校验」：门禁里选到**非当前**档案时用。
  ///
  /// 为什么需要落盘标记：切换档案要求重启进程（十几个单例的缓存语义
  /// 各不相同，热切会串档）。重启后 load() 若只看「多档案就要选人」，
  /// 用户每切一次都要重输 PIN，等于白选。标记是一次性的，读完即删。
  Future<void> selectAndUnlock(String id) async {
    await select(id);
    try {
      if (_web) {
        await storageSetRaw(_unlockMarkerKey, id);
      } else {
        final b = _baseDir;
        if (b != null) {
          File(_join(b, _unlockMarkerName)).writeAsStringSync(id);
        }
      }
    } catch (e) {
      // 标记写不进去只影响「下次重启是否要重新选人」，不影响本次切换。
      debugPrint('[biology] AccountsStore 写解锁标记失败: $e');
    }
  }

  /// 读出并删除一次性解锁标记（读后即删，避免永久免 PIN）。
  Future<String?> _takeUnlockMarker() async {
    try {
      if (_web) {
        final raw = storageGetRaw(_unlockMarkerKey);
        if (raw == null) return null;
        await storageSetRaw(_unlockMarkerKey, '');
        return raw.trim().isEmpty ? null : raw.trim();
      }
      final b = _baseDir;
      if (b == null) return null;
      final f = File(_join(b, _unlockMarkerName));
      if (!f.existsSync()) return null;
      final raw = f.readAsStringSync().trim();
      try {
        f.deleteSync();
      } catch (_) {}
      return raw.isEmpty ? null : raw;
    } catch (e) {
      debugPrint('[biology] AccountsStore 读解锁标记失败: $e');
      return null;
    }
  }

  /// 门禁通过后由 UI 调（PIN 校验成功 / 无 PIN 点入）。
  void markUnlocked() {
    if (_unlocked) return;
    _unlocked = true;
    notifyListeners();
  }

  /// 重新上锁：回到选人页。Gate 订阅的是 unlocked，置 false 即可。
  void lock() {
    if (!_unlocked) return;
    _unlocked = false;
    notifyListeners();
  }

  /// PBKDF2-HMAC-SHA256 ×100k → hex。与错题本导出同参数，纯 Dart，跨端一致。
  static Future<String> hashPin(String pin, String saltHex) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: _pinIterations,
      bits: 256,
    );
    final key = await pbkdf2.deriveKey(
      secretKey: SecretKey(utf8.encode(pin)),
      nonce: _fromHex(saltHex),
    );
    return _toHex(await key.extractBytes());
  }

  /// 16 字节 Random.secure → hex。PIN 只有 4 位，盐是防彩虹表的唯一屏障。
  static String randomSaltHex() {
    final r = Random.secure();
    return _toHex(List<int>.generate(16, (_) => r.nextInt(256)));
  }

  /// 测试用：清内存态（不碰磁盘），让同一进程能重复跑 load()。
  @visibleForTesting
  void debugReset() {
    _accounts.clear();
    _activeId = null;
    _baseDir = null;
    _web = false;
    _loaded = false;
    _unlocked = true;
    accountDataDir = null;
    accountKeyPrefix = null;
  }

  // ---- 内部 ----

  AccountProfile _defaultProfile() => AccountProfile(
        id: _defaultId,
        name: '本机用户',
        pinSalt: '',
        pinHash: '',
        createdAt: DateTime.now().millisecondsSinceEpoch,
      );

  /// 读清单。null = 不存在或读不出来（两条路都走"重建"，但重建前先备份）。
  Future<({List<AccountProfile> accounts, String? activeId})?> _readDoc() async {
    try {
      String? raw;
      if (_web) {
        raw = storageGetRaw(_accountsKey);
      } else {
        final b = _baseDir;
        if (b == null) return null;
        final f = File(_join(b, _manifestName));
        if (!f.existsSync()) return null;
        raw = f.readAsStringSync();
      }
      if (raw == null || raw.isEmpty) return null;
      final j = jsonDecode(raw);
      if (j is! Map) return null;
      final list = <AccountProfile>[];
      final arr = j['accounts'];
      if (arr is List) {
        for (final e in arr) {
          final p = AccountProfile.fromJson(e);
          if (p != null) list.add(p);
        }
      }
      if (list.isEmpty) return null;
      final active = j['activeId'];
      return (accounts: list, activeId: active is String ? active : null);
    } catch (e) {
      debugPrint('[biology] AccountsStore 读清单失败: $e');
      return null;
    }
  }

  /// 清单存在但读不出来：改名留档（不删、不覆盖），人还能手工救回来。
  Future<void> _backupBrokenManifest() async {
    if (_web) return;
    final b = _baseDir;
    if (b == null) return;
    try {
      final f = File(_join(b, _manifestName));
      if (!f.existsSync()) return;
      f.renameSync(
          _join(b, '$_manifestName.bak-${DateTime.now().millisecondsSinceEpoch}'));
    } catch (e) {
      debugPrint('[biology] AccountsStore 备份坏清单失败: $e');
    }
  }

  /// 一次性迁移：老版本把各 store 的文件直接摊在基目录下，逐个搬进
  /// `accounts/local/`（默认档案 = 老数据的主人）。单个条目失败只跳过——
  /// 搬不动的那份留在原地，绝不丢数据。
  Future<void> _migrateLegacyEntries() async {
    final b = _baseDir;
    if (b == null) return;
    try {
      final root = Directory(b);
      if (!root.existsSync()) return;
      final target = Directory(_accountDir(b, _defaultId));
      target.createSync(recursive: true);
      for (final entity in root.listSync(followLinks: false)) {
        final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (_staysAtRoot(name)) continue;
        final dest = '${target.path}${Platform.pathSeparator}$name';
        // 目标已存在 = 之前迁过 / 同名冲突：跳过，不覆盖已有数据。
        if (FileSystemEntity.typeSync(dest) != FileSystemEntityType.notFound) {
          continue;
        }
        try {
          entity.renameSync(dest);
        } catch (e) {
          debugPrint('[biology] AccountsStore 迁移「$name」失败: $e');
        }
      }
    } catch (e) {
      debugPrint('[biology] AccountsStore 迁移失败: $e');
    }
  }

  /// 属于「分档基础设施」而非某个档案的条目，必须留在基目录。
  static bool _staysAtRoot(String name) {
    if (name == 'accounts' || name == '_trash_accounts' || name == '待删除') {
      return true;
    }
    if (name.startsWith('_restore_backup_')) return true;
    // 一次性解锁标记：属于门禁基础设施，搬进档案目录会让它失效。
    if (name == _unlockMarkerName) return true;
    // 清单与它的备份是索引本身，不属于任何档案。
    if (name.startsWith(_manifestName)) return true;
    return false;
  }

  Future<void> _ensureAccountDirs() async {
    for (final a in _accounts) {
      await _ensureDir(a.id);
    }
  }

  Future<void> _ensureDir(String id) async {
    if (_web) return;
    final b = _baseDir;
    if (b == null) return;
    try {
      Directory(_accountDir(b, id)).createSync(recursive: true);
    } catch (e) {
      debugPrint('[biology] AccountsStore 建目录失败 $id: $e');
    }
  }

  Future<void> _trashDir(String id) async {
    final b = _baseDir;
    if (b == null) return;
    try {
      final src = Directory(_accountDir(b, id));
      if (!src.existsSync()) return;
      final trash = Directory(_join(b, '_trash_accounts'));
      trash.createSync(recursive: true);
      final stamp = DateTime.now().millisecondsSinceEpoch;
      var dest = '${trash.path}${Platform.pathSeparator}${id}_$stamp';
      var n = 1;
      // 同毫秒删两次会撞名：加序号重试，绝不覆盖上一份回收数据。
      while (FileSystemEntity.typeSync(dest) != FileSystemEntityType.notFound) {
        dest = '${trash.path}${Platform.pathSeparator}${id}_${stamp}_${n++}';
      }
      src.renameSync(dest);
    } catch (e) {
      debugPrint('[biology] AccountsStore 移入回收站失败 $id: $e');
    }
  }

  /// 把「当前档案」落到平台存储；load() 返回前必须完成，否则各 store 读错目录。
  void _applyActive(String? id) {
    _activeId = id;
    if (_web) {
      accountDataDir = null;
      accountKeyPrefix = _prefixFor(id);
    } else {
      final b = _baseDir;
      accountDataDir = (b == null || id == null) ? null : _accountDir(b, id);
    }
  }

  static String _prefixFor(String? id) =>
      (id == null || id == _defaultId) ? '' : 'acct.$id.';

  Future<void> _save() async {
    final body = jsonEncode(<String, dynamic>{
      'version': 1,
      'activeId': _activeId,
      'accounts': <Map<String, dynamic>>[for (final a in _accounts) a.toJson()],
    });
    try {
      if (_web) {
        await storageSetRaw(_accountsKey, body);
        return;
      }
      final b = _baseDir;
      if (b == null) return;
      final f = File(_join(b, _manifestName));
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(body);
    } catch (e) {
      debugPrint('[biology] AccountsStore 写清单失败: $e');
    }
  }

  static String _join(String a, String b) => '$a${Platform.pathSeparator}$b';

  static String _accountDir(String base, String id) =>
      _join(_join(base, 'accounts'), id);

  static String _toHex(List<int> bytes) {
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  /// 坏 hex → 空字节；配合 hashPin 只会算出不匹配的哈希（门禁失败），不抛错。
  static List<int> _fromHex(String hex) {
    if (hex.isEmpty || hex.length.isOdd) return const <int>[];
    final out = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      final v = int.tryParse(hex.substring(i, i + 2), radix: 16);
      if (v == null) return const <int>[];
      out.add(v);
    }
    return out;
  }
}
