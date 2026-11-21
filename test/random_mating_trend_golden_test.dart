// random_mating_trend_golden_test.dart —— v2.19.41 自由交配逐代频率折线图像素基线。
//
// 只拍折线图组件本身（不进宿主、不进 _resultKey 导出子树）：
//   · 数据驱动：两条 FreqSeries（a 频率 sand / A 频率 teal），数值 = 引擎 gametePool
//   · 浅色 / 深色两张基线，先 loadGoldenFonts + 两个自检（⛔ 方框基线 = 假绿）
//   · 拍带 RenderObject 的 CustomPaint（ StatelessWidget 本身不是 RenderObject）
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/charts/frequency_curve_chart.dart';
import 'package:biology/engine/fraction.dart';
import 'package:biology/engine/genetics_env.dart';
import 'package:biology/engine/random_mating_engine.dart';
import 'package:biology/theme.dart';

import 'golden_fonts.dart';

const double _kHostWidth = 360;

void main() {
  for (final tier in const <({String tag, String label, Brightness b})>[
    (tag: 'light', label: '浅色', b: Brightness.light),
    (tag: 'dark', label: '深色', b: Brightness.dark),
  ]) {
    testWidgets('${tier.label}像素基线（Aa 群体逐代配子频率 a/A 两条曲线）',
        (t) async {
      await loadGoldenFonts();
      assertMaterialIconsLoaded();
      assertMonoLoaded();
      AppColors.sync(tier.b);
      await t.pumpWidget(_host(tier.b));
      await t.pump();
      expect(t.takeException(), isNull);
      await expectLater(
        find.byType(CustomPaint).first,
        matchesGoldenFile('goldens/random_mating_trend_${tier.tag}.png'),
      );
    });
  }

  test('两张基线必须已存在、不是空图，且彼此不同（防恒等三元录成一张）', () {
    const dir = 'test/goldens/';
    final a = File('${dir}random_mating_trend_light.png');
    final b = File('${dir}random_mating_trend_dark.png');
    for (final f in <File>[a, b]) {
      expect(f.existsSync(), isTrue, reason: '基线还没录：${f.path}');
      expect(f.lengthSync(), greaterThan(1000),
          reason: '基线 ${f.path} 只有 ${f.lengthSync()} 字节，多半是空图');
    }
    expect(a.readAsBytesSync(), isNot(equals(b.readAsBytesSync())),
        reason: '浅/深两张基线逐字节相同 —— 多半是主题 token 没跟着亮度走');
  });
}

/// 造「aa 致死、Aa 群体逐代自由交配」的 a/A 频率序列。
///
/// ⛔ 不用 Hardy-Weinberg 平衡（a 频率恒 1/2、两条线重合、golden 对「a 真的
/// 在降」零敏感）。用致死选择：a 频率逐代下降、A 上升，曲线有真趋势，
/// 且 a 线用 [AppColors.sand]（= 隐性表型标记）语义恰好对上「这条是隐性 a」。
List<FreqSeries> _series() {
  final env = GeneticsEnv()..addLoci('Aa');
  env.addLethalRule(GeneticsEnv.lethalOnRecessiveHomozygous('A'));
  final e = RandomMatingEngine(env: env);
  final gens = <Map<String, Fraction>>[];
  var pop = <String, Fraction>{'Aa': Fraction.one};
  for (var i = 0; i < 3; i++) {
    final r = e.randomMate(pop);
    gens.add(r.gametePool);
    pop = Map<String, Fraction>.from(r.offspringGenotypes);
  }
  double freq(String allele, int g) => gens[g][allele]!.toDouble();
  return [
    FreqSeries(
      label: 'a',
      values: [for (var g = 0; g < gens.length; g++) freq('a', g)],
      color: AppColors.sand,
    ),
    FreqSeries(
      label: 'A',
      values: [for (var g = 0; g < gens.length; g++) freq('A', g)],
      color: AppColors.teal,
    ),
  ];
}

/// 裸宿主：只挂折线图组件，不加标题/图例外任何东西 ⇒ 基线每像素都是组件自画。
Widget _host(Brightness b) => MaterialApp(
      theme: AppTheme.build(b),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: _kHostWidth,
            child: FrequencyCurveChart(series: _series()),
          ),
        ),
      ),
    );
