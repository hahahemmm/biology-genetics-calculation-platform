// dna_engine_test.dart —— 分子遗传引擎回归（课标 3.1.2/3.1.3/3.1.4/3.2.1）
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/engine/dna_engine.dart';

void main() {
  group('DNA 碱基组成（3.1.2）', () {
    test('已知 A=30% → A=T=30 G=C=20', () {
      final r = dnaBaseComposition(a: 30);
      expect(r.a, closeTo(30, 1e-9));
      expect(r.t, closeTo(30, 1e-9));
      expect(r.g, closeTo(20, 1e-9));
      expect(r.c, closeTo(20, 1e-9));
    });

    test('已知 G=20% → 补全 A=T=30 G=C=20', () {
      final r = dnaBaseComposition(g: 20);
      expect(r.a, closeTo(30, 1e-9));
      expect(r.c, closeTo(20, 1e-9));
    });

    test('已知 A=30 T=30 → 补 G=C=20', () {
      final r = dnaBaseComposition(a: 30, t: 30);
      expect(r.g, closeTo(20, 1e-9));
      expect(r.c, closeTo(20, 1e-9));
    });

    test('已知 A=30 G=20 → 全组一致', () {
      final r = dnaBaseComposition(a: 30, g: 20);
      expect(r.t, closeTo(30, 1e-9));
      expect(r.c, closeTo(20, 1e-9));
    });

    test('违规配对 A≠T 抛 ArgumentError', () {
      expect(() => dnaBaseComposition(a: 30, t: 20),
          throwsArgumentError);
    });

    test('A+G≠50 抛 ArgumentError', () {
      expect(() => dnaBaseComposition(a: 40, t: 40, g: 20),
          throwsArgumentError);
    });

    test('空输入抛 ArgumentError', () {
      expect(() => dnaBaseComposition(), throwsArgumentError);
    });
  });

  group('DNA 半保留复制（3.1.3）', () {
    test('复制 3 次 → 8 个 DNA、2 个含亲代链、14 条新链', () {
      final r = dnaReplication(copies: 3);
      expect(r.dnaMolecules, 8);
      expect(r.withParentStrand, 2);
      expect(r.newStrands, 14);
    });

    test('复制 1 次 → 2 个 DNA、新链 2 条', () {
      final r = dnaReplication(copies: 1);
      expect(r.dnaMolecules, 2);
      expect(r.newStrands, 2);
    });

    test('copies=0 抛 ArgumentError', () {
      expect(() => dnaReplication(copies: 0), throwsArgumentError);
    });
  });

  group('基因表达 6:3:1（3.1.4）', () {
    test('100 氨基酸 → mRNA 300、基因 600', () {
      final r = geneExpression(aminoAcids: 100);
      expect(r.mrnaBases, 300);
      expect(r.geneBases, 600);
    });

    test('按 mRNA 碱基数反推', () {
      final r = geneExpression(mrnaBases: 300);
      expect(r.aminoAcids, 100);
      expect(r.geneBases, 600);
    });

    test('按基因碱基数反推', () {
      final r = geneExpression(geneBases: 600);
      expect(r.aminoAcids, 100);
      expect(r.mrnaBases, 300);
    });

    test('mRNA 非 3 倍数抛 ArgumentError', () {
      expect(() => geneExpression(mrnaBases: 100),
          throwsArgumentError);
    });
  });

  group('减数分裂配子种类（3.2.1）', () {
    test('2 对同源染色体 → 4 种配子', () {
      expect(gameteKinds(chromosomePairs: 2), 4);
    });

    test('n 对 → 2^n（n=3 → 8）', () {
      expect(gameteKinds(chromosomePairs: 3), 8);
    });

    test('n=0 抛 ArgumentError', () {
      expect(() => gameteKinds(chromosomePairs: 0),
          throwsArgumentError);
    });
  });
}