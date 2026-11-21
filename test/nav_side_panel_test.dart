// nav_side_panel_test.dart —— v2.20.0 SideNavWorkbench 收线回归
//
// 需求（用户裁定「双层左导航」）：信息型页面（课标 / 关于）在 ≥1200 时
// 原本是「280px 纵向目录 + 右内容」，而 HomeShell 在 ≥600 已经有全局
// NavigationRail——两者并排等于屏幕左侧两层导航。本轮删掉 280px 纵向
// 目录，所有宽度统一为「顶部横向滚动选择条 + 右内容」。
//
// M3.1 评审补强（本文件同步扩）：
//   · 宽屏横条里**组名**要上条（只靠细竖线表达大概念太隐晦）；窄屏仍
//     短标签 + 竖线，语义不变。
//   · 组件转 Stateful：父组件程序化改 selectedId 时，选中 pill 若在横条
//     视口外要自动滚进来（课标 focusCode 深链就是这条路）。
//   · railTitle / railIcon 死参已删（调用方同步更新）。
//
// 本文件钉住：
//   S1 @1280：无 280 纵向目录；宽屏全称 pill + 组名上条；分区可切；
//   S2 @390：窄屏短标签 + 分组竖线，不显示组名；
//   S3 @390：**程序化**改 selectedId 到屏外项 → 选中 pill 自动进视口；
//   S4 @390：**手动点击**可见 pill → 选中状态跟手（不因揭示逻辑乱滚）。

import 'package:biology/pages/widgets/side_nav_workbench.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 一个多分区 / 多条目宿主（模拟课标 22 条概念、关于 4 节的规模）。
class _Host extends StatefulWidget {
  const _Host({super.key});

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  String _sel = 'a1';

  static const int _perGroup = 6;

  List<SideNavGroup> get _groups => <SideNavGroup>[
        SideNavGroup(
          label: '概念一 遗传信息控制生物性状',
          entries: <SideNavEntry>[
            for (var i = 1; i <= _perGroup; i++)
              SideNavEntry(
                  id: 'a$i', label: '分区一第 $i 条全称', shortLabel: '一$i'),
          ],
        ),
        SideNavGroup(
          label: '概念二 生物的多样性和适应性',
          entries: <SideNavEntry>[
            for (var i = 1; i <= _perGroup; i++)
              SideNavEntry(
                  id: 'b$i', label: '分区二第 $i 条全称', shortLabel: '二$i'),
          ],
        ),
        const SideNavGroup(
          label: '参考',
          entries: <SideNavEntry>[
            SideNavEntry(
                id: 'ref',
                label: '教材章节对照',
                shortLabel: '教材对照',
                icon: Icons.menu_book_outlined),
          ],
        ),
      ];

  /// 供测试**程序化**改选中项（模拟课标 focusCode 深链）。
  void selectProgrammatically(String id) => setState(() => _sel = id);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SideNavWorkbench(
        groups: _groups,
        selectedId: _sel,
        onSelect: (id) => setState(() => _sel = id),
        bodyMaxWidth: 980,
        body: (context) => Text('内容：$_sel'),
      ),
    );
  }
}

Future<void> _pumpAt(WidgetTester tester, Size size, {GlobalKey? hostKey}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: _Host(key: hostKey)));
  await tester.pumpAndSettle();
}

/// 横条视口（工作台内第一个 SingleChildScrollView = 顶部 pill 条）。
Finder get _barFinder => find
    .descendant(
        of: find.byType(SideNavWorkbench),
        matching: find.byType(SingleChildScrollView))
    .first;

Rect _barRect(WidgetTester tester) => tester.getRect(_barFinder);

void main() {
  testWidgets('S0 @1900 独立构造首帧：横条满宽左起、选中项已可见 ⇒ 不滚动', (tester) async {
    // 真窗/金标准复核用：_v21j_curri_test 的 1900×1200 独立构造路径。
    // 曾出现「整条从 x≈10 漂到 x≈626」——根因是 SingleChildScrollView 在
    // 滚动方向收缩 + Column 居中（不是 reveal 滚动）。这里把几何钉死：
    await _pumpAt(tester, const Size(1900, 1200));

    final bar = _barRect(tester);
    expect(bar.left, 0, reason: '横条必须满宽左起（不得被内容宽收缩后居中）');
    expect(bar.width, 1900, reason: '横条宽度 = 视口宽');
    // 宽屏首元素是组名（限宽 132），pill 紧随其后；与旧 ListView 语义相比
    // 内容偏移量由「组名上条」这个 intentional 变化决定，这里钉住起手位置。
    final groupLabel = tester.getRect(find.text('概念一 遗传信息控制生物性状'));
    expect(groupLabel.left, closeTo(bar.left + 12, 2),
        reason: '组名应贴横条左缘（padding 10 + 2）');
    expect(groupLabel.width, lessThanOrEqualTo(132),
        reason: '组名限宽 132（不得把后面 pill 全推出视口）');
    expect(tester.getRect(find.text('分区一第 1 条全称')).left,
        greaterThan(groupLabel.right),
        reason: '首个 pill 应紧随组名之后');

    // 首帧揭示必须是 no-op：选中项（a1）本来就完整可见。
    final scrollable = tester.state<ScrollableState>(find
        .descendant(
            of: find.byType(SideNavWorkbench), matching: find.byType(Scrollable))
        .first);
    expect(scrollable.position.pixels, 0,
        reason: '首帧不得有任何横向滚动（选中项已可见 ⇒ reveal no-op）');
    // 再等一帧动画时长，确认 postFrame 揭示没有迟到地滚一下。
    await tester.pump(const Duration(milliseconds: 400));
    expect(scrollable.position.pixels, 0,
        reason: '揭示若要滚会在 300ms 动画内发生；此处仍为 0');
    expect(tester.takeException(), isNull);
  });

  testWidgets('S1 @1280：无 280 纵向目录；宽屏全称 pill + 组名上条；分区可切',
      (tester) async {
    await _pumpAt(tester, const Size(1280, 800));

    // 宽屏旧版：280px 侧栏 + 目录标题。现在都不该存在。
    expect(
        find.byWidgetPredicate((w) => w is SizedBox && w.width == 280),
        findsNothing,
        reason: '不得再出现 280px 纵向目录列');
    // v2.20.0：宽屏把组名上条（不能只靠竖线表达大概念）。
    expect(find.text('概念一 遗传信息控制生物性状'), findsOneWidget,
        reason: '宽屏横条应显示组名');
    expect(find.text('参考'), findsOneWidget, reason: '宽屏横条应显示「参考」组名');

    // 宽屏用全称 pill：默认选中分区一第 1 条，切到「教材章节对照」。
    expect(find.text('内容：a1'), findsOneWidget);
    await tester.ensureVisible(find.text('教材章节对照'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('教材章节对照'));
    await tester.pumpAndSettle();
    expect(find.text('内容：ref'), findsOneWidget, reason: '宽屏仍能切分区');

    await tester.ensureVisible(find.text('分区二第 3 条全称'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分区二第 3 条全称'));
    await tester.pumpAndSettle();
    expect(find.text('内容：b3'), findsOneWidget, reason: '所有分区都可切');
    expect(tester.takeException(), isNull);
  });

  testWidgets('S2 @390：窄屏短标签 + 分组竖线，不显示组名', (tester) async {
    await _pumpAt(tester, const Size(390, 844));

    expect(find.text('一1'), findsOneWidget);
    expect(find.text('教材对照'), findsOneWidget);
    expect(find.text('分区一第 1 条全称'), findsNothing, reason: '窄屏用短标签');
    expect(find.text('概念一 遗传信息控制生物性状'), findsNothing,
        reason: '窄屏不上组名（横条宽度不够，分组靠竖线）');
    expect(find.byType(VerticalDivider), findsWidgets, reason: '分组边界竖线保留');

    await tester.ensureVisible(find.text('教材对照'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('教材对照'));
    await tester.pumpAndSettle();
    expect(find.text('内容：ref'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('S3 @390：程序化改 selectedId 到屏外项 → 选中 pill 自动进视口',
      (tester) async {
    final hostKey = GlobalKey();
    await _pumpAt(tester, const Size(390, 844), hostKey: hostKey);

    // 「参考」在 13 个 pill 的最末，390 宽下初始必然在横条视口外。
    final refPill = find.text('教材对照');
    final bar = _barRect(tester);
    final before = tester.getRect(refPill);
    expect(before.left, greaterThan(bar.right),
        reason: '前提：末条 pill 初始在横条视口外');

    // 程序化选中（课标 focusCode 深链走的就是这条）。
    (hostKey.currentState! as _HostState).selectProgrammatically('ref');
    await tester.pumpAndSettle();

    expect(find.text('内容：ref'), findsOneWidget, reason: '内容区已切到参考');
    final after = tester.getRect(find.text('教材对照'));
    expect(after.left, greaterThanOrEqualTo(_barRect(tester).left - 0.5),
        reason: '程序化选中后 pill 应滚进视口（左缘可见）');
    expect(after.right, lessThanOrEqualTo(_barRect(tester).right + 0.5),
        reason: '程序化选中后 pill 应完整可见（右缘可见）');
    expect(tester.takeException(), isNull);
  });

  testWidgets('S4 @390：手动点可见 pill → 选中跟手，横条不乱滚', (tester) async {
    await _pumpAt(tester, const Size(390, 844));

    await tester.tap(find.text('一3'));
    await tester.pumpAndSettle();
    expect(find.text('内容：a3'), findsOneWidget);

    // 已可见项被点中后，揭示逻辑必须是 no-op（不得把 pill 顶到视口起点）。
    final scrollable = tester.state<ScrollableState>(find
        .descendant(
            of: find.byType(SideNavWorkbench), matching: find.byType(Scrollable))
        .first);
    final pixels = scrollable.position.pixels;
    await tester.tap(find.text('一3'));
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, pixels,
        reason: '重复点已可见 pill 不该产生滚动');
    expect(tester.takeException(), isNull);
  });
}
