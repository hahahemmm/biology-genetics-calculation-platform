// v29_actions_test.dart —— v2.9 拍题识别「标准动作序列」
//
// 覆盖：
//   1. parseScanReply 解析 actions 数组（宽容：非对象/缺 type 剔除）
//   2. ModuleFillBus.fillScan：动作路由（applyActions 优先）与填参回退
//   3. 系谱页动作执行端点（widget 层）：create_family / add_external / next_generation
//   4. sendScan 全流程：带 actions 的识别结果自动入库（含动作持久化）

import 'dart:io';

import 'package:biology/services/ai_client.dart';
import 'package:biology/state/scan_bank_store.dart';
import 'package:biology/pages/genetic_pedigree_page.dart';
import 'package:biology/pages/settings_page.dart';
import 'package:biology/state/app_state.dart';
import 'package:biology/ui/ai_chat_controller.dart';
import 'package:biology/ui/module_fill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late File bankFile;
  late File chatFile;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('v29_actions_test');
    bankFile = File('${tmp.path}/scan_bank.json');
    chatFile = File('${tmp.path}/ai_chat_history.json');
    ScanBankStore.debugFilePath = bankFile.path;
    AiChatStore.debugFilePath = chatFile.path;
    AiChatController.instance.reset();
    ModuleFillBus.resetForTest();
  });

  tearDown(() {
    AiChatController.instance.debugScanSender = null;
    AiChatController.instance.reset();
    AiSettingsStore.debugConfig = null;
    ScanBankStore.debugFilePath = null;
    AiChatStore.debugFilePath = null;
    ModuleFillBus.resetForTest();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('parseScanReply 解析 actions', () {
    test('标准 actions 数组', () {
      final r = parseScanReply(
          '{"summary":"系谱题","module":"pedigree","params":{},'
          '"actions":[{"type":"create_family","father":"AaBb","mother":"AaBb"},'
          '{"type":"add_external","generation":1,"kind":"male","genotype":"Aa"},'
          '{"type":"next_generation"}]}');
      expect(r, isNotNull);
      expect(r!.actions.length, 3);
      expect(r.actions[0]['type'], 'create_family');
      expect(r.actions[0]['father'], 'AaBb');
      expect(r.actions[1]['kind'], 'male');
      expect(r.actions[2]['type'], 'next_generation');
    });

    test('宽容：非对象/缺 type 的动作被剔除', () {
      final r = parseScanReply(
          '{"summary":"x","module":"pedigree",'
          '"actions":["垃圾",{"no_type":"x"},{"type":"create_family","father":"Aa","mother":"Aa"}]}');
      expect(r!.actions.length, 1);
      expect(r.actions.single['type'], 'create_family');
    });

    test('无 actions 字段回退空数组（向后兼容）', () {
      final r = parseScanReply('{"summary":"x","module":"other","params":{"p":"1"}}');
      expect(r!.actions, isEmpty);
    });
  });

  group('ModuleFillBus.fillScan 动作路由', () {
    testWidgets('有动作执行器 → 优先走 applyActions；无 → 回退填参', (t) async {
      await t.pumpWidget(const SizedBox());
      final navLog = <int>[];
      final fillLog = <String>[];
      final actionLog = <List<Map<String, String>>>[];
      ModuleFillBus.navigator = navLog.add;

      // 带动作执行器的目标
      ModuleFillBus.register(ModuleFillTarget(
        moduleId: 'pedigree',
        pageIndex: 1,
        label: '遗传图谱',
        apply: (p) {
          fillLog.add('apply');
          return true;
        },
        applyActions: (actions) {
          actionLog.add(actions);
          return true;
        },
      ));
      // 无动作执行器的目标
      ModuleFillBus.register(ModuleFillTarget(
        moduleId: 'cross_dihybrid',
        pageIndex: 2,
        label: '计算器·双基因',
        apply: (p) {
          fillLog.add('apply_dihybrid');
          return true;
        },
      ));

      // 动作路由
      expect(
          ModuleFillBus.fillScan('pedigree', {}, [
            {'type': 'create_family', 'father': 'Aa', 'mother': 'Aa'}
          ]),
          isTrue);
      expect(navLog, [1]);
      await t.pump();
      expect(actionLog.length, 1);
      expect(actionLog.single.single['father'], 'Aa');
      expect(fillLog, isEmpty); // 动作全部消费，不走 apply

      // 无动作执行器 → 回退填参
      expect(
          ModuleFillBus.fillScan('cross_dihybrid', {'p1': 'AaBb', 'p2': 'aabb'},
              const []),
          isTrue);
      await t.pump();
      expect(fillLog, ['apply_dihybrid']);
    });
  });

  group('系谱页动作执行端点（widget）', () {
    testWidgets('create_family（无引擎=初始双亲）→ 画布有结果、上下文更新',
        (t) async {
      AiSettingsStore.debugConfig = AiConfig.presetMinimax;
      t.view.physicalSize = const Size(1600, 5000);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(const MaterialApp(home: GeneticPedigreePage()));
      await t.pump();
      final target = ModuleFillBus.targetOf('pedigree');
      expect(target, isNotNull);

      // 初始无计算结果（引擎未建立）
      final ok = target!.applyActions!([
        {'type': 'create_family', 'father': 'AaBb', 'mother': 'AaBb'},
      ]);
      await t.pump();
      expect(ok, isTrue);
      expect(AppState.instance.buildSnapshot(), contains('AaBb'));

      // 已有引擎 → addFamily 追加独立家族
      final ok2 = target.applyActions!([
        {'type': 'create_family', 'father': 'Aa', 'mother': 'Aa'},
      ]);
      await t.pump();
      expect(ok2, isTrue);

      // 计算下一代
      final ok3 = target.applyActions!([
        {'type': 'next_generation'},
      ]);
      await t.pump();
      expect(ok3, isTrue);
    });

    testWidgets('add_external：向第 1 代添加外来样本', (t) async {
      AiSettingsStore.debugConfig = AiConfig.presetMinimax;
      t.view.physicalSize = const Size(1600, 5000);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(const MaterialApp(home: GeneticPedigreePage()));
      await t.pump();
      final target = ModuleFillBus.targetOf('pedigree')!;
      // 先创建家族
      target.applyActions!([
        {'type': 'create_family', 'father': 'AaBb', 'mother': 'AaBb'},
      ]);
      await t.pump();
      // 添加外来样本
      final ok = target.applyActions!([
        {'type': 'add_external', 'generation': '1', 'kind': 'male', 'genotype': 'AaBb'},
      ]);
      await t.pump();
      expect(ok, isTrue);
    });

    testWidgets('非法动作返回 false（引擎未建立就计算下一代 / 空动作）',
        (t) async {
      AiSettingsStore.debugConfig = AiConfig.presetMinimax;
      t.view.physicalSize = const Size(1600, 5000);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(const MaterialApp(home: GeneticPedigreePage()));
      await t.pump();
      final target = ModuleFillBus.targetOf('pedigree')!;
      expect(target.applyActions!(const []), isFalse); // 空动作
      expect(
          target.applyActions!([
            {'type': 'next_generation'}
          ]),
          isFalse); // 引擎未建立
    });
  });

  group('sendScan 带 actions 全流程', () {
    const scanJson =
        '{"summary":"果蝇系谱","module":"pedigree","params":{},'
        '"actions":[{"type":"create_family","father":"XAXa","mother":"XAY"}]}';

    test('识别结果含动作 → lastScan 带 actions 且自动入库（含动作）', () async {
      AiSettingsStore.debugConfig = AiConfig.presetMinimax;
      AiChatController.instance.debugScanSender =
          (msgs) async => const AiResult.ok(scanJson);
      final c = AiChatController.instance;
      c.attachScanImage('Qk1T', 'image/png', 'pedigree.png');
      await c.sendScan();

      expect(c.lastScan, isNotNull);
      expect(c.lastScan!.actions.length, 1);
      expect(c.lastScan!.actions.single['type'], 'create_family');
      final bank = await ScanBankStore.load();
      expect(bank.single.module, 'pedigree');
      expect(bank.single.actions.single['father'], 'XAXa');
    });
  });
}
