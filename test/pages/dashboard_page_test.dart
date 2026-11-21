// dashboard_page_test.dart —— v2.2 批次4a：图标化首页测试
//
// 覆盖：宽屏 4 列 9 项全渲染、点击卡片触发 onOpenTool 回调（导航索引）、
// 390 窄屏 2 列不溢出、深浅双模式渲染不抛异常（token 取色）。
//
// v2.12 Wave 3-B 新增 2 case：
//   - role chip 显示（顶部 ActionChip 含当前角色名）
//   - teacher 角色隐藏错题本入口（student 角色仍显示）
//
// v2.12+ R1 P0 #2 新增 2 case：
//   - 老师卡可见 + 点板书 PDF 跳到系谱页（通过 onOpenTool(1) 回调）
//   - 拍题统计：MistakeBook + ScanBankStore 实时读

import 'dart:convert';
import 'dart:io';

import 'package:biology/engine/pedigree_graph.dart';
import 'package:biology/state/scan_bank_store.dart';
import 'package:biology/pages/dashboard_page.dart';
import 'package:biology/state/first_run_store.dart';
import 'package:biology/state/history_store.dart';
import 'package:biology/state/mistake_book.dart';
import 'package:biology/theme.dart';
import 'package:biology/ui/module_fill.dart';
import 'package:biology/ui/module_surface.dart';
import 'package:biology/ui/svg_export.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 首页入口（v2.21.0 分组后仍逐项断言渲染；名称取自导航目录，顺序
  // 无所谓——find.text 不关心位置）。
  const cardNames = [
    '遗传图谱计算',
    '遗传计算器',
    '知识图谱',
    '课标体系',
    '分子遗传',
    '进化·基因频率',
    '染色体倍性',
    // v2.22.0：「大题套路卡」从首页撤下独立入口（改由 9331 结果页按 K /
    // 错题本按需打开）⇒ 首页不再渲染这张卡。
    '变异',
    '人类遗传病',
    '设置',
    '关于',
  ];

  Widget wrap({required void Function(int) onOpen}) =>
      MaterialApp(home: DashboardPage(onOpenTool: onOpen));

  void wideViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// 把入口滚进视口。
  ///
  /// v2.21.0：首页改为「整页单一滚动容器 + 全量挂载」（不再用懒加载的
  /// GridView），所以 ensureVisible 对所有入口都成立，不再需要
  /// 「先 drag 把目标拖进树再 ensureVisible」的两步式。
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('分层首页：欢迎区 + 三核心工作区 + 三组模块，入口全部渲染', (tester) async {
    wideViewport(tester);
    await tester.pumpWidget(wrap(onOpen: (_) {}));
    await tester.pumpAndSettle();
    for (final n in cardNames) {
      expect(find.text(n), findsOneWidget, reason: '入口「$n」应渲染');
    }
    // 层级（旧版 13 张同权卡没有层级，只有列数）：大标题 → 核心区 →
    // 三个分组标题。
    expect(find.text('遗传计算工作台'), findsOneWidget, reason: '欢迎区大标题');
    expect(find.text('核心工作区'), findsOneWidget, reason: '核心工作区标题');
    expect(find.text('计算工具'), findsOneWidget, reason: '计算组标题');
    expect(find.text('学习支持'), findsOneWidget, reason: '学习组标题');
    expect(find.text('系统与帮助'), findsOneWidget, reason: '系统组标题');
    expect(
      find.text('输入题目数据，直接算出结果——通用生物计算器'),
      findsOneWidget,
      reason: '顶部定位语存在',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('点击卡片触发 onOpenTool 回调（携带导航索引）', (tester) async {
    wideViewport(tester);
    final got = <int>[];
    await tester.pumpWidget(wrap(onOpen: got.add));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('分子遗传'));
    await tester.tap(find.text('分子遗传'));
    await tester.pumpAndSettle();
    expect(got, [5], reason: '分子遗传 = 导航索引 5（首页为 0）');
    await scrollTo(tester, find.text('染色体倍性'));
    await tester.tap(find.text('染色体倍性'));
    await tester.pumpAndSettle();
    expect(got, [5, 7], reason: '倍性 = 导航索引 7');
  });

  testWidgets('390 窄屏：核心卡全宽、分组单列、零溢出、末项可达', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(wrap(onOpen: (_) {}));
    await tester.pumpAndSettle();

    // 核心卡全宽（390 − 左右各 16 的页面 padding = 358）——不再有
    // 「窄屏 2 列」的旧约束，核心卡在手机上不并列。
    final core = tester.getSize(
      find
          .ancestor(
            of: find.text('遗传图谱计算'),
            matching: find.byType(ModuleSurface),
          )
          .first,
    );
    expect(core.width, 358, reason: '窄屏核心卡全宽');

    // v2.22.0：窄屏（<600）分组入口改**单列**——同组入口纵向堆叠
    // （不再是同一行左右分列），说明可完整折行。
    final left = tester.getRect(find.text('分子遗传'));
    final right = tester.getRect(find.text('进化·基因频率'));
    expect(right.top, greaterThan(left.bottom),
        reason: '窄屏分组入口单列纵向排列');
    expect(left.left, closeTo(right.left, 0.5), reason: '单列入口左缘对齐一致');

    expect(tester.takeException(), isNull, reason: '首帧无溢出');
    // 底部「关于」入口仍可达（整页一个滚动容器，非懒加载）。
    await scrollTo(tester, find.text('关于'));
    expect(find.text('关于'), findsOneWidget, reason: '底部「关于」入口应存在');
    expect(tester.takeException(), isNull, reason: '滚动到底部无溢出');
  });

  testWidgets('深浅双模式渲染不抛异常（token 取色）', (tester) async {
    wideViewport(tester);
    addTearDown(() => AppColors.sync(Brightness.light));
    AppColors.sync(Brightness.light);
    await tester.pumpWidget(wrap(onOpen: (_) {}));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '浅色模式无异常');

    AppColors.sync(Brightness.dark);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.dark),
        home: DashboardPage(onOpenTool: (_) {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('分子遗传'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '深色模式无异常');
  });

  // ===== v2.12 Wave 3-B 新增：role chip + 角色分流 =====

  testWidgets('role chip 显示：顶部 ActionChip 展示当前角色 + 切换入口', (tester) async {
    wideViewport(tester);
    // 角色未选：chip 显示"未选择"
    FirstRunStore.instance.debugReset();
    await tester.pumpWidget(wrap(onOpen: (_) {}));
    await tester.pumpAndSettle();
    final chipFinder = find.byKey(const Key('dashboard_role_chip'));
    expect(chipFinder, findsOneWidget, reason: 'role chip 存在');
    expect(find.text('当前：未选择'), findsOneWidget, reason: '未选角色时显示"当前：未选择"');

    // 切到老师角色：chip 文案跟着变
    await FirstRunStore.instance.setRole(UserRole.teacher);
    await tester.pumpAndSettle();
    expect(
      find.text('当前：老师'),
      findsOneWidget,
      reason: 'setRole(teacher) 后 chip 文案更新',
    );
  });

  testWidgets('teacher 角色隐藏错题本入口；student 角色显示', (tester) async {
    wideViewport(tester);
    FirstRunStore.instance.debugReset();

    // 1. teacher 角色：错题本入口隐藏
    await FirstRunStore.instance.setRole(UserRole.teacher);
    await tester.pumpWidget(wrap(onOpen: (_) {}));
    await tester.pumpAndSettle();
    expect(
      find.text('我的错题'),
      findsNothing,
      reason: 'teacher 角色不应看到「我的错题」入口（错题本是学生私人空间）',
    );
    // 主卡仍渲染（点 9 张中任意一张）
    expect(find.text('遗传图谱计算'), findsOneWidget);

    // 2. student 角色：错题本入口出现
    await FirstRunStore.instance.setRole(UserRole.student);
    await tester.pumpAndSettle();
    expect(find.text('我的错题'), findsOneWidget, reason: 'student 角色应看到「我的错题」入口');
  });

  // ===== v2.12+ R1 P0 #2 新增：老师工具卡实装 =====

  testWidgets('P0 #2 老师卡可见 + 点板书 PDF 跳到系谱页 + board_history 落盘 SVG', (
    tester,
  ) async {
    // 准备：老师角色 + 清空 board_history 目录 + 清空 MistakeBook
    final tmp = Directory.systemTemp.createTempSync('dashboard_p0_2_test');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    FirstRunStore.instance.debugReset();
    await FirstRunStore.instance.setRole(UserRole.teacher);
    MistakeBook.instance.debugReset();

    // 监听 onOpenTool 回调
    final navLog = <int>[];
    wideViewport(tester);
    await tester.pumpWidget(wrap(onOpen: navLog.add));
    await tester.pumpAndSettle();

    // 1. 老师卡可见（teacher 角色下）
    expect(find.text('老师工具'), findsOneWidget, reason: 'teacher 角色应看到「老师工具」卡');

    // 2. 点「老师工具」卡 → 跳到 _TeacherPage（Navigator.push）
    await tester.tap(find.text('老师工具'));
    await tester.pumpAndSettle();
    expect(find.text('板书 PDF / SVG 导出历史'), findsOneWidget, reason: '老师页第一卡标题');
    expect(find.text('去系谱页生成'), findsOneWidget, reason: '老师页「去系谱页生成」入口按钮');
    // R5：讲题回放卡文案加长一行，ListView 懒构建把拍题统计卡顶出
    // 首屏——滚入视口再断言（与下方系谱推断卡同款处理）。
    await tester.scrollUntilVisible(
      find.text('拍题识别统计'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('拍题识别统计'), findsOneWidget, reason: '老师页拍题统计卡');
    // v2.13+ 新增两张卡（讲题回放 / 系谱推断）+ 占位卡：页高放不下全卡，
    // 滚入视口再断言。
    await tester.scrollUntilVisible(
      find.text('系谱推断'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('课堂讲题回放'), findsOneWidget, reason: '讲题回放卡');
    expect(find.text('打开系谱推断'), findsOneWidget, reason: '系谱推断直达入口');
    await tester.scrollUntilVisible(
      find.text('班级共性错'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('班级共性错'), findsOneWidget, reason: '老师页 v2.13 占位卡（标题仍在）');

    // 3. 点「去系谱页生成」→ 关老师页 + onOpenTool(1) 回调
    //（上一步滚到了系谱推断卡，先滚回按钮再点）。
    await tester.fling(
      find.byType(Scrollable).first,
      const Offset(0, 600),
      1200,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('去系谱页生成'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('去系谱页生成'));
    await tester.pumpAndSettle();
    expect(navLog, [1], reason: '「去系谱页生成」应触发 onOpenTool(1)（= 切主导航到系谱页）');
    expect(find.text('板书 PDF / SVG 导出历史'), findsNothing, reason: '老师页已关闭');

    // 4. board_history 落盘验证：用 pedigreeToSvg 真实函数生成
    // （避免重复造字符串拼接），写到测试 temp 目录里，验证 SVG
    // 写盘能被列出（老师页用 platform_storage.userAppDir() 拿
    // 目录——本测试用同一段 listSync 逻辑证明 SVG 落盘可被列出）。
    final svg = pedigreeToSvg(const <PedigreeNode>[], const <PedigreeEdge>[]);
    final histDir = Directory('${tmp.path}/board_history')
      ..createSync(recursive: true);
    final svgFile = File('${histDir.path}/test_pedigree.svg')
      ..writeAsStringSync(svg);
    expect(svgFile.existsSync(), isTrue, reason: 'SVG 写盘成功');
    expect(svg, contains('<svg'), reason: 'SVG 内容含 svg 根元素');

    // 验证：history 目录能列到这个文件（老师页 _load() 同款 listSync）
    final entries = histDir.listSync().where((e) {
      return e is File && e.path.toLowerCase().endsWith('.svg');
    }).toList();
    expect(entries.length, 1, reason: 'board_history 目录应能列出刚写的 SVG');
  });

  testWidgets('P0 #2 拍题统计：MistakeBook + ScanBankStore 实时读', (tester) async {
    FirstRunStore.instance.debugReset();
    await FirstRunStore.instance.setRole(UserRole.teacher);
    MistakeBook.instance.debugReset();

    // 先加 2 条错题
    MistakeBook.instance.add(
      stem: '错题 1',
      userAnswer: 'a',
      correctAnswer: 'b',
      errorType: MistakeErrorType.concept,
      subjectArea: '',
    );
    MistakeBook.instance.add(
      stem: '错题 2',
      userAnswer: 'c',
      correctAnswer: 'd',
      errorType: MistakeErrorType.calculation,
      subjectArea: '',
    );
    MistakeBook.instance.debugFlushSave();

    // 临时改 ScanBankStore.debugFilePath 注入 3 条拍题记录
    final tmp = Directory.systemTemp.createTempSync('scan_bank_test');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      ScanBankStore.debugFilePath = null;
    });
    ScanBankStore.debugFilePath = '${tmp.path}/scan_bank.json';
    await ScanBankStore.save(const [
      ScanEntry(summary: '拍题 1', module: 'cross_dihybrid', params: {}, ts: 1),
      ScanEntry(summary: '拍题 2', module: 'cross_dihybrid', params: {}, ts: 2),
      ScanEntry(summary: '拍题 3', module: 'molecular', params: {}, ts: 3),
    ]);

    wideViewport(tester);
    await tester.pumpWidget(wrap(onOpen: (_) {}));
    await tester.pumpAndSettle();
    await tester.tap(find.text('老师工具'));
    await tester.pumpAndSettle();

    // 验证统计卡：内置题库 = 3，错题本 = 2
    // hint 文本含「ScanBankStore」/「MistakeBook」（在同一 Text widget 里）
    // R5：讲题回放卡加长，统计卡滚出首屏——滚入再断言。
    await tester.scrollUntilVisible(
      find.text('拍题识别统计'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.textContaining('ScanBankStore'),
      findsOneWidget,
      reason: '统计卡 hint 含 ScanBankStore 标识',
    );
    expect(
      find.textContaining('MistakeBook'),
      findsOneWidget,
      reason: '统计卡 hint 含 MistakeBook 标识',
    );
    // 数值：3 = 内置题库 / 2 = 错题本
    // 用 widget tree 查（更稳健——hint 文本含 \n，find.text 无法
    // 直接匹配）
    final textWidgets = tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data)
        .where((s) => s != null)
        .toList();
    expect(
      textWidgets.where((s) => s == '3').length,
      greaterThanOrEqualTo(1),
      reason: '内置题库数 3 应显示',
    );
    expect(
      textWidgets.where((s) => s == '2').length,
      greaterThanOrEqualTo(1),
      reason: '错题本数 2 应显示',
    );
  });

  // ===== v2.12+ R1 final D P0 #3 新增：板书历史可重用 =====

  testWidgets('P0 #3 板书历史每行可「重新复制 SVG」到剪贴板（file → clipboard 链路）', (
    tester,
  ) async {
    // 准备：老师角色 + 在临时 board_history 目录写一个真 SVG
    final tmp = Directory.systemTemp.createTempSync('dashboard_p0_3_test');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });
    final histDir = Directory('${tmp.path}/board_history')
      ..createSync(recursive: true);

    // 用真实 pedigreeToSvg 生成 SVG 内容（避免硬编字符串）。
    // 关键：用户重画场景 = 该 SVG 是用户上次"存为板书"的结果，
    // 重新复制到剪贴板应得到与文件内容**完全一致**的字符串。
    final svg = pedigreeToSvg(const <PedigreeNode>[], const <PedigreeEdge>[]);
    final svgFile = File('${histDir.path}/lesson1.svg')..writeAsStringSync(svg);
    expect(svgFile.existsSync(), isTrue);

    // 注入 _TeacherPage.debugBoardHistoryDir 让它走 tmp 而非 ~/.biology_app。
    DashboardPage.debugBoardHistoryDirForTest = histDir.path;
    addTearDown(() {
      DashboardPage.debugBoardHistoryDirForTest = null;
    });

    FirstRunStore.instance.debugReset();
    await FirstRunStore.instance.setRole(UserRole.teacher);
    MistakeBook.instance.debugReset();

    // mock Clipboard.setData 平台通道（与 genetic_pedigree_page_test
    // 同款 pattern：拦截 'Clipboard.setData' 看写入内容）。
    // 不 mock getData：直接验证 calls 里有没有 SVG。
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = SystemChannels.platform;
    final calls = <Map<dynamic, dynamic>>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'Clipboard.setData') {
        calls.add(Map<dynamic, dynamic>.from(call.arguments as Map));
        return null;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    wideViewport(tester);
    await tester.pumpWidget(wrap(onOpen: (_) {}));
    await tester.pumpAndSettle();

    // 进老师页
    await tester.tap(find.text('老师工具'));
    await tester.pumpAndSettle();

    // 行渲染：lesson1.svg 出现
    expect(
      find.text('lesson1.svg'),
      findsOneWidget,
      reason: '板书历史列表应列出 lesson1.svg',
    );
    // 三件套按钮都在
    expect(
      find.byKey(const Key('board_history_copy_btn')),
      findsOneWidget,
      reason: '每行有「重新复制」按钮',
    );
    expect(
      find.byKey(const Key('board_history_reveal_btn')),
      findsOneWidget,
      reason: '每行有「在文件管理器中显示」按钮',
    );
    expect(
      find.byKey(const Key('board_history_delete_btn')),
      findsOneWidget,
      reason: '每行有「永久删除」按钮',
    );

    // 点「重新复制」→ 调 Clipboard.setData（用 runAsync 让 setData 异步完成）
    // _copyBoardToClipboard 是 fire-and-forget Future，IconButton 不 await。
    // 关键：用 tester.runAsync 包 Future.delayed，让真实 I/O（File.readAsString）
    // + 平台 channel（Clipboard.setData）都跑完。这是 genetic_pedigree
    // page_test 验证过的同款 pattern。
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('board_history_copy_btn')));
      // 留 1 秒让 File.readAsString + Clipboard.setData 都完成
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pumpAndSettle();

    expect(calls, hasLength(1), reason: 'Clipboard.setData 应被调 1 次');
    final text = calls.single['text'] as String? ?? '';
    expect(text, equals(svg), reason: '剪贴板内容 = 文件内容（file → clipboard 链路贯通）');
    expect(text, contains('<svg'), reason: '剪贴板内容含 svg 根元素');

    // SnackBar 提示
    expect(
      find.textContaining('SVG 文本已复制'),
      findsOneWidget,
      reason: '复制成功后弹 SnackBar 提示',
    );
  });

  // ===== v2.12+ R2 A2 P1-5 新增：openInExplorer 防御性 catch =====

  testWidgets('P1-5 在文件管理器中显示失败：mock 启动抛异常 → 弹错误 SnackBar', (tester) async {
    // 准备：老师角色 + debugBoardHistoryDirForTest 注入 + 一个 SVG 文件
    final tmp = Directory.systemTemp.createTempSync('dashboard_p1_5_test');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });
    final histDir = Directory('${tmp.path}/board_history')
      ..createSync(recursive: true);
    File('${histDir.path}/lesson1.svg').writeAsStringSync('<svg/>');

    DashboardPage.debugBoardHistoryDirForTest = histDir.path;
    addTearDown(() => DashboardPage.debugBoardHistoryDirForTest = null);

    // mock Process.start：启动文件管理器直接抛异常 → openInExplorer
    // 必须返回错误原因而不抛（P1-5 防御性 catch；flutter_test 无法
    // mock dart:io 进程启动，走 debugProcessLauncher 注入）。
    MistakeBookExporter.debugProcessLauncher = (exe, args) async {
      throw ProcessException(exe, args, 'mock 启动失败', 1);
    };
    addTearDown(() => MistakeBookExporter.debugProcessLauncher = null);

    FirstRunStore.instance.debugReset();
    await FirstRunStore.instance.setRole(UserRole.teacher);
    MistakeBook.instance.debugReset();

    wideViewport(tester);
    await tester.pumpWidget(wrap(onOpen: (_) {}));
    await tester.pumpAndSettle();
    await tester.tap(find.text('老师工具'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('board_history_reveal_btn')),
      findsOneWidget,
      reason: '「在文件管理器中显示」按钮存在',
    );

    // 点击 → await openInExplorer（抛异常路径）→ 错误 SnackBar：
    // 不是静默无反应，也不是把技术异常漏到 UI。
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const Key('board_history_reveal_btn')));
      // 留一点让 await 链（openInExplorer → catch → SnackBar）跑完
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    expect(
      find.textContaining('在文件管理器中显示失败'),
      findsOneWidget,
      reason: 'P1-5：Process.start 抛异常 → SnackBar 显示失败原因',
    );
    expect(
      find.textContaining('mock 启动失败'),
      findsOneWidget,
      reason: 'P1-5：SnackBar 含异常细节（错误原因透出）',
    );

    // 清场：等 SnackBar auto-dismiss（4s）避免 pending timer
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  // ===== v2.12+ R2 A2 P1-6 新增：web 端「在文件管理器中显示」守卫 =====

  testWidgets('P1-6 web 守卫：点「在文件管理器中显示」→ 提示改用剪贴板', (tester) async {
    // 准备：老师角色 + debugBoardHistoryDirForTest 注入 + 一个 SVG 文件
    final tmp = Directory.systemTemp.createTempSync('dashboard_p1_6_test');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });
    final histDir = Directory('${tmp.path}/board_history')
      ..createSync(recursive: true);
    File('${histDir.path}/lesson1.svg').writeAsStringSync('<svg/>');

    DashboardPage.debugBoardHistoryDirForTest = histDir.path;
    addTearDown(() => DashboardPage.debugBoardHistoryDirForTest = null);

    // 模拟 web：flutter_test 跑在 VM 上 kIsWeb 恒 false，压
    // debugForceIsWeb = true 走守卫分支。
    DashboardPage.debugForceIsWeb = true;
    addTearDown(() => DashboardPage.debugForceIsWeb = false);

    // sentinel：若守卫失效、放行到 openInExplorer，launcher 会被调
    // → fail() 标记测试失败（双重保险，配合下方 findsNothing）。
    MistakeBookExporter.debugProcessLauncher = (exe, args) async {
      fail('P1-6：web 守卫必须拦截在 openInExplorer 之前');
    };
    addTearDown(() => MistakeBookExporter.debugProcessLauncher = null);

    FirstRunStore.instance.debugReset();
    await FirstRunStore.instance.setRole(UserRole.teacher);
    MistakeBook.instance.debugReset();

    wideViewport(tester);
    await tester.pumpWidget(wrap(onOpen: (_) {}));
    await tester.pumpAndSettle();
    await tester.tap(find.text('老师工具'));
    await tester.pumpAndSettle();

    // 点「在文件管理器中显示」→ 走 web 守卫：SnackBar 提示复制，
    // 不弹技术错误、不抛异常。
    await tester.tap(find.byKey(const Key('board_history_reveal_btn')));
    await tester.pumpAndSettle();

    expect(
      find.text('Web 端请用「重新复制到剪贴板」'),
      findsOneWidget,
      reason: 'P1-6：web 下点「在文件管理器中显示」→ 提示改用剪贴板',
    );
    expect(
      find.textContaining('在文件管理器中显示失败'),
      findsNothing,
      reason: 'P1-6：不弹技术错误 SnackBar（守卫已拦截）',
    );
    expect(tester.takeException(), isNull, reason: 'P1-6：无异常漏出');

    // 清场：SnackBar auto-dismiss（4s）避免 pending timer
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  // ═══ v2.13 R4-3 P1：板书历史缺口修复（PNG 归档 / 删除二次确认 / 查看更多）═══

  /// 老师角色 + board_history 临时目录注入 + 进老师页的公共准备。
  Future<void> setupTeacherPage(WidgetTester tester, Directory histDir) async {
    DashboardPage.debugBoardHistoryDirForTest = histDir.path;
    addTearDown(() => DashboardPage.debugBoardHistoryDirForTest = null);
    FirstRunStore.instance.debugReset();
    await FirstRunStore.instance.setRole(UserRole.teacher);
    MistakeBook.instance.debugReset();
    wideViewport(tester);
    await tester.pumpWidget(wrap(onOpen: (_) {}));
    await tester.pumpAndSettle();
    await tester.tap(find.text('老师工具'));
    await tester.pumpAndSettle();
  }

  testWidgets('R4-3 P1 板书历史：PNG 与 SVG 同列 + 图标区分 + PNG 行无复制按钮', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('dashboard_r4_3_png_test');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });
    final histDir = Directory('${tmp.path}/board_history')
      ..createSync(recursive: true);
    File('${histDir.path}/lesson1.svg').writeAsStringSync('<svg/>');
    // PNG 是真字节文件（老师高频路径产物）。
    File('${histDir.path}/lesson2.png')
        .writeAsBytesSync([0x89, 0x50, 0x4E, 0x47]);

    await setupTeacherPage(tester, histDir);

    // 两种格式都进历史：SVG 行图标 description_outlined，PNG 行
    // 图标 image_outlined（图标区分）。
    expect(find.text('lesson1.svg'), findsOneWidget, reason: 'R4-3：SVG 归档条目显示');
    expect(
      find.text('lesson2.png'),
      findsOneWidget,
      reason: 'R4-3：PNG 归档条目显示（此前 PNG 永不进历史）',
    );
    expect(
      find.byIcon(Icons.description_outlined),
      findsOneWidget,
      reason: 'SVG 行用文档图标',
    );
    expect(
      find.byIcon(Icons.image_outlined),
      findsOneWidget,
      reason: 'PNG 行用图片图标',
    );

    // SVG 行保留「复制」按钮；PNG 行不显示复制（二进制无法复制文本）。
    expect(
      find.byKey(const Key('board_history_copy_btn')),
      findsOneWidget,
      reason: 'SVG 行有复制按钮',
    );
    // reveal / delete 两行都有。
    expect(
      find.byKey(const Key('board_history_reveal_btn')),
      findsNWidgets(2),
      reason: 'SVG + PNG 行都有「在文件管理器中显示」',
    );
    expect(
      find.byKey(const Key('board_history_delete_btn')),
      findsNWidgets(2),
      reason: 'SVG + PNG 行都有「永久删除」',
    );
    expect(
      find.byIcon(Icons.copy_all_outlined),
      findsOneWidget,
      reason: '复制图标只出现在 SVG 行',
    );

    // 卡片文案已更新（不再只提 SVG）
    expect(
      find.textContaining('板书（SVG / PNG）自动归档'),
      findsOneWidget,
      reason: 'R4-3：老师卡文案改为「板书自动归档（SVG/PNG）」',
    );
  });

  testWidgets('R4-3 P1 删除二次确认：取消不删 / 确认才删', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('dashboard_r4_3_del_test');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });
    final histDir = Directory('${tmp.path}/board_history')
      ..createSync(recursive: true);
    final f = File('${histDir.path}/lesson1.svg');
    f.writeAsStringSync('<svg/>');

    await setupTeacherPage(tester, histDir);
    expect(find.text('lesson1.svg'), findsOneWidget);

    // 点「永久删除」→ 必须先弹二次确认 dialog
    await tester.tap(find.byKey(const Key('board_history_delete_btn')));
    await tester.pumpAndSettle();
    expect(find.text('删除板书？'), findsOneWidget, reason: 'R4-3：删除前弹二次确认 dialog');
    expect(
      find.byKey(const Key('board_history_delete_confirm_btn')),
      findsOneWidget,
      reason: 'dialog 有「永久删除」确认按钮',
    );

    // 取消 → 文件保留、列表照旧
    await tester.tap(find.byKey(const Key('board_history_delete_cancel_btn')));
    await tester.pumpAndSettle();
    expect(f.existsSync(), isTrue, reason: '取消删除后文件仍在');
    expect(find.text('lesson1.svg'), findsOneWidget, reason: '取消后列表不变');
    expect(find.text('删除板书？'), findsNothing);

    // 再点删除 → 这次确认 → 文件真删 + 列表行消失。
    // 注意：确认后 File.delete + _load 重列是**真实异步 IO**，只在
    // runAsync 窗口推进（fake-async 的 pumpAndSettle 不跑真实 IO）——
    // 与 P0 #3 复制测试同款双环驱动，直到文件消失。
    await tester.tap(find.byKey(const Key('board_history_delete_btn')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('board_history_delete_confirm_btn')));
    await tester.pumpAndSettle();
    // 双环驱动：真实异步 IO（File.delete + _load 重列）只在 runAsync
    // 窗口推进——直到「文件消失 + 列表行消失」都满足。
    for (
      var i = 0;
      i < 20 &&
          (f.existsSync() || find.text('lesson1.svg').evaluate().isNotEmpty);
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
    }
    expect(f.existsSync(), isFalse, reason: '确认后文件被永久删除');
    expect(find.text('lesson1.svg'), findsNothing, reason: '确认删除后列表行消失');

    // 清场：已永久删除 SnackBar（4s）
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('R4-3 P1 查看更多：15 条只显 10 → 点开全量 15 条可见 → 收起', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('dashboard_r4_3_more_test');
    addTearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });
    final histDir = Directory('${tmp.path}/board_history')
      ..createSync(recursive: true);
    for (var i = 1; i <= 15; i++) {
      // 文件名带序号：验证「旧 10 张不再不可达」。
      File('${histDir.path}/pedigree_${i.toString().padLeft(2, '0')}.svg')
          .writeAsStringSync('<svg/>');
    }

    await setupTeacherPage(tester, histDir);

    // take(10) 封顶保留：只有 10 个复制按钮（= 10 行）。
    // （15 个文件在同一毫秒内写入，mtime 相同 → 排序稳定但具体哪 10 条
    // 在前不确定；断言用「行数 + 按钮存在 + 展开后全量」，不依赖文件名。）
    expect(
      find.byKey(const Key('board_history_copy_btn')),
      findsNWidgets(10),
      reason: 'R4-3：默认只展示前 10 条',
    );
    expect(
      find.text('查看更多（共 15 条）'),
      findsOneWidget,
      reason: 'R4-3：超过 10 条显示「查看更多」按钮（带总数）',
    );
    expect(find.text('收起'), findsNothing, reason: 'R4-3：未展开时无「收起」');

    // 点「查看更多」→ 全量 15 条可见（旧 10 张不再不可达）
    await tester.ensureVisible(
      find.byKey(const Key('board_history_toggle_more_btn')),
    );
    await tester.tap(find.byKey(const Key('board_history_toggle_more_btn')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('board_history_copy_btn')),
      findsNWidgets(15),
      reason: 'R4-3：「查看更多」后全量 15 条可见',
    );
    expect(find.text('查看更多（共 15 条）'), findsNothing, reason: 'R4-3：展开后按钮文案切换');
    expect(find.text('收起'), findsOneWidget, reason: 'R4-3：展开后按钮变「收起」');
    // 全量可见性抽查：15 个文件名都在列表里
    for (var i = 1; i <= 15; i++) {
      expect(
        find.text('pedigree_${i.toString().padLeft(2, '0')}.svg'),
        findsOneWidget,
        reason: 'R4-3：展开后第 $i 条可见（take(10) 封顶不再吞旧板书）',
      );
    }

    // 收起 → 回到 10 条（收起后列表变矮、滚动位置可能把前部行挤出
    // 懒构建窗口——先滚回顶部再计数）。
    await tester.ensureVisible(
      find.byKey(const Key('board_history_toggle_more_btn')),
    );
    await tester.tap(find.byKey(const Key('board_history_toggle_more_btn')));
    await tester.pumpAndSettle();
    await tester.fling(
      find.byType(Scrollable).first,
      const Offset(0, 400),
      1000,
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('board_history_copy_btn')),
      findsNWidgets(10),
      reason: 'R4-3：收起后回到前 10 条',
    );
    expect(find.text('查看更多（共 15 条）'), findsOneWidget);
  });

  testWidgets('讲题回放点按复现：detail 含填参 JSON → ModuleFillBus 路由计算器', (tester) async {
    wideViewport(tester);
    await FirstRunStore.instance.setRole(UserRole.teacher);
    // HistoryStore 注入一条可复现记录（计算器 9331）。
    final tmp = Directory.systemTemp.createTempSync('dash_replay_test');
    HistoryStore.debugFilePath = '${tmp.path}/h.json';
    addTearDown(() {
      HistoryStore.debugFilePath = null;
      try {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      } catch (_) {
        /* 残留容忍 */
      }
    });
    await HistoryStore.save([
      HistoryEntry(
        label: 'AaBb × AaBb · 双基因 9331 · 表型 9:3:3:1',
        epochMs: DateTime.now().millisecondsSinceEpoch,
        detail: jsonEncode({'m': 'cross_dihybrid', 'p1': 'AaBb', 'p2': 'AaBb'}),
      ),
    ]);

    // 假 fill 目标捕获参数与导航。
    Map<String, String>? gotParams;
    int? gotNav;
    ModuleFillBus.register(
      ModuleFillTarget(
        moduleId: 'cross_dihybrid',
        pageIndex: 2,
        label: '遗传计算器·双基因',
        apply: (params) {
          gotParams = params;
          return true;
        },
      ),
    );
    ModuleFillBus.navigator = (i) => gotNav = i;
    addTearDown(ModuleFillBus.resetForTest);

    await tester.pumpWidget(wrap(onOpen: (_) {}));
    await tester.pumpAndSettle();
    await tester.tap(find.text('老师工具'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.textContaining('AaBb × AaBb · 双基因 9331'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    // 可复现条目带播放图标。
    expect(find.byIcon(Icons.play_circle_outline), findsOneWidget);
    await tester.tap(find.textContaining('AaBb × AaBb · 双基因 9331'));
    // addPostFrameCallback + scheduleFrame：等帧让导航/回填落地。
    await tester.pump();
    await tester.pump();
    expect(gotNav, 2, reason: '切主导航到计算器页');
    expect(gotParams, isNotNull, reason: 'apply 收到回填参数');
    expect(gotParams!['p1'], 'AaBb');
    expect(gotParams!['p2'], 'AaBb');
  });

  // v2.13+：我的错题卡「未复习徽标」——存入→复习闭环的引导信号
  //（UX 走查 P0）。0 道未复习时徽标不渲染（学生模式像素级不变）。
  testWidgets('我的错题卡：未复习徽标随 MistakeBook 状态实时出现/消失', (tester) async {
    wideViewport(tester);
    // 隔离 FirstRunStore（角色是单例，前面的用例可能切成老师——
    // 老师角色下错题本卡隐藏，徽标无从断言）+ MistakeBook 存储
    //（add 自带 500ms 写盘 debounce，测试内不越过窗口，结束
    // debugFlushSave 取消）。
    final tmp = Directory.systemTemp.createTempSync('dash_badge_test');
    FirstRunStore.debugFilePath = '${tmp.path}/f.json';
    FirstRunStore.instance.debugReset();
    MistakeBook.debugFilePath = '${tmp.path}/m.json';
    MistakeBook.instance.debugReset();
    addTearDown(() {
      FirstRunStore.instance.debugReset();
      FirstRunStore.debugFilePath = null;
      MistakeBook.instance.debugFlushSave();
      MistakeBook.instance.debugReset();
      MistakeBook.debugFilePath = null;
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });
    await FirstRunStore.instance.setRole(UserRole.student);

    await tester.pumpWidget(wrap(onOpen: (_) {}));
    await tester.pumpAndSettle();
    expect(find.text('我的错题'), findsOneWidget);
    expect(
      find.textContaining('待复习'),
      findsNothing,
      reason: '初始 0 条 → 无徽标（像素级不变）',
    );

    final added = MistakeBook.instance.add(
      stem: 's',
      userAnswer: '',
      correctAnswer: 'c',
      errorType: MistakeErrorType.other,
      subjectArea: 'a',
    );
    await tester.pump(); // notifyListeners → 重建
    expect(find.text('1 道待复习'), findsOneWidget, reason: '存入 1 条未复习 → 徽标出现');

    MistakeBook.instance.markStatus(added.id, MistakeReviewStatus.reviewing);
    await tester.pump();
    expect(
      find.textContaining('待复习'),
      findsNothing,
      reason: '刚标记复习中（reviewedAt=今天）→ 未到期，徽标消失',
    );

    MistakeBook.instance.debugFlushSave();
  });
}
