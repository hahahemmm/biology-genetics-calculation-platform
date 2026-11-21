// linkage_test.dart —— 连锁互换引擎单元测试
//
// 验证精确分数结果：完全连锁、r=1/5 测交 4:4:1:1、r=1/2 等价自由组合，
// 以及任意组合下概率总和恒为 1。

import 'package:biology/engine/fraction.dart';
import 'package:biology/engine/linkage_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final engine = LinkageEngine();

  group('连锁基因型解析', () {
    test('合法形式', () {
      expect(engine.parseParent('AB/ab').label, 'AB/ab');
      expect(engine.parseParent('Ab/aB').label, 'Ab/aB');
      expect(engine.parseParent('ABC/abc').label, 'ABC/abc');
    });

    test('非法形式抛 ArgumentError', () {
      expect(() => engine.parseParent('ABAB'), throwsArgumentError); // 无斜杠
      expect(() => engine.parseParent('Aa/bb'), throwsArgumentError); // 位点字母不配
      expect(() => engine.parseParent('AB/ab/c'), throwsArgumentError); // 三段
      expect(() => engine.parseParent('A/a'), throwsArgumentError); // 单位点
    });

    test('位点字母提取', () {
      expect(engine.parseParent('Ab/aB').loci, ['A', 'B']);
    });
  });

  group('交换值解析', () {
    test('三种写法等价', () {
      expect(engine.parseRecombination('20%'), Fraction(1, 5));
      expect(engine.parseRecombination('1/5'), Fraction(1, 5));
      expect(engine.parseRecombination('0.2'), Fraction(1, 5));
    });

    test('边界值', () {
      expect(engine.parseRecombination('0'), Fraction.zero);
      expect(engine.parseRecombination('0.5'), Fraction.half);
      expect(engine.parseRecombination('50%'), Fraction.half);
    });

    test('超范围或格式错抛 ArgumentError', () {
      expect(() => engine.parseRecombination('0.6'), throwsArgumentError);
      expect(() => engine.parseRecombination('60%'), throwsArgumentError);
      expect(() => engine.parseRecombination('-0.1'), throwsArgumentError);
      expect(() => engine.parseRecombination('abc'), throwsArgumentError);
    });
  });

  group('配子分布', () {
    test('完全连锁 r=0：只产亲本型，各 1/2', () {
      final p = engine.parseParent('AB/ab');
      final g = engine.gametesOf(p, Fraction.zero);
      expect(g.length, 2);
      expect(g['AB'], Fraction.half);
      expect(g['ab'], Fraction.half);
    });

    test('r=1/5：亲本型各 2/5，重组型各 1/10', () {
      final p = engine.parseParent('AB/ab');
      final g = engine.gametesOf(p, Fraction(1, 5));
      expect(g['AB'], Fraction(2, 5));
      expect(g['ab'], Fraction(2, 5));
      expect(g['Ab'], Fraction(1, 10));
      expect(g['aB'], Fraction(1, 10));
    });

    test('r=1/2：四种配子各 1/4（等价自由组合）', () {
      final p = engine.parseParent('Ab/aB');
      final g = engine.gametesOf(p, Fraction.half);
      expect(g['Ab'], Fraction(1, 4));
      expect(g['aB'], Fraction(1, 4));
      expect(g['AB'], Fraction(1, 4));
      expect(g['ab'], Fraction(1, 4));
    });
  });

  group('测交 AB/ab × ab/ab，r=1/5', () {
    final r = LinkageEngine().cross('AB/ab', 'ab/ab', '1/5');

    test('子代基因型 2:2:1:1', () {
      expect(r.offspring['AB/ab'], Fraction(2, 5));
      expect(r.offspring['ab/ab'], Fraction(2, 5));
      expect(r.offspring['Ab/ab'], Fraction(1, 10));
      expect(r.offspring['aB/ab'], Fraction(1, 10));
    });

    test('表型分布：显显 2/5、隐隐 2/5、显隐/隐显各 1/10', () {
      expect(r.phenotypes['A显 B显'], Fraction(2, 5));
      expect(r.phenotypes['A隐 B隐'], Fraction(2, 5));
      expect(r.phenotypes['A显 B隐'], Fraction(1, 10));
      expect(r.phenotypes['A隐 B显'], Fraction(1, 10));
    });

    test('表型整数比为 {4,4,1,1}', () {
      expect(r.phenotypeRatio.toSet(), {1, 4});
      expect(r.phenotypeRatio.fold(0, (a, b) => a + b), 10);
      expect(r.phenotypeRatio.where((v) => v == 4).length, 2);
    });

    test('实测交换值等于输入 r', () {
      expect(r.observedRecombination, Fraction(1, 5));
    });
  });

  group('特殊情形', () {
    test('完全连锁测交：后代 1:1', () {
      final r = engine.cross('AB/ab', 'ab/ab', '0');
      expect(r.offspring.length, 2);
      expect(r.observedRecombination, Fraction.zero);
      expect(r.phenotypeRatio.toSet(), {1});
    });

    test('r=1/2 测交：四种表型各 1/4', () {
      final r = engine.cross('AB/ab', 'ab/ab', '1/2');
      expect(r.phenotypes.length, 4);
      for (final v in r.phenotypes.values) {
        expect(v, Fraction(1, 4));
      }
    });

    test('相斥相 Ab/aB 亲本型是 Ab、aB', () {
      final r = engine.cross('Ab/aB', 'ab/ab', '1/5');
      // 亲本型配子 Ab、aB 各占 2/5 → Ab/ab、aB/ab 各 2/5
      expect(r.offspring['Ab/ab'], Fraction(2, 5));
      expect(r.offspring['aB/ab'], Fraction(2, 5));
      expect(r.offspring['AB/ab'], Fraction(1, 10));
      expect(r.offspring['ab/ab'], Fraction(1, 10));
    });

    test('双亲位点字母不一致抛 ArgumentError', () {
      expect(() => engine.cross('AB/ab', 'cd/cd', '0.2'),
          throwsArgumentError);
    });
  });

  group('概率守恒', () {
    test('多组合下配子与子代概率总和恒为 1', () {
      final cases = <(String, String, String)>[
        ('AB/ab', 'ab/ab', '0'),
        ('AB/ab', 'ab/ab', '1/5'),
        ('Ab/aB', 'ab/ab', '0.2'),
        ('AB/ab', 'AB/ab', '20%'),
        ('Ab/aB', 'Ab/aB', '1/2'),
        ('AB/ab', 'Ab/aB', '0.3'),
      ];
      for (final c in cases) {
        final r = engine.cross(c.$1, c.$2, c.$3);
        var sum = Fraction.zero;
        for (final v in r.gametesP1.values) {
          sum = sum + v;
        }
        expect(sum, Fraction.one, reason: '${c.$1} 配子总和');
        var sum2 = Fraction.zero;
        for (final v in r.offspring.values) {
          sum2 = sum2 + v;
        }
        expect(sum2, Fraction.one, reason: '${c.$1}×${c.$2} 子代总和');
        var sum3 = Fraction.zero;
        for (final v in r.phenotypes.values) {
          sum3 = sum3 + v;
        }
        expect(sum3, Fraction.one, reason: '${c.$1}×${c.$2} 表型总和');
      }
    });

    test('三位点简化模型：概率总和恒为 1', () {
      final r = engine.cross('ABC/abc', 'abc/abc', '0.2');
      var sum = Fraction.zero;
      for (final v in r.gametesP1.values) {
        sum = sum + v;
      }
      expect(sum, Fraction.one);
      expect(r.gametesP1['ABC'], Fraction(2, 5));
      expect(r.gametesP1['abc'], Fraction(2, 5));
    });
  });
}
