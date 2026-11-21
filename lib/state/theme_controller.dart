// theme_controller.dart —— 主题模式控制器（浅色 / 深色 / 跟随系统）。
//
// 持久化：与 FirstRunStore / AppState / HistoryStore 同构——
//   桌面 / 安卓：`~/.biology_app/theme_mode.json`（File 写盘）。
//   Web：localStorage（key = `theme_mode_json`），避免 dart:io 在 Web
//   端抛 UnimplementedError（v2.12 R1 C P0 #7 修复：原
//   `Platform.environment['USERPROFILE']` 直接拼路径在 Web 端 build
//   成功但运行时 writeAsString 抛 UnimplementedError，catch 吞掉 →
//   主题写不进去 → 刷新回到默认 system）。本次改用 platform_storage
//   中性 API（userAppDir() / storageGet / storageSet + isWebStorage
//   分支）让 Web 端走 localStorage，桌面 / 安卓继续走 File。
//
// 全局单例，MaterialApp 通过 ListenableBuilder 监听并切换 themeMode。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../storage/platform_storage_io.dart'
    if (dart.library.html) '../storage/platform_storage_web.dart';

/// 主题模式控制器：浅色 / 深色 / 跟随系统。
///
/// 持久化到 `~/.biology_app/theme_mode.json`；全局单例，
/// MaterialApp 通过 ListenableBuilder 监听并切换 themeMode。
class ThemeController extends ChangeNotifier {
  ThemeController._();

  static final ThemeController instance = ThemeController._();

  ThemeMode _mode = ThemeMode.system;
  bool _loaded = false;
  // v2.13 R8-W3：护眼档独立于 ThemeMode 3 档的 bool 覆盖层。
  // MaterialApp.builder 读 _eyeCare 用 ColorFiltered 套暖色矩阵。
  // 持久化：与 mode 独立 key（避免污染 mode 持久化数据）。
  bool _eyeCare = false;
  bool _eyeCareLoaded = false;

  ThemeMode get mode => _mode;
  bool get eyeCare => _eyeCare;

  /// v2.2 主题重写：**有效亮度**（effective brightness）的单一事实源。
  /// - 用户锁浅色 → light；锁深色 → dark；跟随系统 → 实时读平台亮度。
  /// 颜色 token（AppColors）从此值实时派生，**不再依赖任何
  /// notify/rebuild 时序**——彻底消灭「_dark 静态残留 → 白底白字」
  /// 这类 bug 的生存土壤。
  Brightness get effectiveBrightness {
    switch (_mode) {
      case ThemeMode.light:
        return Brightness.light;
      case ThemeMode.dark:
        return Brightness.dark;
      case ThemeMode.system:
        // 纯 Dart 单测环境 WidgetsBinding 可能未初始化，兜底浅色
        try {
          return WidgetsBinding.instance.platformDispatcher.platformBrightness;
        } catch (_) {
          return Brightness.light;
        }
    }
  }

  // ─── 持久化（v2.12 R1 C P0 #7 修复：走 platform_storage 中性 API）────

  /// 测试注入：非空时 load / save 走该文件而非用户目录（同 FirstRunStore
  /// / AppState / HistoryStore）。
  @visibleForTesting
  static String? debugFilePath;

  /// 测试注入：mock Web 端 localStorage。flutter_test 无 window 对象
  /// （`package:web` 的 `localStorage` 不可用），此 hook 让
  /// `test/theme_controller_test.dart` 能验证 web 端 round-trip
  /// 链路（setMode 写 localStorage → load 读回 → mode 一致）。
  @visibleForTesting
  static Map<String, String>? debugWebStorage;

  /// 测试注入：mock `isWebStorage` 标志。非空时强制走 web / desktop 路径。
  /// 配合 `debugWebStorage` 模拟"用户在浏览器中"的完整链路。
  @visibleForTesting
  static bool? debugForceIsWebStorage;

  /// localStorage key。Web 端 load / save 走 storageGet / storageSet。
  static const String _key = 'theme_mode_json';

  /// v2.13 R8-W3：护眼档独立 key（与 mode 分离）。R8 阶段只做后端
  /// 状态+持久化，MaterialApp.builder 套暖色矩阵待 R9 集成。
  static const String _eyeCareKey = 'eye_care_json';

  /// 当前是否走 web 存储路径（test hook 优先于真实 isWebStorage）。
  bool get _isWebStorage => debugForceIsWebStorage ?? isWebStorage;

  /// 加载磁盘 / localStorage 数据。重复调用幂等。
  ///
  /// v2.12 R1 C P0 #7 修复：原 `Platform.environment['USERPROFILE']`
  /// 直接拼路径在 Web 端写盘抛 UnimplementedError 被 catch 吞，导致
  /// 主题写不进去 → 刷新回到默认 system。改用 platform_storage 中性
  /// API + `_isWebStorage` 分支：Web 端走 localStorage（不调 File），
  /// 桌面 / 安卓走 `~/.biology_app/theme_mode.json`。
  Future<void> load() async {
    if (_loaded && _eyeCareLoaded) return;
    // v2.13 R3 W1（P0）：Android 先等 getFilesDir() 缓存就绪，避免
    // _file() fallback 到 '/'（EACCES 静默丢数据）。桌面/Web no-op。
    await ensureAppDirReady();
    // 加载 mode（与原逻辑一致）
    if (!_loaded) {
      _loaded = true;
      try {
        String? raw;
        if (_isWebStorage) {
          raw = _storageGet(_key);
          if (raw != null && raw.isNotEmpty) {
            final j = jsonDecode(raw);
            if (j is Map) {
              _mode = switch (j['mode']) {
                'light' => ThemeMode.light,
                'dark' => ThemeMode.dark,
                _ => ThemeMode.system,
              };
            }
          }
        } else {
          final f = File(_file());
          if (f.existsSync()) {
            final raw = f.readAsStringSync();
            if (raw.isNotEmpty) {
              final j = jsonDecode(raw);
              if (j is Map) {
                _mode = switch (j['mode']) {
                  'light' => ThemeMode.light,
                  'dark' => ThemeMode.dark,
                  _ => ThemeMode.system,
                };
              }
            }
          }
        }
      } catch (_) {
        // 损坏文件 / Web 端 Storage 异常不抛错；保持默认 system
      }
    }
    // v2.13 R8-W3：加载 eyeCare 独立 key。损坏 / 缺文件 = 默认 false。
    if (!_eyeCareLoaded) {
      _eyeCareLoaded = true;
      try {
        String? raw;
        if (_isWebStorage) {
          raw = _storageGet(_eyeCareKey);
        } else {
          final f = File(_eyeCareFile());
          if (f.existsSync()) raw = f.readAsStringSync();
        }
        if (raw != null && raw.isNotEmpty) {
          final j = jsonDecode(raw);
          if (j is Map && j['eyeCare'] == true) _eyeCare = true;
        }
      } catch (_) {
        // 损坏文件 / Web 端 Storage 异常不抛错；保持默认 false
      }
    }
    notifyListeners();
  }

  Future<void> setMode(ThemeMode mode) async {
    _mode = mode;
    notifyListeners();
    final s = jsonEncode({'mode': mode.name});
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
      // 目录异常时主题选择每次启动回到默认，用户零提示。
      debugPrint('[biology] ThemeController save failed: $e');
    }
  }

  /// v2.13 R8-W3：护眼档切换（与 setMode 独立，叠加在 3 档主题之上）。
  /// R8 阶段只做状态+持久化，MaterialApp.builder 套暖色矩阵待 R9
  /// 集成。返回最终 eyeCare 状态。
  Future<bool> setEyeCare(bool value) async {
    if (_eyeCare == value && _eyeCareLoaded) {
      // 幂等：状态已匹配且已加载，no-op 避免无谓写盘
      return _eyeCare;
    }
    _eyeCare = value;
    _eyeCareLoaded = true;
    notifyListeners();
    final s = jsonEncode({'eyeCare': value});
    try {
      if (_isWebStorage) {
        await _storageSet(_eyeCareKey, s);
        return _eyeCare;
      }
      final f = File(_eyeCareFile());
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(s);
    } catch (e) {
      debugPrint('[biology] ThemeController eyeCare save failed: $e');
    }
    return _eyeCare;
  }

  /// 测试专用：只切模式不写盘（避免污染本机配置文件）。
  @visibleForTesting
  void debugSetMode(ThemeMode mode) {
    _mode = mode;
    notifyListeners();
  }

  /// 测试专用：重置内存 + loaded 标记。**不**触碰磁盘 / localStorage。
  /// v2.13 R8-W3：同步重置 _eyeCare / _eyeCareLoaded。
  @visibleForTesting
  void debugReset() {
    _mode = ThemeMode.system;
    _loaded = false;
    _eyeCare = false;
    _eyeCareLoaded = false;
  }

  /// 测试专用：同步等待持久化加载完成（_loaded 守卫生效）。
  /// 竞态实锤（2.2 批次5 深色巡检）：load() 是真实文件 I/O，
  /// 测试里若不先让它落地，其完成后的 notify 会在数帧之后
  /// 把 debugSetMode 设的模式覆盖回磁盘值（如磁盘存 light，
  /// 巡检中途从深色翻回浅色）。测试流程：先 await 本方法，
  /// 再 debugSetMode，最后 pumpWidget——initState 的 load()
  /// 因 _loaded=true 直接 return，不再覆盖。
  @visibleForTesting
  Future<void> debugEnsureLoaded() => load();

  /// v2.1k：系统亮度变化通知。
  /// 顶层 ListenableBuilder 只监听 ThemeController.mode 变化，**不**
  /// 响应系统亮度切换——当 Windows 从白天切到晚上，MediaQuery 通知
  /// platformBrightness 变，但 ListenableBuilder 不 rebuild，AppColors.sync
  /// 不会被调 → _dark 残留 → 课标页 description "白字白底"不可见。
  /// 此方法供 _BiologyAppState.didChangePlatformBrightness 调，强制
  /// ListenableBuilder rebuild，让 AppColors.sync 用最新 platformBrightness
  /// 重新求值。
  ///
  /// v2.2 批次5 修正：手动 light/dark 模式也必须响应系统亮度变化。
  /// 否则会命中"用户已锁定浅色，但 Windows 系统从 dark 切到 light 时
  /// _dark 残留 dark → ink 仍返 inkD 米白 → 写在 surfaceL 白底上 = 白底白字"
  /// （像素取证：用户截图里 1842 个 #9C988D 浅像素 + 0 个 #6E695C 钢蓝 +
  /// 0 个 #5D594F 石墨，证实 _dark 残留）。解决：取消 system-only 限制，
  /// 任何模式下都 notify，让 ListenableBuilder rebuild 重新同步 _dark。
  void onPlatformBrightnessChanged() {
    notifyListeners();
  }

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

  /// 桌面 / 安卓路径：`<userAppDir>/theme_mode.json`。
  /// 注入的 debugFilePath 优先（同 FirstRunStore / AppState / HistoryStore）。
  /// Web 端走 storageGet / storageSet，不会调到此处。
  static String _file() {
    if (debugFilePath != null) return debugFilePath!;
    final appDir = userAppDir();
    if (appDir == null) return 'theme_mode.json'; // Web 兜底占位（实际不会走）
    final dir = Directory(appDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return '${dir.path}/theme_mode.json';
  }

  /// v2.13 R8-W3：护眼档独立文件路径。test 走 debugFilePath + 后缀
  /// `.eye_care`，避免污染 mode 测试数据。
  static String _eyeCareFile() {
    if (debugFilePath != null) return '${debugFilePath!}.eye_care';
    final appDir = userAppDir();
    if (appDir == null) return 'eye_care.json'; // Web 兜底占位（实际不会走）
    final dir = Directory(appDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return '${dir.path}/eye_care.json';
  }
}
