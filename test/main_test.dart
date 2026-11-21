// main_test.dart —— v2.12.0+2 hotfix: 拍题 FAB 可见性测试
//
// 老师 persona 报告 P0：v2.11 把拍题 FAB 在课堂模式整体隐藏
//（main.dart:562-577 的 `!inClass` 条件），但老师上课时**有拍
// 学生板书的需求**——学生写到黑板上的题目老师想拍下来让该生
// 下去算。这个隐藏等于砍掉了一个老师工作流核心功能，必须修。
//
// 本测试覆盖：
//   1. 课堂模式：拍题 FAB 仍然可见（老师 P0 bug 修复核心断言）
//   2. 学生角色（任何模式）：FAB 图标 20px / 课堂模式 0.7× = 14px
//   3. 老师角色（任何模式）：FAB 图标 20px 正常尺寸 + 课堂模式
//      触发后给"广播到大屏"按钮（让老师有切换余地）
//   4. v2.13 R3 P0-B1：老师"广播到大屏"假按钮 → 锁样式占位
//      （disabled + 「敬请期待 v2.13」副标题 + 点击弹"该功能开发中"
//      提示且不开拍题 dialog）
//
// 测试策略：用 debugFilePath 注入临时 first_run.json 隔离真实磁盘；
// 用 debugSetEnabled 注入课堂模式（不写盘）。BiologyApp 启动后用
// `find.byWidgetPredicate` 定位 _ScanFab 内部的 FloatingActionButton
// 查 heroTag——'scanFab'。

import 'dart:io';

import 'package:biology/main.dart';
import 'package:biology/state/first_run_store.dart';
import 'package:biology/state/present_mode_controller.dart';
import 'package:biology/state/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late String filePath;

  /// 通过 heroTag 定位 _ScanFab 内部的 FloatingActionButton。
  /// heroTag 是 'scanFab'（main.dart `_ScanFab.build` 写死）。
  Finder scanFabFinder() => find.byWidgetPredicate(
        (w) => w is FloatingActionButton && w.heroTag == 'scanFab',
      );

  /// 真实文件 I/O（~/.biology_app/*.json）必须 runAsync 放行——
  /// 直接在 FakeAsync 测试体里 await 会挂死（present_mode_test
  /// 既有踩坑实锤）。
  Future<void> ensureLoaded(WidgetTester tester) async {
    await tester.runAsync(() async {
      await ThemeController.instance.debugEnsureLoaded();
      await PresentModeController.instance.debugEnsureLoaded();
    });
  }

  /// 写一份 first_run.json 并触发 store 重新 load（不走首启 dialog）。
  Future<void> setRole(WidgetTester tester, UserRole r) async {
    File(filePath).writeAsStringSync('{"role":"${r.name}"}');
    FirstRunStore.instance.debugReset();
    await tester.runAsync(() => FirstRunStore.instance.load());
  }

  /// 老师 + 课堂模式：pump 应用后长按 FAB 1 秒解锁 → 弹"课堂模式拍题"
  /// 底部 sheet（v2.13 R3 P0-B1 新增：打开 sheet 的公共路径）。
  Future<void> openBroadcastSheet(WidgetTester tester) async {
    PresentModeController.instance.debugSetEnabled(true);
    await tester.pumpWidget(const BiologyApp());
    await tester.pumpAndSettle();
    // 模拟长按：用 Listener 接收 pointer 事件，_ScanFab 自管 Timer。
    // 1.1s pump 让 Timer(1000ms) fire 调 _onUnlocked。
    final fabCenter = tester.getCenter(scanFabFinder());
    final gesture = await tester.startGesture(fabCenter);
    await tester.pump(const Duration(milliseconds: 1100));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('main_test_scan_fab');
    filePath = '${tmp.path}/first_run.json';
    FirstRunStore.debugFilePath = filePath;
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = false;
    FirstRunStore.instance.debugReset();
    // 兜底文件存在（避免走首启 dialog 路径污染测试）
    if (!File(filePath).existsSync()) {
      File(filePath).writeAsStringSync('{"role":"student"}');
    }
  });

  tearDown(() {
    FirstRunStore.debugFilePath = null;
    FirstRunStore.debugWebStorage = null;
    FirstRunStore.debugForceIsWebStorage = null;
    FirstRunStore.instance.debugReset();
    PresentModeController.instance.debugSetEnabled(false);
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  testWidgets('课堂模式：拍题 FAB 仍可见（v2.12.0+2 hotfix 核心断言）',
      (tester) async {
    await ensureLoaded(tester);

    // 注入学生角色（不区分角色：可见性是 FAB 级别的，跟角色无关）
    await setRole(tester, UserRole.student);
    // 关键：开课堂模式（这是触发 v2.11 隐藏的开关）
    PresentModeController.instance.debugSetEnabled(true);

    await tester.pumpWidget(const BiologyApp());
    await tester.pumpAndSettle();

    // 核心断言：课堂模式下 scanFab 必须存在（v2.11 修复前会被
    // `!inClass` 条件隐藏）。
    expect(scanFabFinder(), findsOneWidget,
        reason: '课堂模式拍题 FAB 仍可见（v2.12.0+2 hotfix 修法核心）');

    // 关闭课堂模式时也应可见（v2.10 原行为保持）
    PresentModeController.instance.debugSetEnabled(false);
    await tester.pump();
    expect(scanFabFinder(), findsOneWidget,
        reason: '非课堂模式拍题 FAB 仍可见（v2.10 原行为保留）');
  });

  testWidgets('学生角色：FAB 图标 20px 正常尺寸（无论课堂/非课堂）',
      (tester) async {
    await ensureLoaded(tester);
    await setRole(tester, UserRole.student);

    // 非课堂模式：图标 20px
    PresentModeController.instance.debugSetEnabled(false);
    await tester.pumpWidget(const BiologyApp());
    await tester.pumpAndSettle();
    var iconWidget = tester.widget<Icon>(
      find.descendant(of: scanFabFinder(), matching: find.byType(Icon)),
    );
    expect(iconWidget.size, 20.0,
        reason: '学生非课堂：图标 20px（v2.10 原始）');

    // 课堂模式（学生）：图标 0.7× = 14px
    PresentModeController.instance.debugSetEnabled(true);
    await tester.pump();
    iconWidget = tester.widget<Icon>(
      find.descendant(of: scanFabFinder(), matching: find.byType(Icon)),
    );
    expect(iconWidget.size, 14.0,
        reason: '学生课堂：图标 0.7× = 14px（hotfix 防占据大屏）');
  });

  testWidgets('老师角色：FAB 图标 20px 正常 + 课堂模式有"广播"按钮',
      (tester) async {
    await ensureLoaded(tester);
    await setRole(tester, UserRole.teacher);

    // 非课堂模式老师：FAB 全尺寸（20px）
    PresentModeController.instance.debugSetEnabled(false);
    await tester.pumpWidget(const BiologyApp());
    await tester.pumpAndSettle();
    var iconWidget = tester.widget<Icon>(
      find.descendant(of: scanFabFinder(), matching: find.byType(Icon)),
    );
    expect(iconWidget.size, 20.0,
        reason: '老师非课堂：FAB 全尺寸 20px');

    // 课堂模式老师：FAB 仍全尺寸（"全功能"），不缩
    PresentModeController.instance.debugSetEnabled(true);
    await tester.pump();
    iconWidget = tester.widget<Icon>(
      find.descendant(of: scanFabFinder(), matching: find.byType(Icon)),
    );
    expect(iconWidget.size, 20.0,
        reason: '老师课堂：FAB 全功能 20px（学生才缩 0.7×）');

    // 课堂模式老师长按 1 秒解锁 → 应弹底部 sheet 含 "广播到大屏" 按钮
    // 模拟长按：用 Listener 接收 pointer 事件，_ScanFab 自管 Timer。
    // 1.1s pump 让 Timer(1000ms) fire 调 _onUnlocked。
    final fabCenter = tester.getCenter(scanFabFinder());
    final gesture = await tester.startGesture(fabCenter);
    // pump 1.1s 让 Timer(1000ms) 触发 _onUnlocked
    await tester.pump(const Duration(milliseconds: 1100));
    // 释放手势
    await gesture.up();
    await tester.pumpAndSettle();

    // 弹底部 sheet：含 "广播到大屏" 按钮 + "仅入错题本" 按钮
    expect(find.text('课堂模式拍题'), findsOneWidget,
        reason: '老师解锁后弹"课堂模式拍题" sheet');
    expect(find.text('广播到大屏'), findsOneWidget,
        reason: '老师课堂模式额外提供"广播"按钮（hotfix 给老师切换余地）');
    expect(find.text('仅入错题本'), findsOneWidget,
        reason: '老师课堂模式默认"仅入错题本"按钮');
  });

  // ═══ v2.13 R3 P0-B1：老师"广播到大屏"假按钮 → 锁样式占位 ═══
  //
  // 背景：全 lib grep「广播」只有文案、0 处实现，原"广播到大屏"点了
  // 只开拍题 dialog + SnackBar，什么都没广播、也无"未接通"提示
  // （Opt3B 一票否决 P0）。修法（推荐 A）：按钮 disabled + 副标题
  // 「敬请期待 v2.13」+ 点击弹"该功能开发中"提示（参考班级共性错卡
  // 先例），绝不开拍题 dialog。
  testWidgets('老师课堂："广播到大屏"为锁样式占位（disabled + 点击提示开发中且不开 dialog）',
      (tester) async {
    await ensureLoaded(tester);
    await setRole(tester, UserRole.teacher);
    await openBroadcastSheet(tester);

    expect(find.text('课堂模式拍题'), findsOneWidget,
        reason: '老师解锁后弹"课堂模式拍题" sheet');
    expect(find.text('广播到大屏'), findsOneWidget,
        reason: '"广播到大屏"按钮仍在（锁样式占位）');
    // R6 老师走查 #6：占位副标题不写死版本号（「下版本就有」跨版本
    // 未兑现损害更新日志可信度）——固定文案「开发中」。
    expect(find.text('开发中'), findsOneWidget,
        reason: '"广播到大屏"带副标题「开发中」（占位不假装可用）');

    // 1. 按钮本体必须 disabled（onPressed == null）——广播通道未接通
    final broadcastBtn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '广播到大屏'),
    );
    expect(broadcastBtn.onPressed, isNull,
        reason: '广播通道未接通：FilledButton 必须 disabled（假按钮修复核心）');

    // 2. 点击 → 弹"该功能开发中"SnackBar 提示
    await tester.tap(find.text('广播到大屏'));
    await tester.pump();
    expect(find.textContaining('该功能开发中'), findsOneWidget,
        reason: '点击广播到大屏 → 提示"该功能开发中"（班级共性错先例：SnackBar）');
    expect(find.textContaining('该功能随版本更新逐步开放'), findsOneWidget,
        reason: 'SnackBar 提示含「该功能随版本更新逐步开放」（不写死版本号）');

    // 3. 绝不开拍题 dialog（假按钮修复核心），sheet 保持打开
    expect(find.byType(Dialog), findsNothing,
        reason: '点击广播占位绝不开拍题 dialog（原假按钮行为已移除）');
    expect(find.text('课堂模式拍题'), findsOneWidget,
        reason: 'sheet 保持打开（只有"仅入错题本"才真正进拍题 dialog）');
  });

  // ═══ v2.12 R1 C P0 #8：IndexedStack 10 页 5min offstage 内存治理 ═══
  //
  // 覆盖：
  //   1. 6 分钟未访问 → page 被 offstage（visible=false 但 maintainState）
  //   2. 重新 tap → page 重新可见 + state 保留（不重建）
  //   3. debugForceOffstageCheck 立刻触发扫描（绕开 15s Timer.periodic）
  //
  // 实现：HomeShell 内 `_lastAccess: Map<int, DateTime>` +
  // `Timer.periodic(15s)` + `Visibility(visible: !_shouldOffstage(i),
  // maintainState: true)`。test 用 `debugSetAccessTimeForTest` +
  // `debugForceOffstageCheck` 模拟"6 分钟前访问"路径。
  //
  // 注意：HomeShell 是 private class，test 通过 BiologyApp → HomeShell
  // 间接验证。`debugSetAccessTimeForTest` / `debugForceOffstageCheck`
  // 暴露在 `_HomeShellState`，但通过 widget tree 能找到
  // `State<HomeShell>`。

  group('v2.12 R1 C P0 #8 IndexedStack 5min offstage 治理', () {
    /// 通过 widget tree 找到 HomeShell 的 State 实例。
    /// HomeShellState 是公开类（v2.12 R1 C P0 #8：原 `_HomeShellState`
    /// private 类改名 public，让同 package test 能 import 跨边界访问）。
    HomeShellState? homeShellState(WidgetTester tester) {
      return tester.state<HomeShellState>(find.byType(HomeShell));
    }

    /// 触发 offstage 检查（绕开 15s Timer）。
    Future<void> forceCheck(WidgetTester tester) async {
      final s = homeShellState(tester);
      s?.debugForceOffstageCheck();
      await tester.pump();
    }

    testWidgets('初始态：所有页 _lastAccess = now（首帧不 offstage）',
        (tester) async {
      await ensureLoaded(tester);
      await setRole(tester, UserRole.student);
      await tester.pumpWidget(const BiologyApp());
      await tester.pumpAndSettle();

      final s = homeShellState(tester);
      expect(s, isNotNull, reason: 'HomeShell state 应被找到');
      final accessTimes = s!.debugGetAccessTimes();
      expect(accessTimes.length, 13, reason: '13 页都应有 _lastAccess');
      // 所有时间应非常接近"现在"（首帧刚初始化）
      final now = DateTime.now();
      for (final t in accessTimes.values) {
        expect(now.difference(t).inSeconds.abs(), lessThan(5),
            reason: '首帧所有页 _lastAccess 接近 now（不被立即 offstage）');
      }
    });

    testWidgets('6 分钟未访问 → page 被 offstage', (tester) async {
      await ensureLoaded(tester);
      await setRole(tester, UserRole.student);
      await tester.pumpWidget(const BiologyApp());
      await tester.pumpAndSettle();

      final s = homeShellState(tester);
      expect(s, isNotNull);

      // 把第 1 页（遗传图谱）的 _lastAccess 设为 6 分钟前
      final sixMinAgo = DateTime.now().subtract(const Duration(minutes: 6));
      s!.debugSetAccessTimeForTest(1, sixMinAgo);
      // 立即触发扫描（绕开 15s Timer）
      await forceCheck(tester);

      // _offstageTick 应递增（说明命中 offstage 条件）
      expect(s.debugGetOffstageTick(), greaterThan(0),
          reason: '6 分钟前访问 + 立即扫描 → _offstageTick++');

      // 验证：第 1 页的 Visibility visible=false（offstage）
      // 通过 _lastAccess 查"现在"应 > 5min
      final last1 = s.debugGetAccessTimes()[1]!;
      final elapsed = DateTime.now().difference(last1);
      expect(elapsed.inMinutes, greaterThanOrEqualTo(6),
          reason: '第 1 页 _lastAccess 是 6 分钟前');
    });

    testWidgets('重新 tap → page 重新可见 + state 保留（不重建）',
        (tester) async {
      await ensureLoaded(tester);
      await setRole(tester, UserRole.student);
      await tester.pumpWidget(const BiologyApp());
      await tester.pumpAndSettle();

      final s = homeShellState(tester);
      expect(s, isNotNull);

      // 模拟"第 1 页 6 分钟前被访问过，然后 5 分钟过去"
      s!.debugSetAccessTimeForTest(
          1, DateTime.now().subtract(const Duration(minutes: 6)));
      await forceCheck(tester);
      expect(s.debugGetOffstageTick(), greaterThan(0),
          reason: 'retap 前 _offstageTick > 0（第 1 页已 offstage）');

      // 模拟"用户现在 tap 第 1 页"——通过 debugSelectPageAt(i) 触发
      s.debugSelectPageAt(1);
      await tester.pump();
      // 此时 _lastAccess[1] = now → 5min 内不会再 offstage
      final last1 = s.debugGetAccessTimes()[1]!;
      final elapsed = DateTime.now().difference(last1);
      expect(elapsed.inSeconds, lessThan(2),
          reason: 'retap 后 _lastAccess[1] = now');

      // 立即 forceCheck → 因为 _lastAccess 是 now，shouldOffstage(1)=false
      await forceCheck(tester);
      // 关键：retap 后 _lastAccess[1] = now 一定成立
      expect(elapsed.inSeconds, lessThan(2),
          reason: 'retap 后第 1 页 _lastAccess = now（5min 阈值保护）');
    });

    testWidgets('debugForceOffstageCheck 立刻触发扫描（绕开 15s Timer）',
        (tester) async {
      await ensureLoaded(tester);
      await setRole(tester, UserRole.student);
      await tester.pumpWidget(const BiologyApp());
      await tester.pumpAndSettle();

      final s = homeShellState(tester);
      expect(s, isNotNull);

      // 0. 验证 debugForceOffstageCheck 存在且不抛
      expect(s!.debugGetOffstageTick(), 0,
          reason: 'init 后 _offstageTick=0');

      // 1. 没有任何页超阈值 → forceCheck 不应 ++
      s.debugForceOffstageCheck();
      await tester.pump();
      expect(s.debugGetOffstageTick(), 0,
          reason: '无超阈值页 → forceCheck 不 ++');

      // 2. 把第 5 页（分子）设为 6 分钟前 → forceCheck 应 ++
      s.debugSetAccessTimeForTest(
          5, DateTime.now().subtract(const Duration(minutes: 6)));
      s.debugForceOffstageCheck();
      await tester.pump();
      expect(s.debugGetOffstageTick(), greaterThan(0),
          reason: '分子页超阈值 → forceCheck ++');
    });

    testWidgets('当前页 _index 永不 offstage（_shouldOffstage 守护）',
        (tester) async {
      await ensureLoaded(tester);
      await setRole(tester, UserRole.student);
      await tester.pumpWidget(const BiologyApp());
      await tester.pumpAndSettle();

      final s = homeShellState(tester);
      expect(s, isNotNull);

      // 当前 _index=0。把第 0 页 debugSetAccessTimeForTest 设为 6 分钟前。
      // 但 _shouldOffstage 内部 `if (i == _index) return false` 守护当前页
      // 永远不 offstage。验证：forceCheck 后 _offstageTick 不应 ++（因
      // _shouldOffstage(0) 返 false → changed=false → tick 不变）。
      final tickBefore = s!.debugGetOffstageTick();
      s.debugSetAccessTimeForTest(
          0, DateTime.now().subtract(const Duration(minutes: 6)));
      s.debugForceOffstageCheck();
      await tester.pump();
      // 验证 tick 不变（current index page 不被治理）
      // 但 _select(0) 之前的 pump 可能让其他页 offstage...为了纯净，
      // 我们清空所有其他页时间戳为 now
      for (var i = 1; i < 11; i++) {
        s.debugSetAccessTimeForTest(i, DateTime.now());
      }
      final tickMid = s.debugGetOffstageTick();
      s.debugForceOffstageCheck();
      await tester.pump();
      expect(s.debugGetOffstageTick(), tickMid,
          reason: '当前页 _index=0 即使 _lastAccess 是 6 分钟前，'
              '_shouldOffstage(i) 内部 `if (i == _index) return false` 守护，'
              'forceCheck 不 ++');
    });
  });
}
