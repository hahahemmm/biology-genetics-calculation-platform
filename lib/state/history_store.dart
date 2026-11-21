// history_store.dart —— 计算历史存储（v2.1）
//
// 自动记录每次计算的基因型/家族/产出；「保存并开新对话」归档当前
// 白板。桌面/安卓 File 持久化；Web 走 localStorage（settings_storage 条件
// 导入）。隔离语义：历史只读回看，与新白板互不干扰。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../storage/platform_storage_io.dart'
    if (dart.library.html) '../storage/platform_storage_web.dart';

/// 一条历史记录：一次计算或一次「保存并开新」的完整快照。
class HistoryEntry {
  final String label; // 摘要（如 '♂AABBCC × ♀aabbcc · 家族 A · 产出至 F2'）
  final int epochMs; // 归档时间
  final String detail; // 详情（每代产出逐行）
  const HistoryEntry({
    required this.label,
    required this.epochMs,
    required this.detail,
  });

  Map<String, dynamic> toJson() =>
      {'label': label, 'epochMs': epochMs, 'detail': detail};

  static HistoryEntry fromJson(Map<String, dynamic> j) => HistoryEntry(
        label: j['label']?.toString() ?? '',
        epochMs: (j['epochMs'] as num?)?.toInt() ?? 0,
        detail: j['detail']?.toString() ?? '',
      );
}

/// 历史条目存储（上限 200 条，超出丢弃最旧）。
class HistoryStore {
  static const int maxEntries = 200;

  static const _key = 'history_json';

  /// v2.13+：每次 save() 递增——订阅方（dashboard 讲题回放卡）据此
  /// 自动刷新，不用轮询文件。
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// v2.13+ R5：append 串行链——两次 append 交错时「都 load 到旧表再
  /// 各自 add+save」会让先写的那条被后写覆盖（讲题回放卡少一条）。
  /// 用 Future 链把 读-改-写 串行化；单条失败不拖垮后续（fire-and-forget
  /// 语义不变）。
  static Future<void>? _appendChain;

  /// 同 label 去重窗口：10 分钟内同摘要（同题重算/连点）不重复落盘——
  /// 内存历史本就「同组合去重置顶」，但磁盘之前每次都追加，回放卡同
  /// 一道题列 N 行。
  static const int _dedupWindowMs = 10 * 60 * 1000;

  /// 追加一条历史（读-改-写，超上限丢最旧）。供计算器各 tab 在
  /// 计算成功后调用——此前只有系谱页写历史，讲题回放卡对计算器
  /// 是空头支票（老师走查 P0）。
  static Future<void> append(HistoryEntry e) async {
    // ⚠️ FLUTTER_TEST 守卫：`flutter test` 环境下静默跳过——否则全量
    // 回归时几百个用例的计算会污染用户真实 ~/.biology_app/history.json
    // （讲题回放卡冒出假记录）。测追加行为用 debugFilePath 隔离 + 显式
    // 调 save()（系谱页测试的既有模式）。
    // R5 修订：注入 debugFilePath（隔离临时文件）时放行——append 内部
    // 的串行链/去重窗口逻辑也要可测。
    if (!kIsWeb && Platform.environment['FLUTTER_TEST'] == 'true' &&
        debugFilePath == null) {
      return;
    }
    final prev = _appendChain ?? Future<void>.value();
    final completer = Completer<void>();
    _appendChain = completer.future;
    await prev;
    try {
      // 防御性拷贝：load() 在文件不存在时返回 const []（不可 grow），
      // 直接 add 会抛 UnsupportedError 被吞——首张历史永远写不进去。
      final list = [...await load()];
      if (list.isNotEmpty) {
        final last = list.last;
        if (last.label == e.label &&
            e.epochMs - last.epochMs < _dedupWindowMs) {
          return; // 同题短窗内重复计算 = 去重置顶语义，磁盘不追加
        }
      }
      list.add(e);
      await save(list);
    } catch (_) {/* fire-and-forget：失败不阻塞调用方 */}
    finally {
      completer.complete();
    }
  }

  /// 测试注入：非空时读写该文件而非用户目录（隔离真实历史）。
  static String? debugFilePath;

  static String _file() {
    if (debugFilePath != null) return debugFilePath!;
    // v2.11 M8：改用 platform_storage.userAppDir() 中性 API。
    // 桌面/安卓返 ~/.biology_app，Web 端 stub 返 null。
    // 冷路径 web 端通过 localStorage 早返通常不调到此处。
    final appDir = userAppDir();
    if (appDir == null) return 'history.json'; // Web 兜底占位
    final dir = Directory(appDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return '${dir.path}/history.json';
  }

  static Future<List<HistoryEntry>> load() async {
    // v2.13 R3 W1（P0）：Android 先等 getFilesDir() 缓存就绪，避免
    // _file() fallback 到 '/'（EACCES 静默丢数据）。桌面/Web no-op。
    await ensureAppDirReady();
    // ⚠️ FLUTTER_TEST 守卫：系谱页/ dashboard 等入口（v2.15 起）在
    // widget 测试里也会触发 load——无 guard 会读用户真实
    // ~/.biology_app/history.json，条数随真机使用漂移，计算历史
    // 按钮「历史（N）」把 golden 测试变成非确定性（2026-09-19 实爆：
    // 用户中午用了软件，下午 golden 就对不上）。注入 debugFilePath
    // （隔离临时文件）时放行。
    if (!kIsWeb && Platform.environment['FLUTTER_TEST'] == 'true' &&
        debugFilePath == null) {
      return [];
    }
    try {
      final webRaw = storageGet(_key);
      if (webRaw != null) {
        final j = jsonDecode(webRaw);
        if (j is! List) return [];
        return [
          for (final e in j)
            if (e is Map) HistoryEntry.fromJson(e.cast<String, dynamic>()),
        ];
      }
      // Web 上没有本地文件系统：storageGet 为 null 只说明 localStorage 空。
      // 不守卫就会构造 File 并 existsSync()，dart2js 下抛 UnsupportedError，
      // 靠外层 catch 吞成空表——结果碰巧对，但属于「靠 catch 兜」而非分支守卫。
      if (kIsWeb) return [];
      final f = File(_file());
      // R5 修复：不可返回 const []——调用方 add（append 读-改-写）会抛
      // UnsupportedError 且被吞，首张历史永远写不进去。一律返可变表。
      if (!f.existsSync()) return [];
      final j = jsonDecode(f.readAsStringSync());
      if (j is! List) return [];
      return [
        for (final e in j)
          if (e is Map) HistoryEntry.fromJson(e.cast<String, dynamic>()),
      ];
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<HistoryEntry> entries) async {
    // save 也必须自带闸门：系谱 _appendHistory 为合并磁盘最新记录会
    // 直接调 save，绕过 append 的同名守卫。默认真实路径在测试里一律
    // 不写；只有显式隔离的 debugFilePath 才允许 round-trip。
    if (!kIsWeb && Platform.environment['FLUTTER_TEST'] == 'true' &&
        debugFilePath == null) {
      return;
    }
    final trimmed = entries.length > maxEntries
        ? entries.sublist(entries.length - maxEntries)
        : entries;
    final json = jsonEncode(
        [for (final e in trimmed) e.toJson()]);
    try {
      // v2.13+：写入即 bump revision——dashboard 讲题回放卡监听它
      // 自动刷新（此前只在 initState 读一次，计算器算完回到 dashboard
      // 看不到新记录）。
      revision.value++;
      if (isWebStorage) {
        await storageSet(_key, json);
        return;
      }
      File(_file()).writeAsStringSync(json);
    } catch (e) {
      // 写盘失败不影响主流程；v2.13 R3 W1 P0：debugPrint 暴露失败
      // 原因——之前 catch(_) 静默吞 → Android 目录异常时历史全丢，
      // 用户零提示。
      debugPrint('[biology] HistoryStore save failed: $e');
    }
  }
}