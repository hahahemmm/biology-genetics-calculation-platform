// pedigree_graph_engine_test.dart —— 系谱计算图引擎单元测试
//
// 覆盖（对应派工指令 T-A2）：
//   1. 初始化：P 代两节点一 mating 边，性别正确
//   2. expandNextGeneration：AaBb×AaBb 的 F1 分布与 PedigreeEngine.cross 一致
//   3. 连续扩展到 F6 无上限报错
//   4. addExternal 到 F1 后 recomputeFrom(1)，F2 分布包含外来贡献（前后确实变化）
//   5. connect 校验矩阵：同性/跨代/自连/重复拒绝，合法通过
//   6. 显式 mating 边的定向杂交并入下一代（分布变化）
//   7. removeExternal 后重算回到接入前分布
//   8. 致死场景不回归（引擎输出可被上层致死过滤且仍合法；见状态文件说明）
//   9. id 稳定性：重算后 F2#0 等 id 复用，EXT id 永不复用
//  10. 超过 20 代抛 StateError

import 'package:biology/engine/pedigree_engine.dart';
import 'package:biology/engine/pedigree_graph.dart';
import 'package:flutter_test/flutter_test.dart';

/// 取某代的 <基因型, 概率> 分布（仅 group 桶，外来样本不参与概率展示）。
Map<String, double> distOf(PedigreeGraphEngine e, int generation) {
  final out = <String, double>{};
  for (final n in e.nodesOf(generation)) {
    if (n.kind == PedigreeNodeKind.group) {
      out[n.genotype] = n.probability;
    }
  }
  return out;
}

/// 两个 double 分布近似相等。
void expectDistClose(
    Map<String, double> actual, Map<String, double> expected, double eps) {
  expect(actual.keys.toSet(), expected.keys.toSet(),
      reason: '基因型桶集合不一致');
  expected.forEach((k, v) {
    expect(actual[k], closeTo(v, eps), reason: '桶 $k 概率偏差');
  });
}

void main() {
  group('T-A2.1 初始化', () {
    test('P 代：父 male、母 female、一条 mating 边', () {
      final e = PedigreeGraphEngine(
          fatherGenotype: 'AaBb', motherGenotype: 'AaBb');
      expect(e.maxGeneration, 0);
      final p = e.nodesOf(0);
      expect(p.length, 2);
      final father = p.firstWhere((n) => n.id == 'P-father');
      final mother = p.firstWhere((n) => n.id == 'P-mother');
      expect(father.kind, PedigreeNodeKind.male);
      expect(mother.kind, PedigreeNodeKind.female);
      expect(father.genotype, 'AaBb');
      expect(mother.genotype, 'AaBb');
      expect(father.isExternal, isFalse);
      expect(mother.isExternal, isFalse);
      final mating = e.edges.where((x) => x.kind == PedigreeEdgeKind.mating);
      expect(mating.length, 1);
      expect(
          {mating.single.fromId, mating.single.toId},
          {'P-father', 'P-mother'});
    });
  });

  group('T-A2.2 expandNextGeneration 与数学库一致', () {
    test('AaBb×AaBb 的 F1 分布 == PedigreeEngine.cross，且带 lineage 边', () {
      final e = PedigreeGraphEngine(
          fatherGenotype: 'AaBb', motherGenotype: 'AaBb');
      final f1 = e.expandNextGeneration();
      expect(e.maxGeneration, 1);
      expect(f1, isNotEmpty);
      expect(f1.every((n) => n.kind == PedigreeNodeKind.group), isTrue);
      expectDistClose(
          distOf(e, 1), PedigreeEngine().cross('AaBb', 'AaBb'), 1e-9);
      // 每个 F1 节点都有来自 P 代双亲的 lineage 边
      for (final n in f1) {
        final src = e.edges
            .where((x) => x.kind == PedigreeEdgeKind.lineage && x.toId == n.id)
            .map((x) => x.fromId)
            .toSet();
        expect(src, containsAll({'P-father', 'P-mother'}));
      }
    });
  });

  group('T-A2.3 懒世代连续扩展', () {
    test('连续扩展到 F6 无上限报错，分布每代归一', () {
      final e =
          PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      e.ensureGeneration(6);
      expect(e.maxGeneration, 6);
      for (int g = 1; g <= 6; g++) {
        final d = distOf(e, g);
        expect(d, isNotEmpty, reason: 'F$g 不应为空');
        final sum = d.values.fold(0.0, (a, b) => a + b);
        expect(sum, closeTo(1.0, 1e-9), reason: 'F$g 分布应归一');
      }
    });
  });

  group('T-A2.4 外来接入 + 重算携带新样本', () {
    test('addExternal(aa♂) 到 F1 后 recomputeFrom(1)，F2 分布确实变化', () {
      final e =
          PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      e.ensureGeneration(2);
      final before = distOf(e, 2);

      final extId = e.addExternal(
          generation: 1, kind: PedigreeNodeKind.male, genotype: 'aa');
      expect(extId, 'EXT#1');
      // 添加后不自动重算：F2 分布仍等于接入前
      expectDistClose(distOf(e, 2), before, 1e-12);

      e.recomputeFrom(1);
      final after = distOf(e, 2);
      // 接入 aa 雄后 a 频率上升 → aa 桶概率增大，分布确实变化
      expect(after.keys.toSet(), before.keys.toSet());
      expect(after['aa']!, greaterThan(before['aa']!));
      expect((after['aa']! - before['aa']!).abs(), greaterThan(1e-6));
    });
  });

  group('T-A2.5 connect 校验矩阵', () {
    test('同性/自连/重复/不存在 均拒绝，合法（含 group/跨代回交）通过', () {
      final e =
          PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      e.ensureGeneration(1);
      final m0 = e.addExternal(
          generation: 0, kind: PedigreeNodeKind.male, genotype: 'AA');
      final m1 = e.addExternal(
          generation: 1, kind: PedigreeNodeKind.male, genotype: 'AA');
      final f1 = e.addExternal(
          generation: 1, kind: PedigreeNodeKind.female, genotype: 'aa');

      // 自连
      expect(e.connect(m1, m1), isFalse);
      // 不存在
      expect(e.connect(m1, 'NOPE'), isFalse);
      // 同性 male×male
      expect(e.connect('P-father', m0), isFalse);
      // 跨代（回交）现在合法：P-father × F1 外来♀
      expect(e.connect('P-father', f1), isTrue);
      expect(e.isBackcross('P-father', f1), isTrue);
      // 拒绝原因具体化
      expect(e.connectBlockReason(m1, m1), contains('自身'));
      expect(e.connectBlockReason('P-father', m0), contains('一雄一雌'));
      // 合法 male×female
      expect(e.connect(m1, f1), isTrue);
      // 重复（含反向）
      expect(e.connect(m1, f1), isFalse);
      expect(e.connect(f1, m1), isFalse);
      // group 可与任何性别连
      final groupNode = e
          .nodesOf(1)
          .firstWhere((n) => n.kind == PedigreeNodeKind.group);
      expect(e.connect(groupNode.id, f1), isTrue);
    });

    test('addExternal 拒绝 group 种类', () {
      final e =
          PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      expect(
          () => e.addExternal(
              generation: 0, kind: PedigreeNodeKind.group, genotype: 'Aa'),
          throwsArgumentError);
    });
  });

  group('T-A2.6 显式 mating 边定向杂交并入下一代', () {
    test('连边 AA♂×aa♀ 后重算，F2 分布与不连边引擎不同', () {
      PedigreeGraphEngine build({required bool withEdge}) {
        final e = PedigreeGraphEngine(
            fatherGenotype: 'Aa', motherGenotype: 'Aa');
        e.ensureGeneration(1);
        if (withEdge) {
          final m = e.addExternal(
              generation: 1, kind: PedigreeNodeKind.male, genotype: 'AA');
          final f = e.addExternal(
              generation: 1, kind: PedigreeNodeKind.female, genotype: 'aa');
          expect(e.connect(m, f), isTrue);
        }
        e.expandNextGeneration();
        return e;
      }

      final withoutEdge = distOf(build(withEdge: false), 2);
      final withEdgeDist = distOf(build(withEdge: true), 2);
      // AA×aa 定向杂交只产 Aa，并入后分布必然偏移
      var diff = 0.0;
      withoutEdge.forEach((k, v) {
        diff += ((withEdgeDist[k] ?? 0) - v).abs();
      });
      expect(diff, greaterThan(1e-6), reason: '显式 mating 边应改变 F2 分布');
      // 两引擎 F2 都仍归一
      expect(withEdgeDist.values.fold(0.0, (a, b) => a + b),
          closeTo(1.0, 1e-9));
    });
  });

  group('T-A2.7 removeExternal 回滚', () {
    test('删除外来样本后重算回到接入前分布', () {
      final e =
          PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      e.ensureGeneration(2);
      final before = distOf(e, 2);

      final extId = e.addExternal(
          generation: 1, kind: PedigreeNodeKind.male, genotype: 'aa');
      e.recomputeFrom(1);
      expect(distOf(e, 2)['aa'], isNot(closeTo(before['aa']!, 1e-9)));

      expect(e.removeExternal(extId), isTrue);
      e.recomputeFrom(1);
      expectDistClose(distOf(e, 2), before, 1e-9);
      // 相关边已连带删除
      expect(e.edges.any((x) => x.fromId == extId || x.toId == extId),
          isFalse);
    });

    test('非外来节点（P 代 / group 桶）不可删', () {
      final e =
          PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      e.ensureGeneration(1);
      expect(e.removeExternal('P-father'), isFalse);
      expect(e.removeExternal('F1#0'), isFalse);
      expect(e.removeExternal('NOPE'), isFalse);
    });
  });

  group('T-A2.8 致死场景不回归', () {
    test('引擎输出可被上层致死规则过滤（AA 致死）且剩余分布仍合法', () {
      // 说明：pedigree_engine.dart 本身无致死路径（致死规则在
      // genetics_env.dart，归 UI/环境层）。本用例验证图引擎输出的
      // 归一化分布与上层致死过滤流程兼容：剔除致死桶后归一化仍成立，
      // 且过滤后的分布可作为下一次扩展的输入而不破坏引擎。
      final e = PedigreeGraphEngine(
          fatherGenotype: 'Aa', motherGenotype: 'Aa');
      e.ensureGeneration(2);
      final f2 = distOf(e, 2);
      expect(f2['AA'], closeTo(0.25, 1e-9));

      // 上层致死过滤：AA 致死 → 剔除后归一化 → Aa:aa = 2:1
      final survived = Map<String, double>.of(f2)..remove('AA');
      final total = survived.values.fold(0.0, (a, b) => a + b);
      survived.updateAll((k, v) => v / total);
      expect(survived['Aa'], closeTo(2 / 3, 1e-9));
      expect(survived['aa'], closeTo(1 / 3, 1e-9));
      expect(survived.values.fold(0.0, (a, b) => a + b), closeTo(1.0, 1e-9));

      // 引擎自身在无致死下继续扩展不受影响
      e.expandNextGeneration();
      expect(e.maxGeneration, 3);
      expect(distOf(e, 3).values.fold(0.0, (a, b) => a + b),
          closeTo(1.0, 1e-9));
    });
  });

  group('T-A2.9 id 稳定性', () {
    test('重算后 F<代>#<序号> 位置 id 复用；EXT id 单调递增永不复用', () {
      final e =
          PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      e.ensureGeneration(2);
      final idsBefore = e.nodesOf(2).map((n) => n.id).toList();
      expect(idsBefore, contains('F2#0'));
      expect(
          idsBefore.every((id) => RegExp(r'^F2#\d+$').hasMatch(id)), isTrue);

      final ext1 = e.addExternal(
          generation: 1, kind: PedigreeNodeKind.male, genotype: 'aa');
      expect(ext1, 'EXT#1');
      e.recomputeFrom(1);
      final idsAfter = e.nodesOf(2).map((n) => n.id).toList();
      // 同位置 id 复用：仍是 F2#0..F2#n 形态
      expect(idsAfter, contains('F2#0'));
      expect(idsAfter.every((id) => RegExp(r'^F2#\d+$').hasMatch(id)),
          isTrue);

      // EXT 永不复用：删除后新增仍递增
      expect(e.removeExternal(ext1), isTrue);
      final ext2 = e.addExternal(
          generation: 1, kind: PedigreeNodeKind.female, genotype: 'AA');
      expect(ext2, 'EXT#2');
      expect(ext2, isNot(ext1));
    });
  });

  group('T-A2.10 安全阀', () {
    test('第 20 代可展开，第 21 代抛 StateError', () {
      final e =
          PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      e.ensureGeneration(20);
      expect(e.maxGeneration, 20);
      expect(() => e.expandNextGeneration(), throwsStateError);
      expect(() => e.ensureGeneration(21), throwsStateError);
    });
  });

  group('T-A2.11 重算保留下游外来样本（集成回归）', () {
    test('外来样本接入 F1 后 recomputeFrom(0)，样本存活且参与 F2 重算', () {
      // 基线：无外来样本时的 F2 分布
      final baseline =
          PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      baseline.ensureGeneration(2);
      final baseF2 = {
        for (final n in baseline.nodesOf(2)) n.genotype: n.probability
      };

      // 外来 aa♂ 接入 F1，从 P 代全量重算（模拟 UI「计算」按钮）
      final e =
          PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      e.ensureGeneration(2);
      e.addExternal(
          generation: 1, kind: PedigreeNodeKind.male, genotype: 'aa');
      e.recomputeFrom(0);

      // 外来样本存活（集成前会被 recomputeFrom(0) 吞掉）
      final f1 = e.nodesOf(1);
      expect(f1.any((n) => n.isExternal && n.genotype == 'aa'), isTrue,
          reason: 'recomputeFrom(0) 不得丢弃 F1 的外来样本');
      // F2 分布因外来样本参与而变化
      final f2 = {for (final n in e.nodesOf(2)) n.genotype: n.probability};
      var differs = f2.length != baseF2.length;
      if (!differs) {
        for (final k in f2.keys) {
          if ((f2[k]! - (baseF2[k] ?? 0)).abs() > 1e-9) differs = true;
        }
      }
      expect(differs, isTrue, reason: '外来样本应参与 F2 重算使分布变化');
    });
  });

  group('T-A2.12 回交（跨代 mating）', () {
    test('F1 group × P-father 回交边在扩展到 F2 时贡献定向杂交', () {
      PedigreeGraphEngine build({required bool backcross}) {
        final e =
            PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
        e.ensureGeneration(1);
        if (backcross) {
          final f1Group =
              e.nodesOf(1).firstWhere((n) => n.genotype == 'aa');
          expect(e.connect(f1Group.id, 'P-mother'), isTrue,
              reason: '跨代回交应允许');
        }
        e.expandNextGeneration();
        return e;
      }

      final plain = build(backcross: false);
      final crossed = build(backcross: true);
      Map<String, double> distOf(PedigreeGraphEngine e) =>
          {for (final n in e.nodesOf(2)) n.genotype: n.probability};
      final a = distOf(plain);
      final b = distOf(crossed);
      // aa(F1) × Aa(P-mother) 定向杂交并入 → F2 分布变化且 aa 占比上升
      var differs = a.length != b.length;
      if (!differs) {
        for (final k in b.keys) {
          if ((b[k]! - (a[k] ?? 0)).abs() > 1e-9) differs = true;
        }
      }
      expect(differs, isTrue, reason: '回交边应改变 F2 分布');
      expect((b['aa'] ?? 0) > (a['aa'] ?? 0), isTrue,
          reason: 'aa×Aa 回交应抬高 F2 中 aa 占比');
    });
  });

  group('T-A2.13 editExternal 编辑样本', () {
    test('编辑基因型/性别生效；非法目标拒绝；性别翻转后同性 mating 边被清理', () {
      final e =
          PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      e.ensureGeneration(1);
      final id = e.addExternal(
          generation: 1, kind: PedigreeNodeKind.male, genotype: 'AA');
      final fId = e.addExternal(
          generation: 1, kind: PedigreeNodeKind.female, genotype: 'aa');
      expect(e.connect(id, fId), isTrue);

      // 非外来节点不可编辑
      expect(e.editExternal('P-father', genotype: 'AA'), isFalse);
      // 奇数长度基因型拒绝
      expect(e.editExternal(id, genotype: 'AaB'), isFalse);
      // group 种类拒绝
      expect(
          e.editExternal(id, kind: PedigreeNodeKind.group), isFalse);

      // 合法编辑：基因型 + 性别翻转（male→female 后与 fId 的边变同性，应被清理）
      expect(
          e.editExternal(id,
              genotype: 'Aa', kind: PedigreeNodeKind.female),
          isTrue);
      final edited = e.nodes.firstWhere((n) => n.id == id);
      expect(edited.genotype, 'Aa');
      expect(edited.kind, PedigreeNodeKind.female);
      expect(
          e.edges.any((ed) =>
              ed.kind == PedigreeEdgeKind.mating &&
              ((ed.fromId == id && ed.toId == fId) ||
                  (ed.fromId == fId && ed.toId == id))),
          isFalse,
          reason: '性别翻转后同性 mating 边必须清理');

      // 编辑后重算下游携带新基因型
      e.ensureGeneration(2);
      e.recomputeFrom(1);
      final f2 = {for (final n in e.nodesOf(2)) n.genotype: n.probability};
      expect(f2.isNotEmpty, isTrue);
    });
  });

  group('T-A2.14 回交边跨重算存活（group 端点基因型重映射）', () {
    test('连线 → 计算（recomputeFrom(0)）→ 回交边存活且子代分布不变', () {
      final e = PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      e.expandNextGeneration(); // F1
      final aa = e.nodesOf(1).firstWhere((n) => n.genotype == 'aa');
      expect(e.connect('P-mother', aa.id), isTrue, reason: '回交允许');
      e.ensureOffspringCoverage(); // 回交子代落在 F2
      expect(e.maxGeneration, 2, reason: '回交连线应触发覆盖到子代世代');
      final before = distOf(e, 2);

      // 对照：无回交的 F2 分布必须不同（回交确实生效）
      final ctrl = PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      ctrl.ensureGeneration(2);
      final plain = distOf(ctrl, 2);
      var differs = before.length != plain.length;
      if (!differs) {
        for (final k in before.keys) {
          if ((before[k]! - (plain[k] ?? 0)).abs() > 1e-9) differs = true;
        }
      }
      expect(differs, isTrue, reason: '回交边应改变 F2 分布');

      // 用户操作路径：连线后点「计算」= recomputeFrom(0)。
      // 修复前：回交边随 F1 group 销毁永久丢失 → 无计算结果。
      e.recomputeFrom(0);

      // 边存活（P-father×P-mother + 重映射后的回交边）
      final matings = e.edges
          .where((x) => x.kind == PedigreeEdgeKind.mating)
          .toList();
      expect(matings.length, 2, reason: '回交边必须跨重算存活');
      final bc = matings.firstWhere((x) =>
          (x.fromId == 'P-mother' && x.toId != 'P-father') ||
          (x.toId == 'P-mother' && x.fromId != 'P-father'));
      final other = bc.fromId == 'P-mother' ? bc.toId : bc.fromId;
      final remapped = e.nodes.firstWhere((n) => n.id == other);
      expect(remapped.generation, 1);
      expect(remapped.genotype, 'aa', reason: '重映射必须指向新 F1 的 aa 桶');

      // 分布与重算前一致 → 回交边真正参与计算
      expectDistClose(distOf(e, 2), before, 1e-9);
    });

    test('重算后基因型消失的 group 端点边被干净丢弃', () {
      final e = PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      e.expandNextGeneration(); // F1
      final extId = e.addExternal(
          generation: 1, kind: PedigreeNodeKind.female, genotype: 'bb');
      e.expandNextGeneration(); // F2 含带 b 的桶（F1 池 × bb 外来样本）
      final bGeno =
          e.nodesOf(2).firstWhere((n) => n.genotype.contains('b'));
      expect(e.connect('P-father', bGeno.id), isTrue, reason: '回交到 F2 允许');

      // 删除外来贡献者 → F2 重建后带 b 的桶消失 → 边应干净丢弃
      e.removeExternal(extId);
      e.recomputeFrom(1);
      expect(
          distOf(e, 2).keys.any((g) => g.contains('b')), isFalse,
          reason: '删除 bb 后 F2 不应再有带 b 基因型');
      final matings = e.edges
          .where((x) => x.kind == PedigreeEdgeKind.mating)
          .toList();
      expect(matings.length, 1, reason: '基因型消失的回交边必须丢弃，不留悬空端点');
      expect(matings.single.fromId, 'P-father');
      expect(matings.single.toId, 'P-mother');
    });
  });

  group('T-A2.15 同性交配开关', () {
    test('默认雄性×雄性拒绝；开启开关后允许', () {
      final e = PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      e.expandNextGeneration();
      final m = e.addExternal(
          generation: 1, kind: PedigreeNodeKind.male, genotype: 'AA');
      // 默认：雄×雄拒绝
      expect(e.connect('P-father', m), isFalse);
      expect(e.connectBlockReason('P-father', m), contains('同性交配'));
      // 开启开关：允许
      e.allowSameSexMating = true;
      expect(e.connect('P-father', m), isTrue);
      // 关闭开关后既有边不追溯清理，但新连线再次被拒
      e.allowSameSexMating = false;
      final m2 = e.addExternal(
          generation: 1, kind: PedigreeNodeKind.male, genotype: 'aa');
      expect(e.connect('P-father', m2), isFalse);
    });
  });

  group('T-A2.16 XY 性别存证开关', () {
    test('开启后新计算桶携带 maleFraction=0.5，关闭为 null', () {
      final e = PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      e.trackSex = true;
      e.expandNextGeneration();
      for (final n in e.nodesOf(1)) {
        expect(n.maleFraction, 0.5, reason: 'XY 开关开启后桶应有雌雄比存证');
      }
      final plain = PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      plain.expandNextGeneration();
      for (final n in plain.nodesOf(1)) {
        expect(n.maleFraction, isNull, reason: '默认不区分性别');
      }
    });
  });

  group('T-A2.17 detachLatestMating（收线）', () {
    test('摘下最近一条 mating 边并返回；无边返回 null；不影响 lineage', () {
      final e = PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      e.expandNextGeneration();
      final m = e.addExternal(
          generation: 1, kind: PedigreeNodeKind.female, genotype: 'AA');
      e.connect('P-father', m);
      expect(e.matingCountOf('P-father'), 2);

      // 摘下 P-father 最近一条 = P-father×EXT（后建的）
      final detached = e.detachLatestMating('P-father');
      expect(detached, isNotNull);
      expect(detached!.toId, m);
      expect(e.matingCountOf('P-father'), 1);

      // 再摘 = 创始边 P-father×P-mother
      final founding = e.detachLatestMating('P-father');
      expect(founding, isNotNull);
      expect(founding!.toId, 'P-mother');
      expect(e.matingCountOf('P-father'), 0);
      expect(e.detachLatestMating('P-father'), isNull);

      // lineage 边不受影响
      expect(
          e.edges.any((x) => x.kind == PedigreeEdgeKind.lineage), isTrue);
    });
  });
  group('R7 新增：世代收缩 / 桶分裂 / 伴性标注', () {
    test('collapseGeneration(1) 删除 F1+ 及其边，保留下游外来样本，可再展开',
        () {
      final e = PedigreeGraphEngine(
          fatherGenotype: 'AaBb', motherGenotype: 'AaBb');
      e.expandNextGeneration();
      e.expandNextGeneration();
      final ext = e.addExternal(generation: 2, kind: PedigreeNodeKind.male, genotype: 'aabb');
      expect(e.maxGeneration, 2);
      e.collapseGeneration(1);
      expect(e.maxGeneration, 0);
      expect(e.nodes.any((n) => n.id == ext), isTrue); // 外来样本保留
      expect(
          e.edges.any((x) =>
              x.kind == PedigreeEdgeKind.lineage &&
              (x.fromId.startsWith('F1') || x.toId.startsWith('F1'))),
          isFalse);
      expect(e.nodes.where((n) => n.generation >= 1 && !n.isExternal),
          isEmpty);
      e.expandNextGeneration(); // 收缩后仍可再展开
      expect(e.maxGeneration, 1);
    });

    test('collapseGeneration(0) 清空全部世代，回到初始 P×P', () {
      final e =
          PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      e.expandNextGeneration();
      e.expandNextGeneration();
      e.collapseGeneration(0);
      expect(e.maxGeneration, 0);
      expect(e.nodes.length, 2);
      e.expandNextGeneration();
      expect(distOf(e, 1)['AA'], closeTo(0.25, 1e-9));
    });

    test('splitBucketBySex：桶拆成 X(矩形)+Y(圆)，概率各半，幂等', () {
      final e =
          PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      e.expandNextGeneration();
      final bucket = e
          .nodesOf(1)
          .firstWhere((n) => n.kind == PedigreeNodeKind.group);
      final before = e.nodes.length;
      final children = e.splitBucketBySex(bucket.id);
      expect(children, isNotNull);
      expect(children!.length, 2);
      expect(children[0].kind, PedigreeNodeKind.male);
      expect(children[0].maleFraction, 1.0);
      expect(children[1].kind, PedigreeNodeKind.female);
      expect(children[1].maleFraction, 0.0);
      expect(children[0].probability,
          closeTo(bucket.probability / 2, 1e-12));
      expect(children[1].probability,
          closeTo(bucket.probability / 2, 1e-12));
      expect(e.nodes.length, before + 2);
      // lineage 边挂到两个子节点
      expect(
          e.edges.where((x) =>
              x.kind == PedigreeEdgeKind.lineage &&
              (x.toId == children[0].id || x.toId == children[1].id)).length,
          2);
      // 幂等：再分裂返回同一对，不新增
      final again = e.splitBucketBySex(bucket.id);
      expect(again!.map((c) => c.id).toSet(),
          children.map((c) => c.id).toSet());
      expect(e.nodes.length, before + 2);
      // 非桶节点拒绝
      expect(e.splitBucketBySex('P-father'), isNull);
    });

    test('SexLinkedConfig.annotate：X/x 段标注且大小写正确，常染色体位点不标',
        () {
      const cfg = SexLinkedConfig(xLabel: '病', xLowerLabel: '正常');
      expect(cfg.isEmpty, isFalse);
      final segs = cfg.annotate('AaXx');
      expect(segs.length, 4);
      expect(segs[0].isSexLinked, isFalse); // A
      expect(segs[2].allele, 'X');
      expect(segs[2].isSexLinked, isTrue);
      expect(segs[2].isUpper, isTrue);
      expect(segs[2].label, '病');
      expect(segs[3].allele, 'x');
      expect(segs[3].isUpper, isFalse);
      expect(segs[3].label, '正常');
      const empty = SexLinkedConfig();
      expect(empty.isEmpty, isTrue);
      expect(empty.annotate('Xx').every((s) => s.label == null), isTrue);
    });
  });
  group('T-A2.15 多家族（R14）', () {
    test('T-A2.15.1 addFamily 建独立双亲 + 家族标签', () {
      final e = PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      final k = e.addFamily(fatherGenotype: 'Bb', motherGenotype: 'Bb');
      expect(k, 1);
      expect(e.familyLabel(0), 'A');
      expect(e.familyLabel(1), 'B');
      expect(e.familyIds, [0, 1]);
      expect(e.nodes.firstWhere((n) => n.id == 'P1-father').familyId, 1);
      expect(e.nodes.firstWhere((n) => n.id == 'P1-mother').familyId, 1);
      // 新家族自带 P×P 交配边
      expect(
          e.edges.any((x) =>
              x.kind == PedigreeEdgeKind.mating &&
              ((x.fromId == 'P1-father' && x.toId == 'P1-mother') ||
                  (x.fromId == 'P1-mother' && x.toId == 'P1-father'))),
          isTrue);
      // 非法基因型抛 ArgumentError
      expect(() => e.addFamily(fatherGenotype: 'A', motherGenotype: 'Aa'),
          throwsArgumentError);
    });

    test('T-A2.15.2 两家族独立繁衍（各自交配池互不串味）', () {
      final e = PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      e.addFamily(fatherGenotype: 'Bb', motherGenotype: 'Bb');
      e.expandNextGeneration();
      final fam0 = e.nodesOf(1).where((n) => n.familyId == 0).toList();
      final fam1 = e.nodesOf(1).where((n) => n.familyId == 1).toList();
      expect(fam0.map((n) => n.genotype).toSet(), {'AA', 'Aa', 'aa'});
      expect(fam1.map((n) => n.genotype).toSet(), {'BB', 'Bb', 'bb'});
      // 各家族分布各自归一化
      expect(fam0.fold(0.0, (s, n) => s + n.probability), closeTo(1.0, 1e-9));
      expect(fam1.fold(0.0, (s, n) => s + n.probability), closeTo(1.0, 1e-9));
    });

    test('T-A2.15.3 跨家族交配产生合并家族子代（且只触发一次）', () {
      final e = PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      e.addFamily(fatherGenotype: 'Bb', motherGenotype: 'Bb');
      e.ensureGeneration(1);
      final a = e
          .nodesOf(1)
          .firstWhere((n) => n.familyId == 0 && n.genotype == 'aa');
      final b = e
          .nodesOf(1)
          .firstWhere((n) => n.familyId == 1 && n.genotype == 'bb');
      e.connect(a.id, b.id);
      e.expandNextGeneration();
      // 合并家族 = 编号 2，标签 A×B，子代在 F2
      expect(e.familyLabel(2), 'A\u00d7B');
      final merged = e.nodesOf(2).where((n) => n.familyId == 2).toList();
      expect(merged.length, 1,
          reason: '驱动家族规则保证跨家族边只触发一次，不重复建桶');
      expect(merged.single.genotype, 'ba');
      expect(merged.single.probability, closeTo(1.0, 1e-9));
      // 两个创始家族自己的 F2 也照常产出且各自归一化
      final f0 = e.nodesOf(2).where((n) => n.familyId == 0).toList();
      final f1 = e.nodesOf(2).where((n) => n.familyId == 1).toList();
      expect(f0, isNotEmpty);
      expect(f1, isNotEmpty);
      expect(f0.fold(0.0, (s, n) => s + n.probability), closeTo(1.0, 1e-9));
      expect(f1.fold(0.0, (s, n) => s + n.probability), closeTo(1.0, 1e-9));
    });

    test('T-A2.15.4 合并家族继续自繁（A×B 的 F3）', () {
      final e = PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      e.addFamily(fatherGenotype: 'Bb', motherGenotype: 'Bb');
      e.ensureGeneration(1);
      final a = e
          .nodesOf(1)
          .firstWhere((n) => n.familyId == 0 && n.genotype == 'aa');
      final b = e
          .nodesOf(1)
          .firstWhere((n) => n.familyId == 1 && n.genotype == 'bb');
      e.connect(a.id, b.id);
      e.expandNextGeneration(); // F2：合并家族 ab 桶出现
      e.expandNextGeneration(); // F3：合并家族自繁 ba×ba
      final m3 = e.nodesOf(3).where((n) => n.familyId == 2).toList();
      expect(m3.map((n) => n.genotype).toSet(), {'aa', 'ab', 'ba', 'bb'});
      expect(m3.fold(0.0, (s, n) => s + n.probability), closeTo(1.0, 1e-9));
    });

    test('T-A2.15.5 recomputeFrom(0) 后跨家族边与合并家族分布重建一致', () {
      final e = PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      e.addFamily(fatherGenotype: 'Bb', motherGenotype: 'Bb');
      e.ensureGeneration(1);
      final a = e
          .nodesOf(1)
          .firstWhere((n) => n.familyId == 0 && n.genotype == 'aa');
      final b = e
          .nodesOf(1)
          .firstWhere((n) => n.familyId == 1 && n.genotype == 'bb');
      e.connect(a.id, b.id);
      e.expandNextGeneration();
      List<String> sig() => e.nodes
          .map((n) => '${n.familyId}|${n.generation}|${n.genotype}')
          .toList()
        ..sort();
      final before = sig();
      e.recomputeFrom(0);
      expect(sig(), before, reason: '全量重算后（家族,世代,基因型）集合应不变');
      // 跨家族 mating 边已重挂回新桶 id
      final a2 = e
          .nodesOf(1)
          .firstWhere((n) => n.familyId == 0 && n.genotype == 'aa');
      final b2 = e
          .nodesOf(1)
          .firstWhere((n) => n.familyId == 1 && n.genotype == 'bb');
      expect(
          e.edges.any((x) =>
              x.kind == PedigreeEdgeKind.mating &&
              ((x.fromId == a2.id && x.toId == b2.id) ||
                  (x.fromId == b2.id && x.toId == a2.id))),
          isTrue);
      // 合并家族仍是编号 2（成分幂等）
      expect(e.familyLabel(2), 'A\u00d7B');
    });

    test('T-A2.15.6 删除上一代保留全部家族创始双亲', () {
      final e = PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      e.addFamily(fatherGenotype: 'Bb', motherGenotype: 'Bb');
      e.ensureGeneration(2);
      expect(e.maxGeneration, 2);
      e.collapseGeneration(1);
      expect(e.maxGeneration, 0);
      expect(e.nodes.any((n) => n.id == 'P-father'), isTrue);
      expect(e.nodes.any((n) => n.id == 'P-mother'), isTrue);
      expect(e.nodes.any((n) => n.id == 'P1-father'), isTrue);
      expect(e.nodes.any((n) => n.id == 'P1-mother'), isTrue);
      expect(e.nodesOf(0).length, 4);
      // 折叠后两家族可重新推进
      e.expandNextGeneration();
      expect(e.nodesOf(1).where((n) => n.familyId == 0), isNotEmpty);
      expect(e.nodesOf(1).where((n) => n.familyId == 1), isNotEmpty);
    });

    test('T-A2.15.7 外来样本加入指定家族池（不影响另一家族）', () {
      final e = PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      e.addFamily(fatherGenotype: 'Bb', motherGenotype: 'Bb');
      e.ensureGeneration(1);
      e.addExternal(
          generation: 1,
          kind: PedigreeNodeKind.female,
          genotype: 'AA',
          familyId: 0);
      e.expandNextGeneration();
      // 家族 A 的 F2 因 AA 外来雌加入而 AA 占比上升（基线 0.25）
      final aaBucket = e.nodesOf(2).firstWhere(
          (n) => n.familyId == 0 && n.genotype == 'AA');
      expect(aaBucket.probability, greaterThan(0.25));
      // 家族 B 的 F2 不受任何影响
      final f1 = e.nodesOf(2).where((n) => n.familyId == 1).toList();
      final d = {for (final n in f1) n.genotype: n.probability};
      expect(d['BB'], closeTo(0.25, 1e-9));
      expect(d['Bb'], closeTo(0.5, 1e-9));
      expect(d['bb'], closeTo(0.25, 1e-9));
      // 加错家族编号抛 ArgumentError
      expect(
          () => e.addExternal(
              generation: 1,
              kind: PedigreeNodeKind.male,
              genotype: 'Aa',
              familyId: 99),
          throwsArgumentError);
    });
  });

  group('T-A2.16 R15 组合桶懒分裂（ensureHalf / halfNode）', () {
    test('T-A2.16.1 未分裂桶：ensureHalf 现场分裂，返回对应性别半边', () {
      final e = PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      e.trackSex = true;
      e.ensureGeneration(1);
      final bucket =
          e.nodesOf(1).firstWhere((n) => n.kind == PedigreeNodeKind.group);
      final before = e.nodes.length;
      final maleId = e.ensureHalf(bucket.id, PedigreeNodeKind.male);
      final femaleId = e.ensureHalf(bucket.id, PedigreeNodeKind.female);
      expect(e.nodes.length, before + 2, reason: '分裂只新增 X/Y 两个半边');
      expect(maleId, isNot(femaleId));
      final male = e.nodes.firstWhere((n) => n.id == maleId);
      final female = e.nodes.firstWhere((n) => n.id == femaleId);
      expect(male.kind, PedigreeNodeKind.male);
      expect(female.kind, PedigreeNodeKind.female);
      expect(male.probability, closeTo(bucket.probability * 0.5, 1e-9));
      expect(male.generation, bucket.generation);
      expect(male.familyId, bucket.familyId);
    });

    test('T-A2.16.2 幂等：重复 ensureHalf 返回同一 id，不产生新节点', () {
      final e = PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      e.trackSex = true;
      e.ensureGeneration(1);
      final bucket =
          e.nodesOf(1).firstWhere((n) => n.kind == PedigreeNodeKind.group);
      final first = e.ensureHalf(bucket.id, PedigreeNodeKind.male);
      final countAfterSplit = e.nodes.length;
      final second = e.ensureHalf(bucket.id, PedigreeNodeKind.male);
      expect(second, first);
      expect(e.nodes.length, countAfterSplit);
    });

    test('T-A2.16.3 传入已是半边的节点：kind 匹配返回自身，不匹配抛错', () {
      final e = PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      e.trackSex = true;
      e.ensureGeneration(1);
      final bucket =
          e.nodesOf(1).firstWhere((n) => n.kind == PedigreeNodeKind.group);
      final maleId = e.ensureHalf(bucket.id, PedigreeNodeKind.male);
      // 半边传入：kind 匹配 → 幂等返回自身
      expect(e.ensureHalf(maleId, PedigreeNodeKind.male), maleId);
      // kind 不匹配 → ArgumentError
      expect(() => e.ensureHalf(maleId, PedigreeNodeKind.female),
          throwsArgumentError);
    });

    test('T-A2.16.4 非法输入：非桶非半边 / 节点不存在 / group 性别', () {
      final e = PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      e.ensureGeneration(1);
      expect(() => e.ensureHalf('P-father', PedigreeNodeKind.male),
          throwsArgumentError);
      expect(() => e.ensureHalf('NOPE#1', PedigreeNodeKind.male),
          throwsArgumentError);
      expect(
          () => e.ensureHalf('P-father', PedigreeNodeKind.group),
          throwsArgumentError);
    });

    test('T-A2.16.5 halfNode 只读不分裂；懒分裂后半边可连线（雄×雌）', () {
      final e = PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      e.trackSex = true;
      e.ensureGeneration(1);
      final b1 = e.nodesOf(1).firstWhere(
          (n) => n.kind == PedigreeNodeKind.group && n.genotype == 'AA');
      final b2 = e.nodesOf(1).firstWhere(
          (n) => n.kind == PedigreeNodeKind.group && n.genotype == 'aa');
      // halfNode 只读：未分裂时返回 null 且节点数不变
      final before = e.nodes.length;
      expect(e.halfNode(b1.id, PedigreeNodeKind.male), isNull);
      expect(e.nodes.length, before);
      // 懒分裂 + 连线：两个桶各取一边，一雄一雌合法
      final m = e.ensureHalf(b1.id, PedigreeNodeKind.male);
      final f = e.ensureHalf(b2.id, PedigreeNodeKind.female);
      expect(e.connectBlockReason(m, f), isNull);
      expect(e.connect(m, f), isTrue);
      expect(e.matingCountOf(m), 1);
      // halfNode 现在能查到
      expect(e.halfNode(b1.id, PedigreeNodeKind.male)?.id, m);
    });
  });

  group('T-A2.17 基因对数一致性校验（R15 崩溃修复）', () {
    test('T-A2.17.1 cross 不等长亲本抛 ArgumentError（而非 RangeError 裸崩）',
        () {
      final m = PedigreeEngine();
      expect(() => m.cross('AABBCC', 'aa'), throwsArgumentError);
      // 等长正常
      final d = m.cross('Aa', 'Aa');
      expect(d['Aa'], closeTo(0.5, 1e-9));
    });

    test('T-A2.17.2 connect 拦截基因对数不一致的配对（跨家族场景）', () {
      final e = PedigreeGraphEngine(
          fatherGenotype: 'AABBCC', motherGenotype: 'aabbcc');
      e.addFamily(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      // 家族 A 的 P-father（3 对，雄）× 家族 B 的 P1-mother（1 对，雌）
      final reason = e.connectBlockReason('P-father', 'P1-mother');
      expect(reason, isNotNull);
      expect(reason, contains('基因对数不一致'));
      expect(e.connect('P-father', 'P1-mother'), isFalse);
      // 同家族同对数不受影响（家族 B 加 1 对样本与 P1-father 配对）
      final ext = e.addExternal(
          generation: 0, kind: PedigreeNodeKind.female, genotype: 'aa',
          familyId: 1);
      expect(e.connectBlockReason('P1-father', ext), isNull);
      expect(e.connect('P1-father', ext), isTrue);
    });

    test('T-A2.17.3 addExternal 对数不符抛 ArgumentError，附补齐提示', () {
      final e = PedigreeGraphEngine(
          fatherGenotype: 'AABBCC', motherGenotype: 'aabbcc');
      expect(
          () => e.addExternal(
              generation: 1, kind: PedigreeNodeKind.female, genotype: 'aa'),
          throwsArgumentError);
      // 一致对数正常添加
      final id = e.addExternal(
          generation: 1, kind: PedigreeNodeKind.female, genotype: 'aabbcc');
      expect(id, startsWith('EXT#'));
      // 多家族：以目标家族双亲对数为基准
      e.addFamily(fatherGenotype: 'Bb', motherGenotype: 'Bb');
      final id2 = e.addExternal(
          generation: 0, kind: PedigreeNodeKind.male, genotype: 'bb',
          familyId: 1);
      expect(id2, startsWith('EXT#'));
      expect(
          () => e.addExternal(
              generation: 0,
              kind: PedigreeNodeKind.male,
              genotype: 'bbcc',
              familyId: 1),
          throwsArgumentError);
    });

    test('T-A2.17.4 editExternal：改对数被拒，且 familyId 保留不丢', () {
      final e = PedigreeGraphEngine(
          fatherGenotype: 'AABBCC', motherGenotype: 'aabbcc');
      e.addFamily(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      final id = e.addExternal(
          generation: 0, kind: PedigreeNodeKind.male, genotype: 'AA',
          familyId: 1);
      // 改对数 → false
      expect(e.editExternal(id, genotype: 'AAAA'), isFalse);
      // 同对数编辑成功，familyId 不丢（修复：此前重建节点丢失 familyId）
      expect(e.editExternal(id, genotype: 'aa'), isTrue);
      final n = e.nodes.firstWhere((n) => n.id == id);
      expect(n.genotype, 'aa');
      expect(n.familyId, 1);
    });

    test('T-A2.17.5 用户崩溃场景回归：半边连线+对数一致回交+重算 不抛',
        () {
      final e = PedigreeGraphEngine(
          fatherGenotype: 'AABBCC', motherGenotype: 'aabbcc');
      e.trackSex = true;
      e.recomputeFrom(0);
      e.ensureOffspringCoverage();
      final bucket = e
          .nodesOf(1)
          .firstWhere((n) => n.kind == PedigreeNodeKind.group);
      final m = e.ensureHalf(bucket.id, PedigreeNodeKind.male);
      final f = e.ensureHalf(bucket.id, PedigreeNodeKind.female);
      expect(e.connect(m, f), isTrue);
      final ext = e.addExternal(
          generation: 1, kind: PedigreeNodeKind.female, genotype: 'aabbcc');
      expect(e.connect('P-father', ext), isTrue);
      e.recomputeFrom(0);
      e.ensureOffspringCoverage();
      expect(e.maxGeneration, greaterThanOrEqualTo(1));
    });
  });

  group('T-A2.18 R16 快照与多步回退', () {
    test('T-A2.18.1 快照恢复完整状态：节点/边/计数器/家族表/开关', () {
      final e =
          PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      e.trackSex = true;
      e.ensureGeneration(1);
      e.addFamily(fatherGenotype: 'Bb', motherGenotype: 'Bb');
      final ext = e.addExternal(
          generation: 1, kind: PedigreeNodeKind.female, genotype: 'aa');
      final snap = e.takeSnapshot();
      final nodesAtSnap = e.nodes.length;
      final edgesAtSnap = e.edges.length;

      // 继续操作改变状态
      e.trackSex = false;
      e.expandNextGeneration();
      expect(e.nodes.length, greaterThan(nodesAtSnap));

      // 恢复快照
      e.restoreSnapshot(snap);
      expect(e.nodes.length, nodesAtSnap);
      expect(e.edges.length, edgesAtSnap);
      expect(e.maxGeneration, 1);
      expect(e.trackSex, isTrue, reason: '开关状态也在快照里');
      expect(e.nodes.any((n) => n.id == ext), isTrue);
      expect(e.familyIds.length, 2, reason: '家族注册表恢复');

      // 恢复后继续操作正常：计数器恢复，id 不复用
      final ext2 = e.addExternal(
          generation: 1, kind: PedigreeNodeKind.male, genotype: 'AA');
      expect(ext2, isNot(ext), reason: 'extCounter 恢复后不复用 id');
      final bucket = e
          .nodesOf(1)
          .firstWhere((n) => n.kind == PedigreeNodeKind.group);
      final half = e.ensureHalf(bucket.id, PedigreeNodeKind.male);
      expect(half, startsWith('SPLIT#'), reason: 'splitCounter 恢复后正常');
    });

    test('T-A2.18.2 恢复后重做跨家族合并：家族编号幂等一致', () {
      final e =
          PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      e.addFamily(fatherGenotype: 'Bb', motherGenotype: 'Bb');
      e.ensureGeneration(1);
      final a = e
          .nodesOf(1)
          .firstWhere((n) => n.familyId == 0 && n.genotype == 'aa');
      final b = e
          .nodesOf(1)
          .firstWhere((n) => n.familyId == 1 && n.genotype == 'bb');
      final snap = e.takeSnapshot();

      // 跨家族连线（F1 代节点）→ 扩展后合并家族子代在 F2
      expect(e.connect(a.id, b.id), isTrue);
      e.expandNextGeneration();
      final mergedCount = e.familyIds.length;
      expect(mergedCount, greaterThan(2));

      // 回退 → 合并家族消失；重做 → 编号一致（幂等）
      e.restoreSnapshot(snap);
      expect(e.familyIds.length, 2);
      expect(e.connect(a.id, b.id), isTrue);
      e.expandNextGeneration();
      expect(e.familyIds.length, mergedCount);
    });
  });

  group('R17 混合外部样本（addExternalGroup）', () {
    test('T-A2.19.1 创建混合桶：group + 外来 + 概率0 + 落位目标世代', () {
      final e = PedigreeGraphEngine(
          fatherGenotype: 'AaBb', motherGenotype: 'AaBb');
      e.expandNextGeneration();
      final id = e.addExternalGroup(generation: 1, genotype: 'aabb');
      final n = e.nodes.firstWhere((x) => x.id == id);
      expect(n.kind, PedigreeNodeKind.group);
      expect(n.isExternal, isTrue);
      expect(n.probability, 0.0);
      expect(n.generation, 1);
      expect(n.maleFraction, 0.5);
    });

    test('T-A2.19.2 基因对数不一致 / 空基因型 / addExternal 传 group 均被拦',
        () {
      final e = PedigreeGraphEngine(
          fatherGenotype: 'AaBb', motherGenotype: 'AaBb');
      expect(() => e.addExternalGroup(generation: 1, genotype: 'aa'),
          throwsArgumentError);
      expect(() => e.addExternalGroup(generation: 1, genotype: ''),
          throwsArgumentError);
      expect(
          () => e.addExternal(
              generation: 1,
              kind: PedigreeNodeKind.group,
              genotype: 'aabb'),
          throwsArgumentError);
    });

    test('T-A2.19.3 半边继承外来身份：重算后桶、半边、连线全保留', () {
      final e =
          PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      e.expandNextGeneration(); // F1
      final gid = e.addExternalGroup(generation: 1, genotype: 'aa');
      final fId = e.addExternal(
          generation: 1, kind: PedigreeNodeKind.female, genotype: 'Aa');
      final maleHalf = e.ensureHalf(gid, PedigreeNodeKind.male);
      expect(e.nodes.firstWhere((n) => n.id == maleHalf).isExternal, isTrue,
          reason: '外来混合桶的半边应同为外来（重算不回收）');
      expect(e.connect(maleHalf, fId), isTrue);
      e.expandNextGeneration(); // F2（制造可重算的下游）

      e.recomputeFrom(0);
      expect(e.nodes.any((n) => n.id == gid), isTrue, reason: '混合桶保留');
      expect(e.nodes.any((n) => n.id == maleHalf), isTrue, reason: '半边保留');
      expect(
        e.edges.any((ed) =>
            ed.kind == PedigreeEdgeKind.mating &&
            ((ed.fromId == maleHalf && ed.toId == fId) ||
                (ed.fromId == fId && ed.toId == maleHalf))),
        isTrue,
        reason: '半边上的连线在重算后不应丢失',
      );
    });

    test('T-A2.19.4 删除混合桶连带半边；性别不可改、基因型可改', () {
      final e =
          PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      final gid = e.addExternalGroup(generation: 1, genotype: 'aa');
      final half = e.ensureHalf(gid, PedigreeNodeKind.female);
      expect(e.editExternal(gid, kind: PedigreeNodeKind.male), isFalse,
          reason: '混合桶不可改成单性别');
      expect(e.editExternal(gid, genotype: 'Aa'), isTrue);
      expect(e.nodes.firstWhere((n) => n.id == gid).genotype, 'Aa');

      expect(e.removeExternal(gid), isTrue);
      expect(e.nodes.any((n) => n.id == gid), isFalse);
      expect(e.nodes.any((n) => n.id == half), isFalse,
          reason: '半边应随母桶一并删除');
      expect(e.edges.any((ed) => ed.fromId == gid || ed.toId == gid),
          isFalse);
    });
  });

  group('R18 基因缺失交配（allowMissingGeneMating）', () {
    test('T-A2.20.1 默认关：添加/连线/杂交不同对数全部被拦', () {
      final e = PedigreeGraphEngine(
          fatherGenotype: 'AaBb', motherGenotype: 'AaBb');
      expect(
          () => e.addExternal(
              generation: 0, kind: PedigreeNodeKind.female, genotype: 'aa'),
          throwsArgumentError,
          reason: '默认关：添加不同对数样本被拦');
      expect(() => PedigreeEngine().cross('AaBb', 'aa'), throwsArgumentError,
          reason: '默认关：crossGametes 抛错');
    });

    test('T-A2.20.2 开启后可连可算：子代缺失位点补「-」且概率正确', () {
      final e = PedigreeGraphEngine(
          fatherGenotype: 'AaBb', motherGenotype: 'AaBb');
      e.allowMissingGeneMating = true;
      final ext = e.addExternal(
          generation: 0, kind: PedigreeNodeKind.female, genotype: 'aa');
      expect(e.connectBlockReason('P-father', ext), isNull,
          reason: '开启后不同对数允许连线');
      expect(e.connect('P-father', ext), isTrue);

      e.ensureGeneration(1);
      // 池交配（P♂×P♀）与显式边（P♂×EXT aa）并存，F1 同时含常规桶与
      // 缺失桶；对缺失桶断言：4 种齐备、彼此概率相等（B-/b- 各半对称）。
      final missing = {
        for (final n in e.nodesOf(1).where((n) => n.genotype.contains('-')))
          n.genotype: n.probability
      };
      expect(missing.keys.toSet(), {'AaB-', 'Aab-', 'aaB-', 'aab-'});
      final ps = missing.values.toSet();
      expect(ps.length, 1, reason: '四种缺失桶概率应相等（A位点1/2×B位点1/2）');
      expect(ps.single, greaterThan(0));
    });

    test('T-A2.20.3 缺失后代可再杂交：分布归一、双缺失记作「--」', () {
      final dist =
          PedigreeEngine().cross('AaB-', 'Aa', allowMissing: true);
      final sum = dist.values.fold(0.0, (a, b) => a + b);
      expect(sum, closeTo(1.0, 1e-9));
      expect(dist['AaB-'], closeTo(0.25, 1e-9));
      expect(dist.keys.any((k) => k.contains('--')), isTrue,
          reason: '「-」配子相遇产生双缺失位点「--」');
    });

    test('T-A2.20.4 sortedLabel：缺失等位恒排最后', () {
      expect(GenotypeProfile(['-', 'B'], 1).sortedLabel, 'B-');
      expect(GenotypeProfile(['b', '-'], 1).sortedLabel, 'b-');
      expect(GenotypeProfile(['-', '-'], 1).sortedLabel, '--');
      expect(GenotypeProfile(['a', 'A'], 1).sortedLabel, 'Aa');
    });

    test('T-A2.20.5 快照保留开关；editExternal 对数随开关放宽', () {
      final e = PedigreeGraphEngine(
          fatherGenotype: 'AaBb', motherGenotype: 'AaBb');
      e.allowMissingGeneMating = true;
      final snap = e.takeSnapshot();
      e.allowMissingGeneMating = false;
      e.restoreSnapshot(snap);
      expect(e.allowMissingGeneMating, isTrue, reason: '快照应含缺失开关');

      final id = e.addExternal(
          generation: 0, kind: PedigreeNodeKind.male, genotype: 'AaBb');
      expect(e.editExternal(id, genotype: 'Aa'), isTrue,
          reason: '开关开：允许改对数');
      e.allowMissingGeneMating = false;
      expect(e.editExternal(id, genotype: 'AaBbCc'), isFalse,
          reason: '开关关：对数不可变');
    });
  });

  group('R19 单元素删除 + 按家族删代', () {
    test('T-A2.21.1 删除外来样本：混合桶半边连带删除', () {
      final e =
          PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      final id = e.addExternalGroup(generation: 1, genotype: 'aa');
      final half = e.ensureHalf(id, PedigreeNodeKind.female);
      expect(e.removeElement(id), isTrue);
      expect(e.nodes.any((n) => n.id == id), isFalse);
      expect(e.nodes.any((n) => n.id == half), isFalse,
          reason: '外来混合桶的半边应连带删除');
    });

    test('T-A2.21.2 删除计算桶：立即重算拦一次（黑名单一次性），clear 后可再生', () {
      final e =
          PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      e.ensureGeneration(2);
      final bucket =
          e.nodesOf(1).firstWhere((n) => n.genotype == 'aa');
      expect(e.removeElement(bucket.id), isTrue);
      e.recomputeFrom(0); // 页面语义：删后立即重算
      expect(e.nodesOf(1).any((n) => n.genotype == 'aa'), isFalse,
          reason: '删除后立即重算：被删基因型不复活');
      expect(e.nodesOf(1).isNotEmpty, isTrue, reason: '其余基因型照常');
      final sum =
          e.nodesOf(1).fold(0.0, (s, n) => s + n.probability);
      expect(sum, closeTo(1.0, 1e-6), reason: '删除后分布重新归一化');
      // R20：黑名单一次性——解除后「计算」重新推导出被删基因型
      e.clearRemovedGenotypes();
      e.recomputeFrom(0);
      expect(e.nodesOf(1).any((n) => n.genotype == 'aa'), isTrue,
          reason: '清除删除标记后，重新计算应能再生 F1 的 aa 桶');
    });

    test('T-A2.21.3 删除半边：另一半保留只删半边，只剩一半删整桶', () {
      final e =
          PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      e.ensureGeneration(1);
      final bucket =
          e.nodesOf(1).firstWhere((n) => n.genotype == 'Aa');
      final maleHalf = e.ensureHalf(bucket.id, PedigreeNodeKind.male);
      final femaleHalf = e.ensureHalf(bucket.id, PedigreeNodeKind.female);
      expect(e.removeElement(maleHalf), isTrue);
      expect(e.nodes.any((n) => n.id == maleHalf), isFalse);
      expect(e.nodes.any((n) => n.id == femaleHalf), isTrue,
          reason: '另一半半边保留');
      expect(e.nodes.any((n) => n.id == bucket.id), isTrue,
          reason: '母桶保留（组合桶仍渲染剩余半边）');
      expect(e.removeElement(femaleHalf), isTrue);
      expect(e.nodes.any((n) => n.id == bucket.id), isFalse,
          reason: '只剩一个半边时整桶删除');
    });

    test('T-A2.21.4 初始双亲不可删；未知 id 返回 false', () {
      final e =
          PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      expect(e.removeElement('P-father'), isFalse);
      expect(e.removeElement('P-mother'), isFalse);
      expect(e.removeElement('NOPE'), isFalse);
    });

    test('T-A2.21.5 按家族删代：只删目标家族该代及后代，另一家族不动，外来保留',
        () {
      final e =
          PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      e.addFamily(fatherGenotype: 'Bb', motherGenotype: 'Bb');
      e.ensureGeneration(2);
      // 家族1 添加外来样本到 F1（与家族1 双亲同为 1 对）
      final ext = e.addExternal(
          generation: 1,
          kind: PedigreeNodeKind.female,
          genotype: 'Bb',
          familyId: 1);
      expect(e.removeFamilyGeneration(0, 1), isTrue,
          reason: '家族A F1 及以上存在，可删');
      expect(e.nodesOf(1).any((n) => n.familyId == 0), isFalse,
          reason: '家族A 的 F1 已删');
      expect(e.nodesOf(2).any((n) => n.familyId == 0), isFalse,
          reason: '家族A 的 F2 一并删除');
      expect(e.nodesOf(1).any((n) => n.familyId == 1), isTrue,
          reason: '家族B 的 F1 不受影响');
      expect(e.nodesOf(2).any((n) => n.familyId == 1), isTrue,
          reason: '家族B 的 F2 不受影响');
      expect(e.nodes.any((n) => n.id == ext), isTrue,
          reason: '被删代的外来样本保留在原位');
      expect(e.maxGeneration, greaterThanOrEqualTo(2));
      // 重算不重建家族A 被删世代（前沿已回退）
      e.recomputeFrom(0);
      expect(e.nodesOf(1).any((n) => n.familyId == 0), isFalse,
          reason: '重算后家族A 停在 P 代');
    });

    test('T-A2.21.6 P 代禁删；未展开代返回 false；快照恢复后删除标记清空', () {
      final e =
          PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      expect(e.removeFamilyGeneration(0, 1), isFalse,
          reason: '未展开 F1 时删除返回 false');
      e.ensureGeneration(1);
      final bucket =
          e.nodesOf(1).firstWhere((n) => n.genotype == 'aa');
      e.removeElement(bucket.id);
      final snap = e.takeSnapshot();
      e.recomputeFrom(0);
      expect(e.nodesOf(1).any((n) => n.genotype == 'aa'), isFalse);
      // R20：黑名单不进快照——回退/恢复后删除标记清空，可重新计算
      e.restoreSnapshot(snap);
      e.recomputeFrom(0);
      expect(e.nodesOf(1).any((n) => n.genotype == 'aa'), isTrue,
          reason: '回退后删除标记清空，重新计算能再生成 aa');
    });
  });
  group('R29 同性边清理（removeSameSexEdges）', () {
    test('关闭同性交配语义下移除 male×male/female×female，group 端保留', () {
      final e =
          PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      e.allowSameSexMating = true;
      e.ensureGeneration(2);
      final f1 = e.nodesOf(1).firstWhere((n) => n.genotype == 'Aa');
      final m = e.ensureHalf(f1.id, PedigreeNodeKind.male);
      final f = e.ensureHalf(f1.id, PedigreeNodeKind.female);
      final f2 = e.nodesOf(2).firstWhere((n) => !n.id.startsWith('SPLIT#'));
      final f2m = e.ensureHalf(f2.id, PedigreeNodeKind.male);
      // male×male 与 male×female 各一条
      expect(e.connect(m, f2m), isTrue);
      expect(e.connect(f, m), isTrue);
      final before = e.edges.where((x) => x.kind == PedigreeEdgeKind.mating).length;
      e.allowSameSexMating = false;
      final n = e.removeSameSexEdges();
      expect(n, greaterThan(0), reason: '应移除同性边');
      expect(
        e.edges.where((x) =>
            x.kind == PedigreeEdgeKind.mating &&
            x.fromId.startsWith('SPLIT#') &&
            x.toId.startsWith('SPLIT#')).length,
        lessThan(before),
        reason: '半边同性边被清理');
      // female×male 边仍在
      expect(e.edges.any((x) =>
          x.kind == PedigreeEdgeKind.mating &&
          ((x.fromId == f && x.toId == m) || (x.fromId == m && x.toId == f))),
          isTrue);
    });
  });
  group('R32 mating 边性别标注（fromSex/toSex，同性交配灯效根基）', () {
    test('T-A2.22.1 半边连线记录端点性别：male×male 标注 male/male', () {
      final e =
          PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      e.trackSex = true;
      e.allowSameSexMating = true;
      e.ensureGeneration(1);
      final b1 = e.nodesOf(1).firstWhere(
          (n) => n.kind == PedigreeNodeKind.group && n.genotype == 'AA');
      final b2 = e.nodesOf(1).firstWhere(
          (n) => n.kind == PedigreeNodeKind.group && n.genotype == 'aa');
      final m1 = e.ensureHalf(b1.id, PedigreeNodeKind.male);
      final m2 = e.ensureHalf(b2.id, PedigreeNodeKind.male);
      expect(e.connect(m1, m2), isTrue, reason: '同性交配开启后 male×male 合法');
      final edge = e.edges.firstWhere((x) =>
          x.kind == PedigreeEdgeKind.mating &&
          (x.fromId == m1 || x.toId == m1));
      expect(edge.fromSex, PedigreeNodeKind.male);
      expect(edge.toSex, PedigreeNodeKind.male);
    });

    test('T-A2.22.2 整桶×整桶边性别标注为 null（灯效走异性兜底）', () {
      final e =
          PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      e.ensureGeneration(1);
      final b1 = e.nodesOf(1).firstWhere((n) => n.genotype == 'AA');
      final b2 = e.nodesOf(1).firstWhere((n) => n.genotype == 'aa');
      expect(e.connect(b1.id, b2.id), isTrue);
      final edge = e.edges.firstWhere((x) =>
          x.kind == PedigreeEdgeKind.mating &&
          (x.fromId == b1.id || x.toId == b1.id));
      expect(edge.fromSex, isNull, reason: '整桶端点无单一性别');
      expect(edge.toSex, isNull);
    });

    test('T-A2.22.3 重算把半边端点降级回整桶，性别标注保留（用户 bug 根因）',
        () {
      final e =
          PedigreeGraphEngine(fatherGenotype: 'Aa', motherGenotype: 'Aa');
      e.trackSex = true;
      e.allowSameSexMating = true;
      e.ensureGeneration(2);
      final b1 = e.nodesOf(1).firstWhere(
          (n) => n.kind == PedigreeNodeKind.group && n.genotype == 'AA');
      final b2 = e.nodesOf(1).firstWhere(
          (n) => n.kind == PedigreeNodeKind.group && n.genotype == 'aa');
      final m1 = e.ensureHalf(b1.id, PedigreeNodeKind.male);
      final m2 = e.ensureHalf(b2.id, PedigreeNodeKind.male);
      expect(e.connect(m1, m2), isTrue);
      // 用户路径：连线后点「计算」→ recomputeFrom(0)，F1 桶销毁重建，
      // 半边端点按 (世代,家族,基因型) 重映射回新整桶 id。
      e.recomputeFrom(0);
      final edge = e.edges.firstWhere((x) =>
          x.kind == PedigreeEdgeKind.mating && !x.fromId.startsWith('P-'));
      expect(edge.fromId.startsWith('SPLIT#'), isFalse,
          reason: '重算后半边销毁，端点已降级回整桶');
      expect(edge.fromSex, PedigreeNodeKind.male,
          reason: '重映射不得丢性别标注（否则灯效只能瞎猜异性）');
      expect(edge.toSex, PedigreeNodeKind.male);
    });
  });
}
