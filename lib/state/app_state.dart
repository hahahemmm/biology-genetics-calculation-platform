// app_state.dart —— 全局应用状态（AI 助手的「眼睛」）
//
// 各页面在输入变化、计算完成时把当前上下文快照写入这里。
// AI 助手侧栏打开时读取快照注入 system prompt，
// 让 AI 原生「看到」用户当前在哪个页面、选了什么模块、算了什么结果。
//
// v2.12.0+2 hotfix：加「思维链默认展开」用户偏好（thinkingChainExpandedDefault）。
//   - 默认 true：v2.12 老师 + 学生 persona UX 走查共识——
//     学生需要看到解题过程（学习效果），老师需要看到 AI 推理路径（信任度）。
//   - 用户可在 AI 助手面板的「思维过程」标题右侧勾「下次不展开」关掉。
//   - 持久化：与 FirstRunStore / MistakeBook / HistoryStore 同构——
//     桌面 / 安卓：`<userAppDir>/app_state.json`（File 写盘）
//     Web：localStorage（key = `app_state_json`），避免 dart:io 在 Web
//     端抛 UnimplementedError。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../storage/platform_storage_io.dart'
    if (dart.library.html) '../storage/platform_storage_web.dart';

class AppState extends ChangeNotifier {
  AppState._();
  static final AppState instance = AppState._();

  /// 当前页面名（如「遗传图谱计算」「双基因 9331」）。
  String currentPage = '首页';

  /// 当前选中的子模块（如「单基因杂交」Tab、交配方式）。
  String currentModule = '';

  /// 页面写入的上下文键值对，按插入顺序展示。
  final Map<String, String> contextFields = {};

  /// 思维链（AI 推理过程）默认是否展开。v2.12.0+2 hotfix：默认 true。
  /// 老师 + 学生 persona UX 共识：默认展开才能看到 AI 解题过程。
  bool thinkingChainExpandedDefault = true;

  void setPage(String page, {String module = ''}) {
    currentPage = page;
    currentModule = module;
    contextFields.clear();
    notifyListeners();
  }

  void setModule(String module) {
    currentModule = module;
    notifyListeners();
  }

  /// 页面写入一条上下文（同 key 覆盖）。
  void report(String key, String value) {
    contextFields[key] = value;
    notifyListeners();
  }

  void clearContext() {
    contextFields.clear();
    notifyListeners();
  }

  /// 是否有可用上下文（决定助手面板顶部 chip 显示什么）。
  bool get hasContext => contextFields.isNotEmpty;

  /// 组装成注入 system prompt 的文本快照。
  String buildSnapshot() {
    final sb = StringBuffer()
      ..writeln('【软件当前状态】')
      ..writeln('当前页面：$currentPage');
    if (currentModule.isNotEmpty) sb.writeln('当前模块：$currentModule');
    contextFields.forEach((k, v) => sb.writeln('$k：$v'));
    return sb.toString();
  }

  // ─── 偏好持久化（v2.12.0+2 hotfix：思维链默认展开）────────────

  /// 测试注入：非空时 load / save 走该文件而非用户目录（同 FirstRunStore
  /// / MistakeBook / HistoryStore）。
  @visibleForTesting
  static String? debugFilePath;

  /// 测试注入：mock Web 端 localStorage（flutter_test 无 window 对象）。
  @visibleForTesting
  static Map<String, String>? debugWebStorage;

  /// 测试注入：mock `isWebStorage` 标志。
  @visibleForTesting
  static bool? debugForceIsWebStorage;

  /// localStorage key。Web 端 load / save 走 storageGet / storageSet。
  static const String _key = 'app_state_json';

  bool _prefsLoaded = false;

  /// 当前是否走 web 存储路径（test hook 优先于真实 isWebStorage）。
  bool get _isWebStorage => debugForceIsWebStorage ?? isWebStorage;

  /// 启动时调用一次（幂等），从磁盘 / localStorage 读偏好。
  ///
  /// 失败 / 文件不存在 / 字段缺失 → 保持默认值（思维链默认展开 = true）。
  Future<void> load() async {
    if (_prefsLoaded) return;
    _prefsLoaded = true;
    // v2.13 R3 W1（P0）：Android 先等 getFilesDir() 缓存就绪，避免
    // _file() fallback 到 '/'（EACCES 静默丢数据）。桌面/Web no-op。
    await ensureAppDirReady();
    try {
      String? raw;
      if (_isWebStorage) {
        raw = _storageGet(_key);
      } else {
        final f = File(_file());
        if (!f.existsSync()) return; // 首次启动：保持默认值
        raw = f.readAsStringSync();
      }
      if (raw == null || raw.isEmpty) return;
      final j = jsonDecode(raw);
      if (j is! Map) return;
      final v = j['thinkingChainExpandedDefault'];
      if (v is bool) {
        thinkingChainExpandedDefault = v;
        // 启动期不 notifyListeners——监听者通常还没挂上
      }
    } catch (_) {
      // 损坏文件 / Web 端 Storage 异常不抛错；保持默认（true）
    }
  }

  /// 设置「思维链默认展开」偏好。
  /// 同步更新内存 + 异步写盘（fire-and-forget，不阻塞 UI）。
  /// notifyListeners 触发监听者（如 assistant_panel _ReasoningBlock）
  /// 在重建时读取新值。
  Future<void> setThinkingChainExpandedDefault(bool value) async {
    if (thinkingChainExpandedDefault == value) return;
    thinkingChainExpandedDefault = value;
    notifyListeners();
    await _persist();
  }

  /// 把当前 thinkingChainExpandedDefault 写到磁盘 / localStorage。
  /// 失败不抛错（仅影响持久化，下启动会回到默认）。
  Future<void> _persist() async {
    final s = jsonEncode({'thinkingChainExpandedDefault': thinkingChainExpandedDefault});
    try {
      if (_isWebStorage) {
        await _storageSet(_key, s);
        return;
      }
      final f = File(_file());
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(s);
    } catch (e) {
      // 写盘失败不抛错（仅影响持久化）；v2.13 R3 W1 P0：debugPrint
      // 暴露失败原因——之前 catch(_) 静默吞 → Android 目录异常时
      // 用户零提示以为存了，重启全空。
      debugPrint('[biology] AppState save failed: $e');
    }
  }

  /// 测试用：重置内存 + loaded 标记。**不**触碰磁盘。
  @visibleForTesting
  void debugResetPrefs() {
    thinkingChainExpandedDefault = true;
    _prefsLoaded = false;
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

  /// 桌面 / 安卓路径：`<userAppDir>/app_state.json`。
  /// 注入的 debugFilePath 优先（同 MistakeBook / HistoryStore）。
  /// Web 端走 storageGet / storageSet，不会调到此处。
  static String _file() {
    if (debugFilePath != null) return debugFilePath!;
    final appDir = userAppDir();
    if (appDir == null) return 'app_state.json'; // Web 兜底占位（实际不会走）
    final dir = Directory(appDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return '${dir.path}/app_state.json';
  }
}
