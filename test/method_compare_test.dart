// method_compare_test.dart —— 分解法 vs 配子法 对比引擎单元测试

import 'package:biology/engine/fraction.dart';
import 'package:biology/engine/method_compare.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AaBb × AaBb（双杂合自交）', () {
    final r = compareMethods('AaBb', 'AaBb');

    test('配子法：双方各 4 种配子，16 格', () {
      expect(r.gametesP1.length, 4);
      expect(r.gametesP2.length, 4);
      expect(r.cellCount, 16);
      expect(r.punnett.length, 4);
      expect(r.punnett.every((row) => row.length == 4), isTrue);
    });

    test('分解法：2 步，各 3:1', () {
      expect(r.decomposeSteps, 2);
      expect(r.loci.length, 2);
      for (final l in r.loci) {
        expect(l.integerRatio, [3, 1], reason: l.crossLabel);
      }
    });

    test('最终表型比 9:3:3:1', () {
      expect(r.integerRatio, [9, 3, 3, 1]);
    });

    test('方阵左上角为 AABB', () {
      expect(r.punnett.first.first, 'AABB');
    });
  });

  group('测交 AaBb × aabb', () {
    final r = compareMethods('AaBb', 'aabb');

    test('配子法：4 × 1 = 4 格', () {
      expect(r.gametesP1.length, 4);
      expect(r.gametesP2.length, 1);
      expect(r.cellCount, 4);
    });

    test('表型比 1:1:1:1', () {
      expect(r.integerRatio, [1, 1, 1, 1]);
    });

    test('分解法各位点 1:1', () {
      for (final l in r.loci) {
        expect(l.integerRatio, [1, 1], reason: l.crossLabel);
      }
    });
  });

  group('单基因 Aa × Aa', () {
    final r = compareMethods('Aa', 'Aa');

    test('4 格方阵，表型 3:1', () {
      expect(r.cellCount, 4);
      expect(r.integerRatio, [3, 1]);
      expect(r.decomposeSteps, 1);
    });
  });

  group('三位点 AaBbCc 自交', () {
    final r = compareMethods('AaBbCc', 'AaBbCc');

    test('配子法 64 格，分解法仅 3 步', () {
      expect(r.cellCount, 64);
      expect(r.decomposeSteps, 3);
    });

    test('表型比 27:9:9:9:3:3:3:1（不计顺序）', () {
      final sorted = List.of(r.integerRatio)..sort((a, b) => b.compareTo(a));
      expect(sorted, [27, 9, 9, 9, 3, 3, 3, 1]);
    });
  });

  group('精确分数性质', () {
    test('表型概率之和恒为 1', () {
      for (final (a, b) in [
        ('AaBb', 'AaBb'),
        ('AaBb', 'aabb'),
        ('Aa', 'Aa'),
        ('AaBbCc', 'AaBbCc'),
        ('AABb', 'aaBb'),
      ]) {
        final r = compareMethods(a, b);
        final total =
            r.phenotypeDist.values.fold(Fraction.zero, (s, f) => s + f);
        expect(total, Fraction.one, reason: '$a × $b');
      }
    });
  });

  group('输入校验', () {
    test('位点数不一致抛错', () {
      expect(() => compareMethods('AaBb', 'Aa'), throwsArgumentError);
    });

    test('位点字母不一致抛错', () {
      expect(() => compareMethods('AaBb', 'AaCc'), throwsArgumentError);
    });

    test('超过 3 对位点抛错', () {
      expect(() => compareMethods('AaBbCcDd', 'AaBbCcDd'),
          throwsArgumentError);
    });
  });
}
