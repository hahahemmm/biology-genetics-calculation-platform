// PCR 与电泳实验视觉基线：真实 AppTheme.light/dark + 中文/等宽字体。
// 本文件**只**产出 PCR 的新基线（pcr_lab_*.png）；限制酶切的既有基线
// 不在这里更新。新增或更新后必须逐张目检，不得整批接受。

import 'package:biology/pages/molecular_page.dart';
import 'package:biology/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'golden_fonts.dart';

void main() {
  Future<void> boot(
    WidgetTester tester,
    Size size, {
    bool dark = false,
  }) async {
    await loadGoldenFonts();
    assertMaterialIconsLoaded();
    assertMonoLoaded();
    AppColors.sync(dark ? Brightness.dark : Brightness.light);
    addTearDown(() => AppColors.sync(Brightness.light));
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? AppTheme.dark() : AppTheme.light(),
        home: const MolecularPage(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('基因工程'));
    await tester.tap(find.text('基因工程'));
    await tester.pumpAndSettle();
    // 第 5 页签默认是限制酶切 ⇒ 先切到 PCR 与电泳
    await tester.ensureVisible(find.text('PCR 与电泳'));
    await tester.tap(find.text('PCR 与电泳'));
    await tester.pumpAndSettle();
    expect(find.text('样品 64 bp'), findsOneWidget,
        reason: 'PCR 默认例必须已经算出结果（否则拍的是空屏）');
  }

  testWidgets('桌面：PCR 输入与结果双工作区', (tester) async {
    await boot(tester, const Size(1440, 1000));
    await expectLater(
      find.byType(MolecularPage),
      matchesGoldenFile('goldens/pcr_lab_desktop.png'),
    );
  });

  testWidgets('桌面：凝胶示意的 marker 刻度与样品条带', (tester) async {
    await boot(tester, const Size(1440, 1000));
    await tester.ensureVisible(find.text('凝胶电泳示意'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MolecularPage),
      matchesGoldenFile('goldens/pcr_lab_gel.png'),
    );
  });

  testWidgets('深色：PCR 结果与凝胶保持对比', (tester) async {
    await boot(tester, const Size(1440, 1000), dark: true);
    await tester.ensureVisible(find.text('凝胶电泳示意'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MolecularPage),
      matchesGoldenFile('goldens/pcr_lab_dark.png'),
    );
  });

  testWidgets('手机：PCR 选择器与结果可达且无溢出', (tester) async {
    await boot(tester, const Size(390, 844));
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MolecularPage),
      matchesGoldenFile('goldens/pcr_lab_mobile.png'),
    );
  });

  testWidgets('手机：390 宽下的产物序列与凝胶示意', (tester) async {
    await boot(tester, const Size(390, 844));
    await tester.ensureVisible(find.text('凝胶电泳示意'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MolecularPage),
      matchesGoldenFile('goldens/pcr_lab_mobile_gel.png'),
    );
  });
}
