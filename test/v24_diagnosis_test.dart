// v24_diagnosis_test.dart —— 错因诊断引擎（v2.4 功能 3）
import 'package:biology/engine/error_diagnosis.dart';
import 'package:biology/pages/cross_calculator_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final diag = ErrorDiagnosis();

  test('学生答对但未约分 → 提示规范书写', () {
    final r = diag.diagnose(
        p1: 'AaBb', p2: 'AaBb', correctText: '9:3:3:1', studentText: '18:6:6:2');
    expect(r.studentCorrect, isTrue);
    expect(r.causes.single, contains('未约分'));
  });

  test('两对题答 3:1 → 漏算第二对基因', () {
    final r = diag.diagnose(
        p1: 'AaBb', p2: 'AaBb', correctText: '9:3:3:1', studentText: '3:1');
    expect(r.studentCorrect, isFalse);
    expect(r.causes.any((c) => c.contains('只按一对基因算')), isTrue);
  });

  test('9331 题答 9:7 → 误套变式', () {
    final r = diag.diagnose(
        p1: 'AaBb', p2: 'AaBb', correctText: '9:3:3:1', studentText: '9:7');
    expect(r.causes.any((c) => c.contains('误套')), isTrue);
  });

  test('一对题答 1:2:1 → 基因型比当表型比', () {
    final r = diag.diagnose(
        p1: 'Aa', p2: 'Aa', correctText: '3:1', studentText: '1:2:1');
    expect(r.causes.any((c) => c.contains('基因型比当成表型比')), isTrue);
  });

  test('Aa 自交答 1:1 → 测交自交混淆', () {
    final r = diag.diagnose(
        p1: 'Aa', p2: 'Aa', correctText: '3:1', studentText: '1:1');
    expect(r.causes.any((c) => c.contains('测交与自交混淆')), isTrue);
  });

  test('引擎计算与题面答案一致校验', () {
    final r = diag.diagnose(
        p1: 'AaBb', p2: 'AaBb', correctText: '9:3:3:1', studentText: '9:3:3:1');
    expect(r.correctMatchesEngine, isTrue);
    expect(r.computedRatio, '9:3:3:1');
  });

  test('总份数不对 → 份数体系错误提示（致死先扣再换算）', () {
    final r = diag.diagnose(
        p1: 'AaBb', p2: 'aabb', correctText: '1:1:1:1', studentText: '2:1:1:1');
    expect(r.causes.any((c) => c.contains('份数体系')), isTrue);
  });

  test('未知错误模式 → 分步重算兜底建议', () {
    final r = diag.diagnose(
        p1: 'AaBb', p2: 'AaBb', correctText: '9:3:3:1', studentText: '2:3:4:7');
    expect(r.causes.last, contains('分步重算'));
  });

  testWidgets('9331 错因诊断卡：学生答 3:1 → 提示漏算第二对基因',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: CrossCalculatorPage()));
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('错因诊断（学生答错时）'),
      140,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    // 默认亲本 AaBb×AaBb、正解 9:3:3:1；填学生答案 3:1
    await tester.enterText(
        find.widgetWithText(TextField, '学生答案比（如 3:1）'), '3:1');
    await tester.tap(find.text('诊断错因'));
    await tester.pump();
    expect(find.textContaining('只按一对基因算'), findsOneWidget);
  });
}
