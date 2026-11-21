// tex_formula_test.dart —— TeX 教学公式共享组件（TexFormula）守卫网
//
// 网住组件的四条底线 + 实验页依赖：
//  ① 正常公式必须渲染成 flutter_math_fork 的 Math（真排版），回落文本
//     不出现；
//  ② 解析失败必须回落到人类可读公式且零异常（⛔ 不许崩）；
//  ③ 语义标签可读：显式 semanticsLabel 优先，缺省朗读 fallback；
//  ④ 390 窄屏长分式：局部横向滚动、整页零溢出、不缩放保命；
//  ⑤ 颜色：显式 color 生效；缺省跟随 AppColors.ink 的浅/深 token；
//  ⑥ 种群增长实验用到的 5 条核心 TeX 语法必须解析成功；
//  ⑦ 字形级守卫（防「AST 正确但 glyph 全 .notdef」）：装载 KaTeX 字体后，
//     公式依赖的 family 必须渲染真字形——只有 Math.ast 断言拦不住整屏方框。
import 'package:biology/theme.dart';
import 'package:biology/ui/tex_formula.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_fonts.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(1100, 800),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('正常公式：真排版，不是纯文本', () {
    testWidgets('渲染为 Math 组件（ast 非空、无解析错误），回落文本不出现', (tester) async {
      await _pump(
        tester,
        const TexFormula(
          tex: r'N_t = N_0\,\lambda^{t}',
          fallback: 'N_t = N₀·λᵗ',
        ),
      );

      expect(find.byType(TexFormula), findsOneWidget);
      final math = tester.widget<Math>(find.byType(Math));
      expect(math.parseError, isNull);
      expect(math.ast, isNotNull);
      expect(find.text('N_t = N₀·λᵗ'), findsNothing, reason: '解析成功时不得展示回落纯文本');
      expect(tester.takeException(), isNull);
    });
  });

  group('解析失败：回落人类可读公式，不崩', () {
    testWidgets('非法 TeX → 显示 fallback 文本，零异常', (tester) async {
      await _pump(
        tester,
        const TexFormula(
          tex: r'\frac{1', // 括号不闭合：必然解析失败
          fallback: 'dN/dt = r·N·(1 − N/K)',
        ),
      );

      expect(tester.takeException(), isNull, reason: '⛔ 解析失败不许崩');
      expect(
        find.text('dN/dt = r·N·(1 − N/K)'),
        findsOneWidget,
        reason: '必须回落到人类可读公式',
      );
    });
  });

  group('语义：屏幕阅读器读得懂', () {
    testWidgets('显式 semanticsLabel 优先；缺省朗读 fallback', (tester) async {
      // ⚠️ 句柄必须在测试体内 dispose：addTearDown 的回调晚于
      // binding 的 SemanticsHandle 校验，会被判「句柄泄漏」。
      final handle = tester.ensureSemantics();
      try {
        await _pump(
          tester,
          const Column(
            children: [
              TexFormula(
                tex: r'N_t = N_0\,\lambda^{t}',
                fallback: 'N_t = N₀·λᵗ',
                semanticsLabel: 'J 型通项：N 下标 t 等于 N 下标 0 乘 λ 的 t 次方',
              ),
              TexFormula(tex: r'\frac{dN}{dt} = rN', fallback: 'dN/dt = r·N'),
            ],
          ),
        );

        expect(
          find.bySemanticsLabel('J 型通项：N 下标 t 等于 N 下标 0 乘 λ 的 t 次方'),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel('dN/dt = r·N'),
          findsOneWidget,
          reason: '缺省语义标签 = fallback 公式',
        );
      } finally {
        handle.dispose();
      }
    });
  });

  group('390 窄屏：长分式局部横向滚动', () {
    testWidgets('局部滚动容器存在、整页零溢出、公式不被缩小', (tester) async {
      await _pump(
        tester,
        const TexFormula(
          tex:
              r'N_t = \frac{K}'
              r'{1 + \left(\frac{K}{N_0} - 1\right) e^{-r \cdot t}}',
          fallback: 'N_t = K ÷ [1 + (K/N₀ − 1)·e^(−r·t)]',
        ),
        size: const Size(390, 844),
      );

      expect(tester.takeException(), isNull, reason: '⛔ 整页不许溢出');
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is SingleChildScrollView &&
              w.scrollDirection == Axis.horizontal,
        ),
        findsOneWidget,
        reason: '溢出部分只在本行内横向滚动',
      );
      expect(
        find.descendant(
          of: find.byType(TexFormula),
          matching: find.byType(FittedBox),
        ),
        findsNothing,
        reason: '⛔ 不允许缩放保命（缩到看不清）',
      );

      final size = tester.getSize(find.byType(Math));
      expect(size.width, greaterThan(160), reason: '公式保持原生字号的可读宽度（不整体缩小）');
      expect(size.height, greaterThan(24), reason: '分式不得被压扁');
    });
  });

  group('颜色：显式参数与主题 token', () {
    testWidgets('显式 color 参数生效', (tester) async {
      await _pump(
        tester,
        const TexFormula(
          tex: r'a = b',
          fallback: 'a = b',
          color: Color(0xFFB91C1C),
        ),
      );
      expect(
        tester.widget<Math>(find.byType(Math)).textStyle?.color,
        const Color(0xFFB91C1C),
      );
    });

    testWidgets('缺省跟随 AppColors.ink：浅色 inkL / 深色 inkD', (tester) async {
      AppColors.debugClearOverride();
      addTearDown(AppColors.debugClearOverride);

      await _pump(tester, const TexFormula(tex: r'a = b', fallback: 'a = b'));
      expect(
        tester.widget<Math>(find.byType(Math)).textStyle?.color,
        AppColors.inkL,
        reason: '浅色下公式用 inkL',
      );

      AppColors.sync(Brightness.dark);
      await _pump(tester, const TexFormula(tex: r'a = b', fallback: 'a = b'));
      expect(
        tester.widget<Math>(find.byType(Math)).textStyle?.color,
        AppColors.inkD,
        reason: '深色下公式用 inkD（深底浅字）',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('种群增长实验的 5 条核心 TeX 语法', () {
    testWidgets('J 通式 / S 通式 / 绝对速率 / 相对增长率 / J 新增量全部解析成功', (tester) async {
      await _pump(
        tester,
        const Column(
          children: [
            TexFormula(tex: r'N_t = N_0\,\lambda^{t}', fallback: 'J 通式'),
            TexFormula(
              tex:
                  r'N_t = \frac{K}'
                  r'{1 + \left(\frac{K}{N_0} - 1\right) e^{-r \cdot t}}',
              fallback: 'S 通式',
            ),
            TexFormula(
              tex: r'\frac{dN}{dt} = rN\left(1 - \frac{N}{K}\right)',
              fallback: '绝对速率',
            ),
            TexFormula(
              tex:
                  r'\frac{1}{N}\,\frac{dN}{dt}'
                  r' = r\left(1 - \frac{N}{K}\right)',
              fallback: '相对增长率',
            ),
            TexFormula(
              tex: r'N_{t+1} - N_t = N_t\,(\lambda - 1)',
              fallback: 'J 新增量',
            ),
          ],
        ),
      );

      expect(find.byType(Math), findsNWidgets(5));
      for (final m in tester.widgetList<Math>(find.byType(Math))) {
        expect(m.parseError, isNull);
        expect(m.ast, isNotNull);
      }
      expect(find.text('J 通式'), findsNothing, reason: '解析成功 → 不显示任何 fallback');
      expect(tester.takeException(), isNull);
    });
  });

  group('字形级守卫（防「AST 正确但 glyph 全 .notdef」）', () {
    testWidgets('装载 KaTeX 字体后，公式 family 渲染真字形（像素比对，非 AST）', (tester) async {
      await loadGoldenFonts(); // katex=true（golden_fonts 默认）
      // 逐 family 像素比对：KaTeX_Main / KaTeX_Math 必须与「未注册对照」不同
      // ⇒ 真字形，不是 .notdef 方框。只有 Math.ast 断言拦不住整屏方框，
      // 这里补上字形级证据（见 golden_fonts.assertKatexGlyphsLoaded）。
      await assertKatexGlyphsLoaded(tester);

      // 装载字体后再渲染一条真实 S 通式：仍零异常、且不落回纯文本。
      await _pump(
        tester,
        const TexFormula(
          tex:
              r'N_t = \frac{K}'
              r'{1 + \left(\frac{K}{N_0} - 1\right) e^{-r \cdot t}}',
          fallback: 'S 通式回落',
        ),
      );
      expect(find.byType(Math), findsOneWidget);
      expect(find.text('S 通式回落'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
