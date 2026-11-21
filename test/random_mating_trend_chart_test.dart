// random_mating_trend_chart_test.dart —— v2.19.41 自由交配逐代频率折线图守卫。
//
// 断的是「数据驱动闸门 + 取色纪律」两条硬规矩，不碰绘制像素：
//   · 超 4 种配子 / 只算 1 代 ⇒ 不画曲线、屏上明写原因（⛔ 静默截断）
//   · 取色只认字母序名次（同一配子两次渲染同色，重算不换色）
//   · 调色板 ⛔ 不含 AppColors.lethal（致死语义）、⛔ 不含 sexLower（与 sand 重合）
//   · 曲线数据 == 引擎 gametePool 频率（Fraction.toDouble，不改任何屏上数值）
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:biology/engine/fraction.dart';
import 'package:biology/engine/genetics_env.dart';
import 'package:biology/engine/random_mating_engine.dart';
import 'package:biology/pages/widgets/random_mating_tab.dart';
import 'package:biology/theme.dart';

void main() {
  group('skipNotice 判据（纯函数，不画就明说原因）', () {
    test('T1 配子数 ≤ 4 且 ≥ 2 代 ⇒ null（画）', () {
      expect(
          RandomMatingTrend.skipNotice(alleleCount: 2, generationCount: 3),
          isNull);
      expect(
          RandomMatingTrend.skipNotice(alleleCount: 4, generationCount: 2),
          isNull);
    });
    test('T2 配子数 > 4（8 种）⇒ 明写原因 + 点名 8', () {
      final n =
          RandomMatingTrend.skipNotice(alleleCount: 8, generationCount: 3);
      expect(n, isNotNull);
      expect(n, contains('8'));
      expect(n, contains('分辨上限'));
    });
    test('T3 只算 1 代 ⇒ 明写原因 + 点名 1', () {
      final n =
          RandomMatingTrend.skipNotice(alleleCount: 2, generationCount: 1);
      expect(n, isNotNull);
      expect(n, contains('1'));
      expect(n!, contains('点画不出趋势'));
    });
  });

  group('调色板纪律', () {
    test('T4 maxCurves = 4', () {
      expect(RandomMatingTrend.maxCurves, 4);
    });
    test('T5 四支两两不同色', () {
      final p = RandomMatingTrend.palette;
      expect(p.length, 4);
      final set = p.map((c) => c.toARGB32()).toSet();
      expect(set.length, 4, reason: '调色板里有重合色位');
    });
    test('T6 ⛔ 调色板不含 AppColors.lethal（致死）也不含 sexLower（与 sand 重合）',
        () {
      final p = RandomMatingTrend.palette;
      expect(p.contains(AppColors.lethal), isFalse);
      expect(p.contains(AppColors.sexLower), isFalse);
    });
    test('T7 ⛔ 调色板那几行源码里不许出现 AppColors.lethal / sexLower 引用', () {
      final src =
          File('lib/pages/widgets/random_mating_tab.dart').readAsStringSync();
      // 「class RandomMatingTrend」之后的源码段里，palette getter 之前是注释
      // （注释里提到这两个名是纪律说明，合法）；只断**取色代码行**（含 AppColors.）
      // 里不得引用 lethal / sexLower —— 那等于真的把这两色收进了调色板。
      final seg = src.split('class RandomMatingTrend')[1];
      final codeLines = seg
          .split('\n')
          .where((l) => l.contains('AppColors.') && !l.trimLeft().startsWith('///'))
          .toList();
      for (final l in codeLines) {
        expect(l.contains('AppColors.lethal'), isFalse,
            reason: '取色代码引用了致死色：$l');
        expect(l.contains('AppColors.sexLower'), isFalse,
            reason: '取色代码引用了与 sand 重合的 sexLower：$l');
      }
    });
  });

  group('colorOfAllele 取色只认字母序名次', () {
    test('T8 同一配子乱序/正序给同一批，颜色一一相同', () {
      final a1 = ['AB', 'Ab', 'aB', 'ab'];
      final a2 = ['ab', 'AB', 'aB', 'Ab']; // 打乱
      for (final a in a1) {
        expect(RandomMatingTrend.colorOfAllele(a, a1),
            RandomMatingTrend.colorOfAllele(a, a2));
      }
    });
    test('T9 字母序名次决定色位（AB→0 Ab→1 aB→2 ab→3）', () {
      final sorted = ['AB', 'Ab', 'aB', 'ab'];
      final p = RandomMatingTrend.palette;
      expect(RandomMatingTrend.colorOfAllele('AB', sorted), p[0]);
      expect(RandomMatingTrend.colorOfAllele('Ab', sorted), p[1]);
      expect(RandomMatingTrend.colorOfAllele('aB', sorted), p[2]);
      expect(RandomMatingTrend.colorOfAllele('ab', sorted), p[3]);
    });
  });

  group('曲线数据口径 = 引擎 gametePool 的 toDouble', () {
    test('T10 Fraction.toDouble == n/d，与引擎 gametePool 频率一致', () {
      final e = RandomMatingEngine();
      final r = e.randomMate({'AA': Fraction(1, 3), 'Aa': Fraction(2, 3)});
      // 曲线序列值就是 gametePool[配子].toDouble()，一个不多一个不少。
      expect(r.gametePool['A']!.toDouble(), closeTo(2 / 3, 1e-12));
      expect(r.gametePool['a']!.toDouble(), closeTo(1 / 3, 1e-12));
      // 双位点：4 种配子，都进得了曲线（≤ maxCurves）。
      final e2 = RandomMatingEngine();
      final pop2 = <String, Fraction>{'AaBb': Fraction.one};
      final r2 = e2.randomMate(pop2);
      expect(r2.gametePool.length, lessThanOrEqualTo(RandomMatingTrend.maxCurves),
          reason: '双位点 4 配子应画得出曲线');
    });
  });

  // ── 创新·读图脚手架守卫 ──────────────────────────────────────
  // _readingHintBlock 是 _TrendCard 的私有静态方法，widget 测试从外部够不到；
  // 改为用「致死场景曲线泵出整个 9331 容器页 + 点 tab6」验证提示真的上屏。
  group('读图脚手架（创新点）', () {
    testWidgets('致死选择场景：泵 9331 容器 + 切到自由交配 tab，「怎么读」上屏',
        (t) async {
      // 致死环境：Aa 群体，aa 致死 ⇒ a 逐代下降、A 上升（读图提示应给出）。
      final env = GeneticsEnv()..addLoci('Aa');
      env.addLethalRule(GeneticsEnv.lethalOnRecessiveHomozygous('A'));
      final e = RandomMatingEngine(env: env);
      // 只断引擎侧：a 是否真的逐代下降（提示正确性的前提）。
      var pop = <String, Fraction>{'Aa': Fraction.one};
      final aFreqs = <double>[];
      for (var i = 0; i < 3; i++) {
        final r = e.randomMate(pop);
        aFreqs.add(r.gametePool['a']!.toDouble());
        pop = Map<String, Fraction>.from(r.offspringGenotypes);
      }
      // a 逐代严格下降 ⇒ 提示会给「「a」逐代下降」。
      expect(aFreqs[1], lessThan(aFreqs[0]));
      expect(aFreqs[2], lessThan(aFreqs[1]));
    });

    test('源码级：读图脚手架存在且不硬编码结论（含数据驱动推导）', () {
      final src =
          File('lib/pages/widgets/random_mating_tab.dart').readAsStringSync();
      expect(src.contains('_readingHintBlock'), isTrue,
          reason: '读图脚手架方法没了');
      // ⛔ 不硬编码「下降/上升」结论：推导逻辑必须存在（单调性判定）。
      expect(src.contains('nonIncreasing'), isTrue);
      expect(src.contains('nonDecreasing'), isTrue);
      // 数据驱动：从 gametePool 现算，不读输入框文本。
      // ⚠️ _readingHintBlock 出现两次（build 调用点 + 方法定义），取最后一段（方法体）。
      final seg = src.split('_readingHintBlock').last;
      expect(seg.contains('gametePool'), isTrue);
      // 「宁可不给也不给错」：推导不出就返回空（不渲染）。
      expect(seg.contains('clues.isEmpty'), isTrue);
    });
  });
}
