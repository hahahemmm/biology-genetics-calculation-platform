// dashboard_page_test.dart —— 首页结构 / 导航回调 / 响应式 / 角色分流
//
// v2.21.0 首页排版重做后，本文件从「9 项 3×3 网格」改为钉**分层版面**：
//
//   · 欢迎/状态区：大标题 + 精确定位语 + 使用模式 + 角色 chip
//   · 三核心工作区：系谱推断 / 9331 及变式 / 图谱浏览（桌面并列、手机全宽）
//   · 分组模块：计算工具 / 学习支持 / 系统与帮助
//     （宽屏紧凑双列；v2.22.0 起窄屏 <600 改单列，说明完整折行）
//
// v2.23.1：新增**像素探针回归**（RepaintBoundary.toImage 读原始 RGBA，
// 不落 golden 文件）——钉死「实色主卡的 hover / press / 键盘 focus 真正
// 画在实色之上」。此前实色填充误用 DecoratedBox（画在 ink feature 之下），
// 结构断言全绿但交互高亮全被盖住；纯 widget 树断言发现不了这类问题。
//
// 网格（GridView，旧版按显示名平铺 13 张同权卡）已删——旧的
// `gridCols(tester)` 断言随之失效，但**功能覆盖一条没删**：
//   · 全部入口仍然渲染（且每个入口恰好出现一次，核心卡不在分组里重复）；
//   · 点击仍走 onOpenTool 的导航索引 / customTap 的 Navigator.push；
//   · 角色过滤（老师隐藏错题本、显示老师工具）不变；
//   · 390 窄屏零溢出、深浅双模式零异常。

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:biology/pages/dashboard_page.dart';
import 'package:biology/state/first_run_store.dart';
import 'package:biology/theme.dart';
import 'package:biology/ui/module_surface.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
// v2.22.0：断言「说明没被人为省略号截断」需要读渲染层的
// RenderParagraph.didExceedMaxLines（material.dart 不导出该类型）。
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 学生角色的 12 个入口（核心 3 + 计算 5 + 学习 2 + 系统 2；错题本在
  // 学习组）。顺序按视觉顺序，便于断言「核心在前、分组在后」。
  // v2.22.0：套路卡撤下首页独立入口 ⇒ 学习组少一张（13 → 12）。
  const coreNames = ['遗传图谱计算', '遗传计算器', '知识图谱'];
  const computeNames = ['分子遗传', '进化·基因频率', '染色体倍性', '变异', '人类遗传病'];
  // v2.22.0：「套路卡」从首页撤下独立入口（改由 9331 结果页按 K / 错题本
  // 按需打开）⇒ 首页「学习支持」组不再有这张卡。
  const learnNames = ['课标体系', '我的错题'];
  const systemNames = ['设置', '关于'];
  // v2.23：主入口（遗传图谱计算）的卡面说明——取导航目录 dashboardDesc
  //（无 cardDesc 时回退 desc），窄屏断言用它定位主卡说明文字。
  const pedigreeDesc = '系谱推断 · 亲子代风险概率';

  Widget wrap({required void Function(int) onOpen}) =>
      MaterialApp(home: DashboardPage(onOpenTool: onOpen));

  /// 像素探针专用壳：整页套一层 RepaintBoundary（探针从它读原始 RGBA）。
  final probeBoundaryKey = GlobalKey();
  Widget wrapProbe({required void Function(int) onOpen}) => RepaintBoundary(
        key: probeBoundaryKey,
        child: MaterialApp(home: DashboardPage(onOpenTool: onOpen)),
      );

  setUp(() {
    // 角色是单例状态：每个用例都从「学生」起跑，不继承上一个用例。
    FirstRunStore.instance.debugReset();
  });

  void wideViewport(WidgetTester tester) {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// 把入口滚进视口（整页单一滚动容器，非懒加载）。
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
  }

  /// 离某个文字最近的 ModuleSurface 外壳（核心卡 / 分组各是一层薄壳）。
  Finder surfaceOf(String text) => find
      .ancestor(of: find.text(text), matching: find.byType(ModuleSurface))
      .first;

  /// 某个入口文字之上的 **Sage 实色填充**（v2.23 主入口）：_CoreCard 用
  /// Ink(decoration: BoxDecoration(color: AppColors.teal)) 满铺主卡
  /// （v2.23.1：必须是 Ink——填充注册为 ink feature，hover/focus/splash
  /// 才能叠画在其上；DecoratedBox 会盖住全部交互高亮）。
  /// 据此判定「哪张卡是实色主入口」，而非比对显示名。
  Finder tealFillOf(String text) => find.ancestor(
        of: find.text(text),
        matching: find.byWidgetPredicate(
          (w) =>
              w is Ink &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == AppColors.teal,
        ),
      );

  /// 像素探针（v2.23.1）：抓取整页 RepaintBoundary 的原始 RGBA，返回
  /// 全局坐标 [location] 处的像素色。不写 golden 文件——只做数值比较。
  ///
  /// ⚠️ toImage / toByteData 走真实引擎光栅化回调，在 widget test 的
  /// fake async zone 里永远等不到 Future 完成（会静默挂起整轮测试），
  /// 必须包进 [WidgetTester.runAsync] 跑真实异步。
  Future<Color> probeAt(WidgetTester tester, GlobalKey boundaryKey, Offset location) async {
    final raw = await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(boundaryKey),
      );
      final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final bytes = data!.buffer.asUint8List();
      final x = location.dx.floor();
      final y = location.dy.floor();
      final idx = (y * image.width + x) * 4;
      final color =
          Color.fromARGB(bytes[idx + 3], bytes[idx], bytes[idx + 1], bytes[idx + 2]);
      image.dispose();
      return color;
    });
    expect(raw, isNotNull, reason: '像素探针必须能读到 RGBA 数据（runAsync）');
    return raw!;
  }

  /// 两色的最大通道差（0–255）。用于「可见变化」判定：正常 ink 高亮
  /// （onTeal @0.06–0.12 叠 teal）产生 8+ 的通道差；边缘抗锯齿只有 1–2。
  /// 通道从 toARGB32 解码（Color.red/green/blue 在新 SDK 已废弃）。
  int maxChannelDelta(Color a, Color b) {
    final ia = a.toARGB32();
    final ib = b.toARGB32();
    int d(int shift) => (((ia >> shift) & 0xFF) - ((ib >> shift) & 0xFF)).abs();
    return math.max(d(16), math.max(d(8), d(0)));
  }

  testWidgets('分层版面：欢迎区 + 三核心工作区 + 三组模块，12 个入口各出现一次', (tester) async {
    wideViewport(tester);
    await FirstRunStore.instance.setRole(UserRole.student);
    await tester.pumpWidget(wrap(onOpen: (_) {}));
    await tester.pumpAndSettle();

    // —— 欢迎 / 状态区 ——
    expect(find.text('遗传计算工作台'), findsOneWidget, reason: '大标题（26px 层级）');
    expect(
      find.text('输入题目数据，直接算出结果——通用生物计算器'),
      findsOneWidget,
      reason: '精确定位语（老测试按这串字断言，勿改字）',
    );
    expect(
      find.byKey(const Key('dashboard_role_chip')),
      findsOneWidget,
      reason: '状态行里的角色 chip',
    );

    // —— 三核心工作区 ——
    expect(find.text('核心工作区'), findsOneWidget, reason: '核心区标题');
    for (final n in coreNames) {
      expect(find.text(n), findsOneWidget, reason: '核心卡「$n」应渲染');
    }

    // —— 分组模块 ——
    expect(find.text('计算工具'), findsOneWidget);
    expect(find.text('学习支持'), findsOneWidget);
    expect(find.text('系统与帮助'), findsOneWidget);
    for (final n in [...computeNames, ...learnNames, ...systemNames]) {
      expect(find.text(n), findsOneWidget, reason: '模块入口「$n」应渲染且不重复');
    }

    // 结构：3 张核心卡 + 3 个分组 = 6 个薄壳（不层层套卡）。
    expect(
      find.byType(ModuleSurface),
      findsNWidgets(6),
      reason: '薄壳数量 = 核心卡 3 + 分组 3，核心入口不得在分组里重复',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('桌面：三核心卡并列同一行，分组模块排在其下', (tester) async {
    wideViewport(tester);
    await FirstRunStore.instance.setRole(UserRole.student);
    await tester.pumpWidget(wrap(onOpen: (_) {}));
    await tester.pumpAndSettle();

    // 卡壳（不是卡内文字）对齐：说明文字行数不同会让文字在卡内垂直居中
    // 的起点不同，但三张卡的**外壳**必须同顶、同高（并列）。
    final a = tester.getRect(surfaceOf(coreNames[0]));
    final b = tester.getRect(surfaceOf(coreNames[1]));
    final c = tester.getRect(surfaceOf(coreNames[2]));
    expect(a.top, closeTo(b.top, 0.5), reason: '核心卡同一行（并列）');
    expect(b.top, closeTo(c.top, 0.5));
    expect(a.height, closeTo(b.height, 0.5), reason: '并列卡等高等高，不留参差');
    expect(b.height, closeTo(c.height, 0.5));
    expect(a.left, lessThan(b.left), reason: '按目录顺序从左到右');
    expect(b.left, lessThan(c.left));

    // 分组（计算工具）在三核心卡之下，且属于独立薄壳。
    final coreBottom = tester.getRect(find.text(coreNames[0])).bottom;
    final groupTop = tester.getRect(find.text('分子遗传')).top;
    expect(
      groupTop,
      greaterThan(coreBottom),
      reason: '分组模块排在核心工作区之后（层级：核心 → 分组）',
    );
    expect(
      find
          .ancestor(of: find.text('分子遗传'), matching: find.byType(ModuleSurface))
          .evaluate()
          .length,
      1,
      reason: '分组入口只嵌一层薄壳（不层层套卡）',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('核心工作区：遗传图谱计算 = Sage 实色主入口（onTeal 高对比），另两张核心卡保持浅色', (tester) async {
    wideViewport(tester);
    addTearDown(AppColors.debugClearOverride);
    AppColors.sync(Brightness.light);
    await FirstRunStore.instance.setRole(UserRole.student);
    await tester.pumpWidget(wrap(onOpen: (_) {}));
    await tester.pumpAndSettle();

    // 主入口 = 唯一一张有 Sage 实色满铺的核心卡。
    expect(
      tealFillOf(coreNames[0]),
      findsOneWidget,
      reason: '「遗传图谱计算」应是全页唯一 Sage 实色主入口',
    );
    expect(
      tealFillOf(coreNames[1]),
      findsNothing,
      reason: '「遗传计算器」保持浅色同族层次，不得第二块实色',
    );
    expect(
      tealFillOf(coreNames[2]),
      findsNothing,
      reason: '「知识图谱」保持浅色同族层次',
    );

    // onTeal 高对比：主入口标题走 onTeal；另两张走 ink。
    expect(
      tester.widget<Text>(find.text(coreNames[0])).style?.color,
      AppColors.onTeal,
      reason: '主入口标题用 onTeal（实色卡上高对比）',
    );
    expect(
      tester.widget<Text>(find.text(coreNames[1])).style?.color,
      AppColors.ink,
      reason: '非主入口标题保持 ink（浅色卡）',
    );

    // 「主入口」扫读小标只出现一次，且挂在主卡上。
    expect(find.text('主入口'), findsOneWidget, reason: '主入口小标唯一');
    expect(
      find
          .ancestor(of: find.text('主入口'), matching: tealFillOf(coreNames[0]))
          .evaluate()
          .isNotEmpty,
      isTrue,
      reason: '「主入口」小标应位于实色主卡内',
    );
    // v2.23.1（对比度复核）：小标必须是**透明底** + 不透明 onTeal 文字——
    // 原 onTeal@0.18 半透明底把文字对比度摊薄到 3.61:1（< AA 4.5）。
    final tagBox = tester.widget<Container>(
      find
          .ancestor(of: find.text('主入口'), matching: find.byType(Container))
          .first,
    );
    final tagDeco = tagBox.decoration! as BoxDecoration;
    expect(
      tagDeco.color,
      isNull,
      reason: '小标底色必须透明（对比度由不透明 onTeal 文字 × 卡面 teal 保证）',
    );
    expect(
      (tagDeco.border as Border).top.color,
      AppColors.onTeal,
      reason: '小标描边用不透明 onTeal（非文字元素 ≥3:1）',
    );

    // 主入口卡点击仍走 onOpenTool（导航索引 = 1 = 系谱页），行为不变。
    final got = <int>[];
    await tester.pumpWidget(wrap(onOpen: got.add));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text(coreNames[0]));
    await tester.tap(find.text(coreNames[0]));
    await tester.pumpAndSettle();
    expect(got, [1], reason: '主入口「遗传图谱计算」点击 → onOpenTool(1)');

    expect(tester.takeException(), isNull);
  });

  testWidgets('390 窄屏：主入口卡全宽实色铺满、说明折行、零溢出', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(AppColors.debugClearOverride);
    AppColors.sync(Brightness.light);
    await FirstRunStore.instance.setRole(UserRole.student);
    await tester.pumpWidget(wrap(onOpen: (_) {}));
    await tester.pumpAndSettle();

    // 主入口卡全宽（390 − 左右各 16 = 358，含 1px 边框）且实色仍在。
    expect(
      tester.getSize(surfaceOf(coreNames[0])).width,
      358,
      reason: '窄屏主入口卡应全宽',
    );
    expect(tealFillOf(coreNames[0]), findsOneWidget, reason: '窄屏仍为实色主入口');

    // 主入口说明不被人为截断（完整折行）。
    final primaryDesc = tester.widget<Text>(
      find.descendant(
        of: surfaceOf(coreNames[0]),
        matching: find.text(pedigreeDesc),
      ),
    );
    final para = tester.renderObject<RenderParagraph>(
      find.descendant(
        of: surfaceOf(coreNames[0]),
        matching: find.text(pedigreeDesc),
      ),
    );
    expect(primaryDesc.maxLines, anyOf(isNull, 2));
    expect(para.didExceedMaxLines, isFalse, reason: '主入口说明在 390 下不被截断');

    expect(tester.takeException(), isNull, reason: '390 窄屏主入口零溢出');
  });

  // ===== v2.23.1 像素探针回归（DeepSeek 复核 FAIL 修复） =====
  //
  // 复核实测：实色填充若用 DecoratedBox（画在 ink feature 之下），
  // hover 只剩边缘 6px / maxΔ2、focus 为 0——结构断言全绿也发现不了。
  // 这里用 RepaintBoundary.toImage 读真实像素：主卡 hover / press /
  // 传统键盘 focus 都必须产生**可见**通道差，并保留一张透明对照卡
  // 验证同一手势在普通卡上也有效（排除「手势没送达」的假阳性）。

  testWidgets(
    '像素回归：主卡 hover / press / 键盘 focus 均产生可见变化，透明对照卡同步有效',
    (tester) async {
    wideViewport(tester);
    addTearDown(AppColors.debugClearOverride);
    AppColors.sync(Brightness.light);
    await FirstRunStore.instance.setRole(UserRole.student);
    await tester.pumpWidget(wrapProbe(onOpen: (_) {}));
    await tester.pumpAndSettle();

    // 取主卡内部一个「纯填充」探针点：卡中心偏下（避开标题/说明文字与
    // 图标块，落在 teal 实色区）。
    final primaryRect = tester.getRect(surfaceOf(coreNames[0]));
    final probe = Offset(primaryRect.center.dx, primaryRect.bottom - 10);
    // 透明对照卡：同排第二张核心卡的对应点。
    final plainRect = tester.getRect(surfaceOf(coreNames[1]));
    final plainProbe = Offset(plainRect.center.dx, plainRect.bottom - 10);

    // —— 基线：主卡探针点 = Sage 实色（像素证据，不只是 widget 树断言）——
    final baseline = await probeAt(tester, probeBoundaryKey, probe);
    expect(
      maxChannelDelta(baseline, AppColors.teal),
      lessThan(3),
      reason: '主卡探针点应为纯 teal 实色（基线）',
    );

    // —— hover：鼠标悬停主卡 → 实色之上出现可见 hover 反馈 ——
    final hover = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await hover.addPointer(location: Offset.zero);
    addTearDown(hover.removePointer);
    await hover.moveTo(probe);
    await tester.pumpAndSettle();
    final hoverColor = await probeAt(tester, probeBoundaryKey, probe);
    expect(
      maxChannelDelta(hoverColor, baseline),
      greaterThan(6),
      reason: '主卡 hover 必须在实色之上产生可见变化（修复前仅边缘 6px/maxΔ2）',
    );

    // 对照：同一 hover 手势移到透明普通卡 → 也应有可见变化。若这里
    // 不变而主卡变（或反之），说明手势/探针失效，主卡断言不可信。
    final plainBaseline = await probeAt(tester, probeBoundaryKey, plainProbe);
    await hover.moveTo(plainProbe);
    await tester.pumpAndSettle();
    final plainHover = await probeAt(tester, probeBoundaryKey, plainProbe);
    expect(
      maxChannelDelta(plainHover, plainBaseline),
      greaterThan(6),
      reason: '透明对照卡 hover 也应可见（排除手势未送达的假阳性）',
    );

    // —— press：按下主卡 → splash/highlight 叠画在实色上 ——
    await hover.moveTo(Offset.zero); // 移开 hover，隔离 press 变化
    await tester.pumpAndSettle();
    final down = await tester.startGesture(probe);
    // 按下高亮由 tap recognizer 的 deadline Timer（kPressTimeout）在帧中
    // 途触发创建，controller 从 0 起淡入——单帧 pump(350ms) 只会渲染到
    // 「已创建但 opacity=0」的那一帧（实测 delta=0）。必须再给一帧让
    // 淡入推进（与 hover 用 pumpAndSettle 同理），否则误报「不可见」。
    await tester.pump();
    await tester.pumpAndSettle();
    final pressColor = await probeAt(tester, probeBoundaryKey, probe);
    expect(
      maxChannelDelta(pressColor, baseline),
      greaterThan(6),
      reason: '主卡按下反馈必须在实色之上可见',
    );
    await down.up();
    await tester.pumpAndSettle();

    // —— 传统键盘 focus：Tab 遍历至主卡 → focusColor 可见 ——
    // InkResponse 内建 Focus 节点（未传 focusNode 时自建），Tab 可达。
    final inkWellOfPrimary = find.descendant(
      of: surfaceOf(coreNames[0]),
      matching: find.byType(InkWell),
    );
    var focused = false;
    for (var i = 0; i < 12 && !focused; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      final node = FocusManager.instance.primaryFocus;
      final ctx = node?.context;
      if (ctx is Element) {
        final iw = ctx.findAncestorWidgetOfExactType<InkWell>();
        final cardIW = tester.widget<InkWell>(inkWellOfPrimary);
        focused = identical(iw, cardIW);
      }
    }
    expect(
      focused,
      isTrue,
      reason: '键盘 Tab 应能聚焦主卡（InkWell 内建 Focus 节点）',
    );
    final focusColor = await probeAt(tester, probeBoundaryKey, probe);
    expect(
      maxChannelDelta(focusColor, baseline),
      greaterThan(6),
      reason: '主卡键盘 focus 高亮必须在实色之上可见（修复前为 0）',
    );

    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('像素回归：深色模式主卡实色为深色 Sage 且对比不退化', (tester) async {
    wideViewport(tester);
    addTearDown(AppColors.debugClearOverride);
    AppColors.sync(Brightness.dark);
    await FirstRunStore.instance.setRole(UserRole.student);
    await tester.pumpWidget(wrapProbe(onOpen: (_) {}));
    await tester.pumpAndSettle();

    final primaryRect = tester.getRect(surfaceOf(coreNames[0]));
    final probe = Offset(primaryRect.center.dx, primaryRect.bottom - 10);
    final baseline = await probeAt(tester, probeBoundaryKey, probe);
    expect(
      maxChannelDelta(baseline, AppColors.teal),
      lessThan(3),
      reason: '深色模式主卡填充 = 深色 Sage token（tealD，随主题换肤）',
    );

    // hover 在深色实色上同样可见（onTeal 为近黑，叠在浅 Sage 上）。
    final hover = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await hover.addPointer(location: Offset.zero);
    addTearDown(hover.removePointer);
    await hover.moveTo(probe);
    await tester.pumpAndSettle();
    final hoverColor = await probeAt(tester, probeBoundaryKey, probe);
    expect(
      maxChannelDelta(hoverColor, baseline),
      greaterThan(6),
      reason: '深色模式主卡 hover 也必须可见（不退化）',
    );
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(minutes: 2)));

  testWidgets('对比度：主卡标题/说明/小标 对实色底 ≥ WCAG AA（深浅双模式）', (tester) async {
    // 纯计算断言（相对亮度公式），不依赖渲染环境。
    double luminance(Color c) {
      final argb = c.toARGB32();
      double ch(int shift) {
        var v = ((argb >> shift) & 0xFF) / 255.0;
        return v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
      }
      return 0.2126 * ch(16) + 0.7152 * ch(8) + 0.0722 * ch(0);
    }

    double contrast(Color a, Color b) {
      final la = luminance(a);
      final lb = luminance(b);
      return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
    }

    addTearDown(AppColors.debugClearOverride);
    for (final brightness in [Brightness.light, Brightness.dark]) {
      AppColors.sync(brightness);
      final ratio = contrast(AppColors.onTeal, AppColors.teal);
      expect(
        ratio,
        greaterThanOrEqualTo(4.5),
        reason: '${brightness == Brightness.light ? '浅色' : '深色'}：'
            'onTeal（标题/说明/小标文字与描边）对 teal 实底需 ≥ AA 4.5:1，'
            '实际 ${ratio.toStringAsFixed(2)}:1',
      );
    }
  });

  // ===== v2.23.2 投影复核回归（M3.1 golden FAIL） =====
  //
  // 正式投影 golden（proj_1280/1920，课堂 ×1.75）暴露两个布局缺陷：
  //   1) 主入口标题被 _PrimaryTag 挤压 →「遗传图…/遗传图谱…」省略号；
  //   2) 1280 内容右缘滑进全局「问 AI」FAB 柱 → 压住
  //      「Hardy-Weinberg 与选择逐代模拟」末字。
  // 这里不录 golden（视觉代理负责重录），只钉**几何/排版断言**。

  /// 复刻 HomeShell 的投影几何：左 Rail 占位（课堂 104+分隔线 1）+
  /// 右下 FAB 列（拍题 small + 问 AI extended，endFloat 默认边距 16）。
  /// DashboardPage 在 Expanded 里看到的可用宽度与真实 App 一致。
  Widget wrapProjected({required void Function(int) onOpen}) => MaterialApp(
        home: MediaQuery(
          // 课堂大字号：正文 ×1.75（present_mode_controller 投影门槛）。
          data: const MediaQueryData(textScaler: TextScaler.linear(1.75)),
          child: Scaffold(
            body: Row(
              children: [
                const SizedBox(width: 104),
                const VerticalDivider(width: 1),
                Expanded(child: DashboardPage(onOpenTool: onOpen)),
              ],
            ),
            floatingActionButton: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton.small(
                  onPressed: () {},
                  child: const Icon(Icons.photo_camera_outlined),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.extended(
                  onPressed: () {},
                  icon: const Icon(Icons.psychology_outlined),
                  label: const Text('问 AI'),
                ),
              ],
            ),
          ),
        ),
      );

  for (final size in const [Size(1280, 720), Size(1920, 1080)]) {
    final label = size.width.toInt().toString();
    testWidgets('投影 $label ×1.75：主入口标题完整（无省略号、允许 2 行）', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(AppColors.debugClearOverride);
      AppColors.sync(Brightness.light);
      await FirstRunStore.instance.setRole(UserRole.student);
      await tester.pumpWidget(wrapProjected(onOpen: (_) {}));
      await tester.pumpAndSettle();

      // 主入口标题必须**完整渲染**：didExceedMaxLines=false 即未触发
      // ellipsis（maxLines:2 允许换行，不允许截断）。
      final para = tester.renderObject<RenderParagraph>(
        find.text(coreNames[0]),
      );
      expect(
        para.didExceedMaxLines,
        isFalse,
        reason: '投影 $label ×1.75：「${coreNames[0]}」不得被省略号截断'
            '（此前 Row+Flexible(maxLines:1) 被 _PrimaryTag 挤成「遗传图…」）',
      );
      // 「主入口」小标仍在（修标题不许以隐藏小标为代价）。
      expect(find.text('主入口'), findsOneWidget, reason: '小标必须保留');

      // 另两张核心卡标题同样完整。
      for (final n in [coreNames[1], coreNames[2]]) {
        final p = tester.renderObject<RenderParagraph>(find.text(n));
        expect(p.didExceedMaxLines, isFalse, reason: '「$n」不得被截断');
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('投影 1280 ×1.75：首页任何说明文字不得与问 AI FAB 相交', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(AppColors.debugClearOverride);
    AppColors.sync(Brightness.light);
    await FirstRunStore.instance.setRole(UserRole.student);
    await tester.pumpWidget(wrapProjected(onOpen: (_) {}));
    await tester.pumpAndSettle();

    // FAB 柱 = 拍题 small + 问 AI extended（与 HomeShell 同几何）。
    final fabRects = <Rect>[
      for (final el in find.byType(FloatingActionButton).evaluate())
        () {
          final box = el.renderObject as RenderBox;
          return box.localToGlobal(Offset.zero) & box.size;
        }(),
    ];
    expect(fabRects, hasLength(2), reason: 'FAB 列应在场（拍题 + 问 AI）');

    // 首屏所有可见文字矩形与 FAB 柱零相交（此前 Hardy-Weinberg 末字
    // 被 FAB 左缘压住）。滚出视口的文字不参与（其矩形已在视口外）。
    final offenders = <String>[];
    final viewRect = Offset.zero & const Size(1280, 720);
    for (final el in find
        .descendant(
          of: find.byType(DashboardPage),
          matching: find.byType(Text),
        )
        .evaluate()) {
      final box = el.renderObject;
      if (box is! RenderBox || !box.hasSize) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (!viewRect.overlaps(rect)) continue; // 只查首屏可见文字
      for (final fab in fabRects) {
        if (rect.overlaps(fab)) {
          offenders.add('${(el.widget as Text).data} $rect ∩ FAB $fab');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason: '1280 投影首页文字不得被问 AI FAB 覆盖：\n'
          '${offenders.join('\n')}',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('非投影宽屏（1440×900 ×1.0）：FAB 净空不推移内容（零回归）', (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await FirstRunStore.instance.setRole(UserRole.student);
    await tester.pumpWidget(wrap(onOpen: (_) {}));
    await tester.pumpAndSettle();

    // 1440 ×1.0：freeRight = 24+(1440-48-1040)/2 = 176 > fabZone 136
    // ⇒ 自然净空足够，fabRightPad=0，滚动容器左右对称、内容不被推移
    //（对应 golden 复核里「1400/1440 正常」的档位）。
    final scroll = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView).first,
    );
    final pad = (scroll.padding! as EdgeInsets);
    expect(
      pad.right,
      pad.left,
      reason: '1440 常规桌面不得因 FAB 净空产生不对称推移',
    );
    expect(
      tester.getSize(surfaceOf(coreNames[0])).width,
      greaterThan(300),
      reason: '核心卡宽度不受净空挤压',
    );
  });

  testWidgets('点击入口触发 onOpenTool 回调（携带导航索引）', (tester) async {
    wideViewport(tester);
    await FirstRunStore.instance.setRole(UserRole.student);
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

    // v2.19.25（老用户 P2-5）：插入后续位索引映射零断言缺口补上。
    // v2.22.0：套路卡撤下首页独立入口 ⇒ 这一段改为点「设置」（导航索引 11）。
    await scrollTo(tester, find.text('设置'));
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    expect(got, [5, 7, 11], reason: '设置移到导航末位 = index 11（v2.19.60）');

    await scrollTo(tester, find.text('关于'));
    await tester.tap(find.text('关于'));
    await tester.pumpAndSettle();
    expect(got, [5, 7, 11, 12], reason: '关于移到导航末位 = index 12（v2.19.60）');
  });

  testWidgets('390 窄屏：核心卡全宽、分组紧凑双列、零溢出、末项可达', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await FirstRunStore.instance.setRole(UserRole.student);
    await tester.pumpWidget(wrap(onOpen: (_) {}));
    await tester.pumpAndSettle();

    // 核心卡全宽：390 − 左右各 16 的页面 padding = 358（薄壳含 1px 边框）。
    expect(
      tester.getSize(surfaceOf(coreNames[0])).width,
      358,
      reason: '手机核心卡应全宽，不与其它卡并列',
    );
    expect(tester.getSize(surfaceOf(coreNames[1])).width, 358);

    // v2.22.0：窄屏（<600）分组入口改**单列**——同组入口纵向堆叠，
    // 左缘对齐一致（不再是同一行左右分列）。
    final left = tester.getRect(find.text('分子遗传'));
    final right = tester.getRect(find.text('进化·基因频率'));
    expect(right.top, greaterThan(left.bottom),
        reason: '窄屏分组入口单列纵向排列（不再同一行左右分列）');
    expect(left.left, closeTo(right.left, 0.5), reason: '单列入口左缘对齐一致');
    expect(right.right, lessThanOrEqualTo(390 - 16), reason: '不越出页面 padding');

    expect(tester.takeException(), isNull, reason: '首帧无溢出');
    // 末项（关于）仍可达：整页一个滚动容器，非懒加载。
    await scrollTo(tester, find.text('关于'));
    expect(find.text('关于'), findsOneWidget, reason: '底部「关于」入口应存在');
    expect(tester.takeException(), isNull, reason: '滚到底部无溢出');
  });

  testWidgets('390 窄屏：分组入口单列，说明完整折行不被人为省略号截断',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await FirstRunStore.instance.setRole(UserRole.student);
    await tester.pumpWidget(wrap(onOpen: (_) {}));
    await tester.pumpAndSettle();

    // 两条**原被截断**的说明（双列时各只剩 ~160px 宽）：
    //   '碱基互补 / 两链互推 / DNA 标记' → 曾显示为「碱基互补 / 两链…」
    //   'Hardy-Weinberg 与选择逐代模拟' → 曾显示为「Hardy-Weinber…」
    const descs = <String>[
      '碱基互补 / 两链互推 / DNA 标记',
      'Hardy-Weinberg 与选择逐代模拟',
    ];
    for (final desc in descs) {
      final f = find.text(desc);
      expect(f, findsOneWidget, reason: '说明「$desc」应完整渲染在屏上');
      final text = tester.widget<Text>(f);
      expect(text.maxLines, isNull,
          reason: '窄屏单列不限行数（说明须完整折行，不得限 1 行）');
      expect(text.overflow, isNot(TextOverflow.ellipsis),
          reason: '窄屏单列不得用省略号截断说明');
      // 渲染层证据：段落没有超出最大行数（= 没被截断）。
      final para = tester.renderObject<RenderParagraph>(f);
      expect(para.didExceedMaxLines, isFalse,
          reason: '说明「$desc」在 390 宽下被截断了（应完整折行可读）');
    }

    // 单列后说明确实换行了（不是仍被压在一行里放不下）。
    final descText = tester.getRect(find.text(descs.first));
    expect(descText.height, greaterThan(16.0),
        reason: '说明文字应按内容折行（高度大于单行）');

    expect(tester.takeException(), isNull, reason: '390 窄屏单列零溢出');

    // ── 宽屏不变：分组仍是紧凑双列，说明仍是单行省略号 ──────────
    // 这条同时证明上面的断言有鉴别力（窄屏单列 ⇒ 不截断；
    // 宽屏双列 ⇒ 照旧截断），也钉住「桌面双列与分组不变」。
    tester.view.physicalSize = const Size(1200, 900);
    await tester.pumpAndSettle();
    final wideLeft = tester.getRect(find.text('分子遗传'));
    final wideRight = tester.getRect(find.text('进化·基因频率'));
    expect(wideLeft.top, closeTo(wideRight.top, 0.5),
        reason: '宽屏分组仍是同一行左右分列（本次只改窄屏）');
    expect(wideLeft.left, lessThan(wideRight.left));
    final wideDesc = tester.widget<Text>(find.text(descs.first));
    expect(wideDesc.maxLines, 1, reason: '宽屏双列仍是一行说明');
    expect(wideDesc.overflow, TextOverflow.ellipsis);
    expect(tester.takeException(), isNull, reason: '宽屏零溢出');
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
    expect(find.text('核心工作区'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '深色模式无异常');
  });

  // ===== v2.12 Wave 3-B 新增：role chip + 角色分流 =====

  testWidgets('role chip 显示：状态行 ActionChip 展示当前角色 + 切换入口', (tester) async {
    wideViewport(tester);
    // 角色未选：chip 显示"未选择"
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

  testWidgets('teacher 角色隐藏错题本入口、显示老师工具；student 角色相反', (tester) async {
    wideViewport(tester);

    // 1. teacher 角色：错题本入口隐藏 + 老师工具入口出现
    await FirstRunStore.instance.setRole(UserRole.teacher);
    await tester.pumpWidget(wrap(onOpen: (_) {}));
    await tester.pumpAndSettle();
    expect(
      find.text('我的错题'),
      findsNothing,
      reason: 'teacher 角色不应看到「我的错题」入口（错题本是学生私人空间）',
    );
    expect(find.text('老师工具'), findsOneWidget, reason: 'teacher 角色应看到「老师工具」入口');
    // 主卡仍渲染
    expect(find.text('遗传图谱计算'), findsOneWidget);

    // 2. student 角色：错题本入口出现、老师工具隐藏
    await FirstRunStore.instance.setRole(UserRole.student);
    await tester.pumpAndSettle();
    expect(find.text('我的错题'), findsOneWidget, reason: 'student 角色应看到「我的错题」入口');
    expect(find.text('老师工具'), findsNothing, reason: 'student 角色不应看到老师工作流入口');
  });
}
