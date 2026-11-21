// pedigree_edit_test.dart —— v2.1 基因型编辑规则回归
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/engine/pedigree_graph.dart';

void main() {
  late PedigreeGraphEngine e;
  setUp(() {
    e = PedigreeGraphEngine(
        fatherGenotype: 'AABBCC', motherGenotype: 'aabbcc')
      ..expandNextGeneration(); // 初始 P + F1
  });

  test('P 代初始双亲可编辑', () {
    expect(e.editGenotype('P-father', 'AaBBcc'), isNull);
    final n = e.nodes.firstWhere((x) => x.id == 'P-father');
    expect(n.genotype, 'AaBBcc');
  });

  test('外来样本可编辑', () {
    final extId = e.addExternalGroup(
        generation: 1, genotype: 'Aabbcc');
    expect(e.editGenotype(extId, 'AABbCc'), isNull);
    expect(
        e.nodes.firstWhere((x) => x.id == extId).genotype, 'AABbCc');
  });

  test('计算产出子代只读', () {
    final f1 = e.nodes.firstWhere((n) => n.generation == 1);
    final err = e.editGenotype(f1.id, 'aabbcc');
    expect(err, isNotNull, reason: '子代不可直接修改');
    expect(err, contains('不可直接修改'));
    // 基因型未变
    expect(e.nodes.firstWhere((n) => n.id == f1.id).genotype,
        f1.genotype);
  });

  test('基因型校验：奇数位/非法字符被拒', () {
    expect(e.editGenotype('P-father', 'AaB'), isNotNull);
    expect(e.editGenotype('P-father', 'A1B2'), isNotNull);
  });

  test('不存在的节点返回原因', () {
    expect(e.editGenotype('NOPE#1', 'AaBb'), isNotNull);
  });

  test('编辑后 recompute 重推后代（用户路径由页面执行）', () {
    final before = e.nodes.where((n) => n.generation == 1).length;
    expect(before, greaterThan(0));
    e.editGenotype('P-father', 'aaBBcc');
    e.recomputeFrom(0);
    // 重推后 F1 全部携带父本新基因型对应的配子组合
    final f1s = e.nodes.where((n) => n.generation == 1).toList();
    expect(f1s, isNotEmpty);
    expect(f1s.every((n) => n.genotype.startsWith('a')), isTrue,
        reason: '父本全隐 a 后，F1 首位必为 a');
  });
}