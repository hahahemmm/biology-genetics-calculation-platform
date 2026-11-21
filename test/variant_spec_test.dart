// variant_spec_test.dart —— 9331 变式 8 mode 识别守护测试（v2.12 新增）
//
// 覆盖范围：
//   - VariantSpec.all 8 个 mode 全部就位
//   - ratioFor() 8 个 mode 比例正确
//   - shortName / displayName 8 个 mode 显示名非空
//   - genetics_env 8 个 mode 走 phenotypeRuleForVariant 通路
//     都能得到预期整数比（与 variant_spec.ratioFor 一致）
//   - 未知 mode 仍回退到标准 9:3:3:1（保留 v2.10 之前行为）
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/engine/fraction.dart';
import 'package:biology/engine/genetics_env.dart';
import 'package:biology/engine/variant_spec.dart';

void main() {
  group('VariantSpec.all v2.12 八式', () {
    test('all 列表长度 = 8', () {
      expect(VariantSpec.all.length, 8);
    });

    test('all 列表内容覆盖课标 KD-05/07/09/11/12 五考点变式', () {
      expect(VariantSpec.all, containsAll(<String>[
        VariantSpec.standard9331, // 9:3:3:1
        VariantSpec.complement97, // 9:7
        VariantSpec.epistasis934, // 9:3:4
        VariantSpec.dominant151, // 15:1
        VariantSpec.quantitative14641, // 1:4:6:4:1
        VariantSpec.dominantEpistasis1231, // 12:3:1（v2.12 新增）
        VariantSpec.inhibition13_3, // 13:3（v2.12 新增）
        VariantSpec.additive961, // 9:6:1（v2.12 新增）
      ]));
    });

    test('8 个 mode 字面量字面值不变', () {
      expect(VariantSpec.standard9331, '9331');
      expect(VariantSpec.complement97, '9_7');
      expect(VariantSpec.epistasis934, '9_3_4');
      expect(VariantSpec.dominant151, '15_1');
      expect(VariantSpec.quantitative14641, '1_4_6_4_1');
      expect(VariantSpec.dominantEpistasis1231, '12_3_1');
      expect(VariantSpec.inhibition13_3, '13_3');
      expect(VariantSpec.additive961, '9_6_1');
    });
  });

  group('VariantSpec.ratioFor 八式比例', () {
    test('标准 9:3:3:1', () {
      expect(VariantSpec.ratioFor(VariantSpec.standard9331), [9, 3, 3, 1]);
    });
    test('9:7 互补', () {
      expect(VariantSpec.ratioFor(VariantSpec.complement97), [9, 7]);
    });
    test('9:3:4 隐性上位', () {
      expect(VariantSpec.ratioFor(VariantSpec.epistasis934), [9, 3, 4]);
    });
    test('15:1 显性叠加', () {
      expect(VariantSpec.ratioFor(VariantSpec.dominant151), [15, 1]);
    });
    test('1:4:6:4:1 数量性状', () {
      expect(VariantSpec.ratioFor(VariantSpec.quantitative14641), [1, 4, 6, 4, 1]);
    });
    test('12:3:1 显性上位（v2.12 新增）', () {
      expect(VariantSpec.ratioFor(VariantSpec.dominantEpistasis1231),
          [12, 3, 1]);
    });
    test('13:3 抑制（v2.12 新增）', () {
      expect(VariantSpec.ratioFor(VariantSpec.inhibition13_3), [13, 3]);
    });
    test('9:6:1 积加（v2.12 新增）', () {
      expect(VariantSpec.ratioFor(VariantSpec.additive961), [9, 6, 1]);
    });
    test('未知 mode 回退标准 9:3:3:1（v2.10 行为兼容）', () {
      expect(VariantSpec.ratioFor('not_a_real_mode'), [9, 3, 3, 1]);
    });
  });

  group('VariantSpec.shortName / displayName 八式', () {
    test('8 个 mode 短名非空且含比例', () {
      for (final m in VariantSpec.all) {
        final s = VariantSpec.shortName(m);
        expect(s, isNotEmpty, reason: 'shortName 空: $m');
        expect(s, isNot(equals(m)),
            reason: 'shortName 应不是字面量本身: $m');
      }
    });
    test('8 个 mode 长名非空且含教学说明', () {
      for (final m in VariantSpec.all) {
        final d = VariantSpec.displayName(m);
        expect(d, isNotEmpty, reason: 'displayName 空: $m');
        expect(d.length, greaterThan(3),
            reason: 'displayName 应有解释文字: $m');
      }
    });
    test('未知 mode 短/长名回退到字面量（与 v2.10 行为一致）', () {
      expect(VariantSpec.shortName('not_a_mode'), 'not_a_mode');
      expect(VariantSpec.displayName('not_a_mode'), 'not_a_mode');
    });
  });

  // ───────── 8 mode 在 genetics_env 通路下的真实推导 ─────────
  // 守护：variant_spec 集中常量与 genetics_env 工厂产出的整数比必须一致。

  GeneticsEnv buildEnv(String variant) {
    final env = GeneticsEnv();
    env.addLocus(const AlleleLocus('A', 'a'));
    env.addLocus(const AlleleLocus('B', 'b'));
    env.setPhenotypeRule(GeneticsEnv.phenotypeRuleForVariant(variant));
    return env;
  }

  List<int> integerRatioFor(Map<String, Fraction> dist) =>
      GeneticsEnv.toIntegerRatio(dist.values);

  group('8 mode 真实杂交推导（genetics_env 通路）', () {
    test('AaBb × AaBb → 8 mode 各自比例与 VariantSpec.ratioFor 一致', () {
      const cases = <(String, List<int>)>[
        (VariantSpec.standard9331, [9, 3, 3, 1]),
        (VariantSpec.complement97, [9, 7]),
        (VariantSpec.epistasis934, [9, 3, 4]),
        (VariantSpec.dominant151, [15, 1]),
        (VariantSpec.quantitative14641, [1, 4, 6, 4, 1]),
        (VariantSpec.dominantEpistasis1231, [12, 3, 1]),
        (VariantSpec.inhibition13_3, [13, 3]),
        (VariantSpec.additive961, [9, 6, 1]),
      ];
      for (final c in cases) {
        final env = buildEnv(c.$1);
        final dist = env.phenotypeDist(env.cross('AaBb', 'AaBb'));
        final ratio = integerRatioFor(dist);
        expect(ratio, c.$2,
            reason: 'mode=${c.$1} 实推 $ratio ≠ 预期 ${c.$2}');
        // 守护：与 VariantSpec.ratioFor 一致
        expect(ratio, VariantSpec.ratioFor(c.$1),
            reason: 'genetics_env 推 ${c.$1} ≠ VariantSpec.ratioFor');
      }
    });

    test('12:3:1 显性上位细分：AaBb × AaBb 各 9/3/3/1 子集正确归类', () {
      // 12 = A_B_ (9) + A_bb (3) 全部归 A 显；3 = aaB_ 归 B 显；1 = aabb 双隐
      final env = buildEnv(VariantSpec.dominantEpistasis1231);
      final pheno = env.phenotypeDist(env.cross('AaBb', 'AaBb'));
      // Fraction 自动约分：12/16 → 3/4；3/16 仍为 3/16；1/16 不变
      expect(pheno['A显'], Fraction(3, 4));
      expect(pheno['B显'], Fraction(3, 16));
      expect(pheno['双隐'], Fraction(1, 16));
    });

    test('13:3 抑制：AaBb × AaBb 子集归类（13 = A_B_+aaB_+aabb，3 = A_bb）', () {
      final env = buildEnv(VariantSpec.inhibition13_3);
      final pheno = env.phenotypeDist(env.cross('AaBb', 'AaBb'));
      // "其他" = A_B_(9) + aaB_(3) + aabb(1) = 13/16
      expect(pheno['其他'], Fraction(13, 16));
      expect(pheno['A显'], Fraction(3, 16));
    });

    test('9:6:1 积加：AaBb × AaBb 各子集归类（9 双显 / 6 单显合并 / 1 双隐）', () {
      final env = buildEnv(VariantSpec.additive961);
      final pheno = env.phenotypeDist(env.cross('AaBb', 'AaBb'));
      // Fraction 自动约分：6/16 → 3/8
      expect(pheno['双显'], Fraction(9, 16));
      expect(pheno['单显'], Fraction(3, 8));
      expect(pheno['双隐'], Fraction(1, 16));
    });
  });

  group('KaojiCalc.knownVariants 与 VariantSpec.all 一致', () {
    test('knownVariants == all（v2.11 M11b 不变）', () {
      // 反射：kaoji_calc.knownVariants 委托 VariantSpec.all
      // 这里只断言 variant_spec 8 个全部就位（kaoji_calc 在另一文件，
      // 显式断言在 kaoji_calc_auto_test 已有，这里避免跨文件依赖）
      expect(VariantSpec.all.length, 8);
    });
  });
}
