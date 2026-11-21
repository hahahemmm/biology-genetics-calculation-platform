// main_first_run_test.dart —— BiologyApp 启动首启 dialog 集成测试
//
// v2.12 Wave 3-B P0：补 HomeShell 启动流程的端到端测试。
//
// 覆盖：
//   1. HomeShell 启动首次显示首启 dialog（无 first_run.json）
//   2. 选角色后 dialog 关闭 + dashboard 立刻反映新角色
//   3. 模拟「刷新页面」：debugFilePath 不变 + debugReset → load →
//      不再弹首启 dialog（已选过角色持久化生效）
//
// 测试用 debugFilePath 隔离真实磁盘；debugWebStorage 隔离 web 端
// localStorage（同 FirstRunStore 单元测试）。flutter_test 无 window
// 对象，无法走真实的 localStorage 路径。

import 'dart:io';

import 'package:biology/main.dart';
import 'package:biology/state/first_run_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late String filePath;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('main_first_run_test');
    filePath = '${tmp.path}/first_run.json';
    // 桌面路径：注入临时文件
    FirstRunStore.debugFilePath = filePath;
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = false;
    FirstRunStore.instance.debugReset();
    // 本文件就是要验「首启自动弹引导」：关掉全仓测试基线的抑制开关。
    FirstRunStore.debugSuppressAutoGuide = false;
    // 确保文件不存在（首启场景）
    if (File(filePath).existsSync()) {
      File(filePath).deleteSync();
    }
  });

  tearDown(() {
    FirstRunStore.debugFilePath = null;
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = null;
    FirstRunStore.instance.debugReset();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  testWidgets(
      'HomeShell 启动首次显示首启 dialog：选角色后 dashboard 立刻反映',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // 启动 BiologyApp。initState 会调 FirstRunStore.load()，如果
    // isFirstRun=true 则在首帧后弹 dialog。pumpAndSettle 等首帧 + dialog。
    await tester.pumpWidget(const BiologyApp());
    await tester.pumpAndSettle();

    // 1. 首启 dialog 应已弹出（标题 + 2 选 1 角色列表）
    //    v2.13 R5 P0：移除「家长」选项——产品决策 Biology 不面向家长。
    expect(find.text('欢迎使用 Biology'), findsOneWidget,
        reason: '首启 dialog 标题');
    expect(find.text('老师'), findsOneWidget,
        reason: '老师选项');
    expect(find.text('学生'), findsOneWidget,
        reason: '学生选项');
    expect(find.text('家长'), findsNothing,
        reason: '家长选项已移除（R5 P0）');

    // 2. 点「老师」选项 → dialog 关闭 + dashboard 立刻反映新角色
    //    dashboard 顶部 role chip 应从「未选择」变成「老师」，
    //    且「我的错题」入口应隐藏（错题本是学生私人空间，老师 hide）。
    await tester.tap(find.text('老师'));
    await tester.pumpAndSettle();

    expect(find.text('欢迎使用 Biology'), findsNothing,
        reason: '选完角色后 dialog 关闭');
    // v3.8 首启自动引导：角色选完、guide_done 缺失 → 自动打开第 1 步。
    // 顺序不能反——dialog 是模态的，引导必须先等它关掉。
    expect(find.text('欢迎使用生物遗传计算平台'), findsOneWidget,
        reason: '首启角色选定后应自动开启新手引导');
    expect(find.text('当前：老师'), findsOneWidget,
        reason: 'role chip 立即反映新角色');
    expect(find.text('我的错题'), findsNothing,
        reason: '老师角色下错题本入口隐藏');
    expect(find.text('遗传图谱计算'), findsOneWidget,
        reason: 'dashboard 主卡仍渲染');

    // 3. 验证磁盘有 first_run.json（持久化生效）
    expect(File(filePath).existsSync(), isTrue,
        reason: 'setRole 后磁盘应有 first_run.json');
    final j = File(filePath).readAsStringSync();
    expect(j, contains('"role":"teacher"'),
        reason: '磁盘 JSON 应含 role=teacher');

    // 收尾：跳过引导（同时落盘 guide_done），不把 overlay 留给后续用例。
    await tester.tap(find.text('跳过'));
    await tester.pumpAndSettle();
  });

  testWidgets('二次启动不弹首启 dialog：模拟刷新页面后角色保留', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // 1. 预置 first_run.json（用户上次选过学生）
    File(filePath).writeAsStringSync('{"role":"student","guide_done":true}');

    // 2. 启动 app → load() 读到 student → isFirstRun=false → 不弹 dialog
    await tester.pumpWidget(const BiologyApp());
    await tester.pumpAndSettle();

    // 3. 不应弹首启 dialog
    expect(find.text('欢迎使用 Biology'), findsNothing,
        reason: '已有角色 → 不弹首启 dialog');
    // role chip 应直接显示「学生」
    expect(find.text('当前：学生'), findsOneWidget,
        reason: '从磁盘读出上次选的学生角色');
    // dashboard 主卡应渲染
    expect(find.text('遗传图谱计算'), findsOneWidget,
        reason: 'dashboard 正常渲染');
    // 错题本入口应显示（学生角色可见）
    expect(find.text('我的错题'), findsOneWidget,
        reason: '学生角色下错题本入口可见');
    // guide_done=true：看过一次就不再自动弹引导。
    expect(find.text('欢迎使用生物遗传计算平台'), findsNothing,
        reason: '已看过引导 → 二次启动不再自动弹');
  });

  testWidgets('老用户（已选角色、没看过引导）→ 启动自动开一次引导', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // 升级前的老磁盘：有 role、无 guide_done。走的是「非首启」分支——
    // 不弹角色 dialog，但不能省掉首用引导。
    File(filePath).writeAsStringSync('{"role":"student"}');

    await tester.pumpWidget(const BiologyApp());
    await tester.pumpAndSettle();
    expect(find.text('欢迎使用生物遗传计算平台'), findsOneWidget,
        reason: '老用户也要补看一次引导');

    await tester.tap(find.text('跳过'));
    await tester.pumpAndSettle();
    expect(find.text('欢迎使用生物遗传计算平台'), findsNothing,
        reason: '跳过立即关闭');
    expect(File(filePath).readAsStringSync(), contains('"guide_done":true'),
        reason: '跳过即算看过并落盘（下次启动不再自动弹）');
  });

  testWidgets('web 端：debugForceIsWebStorage=true 时也能正确首启 + 不再弹',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // 模拟 web：localStorage mock + isWebStorage 强制 true
    final webStore = <String, String>{};
    FirstRunStore.debugWebStorage = webStore;
    FirstRunStore.debugForceIsWebStorage = true;
    // web 路径不读桌面文件，清空 debugFilePath
    FirstRunStore.debugFilePath = null;
    FirstRunStore.instance.debugReset();

    // 1. 首次启动：web storage 空 → 弹首启 dialog
    await tester.pumpWidget(const BiologyApp());
    await tester.pumpAndSettle();
    expect(find.text('欢迎使用 Biology'), findsOneWidget,
        reason: 'web 端首启也应弹 dialog');

    // 2. v2.13 R5 P0：选学生（不再有「家长」选项）。与首启 dialog
    //    一样，硬编码 2 张卡——web 端走同款 dialog，行为一致。
    await tester.tap(find.text('学生'));
    await tester.pumpAndSettle();
    expect(find.text('当前：学生'), findsOneWidget,
        reason: 'role chip 反映 web 端 setRole');
    expect(webStore['first_run_json'], isNotNull,
        reason: 'web 端 setRole 写到 localStorage（mock）');

    // web 端同样自动开引导：先验再跳过（落盘 guide_done），让下面的
    // 「刷新」段只验证角色 round-trip，不被 overlay 干扰。
    expect(find.text('欢迎使用生物遗传计算平台'), findsOneWidget,
        reason: 'web 端首启也应自动开引导');
    await tester.tap(find.text('跳过'));
    await tester.pumpAndSettle();

    // 3. 模拟刷新：debugReset 内存 + 重新挂载 app
    FirstRunStore.instance.debugReset();
    await tester.pumpWidget(const SizedBox()); // 卸载
    await tester.pumpWidget(const BiologyApp());
    await tester.pumpAndSettle();
    expect(find.text('欢迎使用 Biology'), findsNothing,
        reason: 'web 端二次启动不再弹 dialog');
    expect(find.text('当前：学生'), findsOneWidget,
        reason: 'web 端 round-trip：从 localStorage 读回学生角色');
  });

  // v2.13：dialog 被异常关闭（返回 null 结果）时写「学生」兜底，
  // 避免下次启动再弹首启 dialog。兑现 main.dart 注释承诺的行为。
  testWidgets('首启 dialog 异常关闭（pop null）→ 写学生兜底落盘', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const BiologyApp());
    await tester.pumpAndSettle();
    expect(find.text('欢迎使用 Biology'), findsOneWidget,
        reason: '首启 dialog 已弹出');

    // 异常关闭：不经选项直接 pop 首启 dialog（路由结果 = null）。
    final ctx = tester.element(find.text('欢迎使用 Biology'));
    Navigator.of(ctx).pop();
    await tester.pumpAndSettle();

    expect(find.text('欢迎使用 Biology'), findsNothing,
        reason: 'dialog 已关闭');
    expect(File(filePath).existsSync(), isTrue,
        reason: '兜底路径也应写盘 first_run.json');
    expect(File(filePath).readAsStringSync(), contains('"role":"student"'),
        reason: '异常关闭兜底为学生角色');
    expect(find.text('当前：学生'), findsOneWidget,
        reason: 'dashboard role chip 同步反映兜底角色');

    // 兜底写角色也算首启走完 → 引导接力自动打开，再跳过收尾。
    expect(find.text('欢迎使用生物遗传计算平台'), findsOneWidget,
        reason: '首启兜底路径同样自动开引导');
    await tester.tap(find.text('跳过'));
    await tester.pumpAndSettle();
  });
}
