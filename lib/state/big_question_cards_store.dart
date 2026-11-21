// big_question_cards_store.dart —— 套路卡「已背熟」标记存储（v2.19.25）
//
// 学生找茬 P1-1：卡片没有任何状态，背完没法标——本 store 给每张卡一个
// 持久化的「已背熟」标记（Set<cardId> → cards_mastered.json）。
// 守卫纪律照抄 HistoryStore：FLUTTER_TEST 下不碰真盘（golden 非确定性
// 实爆过），测试注入 debugFilePath 隔离临时文件时放行。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show ValueNotifier, debugPrint, kIsWeb;

import '../storage/platform_storage_io.dart'
    if (dart.library.html) '../storage/platform_storage_web.dart';

/// 已背熟卡 id 集（内存镜像 + ValueNotifier，页面 ListenableBuilder 跟随）。
class BigQuestionCardsStore {
  static const _key = 'big_question_cards_mastered';
  static const _fileName = 'cards_mastered.json';

  static final ValueNotifier<Set<String>> mastered =
      ValueNotifier<Set<String>>(<String>{});

  /// 测试注入：临时文件路径（隔离真盘）。与 HistoryStore 同款语义。
  static String? debugFilePath;

  static bool _testSkip() =>
      !kIsWeb &&
      Platform.environment['FLUTTER_TEST'] == 'true' &&
      debugFilePath == null;

  static String _file() {
    if (debugFilePath != null) return debugFilePath!;
    final appDir = userAppDir();
    if (appDir == null) return _fileName;
    final dir = Directory(appDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return '${dir.path}/$_fileName';
  }

  /// initState 调一次。损坏/不存在 → 空集（不抛）。
  /// v2.19.26（老用户 ④-A）：补 ensureAppDirReady——HistoryStore/
  /// ScanBankStore 的 Android getFilesDir 缓存竞态纪律（原注释自称
  /// 照抄 HistoryStore 却漏了这条）。
  static Future<void> load() async {
    if (_testSkip()) return;
    await ensureAppDirReady();
    try {
      if (isWebStorage) {
        final raw = storageGet(_key);
        if (raw == null) return;
        final j = jsonDecode(raw);
        if (j is List) {
          mastered.value = {for (final e in j) e.toString()};
        }
        return;
      }
      final f = File(_file());
      if (!f.existsSync()) return;
      final j = jsonDecode(f.readAsStringSync());
      if (j is List) {
        mastered.value = {for (final e in j) e.toString()};
      }
    } catch (e) {
      debugPrint('[biology] BigQuestionCardsStore load failed: $e');
    }
  }

  static bool isMastered(String cardId) => mastered.value.contains(cardId);

  /// 切换标记并落盘。返回切换后的状态（true = 已背熟）。
  static Future<bool> toggle(String cardId) async {
    final next = {...mastered.value};
    final now = !next.contains(cardId);
    if (now) {
      next.add(cardId);
    } else {
      next.remove(cardId);
    }
    mastered.value = next;
    await _save();
    return now;
  }

  static Future<void> _save() async {
    if (_testSkip()) return;
    try {
      final json = jsonEncode(mastered.value.toList());
      if (isWebStorage) {
        await storageSet(_key, json);
        return;
      }
      File(_file()).writeAsStringSync(json);
    } catch (e) {
      debugPrint('[biology] BigQuestionCardsStore save failed: $e');
    }
  }
}
