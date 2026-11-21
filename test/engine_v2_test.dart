// engine_v2_test.dart —— 精确分数 + 规则注册引擎的单元测试
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/engine/fraction.dart';
import 'package:biology/engine/genetics_env.dart';

void main() {
  group('Fraction', () {
    test('构造即约分', () {
      expect(Fraction(9, 16).toString(), '9/16');
      expect(Fraction(6, 8).toString(), '3/4');
      expect(Fraction(4, 2).toString(), '2');
    });
    test('四则运算', () {
      expect((Fraction(1, 2) * Fraction(1, 2)).toString(), '1/4');
      expect((Fraction(1, 4) + Fraction(1, 4)).toString(), '1/2');
      expect((Fraction(3, 4) - Fraction(1, 2)).toString(), '1/4');
      expect((Fraction(9, 16) / Fraction(3, 4)).toString(), '3/4');
    });
    test('符号与相等', () {
      expect(Fraction(1, -2).toString(), '-1/2');
      expect(Fraction(2, 4) == Fraction(1, 2), isTrue);
    });
    test('多代连乘无漂移：1/2^10 精确', () {
      var p = Fraction.one;
      for (int i = 0; i < 10; i++) {
        p = p * Fraction.half;
      }
      expect(p.toString(), '1/1024');
    });
  });

  GeneticsEnv buildEnv({String variant = '9331'}) {
    final env = GeneticsEnv();
    env.addLocus(const AlleleLocus('A', 'a'));
    env.addLocus(const AlleleLocus('B', 'b'));
    env.setPhenotypeRule(GeneticsEnv.phenotypeRuleForVariant(variant));
    return env;
  }

  group('GeneticsEnv 杂交推导', () {
    test('AaBb 配子 4 种各 1/4', () {
      final env = GeneticsEnv()..addLoci('AaBb');
      final g = env.gametesOf('AaBb');
      expect(g.length, 4);
      expect(g['AB'].toString(), '1/4');
    });

    test('AaBb×AaBb → 双显 9/16（精确分数）', () {
      final env = buildEnv();
      final dist = env.cross('AaBb', 'AaBb');
      final pheno = env.phenotypeDist(dist);
      expect(pheno['双显'].toString(), '9/16');
      expect(pheno['双隐'].toString(), '1/16');
    });

    test('9331 整数比推导（统一分母）', () {
      final env = buildEnv();
      final dist = env.phenotypeDist(env.cross('AaBb', 'AaBb'));
      final ratio = GeneticsEnv.toIntegerRatio(dist.values);
      expect(ratio, [9, 3, 3, 1]);
    });

    test('变式 9:7 由表型映射推导而非查表', () {
      final env = buildEnv(variant: '9_7');
      final dist = env.phenotypeDist(env.cross('AaBb', 'AaBb'));
      expect(dist['双显'].toString(), '9/16');
      expect(dist['其他'].toString(), '7/16');
    });

    test('变式 15:1 / 12:3:1 / 9:6:1', () {
      for (final (mode, expected) in [
        ('15_1', ['15', '1']),
        ('12_3_1', ['12', '3', '1']),
        ('9_6_1', ['9', '6', '1']),
      ]) {
        final env = buildEnv(variant: mode);
        final dist = env.phenotypeDist(env.cross('AaBb', 'AaBb'));
        final ratio = GeneticsEnv.toIntegerRatio(dist.values);
        expect(ratio.map((e) => '$e').toList(), expected, reason: mode);
      }
    });

    test('1:4:6:4:1 数量性状按显性基因数分档', () {
      final env = buildEnv(variant: '1_4_6_4_1');
      final dist = env.phenotypeDist(env.cross('AaBb', 'AaBb'));
      final ratio = GeneticsEnv.toIntegerRatio(dist.values);
      expect(ratio, [1, 4, 6, 4, 1]);
    });

    test('致死规则：AA 致死 → Aa×Aa 存活比 2:1', () {
      final env = GeneticsEnv()..addLoci('Aa');
      env.addLethalRule(GeneticsEnv.lethalOnDominantHomozygous('A'));
      final dist = env.cross('Aa', 'Aa');
      expect(dist.containsKey('AA'), isFalse);
      expect(dist['Aa'].toString(), '2/3');
      expect(dist['aa'].toString(), '1/3');
    });

    test('测交 AaBb×aabb → 1:1:1:1', () {
      final env = buildEnv();
      final dist = env.phenotypeDist(env.cross('AaBb', 'aabb'));
      final ratio = GeneticsEnv.toIntegerRatio(dist.values);
      expect(ratio, [1, 1, 1, 1]);
    });
  });
}
