// v25_scan_test.dart —— v2.5 拍题识别（功能 1）测试
//
// 覆盖：
//   1. parseScanReply 宽容解析（标准 JSON / 夹带文字 / 缺 summary / 参数归一化）
//   2. ScanBankStore 持久化（add/load/removeAt/clear/上限截断）
//   3. ModuleFillBus 注册/跳转/填参（假导航器 + postFrame apply）
//   4. AiChatController.sendScan 全流程（debugScanSender 注入隔离网络）：
//      成功→lastScan+消息+自动入库；模型未回 JSON→原文兜底；未配置→提示

import 'dart:io';

import 'package:biology/services/ai_client.dart';
import 'package:biology/state/scan_bank_store.dart';
import 'package:biology/pages/cross_calculator_page.dart';
import 'package:biology/pages/evolution_page.dart';
import 'package:biology/pages/molecular_page.dart';
import 'package:biology/pages/settings_page.dart';
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
    tmp = Directory.systemTemp.createTempSync('v25_scan_test');
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

  group('parseScanReply 宽容解析', () {
    test('标准 JSON', () {
      final r = parseScanReply(
          '{"summary":"豌豆杂交题","module":"cross_dihybrid","params":{"p1":"AaBb","p2":"aabb"}}');
      expect(r, isNotNull);
      expect(r!.summary, '豌豆杂交题');
      expect(r.module, 'cross_dihybrid');
      expect(r.params, {'p1': 'AaBb', 'p2': 'aabb'});
    });

    test('JSON 前后夹带解释文字也能解析', () {
      final r = parseScanReply(
          '好的，识别结果如下：\n{"summary":"系谱图题","module":"pedigree","params":{}}\n以上。');
      expect(r, isNotNull);
      expect(r!.module, 'pedigree');
      expect(r.params, isEmpty);
    });

    test('缺 summary 返回 null', () {
      expect(parseScanReply('{"module":"other"}'), isNull);
      expect(parseScanReply('没有 JSON'), isNull);
    });

    test('module 缺省归一为 other；参数空值被剔除', () {
      final r = parseScanReply('{"summary":"x","params":{"p1":"","p2":"Aa"}}');
      expect(r, isNotNull);
      expect(r!.module, 'other');
      expect(r.params, {'p2': 'Aa'});
    });
  });

  group('ScanBankStore 持久化', () {
    test('add 后 load 读回，新的在前', () async {
      await ScanBankStore.add(const ScanEntry(
          summary: '第一题', module: 'cross_dihybrid', params: {'p1': 'AaBb'}, ts: 1));
      await ScanBankStore.add(const ScanEntry(
          summary: '第二题', module: 'other', params: {}, ts: 2));
      final all = await ScanBankStore.load();
      expect(all.length, 2);
      expect(all.first.summary, '第二题');
      expect(all.last.module, 'cross_dihybrid');
    });

    test('removeAt 与 clear', () async {
      await ScanBankStore.add(
          const ScanEntry(summary: 'A', module: 'other', params: {}, ts: 1));
      await ScanBankStore.add(
          const ScanEntry(summary: 'B', module: 'other', params: {}, ts: 2));
      await ScanBankStore.removeAt(0);
      var all = await ScanBankStore.load();
      expect(all.single.summary, 'A');
      await ScanBankStore.clear();
      all = await ScanBankStore.load();
      expect(all, isEmpty);
    });

    test('损坏文件容错为空', () async {
      bankFile.writeAsStringSync('not json{{{');
      expect(await ScanBankStore.load(), isEmpty);
    });
  });

  group('ModuleFillBus', () {
    testWidgets('fill 先跳页、下一帧再填参', (t) async {
      // 无 widget 树时 pump 不跑帧，postFrame 回调不会触发——先挂个壳
      await t.pumpWidget(const SizedBox());
      final navLog = <int>[];
      final fillLog = <Map<String, String>>[];
      ModuleFillBus.navigator = navLog.add;
      ModuleFillBus.register(ModuleFillTarget(
        moduleId: 'cross_dihybrid',
        pageIndex: 2,
        label: '遗传计算器·双基因',
        apply: (p) {
          fillLog.add(p);
          return true;
        },
      ));
      expect(ModuleFillBus.targetOf('cross_dihybrid'), isNotNull);
      expect(ModuleFillBus.targetOf('nope'), isNull);

      final ok = ModuleFillBus.fill('cross_dihybrid', {'p1': 'AaBb'});
      expect(ok, isTrue);
      expect(navLog, [2]); // 导航同步发生
      expect(fillLog, isEmpty); // 填参等下一帧
      await t.pump();
      expect(fillLog, [
        {'p1': 'AaBb'}
      ]);

      expect(ModuleFillBus.fill('unregistered', {}), isFalse);
      ModuleFillBus.unregister('cross_dihybrid');
      expect(ModuleFillBus.targetOf('cross_dihybrid'), isNull);
    });
  });

  group('页面填参注册（v2.5 路由终点）', () {
    testWidgets('分子页注册 molecular 目标并回填模板链', (t) async {
      AiSettingsStore.debugConfig = AiConfig.presetMinimax;
      // 超高视口：页面是 ListView，中心法则结果卡在默认 800×600 视口外不构建
      t.view.physicalSize = const Size(1600, 6000);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(const MaterialApp(home: MolecularPage()));
      await t.pump();
      final target = ModuleFillBus.targetOf('molecular');
      expect(target, isNotNull);
      expect(target!.pageIndex, 5);
      // 合法模板链：回填并触发计算（mRNA 含 AUG；结果多为 SelectableText 富文本）
      expect(target.apply({'template': 'TACGGA'}), isTrue);
      // v2.19.21 工作台化：apply 会 animateTo 基因表达 tab，等动画落地
      await t.pumpAndSettle();
      expect(find.textContaining('AUG', findRichText: true), findsWidgets);
      // 非法模板拒收
      expect(target.apply({'template': 'XYZ!'}), isFalse);
      expect(target.apply({}), isFalse);
    });

    testWidgets('进化页注册 evolution 目标并回填 p/q', (t) async {
      AiSettingsStore.debugConfig = AiConfig.presetMinimax;
      t.view.physicalSize = const Size(1600, 4000);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(const MaterialApp(home: EvolutionPage()));
      await t.pump();
      final target = ModuleFillBus.targetOf('evolution');
      expect(target, isNotNull);
      expect(target!.pageIndex, 6);
      expect(target.apply({'p': '0.8', 'q': '0.2'}), isTrue);
      // v2.19.21 工作台化：apply 会 animateTo 遗传平衡 tab，等动画落地
      await t.pumpAndSettle();
      // p=0.8 → AA 预测 64%（结果可能为富文本）
      expect(find.textContaining('64', findRichText: true), findsWidgets);
      expect(target.apply({'p': 'abc'}), isFalse);
    });

    testWidgets('计算器页注册双/三基因目标：切 tab + 回填 + 即算', (t) async {
      AiSettingsStore.debugConfig = AiConfig.presetMinimax;
      t.view.physicalSize = const Size(1600, 5000);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(const MaterialApp(home: CrossCalculatorPage()));
      await t.pump();

      // 双基因：测交 AaBb × aabb → 1:1:1:1
      final di = ModuleFillBus.targetOf('cross_dihybrid');
      expect(di, isNotNull);
      expect(di!.pageIndex, 2);
      expect(di.apply({'p1': 'AaBb', 'p2': 'aabb'}), isTrue);
      await t.pump(); // postFrame 填参
      await t.pumpAndSettle(); // tab 动画收尾
      expect(find.textContaining('1:1:1:1', findRichText: true), findsWidgets);

      // 三对基因：测交 AaBbCc × aabbcc → 1:1:1:1:1:1:1:1
      final tri = ModuleFillBus.targetOf('cross_trihybrid');
      expect(tri, isNotNull);
      expect(tri!.apply({'p1': 'AaBbCc', 'p2': 'aabbcc'}), isTrue);
      await t.pump();
      await t.pumpAndSettle();
      expect(find.textContaining('1:1:1:1:1:1:1:1', findRichText: true),
          findsWidgets);

      // 参数长度不对拒收（双基因目标收到 6 字符）
      expect(di.apply({'p1': 'AaBbCc', 'p2': 'aabbcc'}), isFalse);
    });
  });

  group('sendScan 全流程', () {
    const scanJson =
        '{"summary":"果蝇杂交","module":"cross_dihybrid","params":{"p1":"AaBb","p2":"aabb"}}';

    test('成功：lastScan + 消息 + 自动入库 + 图片一次性清空', () async {
      AiSettingsStore.debugConfig = AiConfig.presetMinimax;
      AiChatController.instance.debugScanSender =
          (msgs) async => const AiResult.ok(scanJson);
      final c = AiChatController.instance;
      c.attachScanImage('Qk1T', 'image/png', 'timu.png');
      expect(c.pendingScanImage, 'Qk1T');

      await c.sendScan();

      expect(c.pendingScanImage, isNull);
      expect(c.lastScan, isNotNull);
      expect(c.lastScan!.module, 'cross_dihybrid');
      expect(c.messages.first.text, contains('【题目图片】timu.png'));
      expect(c.messages.last.text, contains('果蝇杂交'));
      expect(c.messages.last.text, contains('遗传计算器·双基因'));
      final bank = await ScanBankStore.load();
      expect(bank.single.module, 'cross_dihybrid');
      expect(bank.single.params['p2'], 'aabb');
    });

    test('模型未回 JSON：原文兜底展示，不入库', () async {
      AiSettingsStore.debugConfig = AiConfig.presetMinimax;
      AiChatController.instance.debugScanSender =
          (msgs) async => const AiResult.ok('这是一道系谱题，但我说不清参数');
      final c = AiChatController.instance;
      c.attachScanImage('Qk1T', 'image/png', 'x.png');
      await c.sendScan();
      expect(c.lastScan, isNull);
      expect(c.messages.last.text, contains('系谱题'));
      expect(await ScanBankStore.load(), isEmpty);
    });

    test('未配置 API：提示且不入库', () async {
      AiSettingsStore.debugConfig = const AiConfig(apiKey: '');
      final c = AiChatController.instance;
      c.attachScanImage('Qk1T', 'image/png', 'x.png');
      await c.sendScan();
      expect(c.messages.last.text, contains('尚未配置'));
      expect(await ScanBankStore.load(), isEmpty);
    });

    test('失败：错误落到消息流', () async {
      AiSettingsStore.debugConfig = AiConfig.presetMinimax;
      AiChatController.instance.debugScanSender =
          (msgs) async => const AiResult.fail('429: 额度用尽');
      final c = AiChatController.instance;
      c.attachScanImage('Qk1T', 'image/png', 'x.png');
      await c.sendScan();
      expect(c.messages.last.text, contains('429'));
      expect(c.busy, isFalse);
    });
  });
}
