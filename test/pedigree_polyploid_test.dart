// pedigree_polyploid_test.dart —— v2.1 图谱引擎扩展回归：
// ①多倍体计算（1n~5n，默认仍 2n）②位点级致死筛选 ③多基因基因频率统计。
//
// 铁律：默认 2n 行为零改变（pedigree_graph_engine_test.dart /
// pedigree_edit_test.dart 等既有套件保持全绿，本文件只测新增能力）。
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/engine/pedigree_graph.dart';

/// 某代计算桶的基因型 → 概率分布（测试辅助）。
/// v2.1i 默认仅返回存活子代（过滤致死节点），与旧版"删除致死"语义一致；
/// 若要看致死节点，传 [includeLethal]=true。
Map<String, double> distOf(PedigreeGraphEngine e, int gen,
        {bool includeLethal = false}) =>
    {
      for (final n in e.nodesOf(gen))
        if (includeLethal || !n.isLethal) n.genotype: n.probability,
    };

void main() {
  group('v2.1 多倍体（allowPolyploid=true）', () {
    test('3n：AaaBbb×aaabbb → F1 存在、每位点字母数=3、无异常', () {
      final e = PedigreeGraphEngine(
          fatherGenotype: 'AaaBbb', motherGenotype: 'aaabbb')
        ..allowPolyploid = true;
      final created = e.expandNextGeneration();
      expect(created, isNotEmpty);
      final f1 = e.nodesOf(1);
      expect(f1, isNotEmpty);
      for (final n in f1) {
        expect(RegExp(r'^[Aa]{3}[Bb]{3}$').hasMatch(n.genotype), isTrue,
            reason: 'F1 每位点 3 字母：${n.genotype}');
      }
      // 概率归一
      final total = f1.fold(0.0, (s, n) => s + n.probability);
      expect(total, closeTo(1.0, 1e-9));
      // 理论分布：父本 A 位点 A(1/3)·a(2/3)，B 位点 B(1/3)·b(2/3)；
      // 子代 = 父方等位 ⌈3/2⌉=2 份 + 母方 ⌊3/2⌋=1 份
      final d = distOf(e, 1);
      expect(d['AAaBBb'], closeTo(1 / 9, 1e-9));
      expect(d['AAabbb'], closeTo(2 / 9, 1e-9));
      expect(d['aaaBBb'], closeTo(2 / 9, 1e-9));
      expect(d['aaabbb'], closeTo(4 / 9, 1e-9));
    });

    test('1n 单倍体：A×a（allowPolyploid）→ 不抛错，F1 每节点 1 个字母', () {
      final e = PedigreeGraphEngine(fatherGenotype: 'A', motherGenotype: 'a')
        ..allowPolyploid = true;
      expect(() => e.expandNextGeneration(), returnsNormally);
      final f1 = e.nodesOf(1);
      expect(f1, isNotEmpty);
      expect(f1.every((n) => n.genotype.length == 1), isTrue);
    });

    test('4n：AaaaBbbb×AaaaBbbb → F1 每位点字母数=4、概率归一', () {
      final e = PedigreeGraphEngine(
          fatherGenotype: 'AaaaBbbb', motherGenotype: 'AaaaBbbb')
        ..allowPolyploid = true;
      final created = e.expandNextGeneration();
      expect(created, isNotEmpty);
      final f1 = e.nodesOf(1);
      expect(f1, isNotEmpty);
      expect(
          f1.every((n) => RegExp(r'^[Aa]{4}[Bb]{4}$').hasMatch(n.genotype)),
          isTrue);
      expect(f1.fold(0.0, (s, n) => s + n.probability), closeTo(1.0, 1e-9));
    });

    test('5n：Aaaaa×Aaaaa → F1 每位点字母数=5', () {
      final e = PedigreeGraphEngine(
          fatherGenotype: 'Aaaaa', motherGenotype: 'Aaaaa')
        ..allowPolyploid = true;
      final created = e.expandNextGeneration();
      expect(created, isNotEmpty);
      expect(
          e.nodesOf(1).every((n) => RegExp(r'^[Aa]{5}$').hasMatch(n.genotype)),
          isTrue);
    });

    test('多倍体开关下 2n 输入与严格模式逐位一致（回归保护）', () {
      final poly = PedigreeGraphEngine(
          fatherGenotype: 'AaBb', motherGenotype: 'AaBb')
        ..allowPolyploid = true;
      final strict =
          PedigreeGraphEngine(fatherGenotype: 'AaBb', motherGenotype: 'AaBb');
      poly.expandNextGeneration();
      strict.expandNextGeneration();
      expect(distOf(poly, 1), distOf(strict, 1));
      expect(poly.nodesOf(1).map((n) => n.genotype).toSet(),
          strict.nodesOf(1).map((n) => n.genotype).toSet());
    });

    test('多倍体后代可继续杂交：F2 保持 3n', () {
      final e = PedigreeGraphEngine(fatherGenotype: 'Aaa', motherGenotype: 'aaa')
        ..allowPolyploid = true;
      e.ensureGeneration(2);
      expect(e.nodesOf(2), isNotEmpty);
      expect(
          e.nodesOf(2).every((n) => RegExp(r'^[Aa]{3}$').hasMatch(n.genotype)),
          isTrue);
      final total = e.nodesOf(2).fold(0.0, (s, n) => s + n.probability);
      expect(total, closeTo(1.0, 1e-9));
    });

    test('多倍体模式 + 位点致死：Aa×Aa（2n 输入）lethal=AA 仍 2/3:1/3', () {
      final e = PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa')
        ..allowPolyploid = true
        ..lethalGenotype = 'AA';
      e.expandNextGeneration();
      final d = distOf(e, 1);
      expect(d.keys.toSet(), {'Aa', 'aa'});
      expect(d['Aa'], closeTo(2 / 3, 1e-9));
      expect(d['aa'], closeTo(1 / 3, 1e-9));
    });
  });

  group('v2.1 位点致死筛选（lethalGenotype）', () {
    test('Aa×Aa 且 AA 致死 → F1 仅 Aa(2/3) 与 aa(1/3)（概率重归一）', () {
      final e = PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa')
        ..lethalGenotype = 'AA';
      e.expandNextGeneration();
      final d = distOf(e, 1);
      expect(d.keys.toSet(), {'Aa', 'aa'});
      expect(d['Aa'], closeTo(2 / 3, 1e-9));
      expect(d['aa'], closeTo(1 / 3, 1e-9));
      expect(d.values.fold(0.0, (a, b) => a + b), closeTo(1.0, 1e-9));
    });

    test('aa×aa 且 aa 致死 → 全部子代淘汰：仅留致死节点、不抛异常', () {
      final e = PedigreeGraphEngine(fatherGenotype: 'aa', motherGenotype: 'aa')
        ..lethalGenotype = 'aa';
      expect(() => e.expandNextGeneration(), returnsNormally);
      // v2.1i 致死节点保留：F1 仍生成 1 个致死节点 (aa)，无存活子代
      final f1 = e.nodesOf(1);
      expect(f1.length, 1);
      expect(f1.single.isLethal, isTrue);
      expect(f1.single.genotype, 'aa');
      expect(e.maxGeneration, 1, reason: '世代仍推进');
    });

    test('aA 与 Aa 视为同一（字母序规范化）→ Aa 杂合致死', () {
      final e = PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa')
        ..lethalGenotype = 'aA'; // 规范化 == 'Aa'
      e.expandNextGeneration();
      final d = distOf(e, 1);
      expect(d.keys.toSet(), {'AA', 'aa'});
      expect(d['AA'], closeTo(1 / 2, 1e-9));
      expect(d['aa'], closeTo(1 / 2, 1e-9));
    });

    test('v2.1c 多条件致死：lethal=BB 淘汰 B 位点 BB 的子代（含 AABB），剩 12 桶归一',
        () {
      final e = PedigreeGraphEngine(fatherGenotype: 'AaBb', motherGenotype: 'AaBb')
        ..addLethal('BB'); // B 位点 BB 致死
      e.expandNextGeneration();
      final d = distOf(e, 1);
      // 16 桶中 AABB(1) AaBB(2) aaBB(1) 共 4 桶被淘汰，剩 12 桶归一：
      expect(d['AABB'] ?? 0.0, 0.0, reason: 'AABB 命中 BB 致死');
      expect(d['AaBB'] ?? 0.0, 0.0);
      expect(d['aaBB'] ?? 0.0, 0.0);
      expect(d['AABb'], closeTo(2 / 12, 1e-9), reason: '2/16 留 2/12');
      expect(d['AaBb'], closeTo(4 / 12, 1e-9));
      expect(d['aaBb'], closeTo(2 / 12, 1e-9));
      expect(d['AAbb'], closeTo(1 / 12, 1e-9));
      expect(d['Aabb'], closeTo(2 / 12, 1e-9));
      expect(d['aabb'], closeTo(1 / 12, 1e-9));
      expect(d.values.fold(0.0, (a, b) => a + b), closeTo(1.0, 1e-9));
      // 多条件：AA + BB 同时致死 → F1 仅留 9 桶（AaBb/Aabb/aaBb/aabb）
      final e2 =
          PedigreeGraphEngine(fatherGenotype: 'AaBb', motherGenotype: 'AaBb')
            ..addLethal('AA')
            ..addLethal('BB');
      e2.expandNextGeneration();
      final d2 = distOf(e2, 1);
      expect(d2['AABb'] ?? 0.0, 0.0, reason: 'AA 命中 AABb');
      expect(d2['AAbb'] ?? 0.0, 0.0);
      expect(d2['AABB'] ?? 0.0, 0.0);
      expect(d2['AaBb'], closeTo(4 / 9, 1e-9));
      expect(d2['Aabb'], closeTo(2 / 9, 1e-9));
      expect(d2['aaBb'], closeTo(2 / 9, 1e-9));
      expect(d2['aabb'], closeTo(1 / 9, 1e-9));
    });
  });

  group('v2.1 基因频率统计（locusFrequencies）', () {
    test('Aa×Aa：p=0.5 q=0.5；AA:Aa:aa 节点比 = 1:3:1（含反序 aA 计 Aa）',
        () {
      final e = PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      // P 代双亲两个杂合节点
      var freqs = e.locusFrequencies();
      expect(freqs.length, 1);
      expect(freqs.single.locus, 'A/a');
      expect(freqs.single.p, closeTo(0.5, 1e-9));
      expect(freqs.single.q, closeTo(0.5, 1e-9));
      expect(freqs.single.fAa, closeTo(1.0, 1e-9));
      expect(freqs.single.fAA, 0.0);
      expect(freqs.single.faa, 0.0);

      // 反序编辑：'aA' 与 'Aa' 同属杂合（fAa 含正反序）
      expect(e.editGenotype('P-father', 'aA'), isNull);
      freqs = e.locusFrequencies();
      expect(freqs.single.fAa, closeTo(1.0, 1e-9));

      // 展开 F1（AA:Aa:aa = 1:2:1 计算桶）→ 全节点 AA:Aa:aa = 1:3:1
      e.expandNextGeneration();
      freqs = e.locusFrequencies();
      expect(freqs.single.p, closeTo(0.5, 1e-9));
      expect(freqs.single.q, closeTo(0.5, 1e-9));
      expect(freqs.single.fAA, closeTo(1 / 5, 1e-9));
      expect(freqs.single.fAa, closeTo(3 / 5, 1e-9));
      expect(freqs.single.faa, closeTo(1 / 5, 1e-9));
      expect(freqs.single.fAA + freqs.single.fAa + freqs.single.faa,
          closeTo(1.0, 1e-9));
    });

    test('多对位点：AABB×aabb → 按位点字母序 A/a、B/b 排列，p/q 正确', () {
      final e =
          PedigreeGraphEngine(fatherGenotype: 'AABB', motherGenotype: 'aabb');
      final freqs = e.locusFrequencies();
      expect(freqs.map((f) => f.locus).toList(), ['A/a', 'B/b']);
      // A/a：父 AA + 母 aa → 等位 2:2、节点 1:0:1
      expect(freqs[0].p, closeTo(0.5, 1e-9));
      expect(freqs[0].q, closeTo(0.5, 1e-9));
      expect(freqs[0].fAA, closeTo(0.5, 1e-9));
      expect(freqs[0].faa, closeTo(0.5, 1e-9));
      expect(freqs[0].fAa, 0.0);
      // B/b 同理
      expect(freqs[1].p, closeTo(0.5, 1e-9));
      expect(freqs[1].fAA, closeTo(0.5, 1e-9));
    });

    test('含缺失 - 的位点：- 不计入等位统计，p+q 恒为 1', () {
      final e = PedigreeGraphEngine(fatherGenotype: 'AaBb', motherGenotype: 'AaBb')
        ..allowMissingGeneMating = true;
      // 落位 P 代（generation 0）避免自动展开 F1 污染节点集
      final ext = e.addExternalGroup(generation: 0, genotype: 'AaB-');
      expect(ext, startsWith('EXT#'));
      expect(() => e.locusFrequencies(), returnsNormally);
      final freqs = e.locusFrequencies();
      final a = freqs.firstWhere((f) => f.locus == 'A/a');
      final b = freqs.firstWhere((f) => f.locus == 'B/b');
      // 节点集 = 双亲 AaBb ×2 + 缺失样本 AaB-：A/a 等位 3:3，p=0.5
      expect(a.p, closeTo(0.5, 1e-9));
      expect(a.p + a.q, closeTo(1.0, 1e-9));
      // B/b：双亲 Bb + 缺失样本 B-（- 不计）→ 显性 3 份、隐性 2 份
      expect(b.p, closeTo(3 / 5, 1e-9));
      expect(b.q, closeTo(2 / 5, 1e-9));
      expect(b.p + b.q, closeTo(1.0, 1e-9));
      // 基因型分类：B- 位点全显性 → fAA 占 1/3，其余两杂合
      expect(b.fAA, closeTo(1 / 3, 1e-9));
      expect(b.fAa, closeTo(2 / 3, 1e-9));
    });
  });

  group('v2.1 非法输入校验', () {
    test('严格模式（allowPolyploid=false）：Aaa 抛 ArgumentError（现状）', () {
      final e = PedigreeGraphEngine(fatherGenotype: 'Aaa', motherGenotype: 'aaa');
      expect(() => e.expandNextGeneration(), throwsArgumentError);
    });

    test('严格模式 addExternal 奇数基因型被拒', () {
      final e = PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      expect(
          () => e.addExternal(
              generation: 1,
              kind: PedigreeNodeKind.male,
              genotype: 'Aaa'),
          throwsArgumentError);
    });

    test('多倍体模式：位点数不一致（AaaBb）抛 ArgumentError', () {
      final e = PedigreeGraphEngine(
          fatherGenotype: 'AaaBb', motherGenotype: 'Aaabb')
        ..allowPolyploid = true;
      expect(() => e.expandNextGeneration(), throwsArgumentError);
    });

    test('多倍体模式 addExternal 与家族倍性不一致被拒', () {
      final e = PedigreeGraphEngine(fatherGenotype: 'Aaa', motherGenotype: 'aaa')
        ..allowPolyploid = true;
      expect(
          () => e.addExternal(
              generation: 0,
              kind: PedigreeNodeKind.male,
              genotype: 'Aaaa'),
          throwsArgumentError);
    });

    test('双方倍性不一致（3n×2n）抛 ArgumentError', () {
      final e = PedigreeGraphEngine(fatherGenotype: 'Aaa', motherGenotype: 'Aa')
        ..allowPolyploid = true;
      expect(() => e.expandNextGeneration(), throwsArgumentError);
    });

    test('超过 5 倍体（6n）抛 ArgumentError', () {
      final e = PedigreeGraphEngine(
          fatherGenotype: 'Aaaaaa', motherGenotype: 'aaaaaa')
        ..allowPolyploid = true;
      expect(() => e.expandNextGeneration(), throwsArgumentError);
    });
  });

  group('v2.1 快照携带新开关', () {
    test('allowPolyploid / lethalGenotype 随快照保存与恢复', () {
      final e = PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa')
        ..allowPolyploid = true
        ..lethalGenotype = 'AA';
      final snap = e.takeSnapshot();
      e.allowPolyploid = false;
      e.lethalGenotype = null;
      e.restoreSnapshot(snap);
      expect(e.allowPolyploid, isTrue);
      expect(e.lethalGenotype, 'AA');
    });
  });
}