// ai_tool_settings.dart —— AI 工具开关设置（v2.24）
//
// AI 工具层（lib/services/ai_tools.dart）能碰本机 Python、命令行和联网。
// 三件事的风险不对等，所以拆成三个独立开关，默认只放行联网：
//   - python=false：本机执行代码（能读盘、能联网），默认关
//   - shell=false ：本机命令行（破坏面最大），默认关
//   - web=true    ：搜网页 / 抓正文（只读，请求经模型服务商转发），默认开
//
// 持久化与 FirstRunStore 同构：
//   桌面 / 安卓：`<userAppDir>/ai_tools.json`
//   Web：localStorage（key = `ai_tools_json`）
// 读失败一律回落默认值，绝不抛——开关文件坏掉不该让 app 起不来。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../storage/platform_storage_io.dart'
    if (dart.library.html) '../storage/platform_storage_web.dart';

/// AI 工具通道开关（不可变值对象）。
class AiToolSettings {
  /// 允许 AI 执行本机 Python。
  final bool python;

  /// 允许 AI 执行本机命令行。
  final bool shell;

  /// 允许 AI 联网搜索 / 抓网页。
  final bool web;

  const AiToolSettings({
    this.python = false,
    this.shell = false,
    this.web = true,
  });

  AiToolSettings copyWith({bool? python, bool? shell, bool? web}) {
    return AiToolSettings(
      python: python ?? this.python,
      shell: shell ?? this.shell,
      web: web ?? this.web,
    );
  }

  Map<String, dynamic> toJson() => {
        'python': python,
        'shell': shell,
        'web': web,
      };

  /// 缺字段 / 类型不对 → 回落默认值（web 默认 true，其余 false）。
  static AiToolSettings fromJson(Map<String, dynamic> j) {
    final p = j['python'];
    final s = j['shell'];
    final w = j['web'];
    return AiToolSettings(
      python: p is bool ? p : false,
      shell: s is bool ? s : false,
      web: w is bool ? w : true,
    );
  }
}

/// 三开关的持久化（纯静态，无内存状态）。
class AiToolSettingsStore {
  /// 测试注入：非空时走该文件而非用户目录（仅桌面 / 安卓 File 路径生效）。
  static String? debugFilePath;

  /// 测试注入：mock Web 端 localStorage（flutter_test 没有 window 对象，
  /// platform_storage_web 的 localStorage 在测试里不可用）。
  @visibleForTesting
  static Map<String, String>? debugWebStorage;

  /// 测试注入：强制 mock `isWebStorage` 标志，配合 [debugWebStorage] 验证
  /// Web 端 round-trip。
  @visibleForTesting
  static bool? debugForceIsWebStorage;

  /// localStorage key（Web 端）。
  static const String _key = 'ai_tools_json';

  /// 当前是否走 Web 存储路径（test hook 优先于真实 isWebStorage）。
  static bool get _isWebStorage => debugForceIsWebStorage ?? isWebStorage;

  /// 是否应**跳过真实用户文件**（`<userAppDir>/ai_tools.json`）。
  ///
  /// 顺序即优先级：Web（localStorage）不跳过；显式 [debugFilePath] 不跳过；
  /// `flutter test` 进程 + 默认路径跳过——否则未隔离的 widget 测试会改写
  /// 真实用户的工具开关。判据与 first_run_store 一致。
  static bool get _skipRealUserFile {
    if (_isWebStorage) return false;
    if (debugFilePath != null) return false;
    // 只在非 Web 分支求值：浏览器里没有 dart:io 运行时。
    return !kIsWeb && Platform.environment['FLUTTER_TEST'] == 'true';
  }

  /// 读取开关。任何异常都返回默认值，绝不抛。
  static Future<AiToolSettings> load() async {
    try {
      // Android 先等 getFilesDir() 缓存就绪（桌面 / Web no-op）。
      await ensureAppDirReady();
      if (_isWebStorage) return _parse(_storageGet(_key));
      if (_skipRealUserFile) return const AiToolSettings();
      final f = File(_file());
      if (!f.existsSync()) return const AiToolSettings();
      return _parse(f.readAsStringSync());
    } catch (_) {
      return const AiToolSettings();
    }
  }

  /// 写入开关。写失败只打日志，绝不抛（开关保存失败不该打断当前对话）。
  static Future<void> save(AiToolSettings s) async {
    final raw = jsonEncode(s.toJson());
    try {
      if (_isWebStorage) {
        await _storageSet(_key, raw);
        return;
      }
      if (_skipRealUserFile) return;
      final f = File(_file());
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(raw);
    } catch (e) {
      debugPrint('[biology] AiToolSettingsStore save failed: $e');
    }
  }

  /// JSON 文本 → 设置对象；null / 非对象 / 坏 JSON 都给默认值。
  static AiToolSettings _parse(String? raw) {
    if (raw == null) return const AiToolSettings();
    final j = jsonDecode(raw);
    if (j is! Map) return const AiToolSettings();
    return AiToolSettings.fromJson(Map<String, dynamic>.from(j));
  }

  /// Web 端读。test 用 [debugWebStorage] 注入，生产用 platform_storage。
  static String? _storageGet(String key) {
    if (debugWebStorage != null) return debugWebStorage![key];
    return storageGet(key);
  }

  /// Web 端写。test 用 [debugWebStorage] 注入，生产用 platform_storage。
  static Future<void> _storageSet(String key, String value) async {
    if (debugWebStorage != null) {
      debugWebStorage![key] = value;
      return;
    }
    await storageSet(key, value);
  }

  /// 桌面 / 安卓路径：`<userAppDir>/ai_tools.json`。
  /// 注入的 [debugFilePath] 优先；Web 端走 localStorage，不会调到此处。
  static String _file() {
    if (debugFilePath != null) return debugFilePath!;
    final appDir = userAppDir();
    if (appDir == null) return 'ai_tools.json'; // Web 兜底占位（实际不会走）
    final dir = Directory(appDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return '${dir.path}${Platform.pathSeparator}ai_tools.json';
  }
}
