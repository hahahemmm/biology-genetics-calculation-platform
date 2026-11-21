// sex_linked_test.dart —— 伴性遗传引擎单元测试
//
// 验证经典伴 X 隐性（红绿色盲）杂交的精确分数结果。

import 'package:biology/engine/fraction.dart';
import 'package:biology/engine/sex_linked_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final engine = SexLinkedEngine();

  group('基因型解析', () {
    test('雌性合法形式', () {
      expect(SexLinkedEngine.parseGenotype('XAXa', expectFemale: true),
          ['A', 'a']);
      expect(SexLinkedEngine.parseGenotype('xaxa', expectFemale: true),
          ['a', 'a']);
    });

    test('雄性合法形式', () {
      expect(SexLinkedEngine.parseGenotype('XaY', expectFemale: false), ['a']);
      expect(SexLinkedEngine.parseGenotype('XAY', expectFemale: false), ['A']);
    });

    test('非法形式抛 ArgumentError', () {
      expect(() => SexLinkedEngine.parseGenotype('Aa', expectFemale: true),
          throwsArgumentError);
      expect(() => SexLinkedEngine.parseGenotype('XAXA', expectFemale: false),
          throwsArgumentError);
      expect(() => SexLinkedEngine.parseGenotype('XAXb', expectFemale: true),
          throwsArgumentError);
    });

    test('标准化：隐性在前自动排为显性在前', () {
      expect(SexLinkedEngine.normalizeFemale('XaXA'), 'XAXa');
      expect(SexLinkedEngine.normalizeMale('xaY'.toUpperCase()), 'XAY');
    });
  });

  group('配子生成', () {
    test('杂合雌性产两种配子各 1/2', () {
      final g = SexLinkedEngine.femaleGametes('XAXa');
      expect(g['XA'], Fraction.half);
      expect(g['Xa'], Fraction.half);
    });

    test('纯合雌性只产一种配子', () {
      final g = SexLinkedEngine.femaleGametes('XAXA');
      expect(g.length, 1);
      expect(g['XA'], Fraction.one);
    });

    test('雄性配子 X 与 Y 各 1/2', () {
      final g = SexLinkedEngine.maleGametes('XaY');
      expect(g['Xa'], Fraction.half);
      expect(g['Y'], Fraction.half);
    });
  });

  group('经典杂交：携带者母亲 × 正常父亲（XAXa × XAY）', () {
    final r = SexLinkedEngine().cross('XAXa', 'XAY');

    test('子代基因型 1:1:1:1', () {
      expect(r.offspring.length, 4);
      for (final o in r.offspring) {
        expect(o.probability, Fraction(1, 4), reason: o.genotype);
      }
    });

    test('女儿全部正常（条件概率）', () {
      final d = r.phenotypeGivenSex('雌性');
      expect(d['显性'], Fraction.one);
      expect(d.containsKey('隐性'), isFalse);
    });

    test('儿子 1/2 患病（交叉遗传核心结论）', () {
      final s = r.phenotypeGivenSex('雄性');
      expect(s['显性'], Fraction.half);
      expect(s['隐性'], Fraction.half);
    });
  });

  group('患病母亲 × 正常父亲（XaXa × XAY）', () {
    final r = SexLinkedEngine().cross('XaXa', 'XAY');

    test('女儿全部携带但正常，儿子全部患病', () {
      final d = r.phenotypeGivenSex('雌性');
      final s = r.phenotypeGivenSex('雄性');
      expect(d['显性'], Fraction.one);
      expect(s['隐性'], Fraction.one);
    });

    test('子代仅两种基因型各 1/2', () {
      expect(r.offspring.length, 2);
      final genotypes = r.offspring.map((o) => o.genotype).toSet();
      expect(genotypes, {'XAXa', 'XaY'});
    });
  });

  group('携带者母亲 × 患病父亲（XAXa × XaY）', () {
    final r = SexLinkedEngine().cross('XAXa', 'XaY');

    test('儿女各 1/2 患病', () {
      expect(r.phenotypeGivenSex('雌性')['隐性'], Fraction.half);
      expect(r.phenotypeGivenSex('雄性')['隐性'], Fraction.half);
    });
  });

  group('正常纯合母亲 × 患病父亲（XAXA × XaY）', () {
    final r = SexLinkedEngine().cross('XAXA', 'XaY');

    test('全部子代正常', () {
      final all = r.phenotypeBySex;
      expect(all['雌性·显性'], Fraction.half);
      expect(all['雄性·显性'], Fraction.half);
      expect(all.containsKey('雌性·隐性'), isFalse);
      expect(all.containsKey('雄性·隐性'), isFalse);
    });
  });

  test('概率总和为 1', () {
    for (final p in SexLinkedEngine.presets) {
      final r = engine.cross(p.female, p.male);
      final total =
          r.offspring.fold(Fraction.zero, (s, o) => s + o.probability);
      expect(total, Fraction.one, reason: p.name);
    }
  });
}
