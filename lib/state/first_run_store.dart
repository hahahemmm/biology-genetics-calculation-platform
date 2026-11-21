// first_run_store.dart —— 首启标记 + 角色分流（v2.13 R5 P0 重做）
//
// 设计目标：
//   1. 区分两类用户：老师（teacher） / 学生（student）。
//   2. 老师不需要「我的错题」入口——错题本是学生私人学习空间，老师工作流
//      不该被干扰。学生看到完整入口。
//   3. 首启 dialog 引导选择角色，选项写盘后下次不再弹。
//   4. 角色可随时在首页顶部 chip 切换（弹 dialog 2 选 1）。
//
// v2.13 R5 P0 修订：移除「家长」角色——
//   产品决策「Biology 不面向家长」（UX 走查 / persona 只考虑学生 + 老师），
//   见 _ver_R5_1st_b.md §1。原 `enum UserRole { teacher, student, parent }`
//   + 家长子标题/图标全部移除；老磁盘数据 `{"role":"parent"}` 由
//   `fromName` 兜底回 student（向后兼容，不丢用户）。
//
// 持久化：与 MistakeBook / HistoryStore / ScanBankStore 同构——
//   桌面 / 安卓：`~/.biology_app/first_run.json`（File 写盘）。
//   Web：localStorage（key = `first_run_json`），避免 dart:io 直接调用
//   在 Web 端抛 UnimplementedError（之前 v2.12 Wave 3-B 报 P0 缺陷：
//   Platform.environment['USERPROFILE'] 在 Web 端 build 成功但运行
//   时 writeAsStringSync 抛 UnimplementedError，catch 吞掉 → 角色
//   写不进去 → 刷新回到首启 dialog）。本次改用 platform_storage 中性
//   API（userAppDir() / storageGet / storageSet + isWebStorage 分支）
//   让 Web 端走 localStorage，桌面 / 安卓继续走 File。
//
// API 风格：单例 + 静态调用 + 同步 getter（role 缓存），异步 IO 用 Future。
// 这样 dashboard_page 在 build 里直接读 `currentRole()` 决定是否渲染错题本
// 卡片——同步路径避免 FutureBuilder 闪烁。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../storage/platform_storage_io.dart'
    if (dart.library.html) '../storage/platform_storage_web.dart';

/// 用户角色枚举（v2.13 R5 P0：移除 parent）。
///
/// 字符串 name 写入 JSON，避免 Dart 枚举 ordinal 重排破坏历史数据。
///
/// 向后兼容：`fromName('parent')` 兜底回 student——v2.12 / v2.13 早期
/// 版本曾写入 `{"role":"parent"}` 的用户，升级后自动归到学生分支，不丢
/// 用户（看不到首启 dialog 重弹、也看不到家长选项带来的其他歧义）。
enum UserRole {
  teacher, // 老师
  student; // 学生

  String get displayName {
    switch (this) {
      case UserRole.teacher:
        return '老师';
      case UserRole.student:
        return '学生';
    }
  }

  static UserRole fromName(String? n) {
    for (final r in UserRole.values) {
      if (r.name == n) return r;
    }
    // 兜底：默认学生。也覆盖老磁盘 'parent'（v2.12 / v2.13 早期版本遗留）。
    return UserRole.student;
  }
}

/// 首启标记 + 角色存储（单例，ChangeNotifier）。
///
/// - `load()` 启动时调用，幂等（_loaded 守护）。
/// - `isFirstRun()` 同步读缓存——true 表示需要弹角色选择 dialog。
/// - `currentRole()` 同步读缓存——null 表示尚未选择。
/// - `setRole(role)` 写盘 + notifyListeners。
/// - 测试用 `debugFilePath` 注入临时文件（同 MistakeBook / HistoryStore）。
/// - 测试用 `debugWebStorage` / `debugForceIsWebStorage` mock localStorage
///   （flutter_test 无 window 对象，platform_storage_web 的 storageGet
///   实际无法使用——test 注入 `Map<String, String>` 模拟 localStorage）。
/// - 测试用 `debugEnsureLoaded()` = `debugReset()` + `load()` 一站式（让
///   `test/main_first_run_test.dart` 这种 HomeShell 集成测试不必关心
///   加载顺序）。
class FirstRunStore extends ChangeNotifier {
  FirstRunStore._();
  static final FirstRunStore instance = FirstRunStore._();

  /// 测试注入：非空时 load/save 走该文件而非用户目录（仅桌面 / 安卓
  /// File 路径生效；Web 端 localStorage 不受 debugFilePath 影响）。
  static String? debugFilePath;

  /// 测试注入：mock Web 端 localStorage。非空时 `_storageGet` /
  /// `_storageSet` 走此 Map 而非 platform_storage。
  ///
  /// flutter_test 没有 window 对象（`package:web` 的 `localStorage` 不可用），
  /// 此 hook 让 `test/first_run_store_test.dart` 能验证 web 端 round-trip
  /// 链路（setRole 写 localStorage → load 读回 → role 一致）。
  @visibleForTesting
  static Map<String, String>? debugWebStorage;

  /// 测试注入：mock `isWebStorage` 标志。非空时强制走 web / desktop 路径。
  /// 配合 `debugWebStorage` 模拟"用户在浏览器中"的完整链路。
  @visibleForTesting
  static bool? debugForceIsWebStorage;

  /// 测试注入：整套 widget 测试默认关掉「首启自动弹新手引导」。
  ///
  /// 整壳测试（main_test / nav_* / mobile_smoke / 各回归套件）都在模拟
  /// 「用过一阵的老用户」，它们各自 setUp 里的 debugReset() 会把
  /// guideDone 清回 false —— 于是引导罩层罩在 App 上吸收所有点击，tap
  /// 全打空。这个静态开关不受 debugReset 影响，测试入口
  /// （test/flutter_test_config.dart）置 true；真正要验自动引导的用例
  /// （main_first_run_test）置 false。生产恒为 false。
  ///
  /// 不加 @visibleForTesting：HomeShell 自己要读它（跨文件用会触发
  /// invalid_use_of_visible_for_testing_member 警告），语义靠 debug
  /// 前缀 + 本注释承担。
  static bool debugSuppressAutoGuide = false;

  /// localStorage key。Web 端 load / save 走 storageGet / storageSet。
  static const String _key = 'first_run_json';

  /// 磁盘加载是否完成（避免重复 load 覆盖内存）。
  bool _loaded = false;

  /// 角色缓存（null = 尚未选择，等同 isFirstRun=true）。
  UserRole? _role;

  /// v2.19.54：快捷键指引一次性提示（任一页面键宿主首次成功触发后弹
  /// 「按 ? 查看本页快捷键」，只弹一次，持久化防每次启动重弹）。
  bool _shortcutNudgeShown = false;

  /// 新手引导是否已走过一遍（完成与跳过都算「看过」）。
  /// 缺失 / 非 true 一律按 false = 下次启动仍自动开引导。
  bool _guideDone = false;

  /// 同步读「是否首启」。仅在 load() 完成后才稳定。
  bool isFirstRun() => _role == null;

  /// 同步读当前角色。null = 尚未选择。
  UserRole? currentRole() => _role;

  /// 同步读快捷键指引是否已弹过。
  bool get shortcutNudgeShown => _shortcutNudgeShown;

  /// 同步读「新手引导是否已走过一遍」。
  bool get guideDone => _guideDone;

  /// 当前是否为 web 存储路径（test hook 优先于真实 isWebStorage）。
  bool get _isWebStorage => debugForceIsWebStorage ?? isWebStorage;

  /// 是否运行在 `flutter test` 进程内（`flutter test` 会向被测进程注入
  /// `FLUTTER_TEST=true`；判据同 `local_secure_store` / `history_store` /
  /// `present_mode_controller`）。
  ///
  /// ⚠️ 只允许在 `!_isWebStorage` 分支里求值：Web 端不得访问
  /// `Platform.environment`（浏览器里没有 dart:io 运行时）。
  static bool get _isFlutterTest =>
      !kIsWeb && Platform.environment['FLUTTER_TEST'] == 'true';

  /// 纯判定：本次 load / save 是否应**跳过真实用户配置**
  ///（`~/.biology_app/first_run.json`）。顺序即优先级：
  ///
  /// 1. Web（localStorage 路径）→ 不跳过：浏览器里本来就没有磁盘配置；
  /// 2. 显式注入 [debugFilePath]（测试隔离的临时文件）→ 不跳过：
  ///    临时文件 round-trip 必须照常工作；
  /// 3. `flutter test` 进程 + 默认路径 → **跳过**：否则未隔离 FirstRunStore
  ///    的 widget 测试（如系谱页键宿主）会 load 真实角色 → `_loaded=true`
  ///    → `ui/shortcut_nudge.dart` 成功触发后 `markShortcutNudgeShown`
  ///    把 `{'role':...,'nudge':true}` 写回真盘，改写用户首启状态
  ///    （2026-10-29 SHA256 审计实爆：测试窗口内 first_run.json
  ///    DCA963CA… → D4BD2881…，其余 5 个用户文件未变）。load 侧同闸：
  ///    真实角色泄入内存会让「弹首启 dialog」类断言随真机数据漂移。
  ///
  /// 拆成纯函数只为可测；真实判据 `_skipRealUserFile` 在其前加一层
  /// 「Web 短路」，保证 Web 端不求值 `Platform.environment`。
  @visibleForTesting
  static bool shouldSkipRealUserFile({
    required bool isWebStorage,
    required bool hasDebugFilePath,
    required bool isFlutterTest,
  }) {
    if (isWebStorage) return false; // Web：走 localStorage，无磁盘配置可跳过
    if (hasDebugFilePath) return false; // 显式隔离路径：照常读写
    return isFlutterTest; // flutter test + 默认真实路径：跳过
  }

  /// 真实判据：先 Web 短路（不访问 `Platform.environment`），再走纯判定。
  bool get _skipRealUserFile {
    if (_isWebStorage) return false;
    return shouldSkipRealUserFile(
      isWebStorage: false,
      hasDebugFilePath: debugFilePath != null,
      isFlutterTest: _isFlutterTest,
    );
  }

  /// 加载磁盘 / localStorage 数据。重复调用幂等。
  ///
  /// v2.12 Wave 3-B P0 修复：原 `Platform.environment['USERPROFILE']`
  /// 直接拼路径在 Web 端写盘抛 UnimplementedError 被 catch 吞，导致
  /// 角色写不进去 → 刷新回到首启 dialog。改用 platform_storage 中性
  /// API + `_isWebStorage` 分支：Web 端走 localStorage（不调 File），
  /// 桌面 / 安卓走 `~/.biology_app/first_run.json`。
  ///
  /// 早返语义：isWebStorage=true 时 storageGet 返 null = localStorage
  /// 空 = 首启，**不**回退到 File 路径（避免在浏览器里尝试读硬盘）。
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    // v2.13 R3 W1（P0）：Android 先等 getFilesDir() 缓存就绪，避免
    // _file() fallback 到 '/'（EACCES 静默丢数据）。桌面/Web no-op。
    await ensureAppDirReady();
    try {
      if (_isWebStorage) {
        // Web 端：仅读 localStorage。null = 首启，保持 _role=null。
        final webRaw = _storageGet(_key);
        if (webRaw == null) return;
        _applyJson(jsonDecode(webRaw));
        return;
      }
      // 桌面 / 安卓：File 路径。
      // FLUTTER_TEST + 默认真实路径：不读真实 first_run.json（保持首启
      // 默认）。显式 debugFilePath / Web mock 不走此跳过（round-trip
      // 必须可测）。
      if (_skipRealUserFile) return;
      final f = File(_file());
      if (!f.existsSync()) return; // 首次启动：_role 保持 null
      _applyJson(jsonDecode(f.readAsStringSync()));
    } catch (_) {
      // 损坏文件 / Web 端 Storage 异常不抛错；保持 null（首启）
    }
  }

  /// JSON 解码后应用 role + nudge + guide_done。null / 损坏 / 字段缺失时
  /// 保持默认值。
  void _applyJson(dynamic j) {
    if (j is! Map) return;
    final roleName = j['role']?.toString();
    if (roleName != null && roleName.isNotEmpty) {
      _role = UserRole.fromName(roleName);
      notifyListeners();
    }
    if (j['nudge'] == true) _shortcutNudgeShown = true;
    if (j['guide_done'] == true) _guideDone = true;
  }

  /// v2.19.54：合并写盘——role / nudge / guide_done 同文件存，⛔ 各写各的
  /// 会互相覆盖丢数据（setRole 只写 role 会把已存的 nudge 与 guide_done
  /// 抹掉，导致快捷键提示与新手引导在下次启动双双重弹）。
  Future<void> _save() async {
    final s = jsonEncode({
      'role': _role?.name,
      'nudge': _shortcutNudgeShown,
      'guide_done': _guideDone,
    });
    try {
      if (_isWebStorage) {
        await _storageSet(_key, s);
        return;
      }
      // FLUTTER_TEST + 默认真实路径：不写真实 first_run.json——未隔离
      // FirstRunStore 的 widget 测试（系谱页键宿主 → shortcut_nudge →
      // markShortcutNudgeShown，或 setRole）在测试里只改内存。
      // 显式 debugFilePath（隔离临时文件）/ Web mock 不跳过。
      if (_skipRealUserFile) return;
      final f = File(_file());
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(s);
    } catch (e) {
      debugPrint('[biology] FirstRunStore save failed: $e');
    }
  }

  /// 写角色到磁盘 / localStorage + 通知监听者。
  Future<void> setRole(UserRole role) async {
    _role = role;
    notifyListeners();
    await _save();
  }

  /// v2.19.54：标记快捷键指引已弹过（一次性提示落盘）。
  ///
  /// ⛔⛔ 写盘前提：store 必须已 load()——_role 还是 null 时写盘会把
  /// `{'role': null}` 落出去，**抹掉用户已选角色**（下次启动重弹首启
  /// dialog）。事故实录：未隔离 FirstRunStore 的测试触发页面键宿主成功
  /// 路径 → nudge 写盘 → 真实角色被 null 覆盖 + 一批泵真 app 的测试被
  /// 首启 dialog 盖住全红。真实 app 启动必 load()，正常路径照常持久化；
  /// 未加载环境只更内存标记（当次会话不再弹）。
  Future<void> markShortcutNudgeShown() async {
    if (_shortcutNudgeShown) return;
    _shortcutNudgeShown = true;
    if (!_loaded) return;
    await _save();
  }

  /// 新手引导已走完一遍：完成 / 跳过都算看过，之后不再自动弹。
  ///
  /// 与 [markShortcutNudgeShown] 同款写盘前提：未 load() 时只更内存——
  /// 写盘会把 `{'role': null}` 落出去，抹掉用户已选角色（见该方法注释）。
  Future<void> markGuideDone() async {
    if (_guideDone) return;
    _guideDone = true;
    if (!_loaded) return;
    await _save();
  }

  /// 测试用：重置内存 + loaded 标记。**不**触碰磁盘。
  @visibleForTesting
  void debugReset() {
    _role = null;
    _shortcutNudgeShown = false;
    _guideDone = false;
    _loaded = false;
  }

  /// 测试用：重置 + 触发 load。返回 load 完成后的 Future。
  ///
  /// 同构 `MistakeBook.debugReset()` + `load()` 链路——`test/main_first_run_test.dart`
  /// 这种 HomeShell 集成测试希望"先清状态再确保加载完成"一站式调用，
  /// 不用关心 setup 顺序。
  @visibleForTesting
  Future<void> debugEnsureLoaded() async {
    debugReset();
    await load();
  }

  /// Web 端 storage 读。test 用 debugWebStorage 注入；生产用 platform_storage。
  String? _storageGet(String key) {
    if (debugWebStorage != null) return debugWebStorage![key];
    return storageGet(key);
  }

  /// Web 端 storage 写。test 用 debugWebStorage 注入；生产用 platform_storage。
  Future<void> _storageSet(String key, String value) async {
    if (debugWebStorage != null) {
      debugWebStorage![key] = value;
      return;
    }
    await storageSet(key, value);
  }

  // ---- 持久化 ----

  /// 桌面 / 安卓路径：`<userAppDir>/first_run.json`。
  /// 注入的 debugFilePath 优先（同 MistakeBook / HistoryStore）。
  /// Web 端走 storageGet / storageSet，不会调到此处。
  static String _file() {
    if (debugFilePath != null) return debugFilePath!;
    final appDir = userAppDir();
    if (appDir == null) return 'first_run.json'; // Web 兜底占位（实际不会走）
    final dir = Directory(appDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return '${dir.path}/first_run.json';
  }
}
