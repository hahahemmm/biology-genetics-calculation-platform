// 限制酶切实验视觉基线：真实 AppTheme.light + 中文/等宽字体。
// 新增或更新后必须逐张目检，不得整批接受。

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
    expect(find.textContaining('长度核算：3 + 9 + 7 = 19 bp'), findsOneWidget);
  }

  testWidgets('桌面：限制酶切输入与结果双工作区', (tester) async {
    await boot(tester, const Size(1440, 1000));
    await expectLater(
      find.byType(MolecularPage),
      matchesGoldenFile('goldens/restriction_lab_desktop.png'),
    );
    await tester.ensureVisible(find.text('双链切点示意'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MolecularPage),
      matchesGoldenFile('goldens/restriction_lab_desktop_sketch.png'),
    );
  });

  testWidgets('深色：限制酶切输入、序列与结果保持对比', (tester) async {
    await boot(tester, const Size(1440, 1000), dark: true);
    await expectLater(
      find.byType(MolecularPage),
      matchesGoldenFile('goldens/restriction_lab_dark.png'),
    );
  });

  testWidgets('手机：限制酶切页签与结果可达且无溢出', (tester) async {
    await boot(tester, const Size(390, 844));
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(MolecularPage),
      matchesGoldenFile('goldens/restriction_lab_mobile.png'),
    );
  });
}
