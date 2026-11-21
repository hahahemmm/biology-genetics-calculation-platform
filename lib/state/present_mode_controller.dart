// present_mode_controller.dart —— 课堂模式（演示模式）控制器：面向教师在大屏/白板
// （鸿合等）讲课场景。
//
// 开启后全局生效（MaterialApp.builder 注入）：
// - 字号 ×[textScale]（R13 移植：1.3→1.75，正文 14pt→24.5px，兑现本文件一直写着却没做到的「正文≥24pt」投影门槛）；
//   按钮/芯片随文字等比变大，触控目标随之放大（白板手指触控友好）。
// - 系谱画布显示激光笔光标（跟随指针的红色光点+渐隐轨迹，引导全班视线）。
//
// v2.20.1 → 2026-10-30 修订（用户裁定）：**课堂模式 enabled 改为持久化的
// 模式记忆**——首次启动（无配置文件 / 字段缺失）一律「标准」普通小字号；
// 之后每次冷启动恢复上次退出时的模式（上次是课堂大屏就仍进课堂大屏）。
// 落盘三项：enabled / laser / hc；enabled 只在用户主动切换时写入，崩溃或
// 强杀不会留下错误状态。Windows 侧窗口仍是 SW_SHOWNORMAL +
// fullscreen_=false（C++ 不改），F11 也只在当次主动按下时切换。
//
// 持久化：与 FirstRunStore / AppState / ThemeController 同构——
//   桌面 / 安卓：`~/.biology_app/present_mode.json`（File 写盘，仅 laser/hc）。
//   Web：localStorage（key = `present_mode_json`），避免 dart:io 在 Web
//   端抛 UnimplementedError（v2.12 R1 C P0 #7 修复：原
//   `Platform.environment['USERPROFILE']` 直接拼路径在 Web 端 build
//   成功但运行时 writeAsString 抛 UnimplementedError，catch 吞掉 →
//   课堂模式 / 激光笔 / 高对比写不进去 → 刷新回到默认关）。本次改用
//   platform_storage 中性 API（userAppDir() / storageGet / storageSet
//   + isWebStorage 分支）让 Web 端走 localStorage，桌面 / 安卓继续
//   走 File。
//
// 全局单例，与 ThemeController 同构（ListenableBuilder 监听）。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../storage/platform_storage_io.dart'
    if (dart.library.html) '../storage/platform_storage_web.dart';

/// 课堂模式（演示模式）控制器：面向教师在大屏/白板（鸿合等）讲课场景。
///
/// 开启后全局生效（MaterialApp.builder 注入）：
/// - 字号 ×[textScale]（R13 移植：1.3→1.75，正文 14pt→24.5px，兑现本文件一直写着却没做到的「正文≥24pt」投影门槛）；
///   按钮/芯片随文字等比变大，触控目标随之放大（白板手指触控友好）；
/// - 系谱画布显示激光笔光标（跟随指针的红色光点+渐隐轨迹，引导全班视线）。
///
/// 持久化到 `~/.biology_app/present_mode.json`（enabled / laser / hc 三项；
/// enabled 用于「记住上次模式」，首次启动无文件时为标准模式）；全局单例，
/// 与 ThemeController 同构（ListenableBuilder 监听）。
class PresentModeController extends ChangeNotifier {
  PresentModeController._();

  static final PresentModeController instance = PresentModeController._();

  /// 课堂模式全局字号倍率。调研共识：教室场景字号「比你以为的再大一档」，
  /// 1.3 倍配合既有字号体系，正文约 18pt→23pt、标题更大，后排可读。
  static const double textScale = 1.75; // R13 移植：兑现「正文≥24pt」投影门槛（14pt×1.75=24.5px，原 ×1.3 只有 18.2px）

  /// 课堂模式开关（**持久化**：冷启动恢复上次选择，首次为 false）。
  bool _enabled = false;

  /// 画布激光笔开关。用户裁定（2026-08-31）：大屏白板场景老师用教鞭
  /// 物理指挥，激光笔没实际用途——**默认关**、不常驻，需要时在设置里开。
  /// 仅在 [enabled] = true 时生效。
  bool _laserEnabled = false;

  /// 高对比配色开关（v2.3.4）：课堂模式下可单独开启。投影仪泛白
  /// 吃对比度——开启后浅色 token 切到高对比变体（近黑文字/纯白底/
  /// 深色边框/深 teal）。会话外的持久化随本 json。
  bool _highContrast = false;

  /// 聚光灯开关（v2.3）：会话级工具，不持久化——讲课中从画布缩放条
  /// 随时开关；下次启动默认关（不打扰日常学习）。
  bool _spotlightOn = false;
  bool _loaded = false;

  bool get enabled => _enabled;
  bool get laserEnabled => _laserEnabled;

  /// 高对比配色（仅课堂模式的浅色主题下生效）。
  bool get highContrast => _highContrast;
  bool get spotlightOn => _spotlightOn;

  // ─── 持久化（v2.12 R1 C P0 #7 修复：走 platform_storage 中性 API）────

  /// 测试注入：非空时 load / save 走该文件而非用户目录
  /// （同 FirstRunStore / AppState / ThemeController）。
  @visibleForTesting
  static String? debugFilePath;

  /// 测试注入：mock Web 端 localStorage。flutter_test 无 window 对象
  /// （`package:web` 的 `localStorage` 不可用），此 hook 让
  /// `test/present_mode_controller_test.dart` 能验证 web 端 round-trip
  /// 链路（setEnabled 写 localStorage → load 读回 → enabled 一致）。
  @visibleForTesting
  static Map<String, String>? debugWebStorage;

  /// 测试注入：mock `isWebStorage` 标志。非空时强制走 web / desktop 路径。
  /// 配合 `debugWebStorage` 模拟"用户在浏览器中"的完整链路。
  @visibleForTesting
  static bool? debugForceIsWebStorage;

  /// localStorage key。Web 端 load / save 走 storageGet / storageSet。
  static const String _key = 'present_mode_json';

  /// 当前是否走 web 存储路径（test hook 优先于真实 isWebStorage）。
  bool get _isWebStorage => debugForceIsWebStorage ?? isWebStorage;

  /// 是否运行在 `flutter test` 进程内（`flutter test` 会向被测进程注入
  /// `FLUTTER_TEST=true`；判据同 `local_secure_store` / `history_store`）。
  ///
  /// ⚠️ 只允许在 `!_isWebStorage` 分支里求值：Web 端不得访问
  /// `Platform.environment`（浏览器里没有 dart:io 运行时）。
  static bool get _isFlutterTest =>
      !kIsWeb && Platform.environment['FLUTTER_TEST'] == 'true';

  /// 纯判定：本次 load / save 是否应**跳过真实用户配置**
  ///（`~/.biology_app/present_mode.json`）。顺序即优先级：
  ///
  /// 1. Web（localStorage 路径）→ 不跳过：浏览器里本来就没有磁盘配置；
  /// 2. 显式注入 [debugFilePath]（测试隔离的临时文件）→ 不跳过：
  ///    临时文件 round-trip 必须照常工作；
  /// 3. `flutter test` 进程 + 默认路径 → **跳过**：否则泵 `BiologyApp` 的
  ///    widget 测试会读到真机配置（真实 `hc=true` ⇒ 高对比配色；v2.20.1 起
  ///    enabled 已不落盘 / 不恢复，但 laser/hc 偏好照旧），把大量 UI / 色彩
  ///    断言变成随真机使用漂移的非确定性；`ClassroomQuickBar` / 设置页的
  ///    真实 setter 还会把测试值写回真实配置。
  ///
  /// 拆成纯函数只为可测；真实判据 `_skipRealUserConfig` 在其前加一层
  /// 「Web 短路」，保证 Web 端不求值 `Platform.environment`。
  @visibleForTesting
  static bool shouldSkipRealUserConfig({
    required bool isWebStorage,
    required bool hasDebugFilePath,
    required bool isFlutterTest,
  }) {
    if (isWebStorage) return false; // Web：走 localStorage，无磁盘配置可跳过
    if (hasDebugFilePath) return false; // 显式隔离路径：照常读写
    return isFlutterTest;
  }

  /// 真实判据：先 Web 短路（不访问 `Platform.environment`），再走纯判定。
  bool get _skipRealUserConfig {
    if (_isWebStorage) return false;
    return shouldSkipRealUserConfig(
      isWebStorage: false,
      hasDebugFilePath: debugFilePath != null,
      isFlutterTest: _isFlutterTest,
    );
  }

  /// 加载磁盘 / localStorage 数据。重复调用幂等。
  ///
  /// v2.12 R1 C P0 #7 修复：原 `Platform.environment['USERPROFILE']`
  /// 直接拼路径在 Web 端写盘抛 UnimplementedError 被 catch 吞，导致
  /// 课堂模式写不进去 → 刷新回到默认关。改用 platform_storage 中性
  /// API + `_isWebStorage` 分支：Web 端走 localStorage（不调 File），
  /// 桌面 / 安卓走 `~/.biology_app/present_mode.json`。
  ///
  /// 2026-10-30 修订：**enabled 参与恢复**（记住上次退出时的模式）。
  /// 文件不存在 / 字段缺失时保持标准模式——「首次启动 = 标准」的落点
  /// 就在默认值 `_enabled = false` 与下面这条 `== true` 判据。
  ///
  /// 早返语义：isWebStorage=true 时 storageGet 返 null = localStorage
  /// 空 = 默认关，**不**回退到 File 路径（避免在浏览器里尝试读硬盘）。
  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    // 默认值：走任何早返分支（无文件 / localStorage 空 / FLUTTER_TEST
    // 闸门）时课堂模式保持关闭 = 首次启动即标准小字号。
    _enabled = false;
    // v2.13 R3 W1（P0）：Android 先等 getFilesDir() 缓存就绪，避免
    // _file() fallback 到 '/'（EACCES 静默丢数据）。桌面/Web no-op。
    await ensureAppDirReady();
    try {
      String? raw;
      if (_isWebStorage) {
        raw = _storageGet(_key);
        if (raw == null) return; // 首次启动：保持默认关
      } else {
        // FLUTTER_TEST + 默认真实路径：不读真实用户配置，保持标准默认
        //（enabled / laser / hc 全 false）。显式 debugFilePath / Web mock
        // 不走此跳过（见 _skipRealUserConfig）。
        if (_skipRealUserConfig) return;
        final f = File(_file());
        if (!f.existsSync()) return; // 首次启动：保持默认关
        raw = f.readAsStringSync();
      }
      if (raw.isEmpty) return;
      final j = jsonDecode(raw);
      if (j is! Map) return;
      // 模式记忆（2026-10-30）：按上次退出时的模式恢复；字段缺失或为
      //    非 true 一律当标准模式——首次启动没有任何文件，走不到这里。
      //    存量配置无 laser 字段时默认关（2026-08-31 裁定：教鞭场景
      //    激光笔没用途，不常驻）；无 hc 字段时默认关。
      _enabled = j['enabled'] == true;
      _laserEnabled = j['laser'] == true;
      _highContrast = j['hc'] == true;
    } catch (_) {
      // 损坏文件 / Web 端 Storage 异常不抛错；保持默认关
    }
    notifyListeners();
  }

  /// 开关课堂模式。
  ///
  /// **持久化**（2026-10-30）：用户主动切换即落盘，下次冷启动恢复同一模式；
  /// 首次启动没有文件，因此第一屏永远是标准模式。签名保留 `Future<void>`
  /// 让既有 `await`/`unawaited` 调用点零改动。
  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    notifyListeners();
    await _save();
  }

  Future<void> setLaserEnabled(bool enabled) async {
    _laserEnabled = enabled;
    notifyListeners();
    await _save();
  }

  /// 高对比配色开关（持久化）。
  Future<void> setHighContrast(bool on) async {
    _highContrast = on;
    notifyListeners();
    await _save();
  }

  /// 聚光灯开关（会话级，不落盘）。
  void setSpotlightOn(bool on) {
    _spotlightOn = on;
    notifyListeners();
  }

  Future<void> _save() async {
    // FLUTTER_TEST + 默认真实路径：不写真实用户配置——ClassroomQuickBar /
    // 设置页的真实 setter（激光笔 / 高对比）在测试里只改内存。Web 路径不跳过。
    if (_skipRealUserConfig) return;
    // 2026-10-30：enabled 一并落盘（记住上次退出时的模式）；laser / hc
    // 仍是偏好项，三者同一个 JSON。
    final s = jsonEncode({
      'enabled': _enabled,
      'laser': _laserEnabled,
      'hc': _highContrast,
    });
    try {
      if (_isWebStorage) {
        await _storageSet(_key, s);
        return;
      }
      final f = File(_file());
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(s);
    } catch (e) {
      // 写盘失败仅影响持久化，不影响本次切换；v2.13 R3 W1 P0：
      // debugPrint 暴露失败原因——之前 catch(_) 静默吞 → Android
      // 目录异常时课堂模式每次启动回到默认关，用户零提示。
      debugPrint('[biology] PresentModeController save failed: $e');
    }
  }

  /// 测试专用：只切换不写盘（避免污染本机配置文件）。
  @visibleForTesting
  void debugSetEnabled(bool enabled) {
    _enabled = enabled;
    notifyListeners();
  }

  /// 测试专用：激光笔开关（不写盘）。
  @visibleForTesting
  void debugSetLaserEnabled(bool enabled) {
    _laserEnabled = enabled;
    notifyListeners();
  }

  /// 测试专用：高对比开关（不写盘）。
  @visibleForTesting
  void debugSetHighContrast(bool on) {
    _highContrast = on;
    notifyListeners();
  }

  /// 测试专用：聚光灯开关（不写盘）。
  @visibleForTesting
  void debugSetSpotlightOn(bool on) {
    _spotlightOn = on;
    notifyListeners();
  }

  /// 测试专用：重置内存 + loaded 标记。**不**触碰磁盘 / localStorage。
  @visibleForTesting
  void debugReset() {
    _enabled = false;
    _laserEnabled = false;
    _highContrast = false;
    _spotlightOn = false;
    _loaded = false;
  }

  /// 测试专用：同步等待持久化加载完成（_loaded 守卫生效后 initState 的
  /// load() 直接 return，不会把 debugSetEnabled 的覆盖回磁盘值）。
  /// 与 ThemeController.debugEnsureLoaded 同因（真实文件 I/O 竞态）。
  @visibleForTesting
  Future<void> debugEnsureLoaded() => load();

  // ─── 内部辅助 ───

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

  /// 桌面 / 安卓路径：`<userAppDir>/present_mode.json`。
  /// 注入的 debugFilePath 优先（同 FirstRunStore / AppState / ThemeController）。
  /// Web 端走 storageGet / storageSet，不会调到此处。
  static String _file() {
    if (debugFilePath != null) return debugFilePath!;
    final appDir = userAppDir();
    if (appDir == null) return 'present_mode.json'; // Web 兜底占位（实际不会走）
    final dir = Directory(appDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return '${dir.path}/present_mode.json';
  }
}
