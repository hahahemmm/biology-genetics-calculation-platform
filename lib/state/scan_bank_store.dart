// scan_bank_store.dart —— 拍题识别「内置题库」持久化（v2.5 功能 1）
//
// 老师上传题目图片 → AI 识别出总结 + 题型 + 参数 → 自动存进内置题库，
// 之后无需再拍同一张题，一键回填对应模块。
//
// 存储：~/.biology_app/scan_bank.json（桌面/安卓 File）；
// Web 端 localStorage（条件导入，与 AiChatStore 同套路）。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../storage/platform_storage_io.dart'
    if (dart.library.html) '../storage/platform_storage_web.dart';

/// 一条识别入库的题目。
class ScanEntry {
  final String summary; // AI 总结（题干+考点，≤200 字）
  final String module; // 模块标识（ModuleFillBus 的 moduleId，或 other）
  final Map<String, String> params; // 提取的参数（可为空）
  /// v2.9 标准动作序列（可为空；如系谱页创建家族/添加样本）
  final List<Map<String, String>> actions;
  final int ts; // 入库时间（毫秒时间戳）

  const ScanEntry({
    required this.summary,
    required this.module,
    required this.params,
    this.actions = const [],
    required this.ts,
  });

  Map<String, dynamic> toJson() => {
        'summary': summary,
        'module': module,
        'params': params,
        'actions': actions,
        'ts': ts,
      };

  static ScanEntry? fromJson(dynamic j) {
    if (j is! Map) return null;
    final summary = j['summary']?.toString() ?? '';
    if (summary.isEmpty) return null;
    final rawParams = j['params'];
    final params = <String, String>{};
    if (rawParams is Map) {
      for (final e in rawParams.entries) {
        params['${e.key}'] = '${e.value}';
      }
    }
    final rawActions = j['actions'];
    final actions = <Map<String, String>>[];
    if (rawActions is List) {
      for (final a in rawActions) {
        if (a is! Map) continue;
        final m = <String, String>{};
        for (final e in a.entries) {
          m['${e.key}'] = '${e.value}';
        }
        if (m['type'] != null) actions.add(m);
      }
    }
    return ScanEntry(
      summary: summary,
      module: j['module']?.toString() ?? 'other',
      params: params,
      actions: actions,
      ts: j['ts'] is int ? j['ts'] as int : 0,
    );
  }
}

/// 内置题库存储（最多保留 [maxEntries] 条，新的在前）。
class ScanBankStore {
  /// 测试注入：非空时读写该路径而非用户目录。
  static String? debugFilePath;

  static const int maxEntries = 100;

  /// v2.11 M8：改用 platform_storage 中性 API 替代直接 dart:io 调用。
  /// 桌面/安卓返 `~/.biology_app`，Web 端返 null（走 localStorage 路径）。
  static String? _appDir() => userAppDir();

  static String _dir() {
    final appDir = _appDir();
    if (appDir == null) {
      // Web 端 cold path 兜底：localStorage 已经有值时不会走到这里
      // （load 早返），但万一走到这里返当前目录作为占位。
      return '.';
    }
    final dir = Directory(appDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return dir.path;
  }

  static File _file() {
    if (debugFilePath != null) return File(debugFilePath!);
    final dir = _dir();
    return File('$dir/scan_bank.json');
  }

  /// 读取题库；文件不存在或损坏时返回空列表。
  static Future<List<ScanEntry>> load() async {
    // v2.13 R3 W1（P0）：Android 先等 getFilesDir() 缓存就绪，避免
    // _file() fallback 到 '/'（EACCES 静默丢数据）。桌面/Web no-op。
    await ensureAppDirReady();
    try {
      final webRaw = storageGet('scan_bank_json');
      if (webRaw != null) {
        final j = jsonDecode(webRaw);
        if (j is! List) return const [];
        return [for (final e in j) if (ScanEntry.fromJson(e) != null) ScanEntry.fromJson(e)!];
      }
      // 同 history_store：Web 上 storageGet 为 null 是「localStorage 空」，
      // 不是「该读文件」。不守卫会落到 File/Directory 构造，dart2js 抛错后
      // 被 catch 吞成空表。
      if (kIsWeb) return const [];
      final f = _file();
      if (!f.existsSync()) return const [];
      final j = jsonDecode(f.readAsStringSync());
      if (j is! List) return const [];
      return [
        for (final e in j)
          if (ScanEntry.fromJson(e) != null) ScanEntry.fromJson(e)!,
      ];
    } catch (_) {
      return const [];
    }
  }

  /// 全量保存（超出 [maxEntries] 只留最新的部分）。
  static Future<void> save(List<ScanEntry> entries) async {
    final trimmed = entries.length > maxEntries
        ? entries.sublist(0, maxEntries)
        : entries;
    final json = jsonEncode([for (final e in trimmed) e.toJson()]);
    try {
      if (isWebStorage) {
        await storageSet('scan_bank_json', json);
        return;
      }
      _file().writeAsStringSync(json);
    } catch (e) {
      // 写盘失败不影响识别主流程；v2.13 R3 W1 P0：debugPrint 暴露
      // 失败原因——之前 catch(_) 静默吞 → Android 目录异常时题库
      // 全丢，用户零提示。
      debugPrint('[biology] ScanBankStore save failed: $e');
    }
  }

  /// 头部插入一条并保存。
  static Future<void> add(ScanEntry entry) async {
    final all = List<ScanEntry>.of(await load());
    all.insert(0, entry);
    await save(all);
  }

  /// 删除指定下标并保存。
  static Future<void> removeAt(int index) async {
    final all = List<ScanEntry>.of(await load());
    if (index < 0 || index >= all.length) return;
    all.removeAt(index);
    await save(all);
  }

  /// 清空题库。
  static Future<void> clear() => save(const []);
}
