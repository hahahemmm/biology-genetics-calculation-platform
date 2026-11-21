// v215_r6_test.dart —— v2.15 AI 通道 DeepSeek 化 + R6 走查修复回归测试
//
// 覆盖（2026-09-18 R6 批次）：
//   1. 存量迁移：ai_config.json 里旧 opencode 配置 → 打开设置页整体
//      切到 DeepSeek 预设（baseUrl/model 全换，key 保留供替换参考）
//   2. 老师页 MistakeBook 预载：不先进错题本页，班级共性错也能读到
//      磁盘错题（修复懒加载恒 0）
//   3. 伴性 tab 结果区「存入错题本」按钮（7 tab 收录全链最后一环）
//   4. 重拍识别清旧结果卡：sendScan 新一次开始时 lastScan 置空——
//      失败时旧卡不再挡住错误提示（信任级缺陷）

import 'dart:convert';
import 'dart:io';

import 'package:biology/services/ai_client.dart';
import 'package:biology/pages/cross_calculator_page.dart';
import 'package:biology/pages/dashboard_page.dart';
import 'package:biology/pages/settings_page.dart';
import 'package:biology/services/local_secure_store.dart';
import 'package:biology/state/first_run_store.dart';
import 'package:biology/state/mistake_book.dart';
import 'package:biology/ui/ai_chat_controller.dart';
import 'package:biology/ui/module_fill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('v2.15 存量迁移：opencode 配置 → DeepSeek', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('v215_mig_test');
      AiSettingsStore.debugFilePath = '${tmp.path}/ai_config.json';
      AiSettingsStore.debugConfig = null;
      AiSettingsStore.debugWebStorage = null;
      AiSettingsStore.debugForceIsWebStorage = null;
      // 机器密钥也收进临时目录，不脏写真实 ~/.biology_app。
      // （debugResetHooks 会清 hook，故必须先 reset 再设。）
      LocalSecureStore.debugResetHooks();
      LocalSecureStore.debugMachineKeyPath = '${tmp.path}/.machine.key';
    });

    tearDown(() {
      AiSettingsStore.debugFilePath = null;
      AiSettingsStore.debugConfig = null;
      LocalSecureStore.debugResetHooks();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    testWidgets('旧 opencode 配置打开设置页 → 整体切 DeepSeek + 落盘',
        (tester) async {
      // 旧版分发留下的 OpenCode 配置（网关已下线）——**明文**存量形态。
      File(AiSettingsStore.debugFilePath!).writeAsStringSync(jsonEncode({
        'provider': 'opencode',
        'baseUrl': 'https://opencode.ai/zen/go/v1',
        'apiKey': 'sk-legacy-opencode',
        'model': 'mimo-v2.5',
      }));

      await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
      await tester.pump();
      // 透明加密适配（只是把断言挪到契约那一侧，**没有**削弱实现）：
      //   迁移路径 `_loadConfig()` 里的 save 现在要先跑一次 100k PBKDF2 才能
      //   落盘。测试进程里 `LocalSecureStore` 走**内联**派生，且 PBKDF2 显式
      //   关掉了每 2000 轮一次的 `Future.delayed` 让帧暂停（真实定时器在
      //   FakeAsync 里永不兑现 ⇒ widget 测试死锁，见
      //   `lib/services/local_secure_store.dart` 的 `_pbkdf2Derive` 注释），
      //   所以整条续体仍落在微任务里 ⇒ 改造前那两下 pump 依旧推得完。
      //   ——这条 pump 序列就是「加密没把热路径变成真实异步」的探针。
      await tester.pump(const Duration(milliseconds: 100));
      // v2.19.30：设置页回退单列平铺——AI 节首屏直接可见。

      List<String> fieldTexts() => [
            for (var i = 0; i < 3; i++)
              tester
                  .widget<TextField>(find.byType(TextField).at(i))
                  .controller!
                  .text,
          ];
      final t = fieldTexts();
      expect(t[0], 'https://api.deepseek.com',
          reason: 'baseUrl 迁到 DeepSeek 官方 API');
      expect(t[1], 'sk-legacy-opencode',
          reason: 'key 保留在输入框供用户替换时参考');
      expect(t[2], 'deepseek-flash');
      expect(find.text('DeepSeek（默认）'), findsOneWidget);

      // 迁移顺手落盘：下次启动不再走迁移路径 —— 磁盘已是 envelope，
      // 必须经 LocalSecureStore.readSecure 读明文（密钥此时已热）。
      final plain =
          await LocalSecureStore.readSecure(AiSettingsStore.debugFilePath!);
      final saved = jsonDecode(plain) as Map<String, dynamic>;
      expect(saved['provider'], 'deepseek');
      expect(saved['baseUrl'], 'https://api.deepseek.com');
      expect(saved['model'], 'deepseek-flash');
      expect(saved['apiKey'], 'sk-legacy-opencode',
          reason: '解密读回的仍是原 key（加密不透传丢数据）');
    });
  });

  group('老师页 MistakeBook 预载（R6 #4）', () {
    late Directory tmp;

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('v215_mb_test');
      MistakeBook.debugFilePath = '${tmp.path}/m.json';
      MistakeBook.debugTrashFilePath = '${tmp.path}/m.trash.json';
      MistakeBook.instance.debugReset();
      // 直接落盘模拟「上次学生用过的讲台机」。
      MistakeBook.instance.add(
          stem: '概念题A',
          userAnswer: 'x',
          correctAnswer: 'y',
          errorType: MistakeErrorType.concept,
          subjectArea: '分离定律');
      MistakeBook.instance.add(
          stem: '概念题B',
          userAnswer: 'x',
          correctAnswer: 'y',
          errorType: MistakeErrorType.concept,
          subjectArea: '分离定律');
      MistakeBook.instance.debugFlushSave();
      MistakeBook.instance.debugReset(); // 内存清零（_loaded 复位）
      FirstRunStore.debugFilePath = '${tmp.path}/fr.json';
      FirstRunStore.debugWebStorage = null;
      FirstRunStore.debugForceIsWebStorage = false;
      FirstRunStore.instance.debugReset();
      await FirstRunStore.instance.setRole(UserRole.teacher);
      addTearDown(() => MistakeBook.instance.debugFlushSave());
    });

    tearDown(() {
      MistakeBook.debugFilePath = null;
      MistakeBook.debugTrashFilePath = null;
      MistakeBook.instance.debugReset();
      FirstRunStore.debugFilePath = null;
      FirstRunStore.instance.debugReset();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    testWidgets('不进错题本页，班级共性错也读到磁盘错题', (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester
          .pumpWidget(MaterialApp(home: DashboardPage(onOpenTool: (_) {})));
      await tester.pumpAndSettle();
      await tester.tap(find.text('老师工具'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('班级共性错'), 250,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('概念错'), findsOneWidget);
      expect(find.text('2 道'), findsOneWidget,
          reason: '两条概念错从磁盘预载进聚合视图');
      expect(find.textContaining('分离定律 ×2'), findsOneWidget);
    });
  });

  group('伴性 tab 存入错题本（R6 学生 #8）', () {
    setUp(() {
      MistakeBook.instance.debugReset();
      addTearDown(() => MistakeBook.instance.debugFlushSave());
    });

    tearDown(() => MistakeBook.instance.debugReset());

    testWidgets('计算完成后结果区出现「存入错题本」', (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
          const MaterialApp(home: CrossCalculatorPage()));
      await tester.pumpAndSettle();
      // 伴性在 tab 3（懒构建）——走 fill 直达链路切 tab + 回填 + 即算。
      ModuleFillBus.navigator = (_) {};
      expect(
          ModuleFillBus.fill(
              'cross_sex_linked', {'p1': 'XAXa', 'p2': 'XAY'}),
          isTrue);
      await tester.pumpAndSettle();
      expect(find.text('存入错题本'), findsOneWidget,
          reason: '伴性结果区补收录按钮（与 9331/单基因一致）');
      ModuleFillBus.resetForTest();
    });
  });

  group('重拍识别清旧结果卡（R6 学生 #5）', () {
    setUp(() {
      AiChatController.instance.reset();
    });

    tearDown(() {
      AiChatController.instance.debugScanSender = null;
      AiChatController.instance.reset();
    });

    test('上一次识别成功后，再次识别开始时 lastScan 即清空', () async {
      const okJson =
          '{"summary":"测交题","module":"cross_dihybrid","params":{"p1":"Aa","p2":"aa"},"actions":[]}';
      final ctrl = AiChatController.instance;
      ctrl.debugScanSender = (msgs) async => const AiResult.ok(okJson);
      ctrl.attachScanImage('aGVsbG8=', 'image/png', 't1.png');
      expect(await ctrl.sendScan(), isTrue);
      expect(ctrl.lastScan, isNotNull, reason: '首次识别成功有结果卡');

      // 第二次识别（失败）：旧卡必须在开始时就清掉，不能挡住失败提示。
      ctrl.debugScanSender =
          (msgs) async => const AiResult.fail('网络超时');
      ctrl.attachScanImage('aGVsbG8=', 'image/png', 't2.png');
      expect(await ctrl.sendScan(), isFalse);
      expect(ctrl.lastScan, isNull,
          reason: 'R6 #5：新一次识别清旧卡，失败提示不被上一题答案挡住');
      expect(ctrl.lastScanError, '网络超时');
    });
  });

  group('设置页角色切换入口（R6 双走查 #2）', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('v215_role_test');
      FirstRunStore.debugFilePath = '${tmp.path}/fr.json';
      FirstRunStore.debugWebStorage = null;
      FirstRunStore.debugForceIsWebStorage = false;
      FirstRunStore.instance.debugReset();
    });

    tearDown(() {
      FirstRunStore.debugFilePath = null;
      FirstRunStore.instance.debugReset();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    testWidgets('设置页切老师 → 写盘 + 首页实时联动', (tester) async {
      AiSettingsStore.debugConfig =
          const AiConfig(baseUrl: '', apiKey: '', model: '');
      addTearDown(() => AiSettingsStore.debugConfig = null);
      await FirstRunStore.instance.setRole(UserRole.student);

      // 1) 设置页出现角色卡，选老师后写盘。
      await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // v2.19.30：设置页回退单列平铺——角色节首屏可见，无需切分区。
      expect(find.text('使用角色'), findsWidgets);
      await tester.tap(find.text('老师'));
      await tester.pump();
      expect(FirstRunStore.instance.currentRole(), UserRole.teacher);
      expect(
          File(FirstRunStore.debugFilePath!).readAsStringSync(),
          contains('"role":"teacher"'));

      // 2) dashboard 已有 FirstRunStore listener——角色卡在设置页切换后
      //    首页实时刷新（不依赖返回时重建）。先回到学生验证可见性，
      //    再切老师验证实时隐藏 + 提示出现。
      await FirstRunStore.instance.setRole(UserRole.student);
      await tester.pumpWidget(
          MaterialApp(home: DashboardPage(onOpenTool: (_) {})));
      await tester.pumpAndSettle();
      // GridView 懒构建——错题卡在第 10 位，滚入视口再断言。
      await tester.scrollUntilVisible(find.text('我的错题'), 300,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('我的错题'), findsOneWidget,
          reason: '学生角色首页有错题本入口');
      // 回顶再切老师：验证 listener 实时性 + 提示出现。
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 600));
      await tester.pumpAndSettle();
      await FirstRunStore.instance.setRole(UserRole.teacher);
      await tester.pump();
      expect(find.text('我的错题'), findsNothing,
          reason: '切老师后错题本入口实时隐藏（listener 生效）');
      expect(
          find.textContaining('错题本是学生私人空间'), findsOneWidget,
          reason: '老师模式给显式说明 + 指路（不再静默消失）');
    });
  });

  group('方法对比 ▷ 复现（v2.15 补齐）', () {
    setUp(() => ModuleFillBus.resetForTest());
    tearDown(() => ModuleFillBus.resetForTest());

    testWidgets('fill cross_method_compare → 切 tab + 回填 + 即算',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
          const MaterialApp(home: CrossCalculatorPage()));
      await tester.pumpAndSettle();

      final t = ModuleFillBus.targetOf('cross_method_compare');
      expect(t, isNotNull, reason: '方法对比 target 注册');
      expect(t!.label, '遗传计算器·方法对比');

      ModuleFillBus.navigator = (_) {};
      expect(
          ModuleFillBus.fill('cross_method_compare',
              {'p1': 'AaBb', 'p2': 'AaBb'}),
          isTrue);
      await tester.pumpAndSettle();
      // 一致性横幅只在 _result != null 时渲染——先确认计算完成。
      // 横幅文案「两法结果一致」；表型比渲染带空格（'9 : 3 : 3 : 1'）。
      expect(find.text('两法结果一致'), findsOneWidget,
          reason: '两法一致性横幅出现 = 计算已完成');
      expect(find.textContaining('9 : 3 : 3 : 1'), findsWidgets,
          reason: 'AaBb×AaBb 两法并排的表型比已算出');
    });

    testWidgets('fill cross_linkage → 切 tab + 三参回填 + 即算',
        (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
          const MaterialApp(home: CrossCalculatorPage()));
      await tester.pumpAndSettle();

      final t = ModuleFillBus.targetOf('cross_linkage');
      expect(t, isNotNull, reason: '连锁互换 target 注册');
      expect(t!.label, '遗传计算器·连锁互换');

      ModuleFillBus.navigator = (_) {};
      expect(
          ModuleFillBus.fill('cross_linkage',
              {'p1': 'AB/ab', 'p2': 'ab/ab', 'r': '20%'}),
          isTrue);
      await tester.pumpAndSettle();
      // 配子分布表（亲本型/重组型标注）只在 _result != null 时渲染。
      expect(find.text('亲本型'), findsWidgets,
          reason: '连锁计算完成，配子分布表呈现');
    });
  });
}
