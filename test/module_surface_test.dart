// module_surface_test.dart —— v2.21.0 ModuleSurface 薄壳契约
//
// 这个组件只做排版（Surface + 细边框 + 14 圆角 + 标题层级），但它承担了
// 两条**结构性**承诺，坏了会静默毁掉页面：
//
//   1. 无标题时**不套 Column**。调用方把 TabBarView / InteractiveViewer /
//      SizedBox.expand 这类有界画布塞进来时，多包一层 Column 会让高度
//      约束从「有界」变「无界」——TabBarView 直接崩（"RenderBox was not
//      laid out" / 无限高度），画布的命中区域与缩放语义也会变。
//   2. fillRemaining 只把「有标题 + 需要占满剩余高度」的输入区撑开，
//      且撑开后仍是有界高度（Expanded 在 Column 内、Column 在父约束内）。
//
// 另外钉住「颜色在 build 期读取、调用方不得 const 缓存」：换肤后同一个
// 薄壳必须立刻取新 token（v2.19.20 / v2.2 白字事故的根因就是 const 实例
// 被 canonicalize → Element identical 短路 → 首帧色值永久冻结）。

import 'package:biology/state/present_mode_controller.dart';
import 'package:biology/theme.dart';
import 'package:biology/ui/module_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 宿主：固定 300×200 的有界盒子（模拟工作台里的一块面板）。
///
/// ⚠ 宿主每次调用都新建实例、**不用 const**——这正是被测纪律
///（调用方不得 const 缓存薄壳）。
Widget host(Widget child, {double width = 300, double height = 200}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(width: width, height: height, child: child),
      ),
    ),
  );
}

/// 薄壳根容器的填充色（ModuleSurface.build 的第一个 Container）。
Color? surfaceFill(WidgetTester tester) {
  final box = tester.widget<Container>(
    find
        .descendant(
          of: find.byType(ModuleSurface),
          matching: find.byType(Container),
        )
        .first,
  );
  final deco = box.decoration;
  return deco is BoxDecoration ? deco.color : null;
}

/// 薄壳标题下的发丝线渐变（有标题路径里唯一带 gradient 的 Container，
/// 按结构特征定位而不是写死下标）。
LinearGradient hairlineGradient(WidgetTester tester) {
  for (final box in tester.widgetList<Container>(
    find.descendant(
      of: find.byType(ModuleSurface),
      matching: find.byType(Container),
    ),
  )) {
    final deco = box.decoration;
    if (deco is BoxDecoration && deco.gradient is LinearGradient) {
      return deco.gradient! as LinearGradient;
    }
  }
  fail('未找到发丝线渐变 Container（有标题路径应有 1px 发丝线）');
}

void main() {
  testWidgets('无标题：子内容不被 Column 包裹，直接吃满内边距后的盒子', (tester) async {
    await tester.pumpWidget(
      host(
        ModuleSurface(
          // 有界画布的最小替身：SizedBox.expand 只有拿到确定高度才不报错，
          // 一旦被塞进 Column（无界高度）就会当场炸。
          child: const SizedBox.expand(key: Key('canvas')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1) 结构：没有标题 ⇒ 薄壳内部不得出现任何 Column。
    expect(
      find.descendant(
        of: find.byType(ModuleSurface),
        matching: find.byType(Column),
      ),
      findsNothing,
      reason: '无标题时不得套 Column——TabBarView / 画布需要保持原尺寸与命中语义',
    );
    // 2) 几何：300×200 − 默认 padding 20×2 − 边框 1×2 = 258×158。
    expect(
      tester.getSize(find.byKey(const Key('canvas'))),
      const Size(258, 158),
      reason: '子内容应恰好等于「盒子 − padding − 1px 边框」，不被额外包裹改变',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('有标题：标题层 + 发丝线 + 内容，fillRemaining 子内容有界且吃掉剩余高度', (tester) async {
    await tester.pumpWidget(
      host(
        ModuleSurface(
          title: '计算输入',
          icon: Icons.tune,
          fillRemaining: true,
          child: Container(key: const Key('fill')),
        ),
        height: 300,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('计算输入'), findsOneWidget);
    expect(find.byIcon(Icons.tune), findsOneWidget);

    // v2.23 标题结构契约（显式数值，不许用动态 headerH 让变化隐身）：
    // 简洁 19px 图标 + 8px 间距 + 16px 标题（height 1.3）——无底瓦，
    // tealWash 瓦对 surface 仅 ~1.2:1 几乎不可见却抬高标题行（M3.1 复核）。
    expect(tester.getSize(find.byIcon(Icons.tune)).width, 19,
        reason: '简洁 19px 图标，不套 26px 底瓦');
    final iconRight = tester.getRect(find.byIcon(Icons.tune)).right;
    final titleLeft = tester.getRect(find.text('计算输入')).left;
    expect(titleLeft - iconRight, 8, reason: '图标与标题间距 8px');

    final fill = tester.getSize(find.byKey(const Key('fill')));
    // 宽度：300 − 20×2 padding − 1×2 边框 = 258。
    expect(fill.width, 258);

    // 标题行高 = 标题文字 16 × 行高 1.3 = 20.8，引擎排版取整 21
    //（图标 19 不抬行）。
    final headerH = tester
        .getSize(
          find
              .descendant(
                of: find.byType(ModuleSurface),
                matching: find.byType(Row),
              )
              .first,
        )
        .height;
    expect(headerH, closeTo(21, 0.1),
        reason: '标题行 = 16 × 1.3 取整 21——显式契约，'
            '改字号/行高/图标尺寸必须有意识地改这里');
    // 高度：300 − 边框 2 − padding 40 − 标题行 21 − (12 + 发丝线 1 + 14)。
    expect(
      fill.height,
      closeTo(210, 0.5),
      reason: 'fillRemaining 的 Expanded 必须拿到有界高度（而不是无限高）',
    );
    expect(fill.height, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('fillRemaining=false：文档流不强制撑满（长内容不被压成视口高）', (tester) async {
    await tester.pumpWidget(
      host(
        ModuleSurface(
          title: '文档',
          child: const SizedBox(key: Key('doc'), width: 100, height: 40),
        ),
        height: 300,
      ),
    );
    await tester.pumpAndSettle();

    // 内容是 40 高 ⇒ 就是 40 高，不会被 Expanded 拉成剩余高度。
    expect(
      tester.getSize(find.byKey(const Key('doc'))).height,
      40,
      reason: '文档流不应被撑成视口高度（fillRemaining 默认 false）',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('token 切换：换肤后立刻取新色（不得 const 缓存实例）', (tester) async {
    addTearDown(() => AppColors.sync(Brightness.light));
    AppColors.sync(Brightness.light);
    final lightSurface = AppColors.surface;

    await tester.pumpWidget(
      host(ModuleSurface(child: const SizedBox.shrink())),
    );
    await tester.pumpAndSettle();
    expect(surfaceFill(tester), lightSurface, reason: '浅色：surface token');

    // 切深色：真实链路由 main.dart 每帧 sync + 主题 rebuild 触发；这里
    // 直接 sync 并重建同一棵树（薄壳必须重新读 token）。
    AppColors.sync(Brightness.dark);
    final darkSurface = AppColors.surface;
    expect(darkSurface, isNot(lightSurface), reason: '前提：深浅 surface 不同');

    await tester.pumpWidget(
      host(ModuleSurface(child: const SizedBox.shrink())),
    );
    await tester.pumpAndSettle();
    expect(
      surfaceFill(tester),
      darkSurface,
      reason: '换肤后薄壳必须取新 token——const 缓存会让色值永久冻结',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('发丝线三档契约：标准/深色淡出不归零，高对比投影整条不透明', (tester) async {
    addTearDown(AppColors.debugClearOverride);
    addTearDown(
        () => PresentModeController.instance.debugSetHighContrast(false));

    Future<LinearGradient> pumpHairline() async {
      await tester.pumpWidget(
        host(ModuleSurface(title: '计算输入', child: const SizedBox.shrink())),
      );
      await tester.pumpAndSettle();
      return hairlineGradient(tester);
    }

    // 1) 标准浅色：左实右淡出，但右端 alpha 0.4 **不归零**——右端 alpha=0
    //    会让整条线在高对比投影（泛白）下消失（M3.1 复核）。
    AppColors.sync(Brightness.light);
    PresentModeController.instance.debugSetHighContrast(false);
    var g = await pumpHairline();
    expect(g.colors.first, AppColors.border, reason: '起点 = border token 实色');
    expect(g.colors.first.a, 1.0);
    expect(g.colors.last.a, 0.4,
        reason: '右端保留少量可见性，不得 alpha=0 完全消失');

    // 2) 深色：同一形状，token 换 borderD（深浅各自取 token，不写死色）。
    AppColors.sync(Brightness.dark);
    g = await pumpHairline();
    expect(g.colors.first, AppColors.borderD);
    expect(g.colors.last.a, 0.4, reason: '深色同样淡出不归零');

    // 3) 高对比（浅色投影）：整条不透明，明显强于标准档的 0.4。
    AppColors.sync(Brightness.light);
    PresentModeController.instance.debugSetHighContrast(true);
    g = await pumpHairline();
    expect(g.colors.first.a, 1.0);
    expect(g.colors.last.a, 1.0,
        reason: '高对比投影下淡出端会整条消失 ⇒ 必须不透明');
    expect(g.colors.first, AppColors.borderHcL,
        reason: '高对比档必须吃 borderHcL（投影加深两档的结构线）');
    expect(tester.takeException(), isNull);
  });
}
