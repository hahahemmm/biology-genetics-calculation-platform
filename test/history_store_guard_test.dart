// HistoryStore 写入闸门：直接 save 也绝不能污染真实用户历史。

import 'dart:io';

import 'package:biology/state/history_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => HistoryStore.debugFilePath = null);

  test('默认真实路径：直接 save 在测试环境跳过，load 返回空', () async {
    HistoryStore.debugFilePath = null;
    await HistoryStore.save([
      HistoryEntry(label: '测试污染', epochMs: 1, detail: '{}'),
    ]);
    expect(await HistoryStore.load(), isEmpty);
  });

  test('显式临时路径：直接 save/load 仍可做 round-trip', () async {
    final tmp = Directory.systemTemp.createTempSync('history_store_guard');
    HistoryStore.debugFilePath = '${tmp.path}/history.json';
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });
    await HistoryStore.save([
      HistoryEntry(label: '隔离记录', epochMs: 1, detail: '{}'),
    ]);
    expect((await HistoryStore.load()).single.label, '隔离记录');
  });
}
