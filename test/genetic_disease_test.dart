// genetic_disease_test.dart —— 遗传病引擎回归（课标 3.3.6）
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/engine/genetic_disease_engine.dart';

void main() {
  test('常隐：Aa × Aa → 患病 1/4、携带 1/2', () {
    final r = mendelianRisk(father: 'Aa', mother: 'Aa', mode: 'rec');
    expect(r.affectedRate, closeTo(0.25, 1e-9));
    expect(r.carrierRate, closeTo(0.5, 1e-9));
    expect(r.offspring['aa'], closeTo(0.25, 1e-9));
  });

  test('常隐：Aa × aa → 患病 1/2', () {
    final r = mendelianRisk(father: 'Aa', mother: 'aa', mode: 'rec');
    expect(r.affectedRate, closeTo(0.5, 1e-9));
  });

  test('常显：Aa × aa → 患病 1/2（杂合即患）', () {
    final r = mendelianRisk(father: 'Aa', mother: 'aa', mode: 'dom');
    expect(r.affectedRate, closeTo(0.5, 1e-9));
    expect(r.carrierRate, closeTo(0, 1e-9));
  });

  test('常显：AA × aa → 患病 1（后代全 Aa）', () {
    final r = mendelianRisk(father: 'AA', mother: 'aa', mode: 'dom');
    expect(r.affectedRate, closeTo(1, 1e-9));
  });

  test('伴X隐（色盲）：XAY × XAXa → 子女患病 1/4', () {
    final r = mendelianRisk(father: 'XAY', mother: 'XAXa', mode: 'rec');
    // XA/Y × XA/Xa → XAXA XAXa XAY XaY：男 1/4 患病（XaY）
    expect(r.affectedRate, closeTo(0.25, 1e-9));
  });

  test('伴X隐：XAY × XaXa → 男全患、女全携带 → 患病 1/2', () {
    final r = mendelianRisk(father: 'XAY', mother: 'XaXa', mode: 'rec');
    expect(r.affectedRate, closeTo(0.5, 1e-9));
  });

  group('伴X隐·携带者口径（v2.19.36 病灶回归）', () {
    test('XAY × XAXa → 携带者恰 1/4（只有 XAXa；XAXA 纯合显性不是携带者）',
        () {
      final r = mendelianRisk(father: 'XAY', mother: 'XAXa', mode: 'rec');
      // XA/Y × XA/Xa → XAXA(1/4) XAXa(1/4) XAY(1/4) XaY(1/4)
      expect(r.affectedRate, closeTo(0.25, 1e-9)); // 仅 XaY
      expect(r.carrierRate, closeTo(0.25, 1e-9),
          reason: '旧判据把 XAXA 也算进来会得 1/2 —— 正是「携带者 50%」'
              '假话的出处（备份仓 v2.19.163 同款病灶，已照其诊断修正）');
      expect(r.offspring['XAXA'], closeTo(0.25, 1e-9));
      expect(r.offspring['XAXa'], closeTo(0.25, 1e-9));
    });

    test('XaY × XAXa → 携带者恰 1/4（XAXa；患病 XaXa/XaY 不算携带）', () {
      final r = mendelianRisk(father: 'XaY', mother: 'XAXa', mode: 'rec');
      // 女：XAXa(1/4 携带) XaXa(1/4 患病)；男：XAY(1/4) XaY(1/4 患病)
      expect(r.affectedRate, closeTo(0.5, 1e-9));
      expect(r.carrierRate, closeTo(0.25, 1e-9));
    });

    test('XAY × XAXA → 携带者 0（女儿全 XAXA 纯合显性——旧码此处印 50%）',
        () {
      final r = mendelianRisk(father: 'XAY', mother: 'XAXA', mode: 'rec');
      expect(r.affectedRate, closeTo(0, 1e-9));
      expect(r.carrierRate, closeTo(0, 1e-9),
          reason: '纯病灶形态：旧判据 any(!=a) 对 XAXA 为真 ⇒ 携带者 1/2');
    });
  });

  test('分类速查：6 类和典型病种齐全', () {
    expect(diseaseCatalog.length, 6);
    final names = diseaseCatalog.map((d) => d.name).toList();
    expect(names, contains('伴 X 隐性'));
    expect(
        diseaseCatalog
            .firstWhere((d) => d.name == '伴 X 隐性')
            .examples,
        contains('红绿色盲'));
    expect(
        diseaseCatalog
            .firstWhere((d) => d.name == '染色体异常遗传病')
            .examples,
        contains('21 三体综合征'));
  });

  test('非法输入抛 ArgumentError', () {
    expect(() => mendelianRisk(father: 'A1', mother: 'Aa', mode: 'rec'),
        throwsArgumentError);
    expect(() => mendelianRisk(father: 'Aa', mother: 'Aa', mode: 'xx'),
        throwsArgumentError);
    expect(() => mendelianRisk(father: '', mother: 'Aa', mode: 'rec'),
        throwsArgumentError);
  });
}