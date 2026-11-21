// pedigree_genotype_test.dart —— 半开放基因型反推引擎测试（v2.13+）
//
// 全部用例来自课本金标准（人教必修2 第5章）：
//   1. 常隐：患者 aa；正常父母生患者 → 父母均 Aa；正常同胞 → 2/3 携带
//   2. 常隐：父患 aa × 正常母 → 正常子女必 Aa
//   3. 常显：患者（亲本正常）→ Aa；正常 → aa
//   4. 伴X隐：男患 XaY / 正常男 XAY；女患 XaXa；父患女必携带
//   5. 伴X显：女患（父正常）→ XDXd；正常男 XdY

import 'package:biology/engine/pedigree_genotype.dart';
import 'package:biology/engine/pedigree_inference.dart';
import 'package:flutter_test/flutter_test.dart';

PdMember m(String id, PdSex sex, PdStatus st) =>
    PdMember(id: id, sex: sex, status: st);
PdRelation r(String parent, String child) =>
    PdRelation(parentId: parent, childId: child);

void main() {
  test('常隐金标准：患者 aa / 双亲携带 / 正常同胞 2/3', () {
    // I1×I2 正常 → II1 患病 + II2 正常。
    final out = PedigreeGenotypeAnalysis.analyze([
      m('I1', PdSex.male, PdStatus.normal),
      m('I2', PdSex.female, PdStatus.normal),
      m('II1', PdSex.male, PdStatus.affected),
      m('II2', PdSex.female, PdStatus.normal),
    ], [
      r('I1', 'II1'),
      r('I2', 'II1'),
      r('I1', 'II2'),
      r('I2', 'II2'),
    ], InheritancePattern.autosomalRecessive);

    final call = (String id) =>
        out.calls.firstWhere((c) => c.memberId == id);
    expect(call('II1').genotype, 'aa');
    expect(call('II1').confidence, GenotypeConfidence.deduced);
    // I1/I2 有患病子女 → 均 Aa（携带者）。
    expect(call('I1').confidence, GenotypeConfidence.deduced);
    expect(call('I1').genotype, contains('Aa'));
    // 正常同胞 II2 → 2/3 携带（课本条件概率）。
    expect(call('II2').confidence, GenotypeConfidence.probabilistic);
    expect(call('II2').genotype, contains('2/3'));
    expect(call('II2').evidence, contains('AA:Aa = 1:2'));
  });

  test('常隐：父患 aa × 正常母 → 正常子女必 Aa（携带）', () {
    final out = PedigreeGenotypeAnalysis.analyze([
      m('I1', PdSex.male, PdStatus.affected),
      m('I2', PdSex.female, PdStatus.normal),
      m('II1', PdSex.male, PdStatus.normal),
    ], [
      r('I1', 'II1'),
      r('I2', 'II1'),
    ], InheritancePattern.autosomalRecessive);

    final c = out.calls.firstWhere((x) => x.memberId == 'II1');
    expect(c.genotype, 'Aa（携带者）');
    expect(c.confidence, GenotypeConfidence.deduced);
  });

  test('常显：患者（亲本正常）→ Aa；正常 → aa', () {
    final out = PedigreeGenotypeAnalysis.analyze([
      m('I1', PdSex.male, PdStatus.normal),
      m('I2', PdSex.female, PdStatus.normal),
      m('II1', PdSex.male, PdStatus.affected),
    ], [
      r('I1', 'II1'),
      r('I2', 'II1'),
    ], InheritancePattern.autosomalDominant);

    final call = (String id) =>
        out.calls.firstWhere((c) => c.memberId == id);
    expect(call('II1').genotype, 'Aa');
    expect(call('II1').evidence, contains('aa'));
    expect(call('I1').genotype, 'aa');
  });

  test('伴X隐：男患 XaY / 女患 XaXa / 父患女必携带', () {
    final out = PedigreeGenotypeAnalysis.analyze([
      m('I1', PdSex.male, PdStatus.affected), // 父患
      m('I2', PdSex.female, PdStatus.normal),
      m('II1', PdSex.male, PdStatus.normal),
      m('II2', PdSex.female, PdStatus.normal),
      m('II3', PdSex.female, PdStatus.affected), // 女患（母携带情形）
    ], [
      r('I1', 'II1'),
      r('I2', 'II1'),
      r('I1', 'II2'),
      r('I2', 'II2'),
      r('I1', 'II3'),
      r('I2', 'II3'),
    ], InheritancePattern.xLinkedRecessive);

    final call = (String id) =>
        out.calls.firstWhere((c) => c.memberId == id);
    expect(call('I1').genotype, 'XaY');
    expect(call('II1').genotype, 'XAY');
    expect(call('II3').genotype, 'XaXa');
    // 父患 → 正常女儿 II2 必携带。
    expect(call('II2').genotype, 'XAXa（携带者）');
    expect(call('II2').confidence, GenotypeConfidence.deduced);
    expect(call('II2').evidence, contains('父亲患病'));
  });

  test('伴X显：女患（父正常）→ XDXd；正常男 → XdY', () {
    final out = PedigreeGenotypeAnalysis.analyze([
      m('I1', PdSex.male, PdStatus.normal),
      m('I2', PdSex.female, PdStatus.affected),
      m('II1', PdSex.female, PdStatus.affected),
      m('II2', PdSex.male, PdStatus.normal),
    ], [
      r('I1', 'II1'),
      r('I2', 'II1'),
      r('I1', 'II2'),
      r('I2', 'II2'),
    ], InheritancePattern.xLinkedDominant);

    call(String id) => out.calls.firstWhere((c) => c.memberId == id);
    expect(call('II1').genotype, 'XDXd');
    expect(call('II1').evidence, contains('父亲正常'));
    expect(call('II2').genotype, 'XdY');
  });

  test('summary 含模式与成员/患者计数', () {
    final out = PedigreeGenotypeAnalysis.analyze([
      m('A', PdSex.male, PdStatus.affected),
    ], const [], InheritancePattern.autosomalRecessive);
    expect(out.summary, contains('常染色体隐性'));
    expect(out.summary, contains('1 名成员'));
    expect(out.summary, contains('1 名患者'));
  });
}
