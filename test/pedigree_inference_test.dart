// pedigree_inference_test.dart —— 经典系谱遗传方式推断引擎测试（v2.13+）
//
// 用例 = 高中教材/高考经典系谱事实（人教版必修2 第5章 + 课标 3.2.6）：
//   1. 常隐金标准：正常父母 → 患病女儿（无中生有 + 女患者父正常）
//   2. X 隐金标准：男患者母亲正常、交叉遗传、女患者父必病
//   3. 常显金标准：患病父母 → 正常孩子（有中生无）+ 代代相传
//   4. X 显排除：女患者父亲正常 → X 显被硬排除
//   5. Y 连锁：三代男传男全患病 → 支持 Y；女患者 → 排除 Y
//   6. 输入校验：空系谱 / 无患者 / 悬空亲子边 → errors 非空
//   7. evidence 条文非空（UI 逐条呈现依赖）

import 'package:biology/engine/pedigree_inference.dart';
import 'package:flutter_test/flutter_test.dart';

PdMember m(String id, PdSex sex, PdStatus st, [int gen = 0]) =>
    PdMember(id: id, sex: sex, status: st, generation: gen);

PdRelation r(String parent, String child) =>
    PdRelation(parentId: parent, childId: child);

void main() {
  test('常染色体隐性金标准：正常父母生出患病女儿', () {
    // I 代正常双亲 → II 代患病女儿（无中生有 + 女患者父正常 →
    // X 隐也被排除，只剩常隐）。
    final engine = PedigreeInferenceEngine();
    final out = engine.infer([
      m('I1', PdSex.male, PdStatus.normal, 0),
      m('I2', PdSex.female, PdStatus.normal, 0),
      m('II1', PdSex.female, PdStatus.affected, 1),
    ], [
      r('I1', 'II1'),
      r('I2', 'II1'),
    ]);
    expect(engine.errors, isEmpty);
    expect(out.best, InheritancePattern.autosomalRecessive,
        reason: '常隐是未排除中得分最高');
    final xR = out.candidates
        .firstWhere((c) => c.pattern == InheritancePattern.xLinkedRecessive);
    expect(xR.excluded, isTrue,
        reason: '女患者父亲正常 → X 隐硬排除');
    final aD = out.candidates
        .firstWhere((c) => c.pattern == InheritancePattern.autosomalDominant);
    expect(aD.excluded, isTrue, reason: '无中生有 → 显性硬排除');
    // 依据条文非空。
    final best = out.candidates
        .firstWhere((c) => c.pattern == InheritancePattern.autosomalRecessive);
    expect(best.evidence.any((e) => e.contains('无中生有')), isTrue);
  });

  test('伴 X 隐性金标准：男患者多、母亲携带、交叉遗传', () {
    // I：正常祖父 I1 × 携带祖母 I2（女，正常）
    // II：男患者 II1（I2 之子）；II1 与正常女 II2 婚配
    // III：男患者 III1（II1 之子，祖父来源的 X 经女儿传递——
    //     典型隔代交叉遗传）。
    final engine = PedigreeInferenceEngine();
    final out = engine.infer([
      m('I1', PdSex.male, PdStatus.normal, 0),
      m('I2', PdSex.female, PdStatus.normal, 0),
      m('II1', PdSex.male, PdStatus.affected, 1),
      m('II2', PdSex.female, PdStatus.normal, 1),
      m('III1', PdSex.male, PdStatus.affected, 2),
    ], [
      r('I1', 'II1'),
      r('I2', 'II1'),
      r('II1', 'III1'),
      r('II2', 'III1'),
    ]);
    expect(engine.errors, isEmpty);
    expect(out.best, InheritancePattern.xLinkedRecessive);
    final xR = out.candidates
        .firstWhere((c) => c.pattern == InheritancePattern.xLinkedRecessive);
    expect(xR.excluded, isFalse);
    expect(xR.evidence.any((e) => e.contains('无中生有')), isTrue,
        reason: 'III1 的父 II1 患病但母 II2 正常——对 X 隐不是硬排除'
            '（母为携带者不矛盾），且 II1 本人是无中生有之子');
  });

  test('常染色体显性金标准：患病父母生出正常孩子 + 代代相传', () {
    final engine = PedigreeInferenceEngine();
    final out = engine.infer([
      m('I1', PdSex.male, PdStatus.affected, 0),
      m('I2', PdSex.female, PdStatus.affected, 0),
      m('II1', PdSex.female, PdStatus.normal, 1),
      m('II2', PdSex.male, PdStatus.affected, 1),
      m('III1', PdSex.female, PdStatus.affected, 2),
    ], [
      r('I1', 'II1'),
      r('I2', 'II1'),
      r('I1', 'II2'),
      r('I2', 'II2'),
      r('II2', 'III1'),
    ]);
    expect(engine.errors, isEmpty);
    expect(out.best, InheritancePattern.autosomalDominant,
        reason: '有中生无 + 连续 3 代患者 → 常显');
    final aD = out.candidates
        .firstWhere((c) => c.pattern == InheritancePattern.autosomalDominant);
    expect(aD.evidence.any((e) => e.contains('有中生无')), isTrue);
    expect(aD.evidence.any((e) => e.contains('代代')), isTrue);
    final aR = out.candidates
        .firstWhere((c) => c.pattern == InheritancePattern.autosomalRecessive);
    expect(aR.excluded, isTrue, reason: 'aa×aa 子女必病，II1 正常');
  });

  test('伴 X 显性排除：女患者父亲正常', () {
    final engine = PedigreeInferenceEngine();
    final out = engine.infer([
      m('I1', PdSex.male, PdStatus.normal, 0),
      m('I2', PdSex.female, PdStatus.normal, 0),
      m('II1', PdSex.female, PdStatus.affected, 1),
    ], [
      r('I1', 'II1'),
      r('I2', 'II1'),
    ]);
    final xD = out.candidates
        .firstWhere((c) => c.pattern == InheritancePattern.xLinkedDominant);
    expect(xD.excluded, isTrue,
        reason: '女患者 II1 的父亲 I1 正常 → X 显硬排除');
    expect(xD.evidence.any((e) => e.contains('排除')), isTrue);
  });

  test('伴 Y 遗传：三代男传男支持；女患者一票否决', () {
    // 支持用例。
    final engine = PedigreeInferenceEngine();
    final out = engine.infer([
      m('I1', PdSex.male, PdStatus.affected, 0),
      m('I2', PdSex.female, PdStatus.normal, 0),
      m('II1', PdSex.male, PdStatus.affected, 1),
      m('II2', PdSex.female, PdStatus.normal, 1),
      m('III1', PdSex.male, PdStatus.affected, 2),
    ], [
      r('I1', 'II1'),
      r('I2', 'II1'),
      r('II1', 'III1'),
      r('II2', 'III1'),
    ]);
    expect(out.best, InheritancePattern.yLinked);
    final y = out.candidates
        .firstWhere((c) => c.pattern == InheritancePattern.yLinked);
    expect(y.excluded, isFalse);
    expect(y.evidence.any((e) => e.contains('伴 Y')), isTrue);

    // 女患者一票否决。
    final engine2 = PedigreeInferenceEngine();
    final out2 = engine2.infer([
      m('I1', PdSex.male, PdStatus.affected, 0),
      m('II1', PdSex.female, PdStatus.affected, 1),
    ], [
      r('I1', 'II1'),
    ]);
    final y2 = out2.candidates
        .firstWhere((c) => c.pattern == InheritancePattern.yLinked);
    expect(y2.excluded, isTrue, reason: '女患者 → 伴 Y 一票否决');
  });

  test('输入校验：空系谱 / 无患者 / 悬空边 / 自环', () {
    final engine = PedigreeInferenceEngine();
    expect(engine.infer([], []).candidates, isEmpty);
    expect(engine.errors, isNotEmpty);

    final engine2 = PedigreeInferenceEngine();
    expect(
        engine2.infer([m('A', PdSex.male, PdStatus.normal)], []).candidates,
        isEmpty);
    expect(engine2.errors.any((e) => e.contains('没有患者')), isTrue);

    final engine3 = PedigreeInferenceEngine();
    engine3.infer([
      m('A', PdSex.male, PdStatus.affected, 0),
      m('B', PdSex.female, PdStatus.normal, 1),
    ], [
      r('A', 'B'),
      r('GHOST', 'B'), // 悬空
    ]);
    expect(engine3.errors.any((e) => e.contains('不存在')), isTrue);

    final engine4 = PedigreeInferenceEngine();
    engine4.infer([m('A', PdSex.male, PdStatus.affected, 0)], [
      r('A', 'A'),
    ]);
    expect(engine4.errors.any((e) => e.contains('自环')), isTrue);
  });

  test('summary 与候选排序：未排除在前、分数降序', () {
    final engine = PedigreeInferenceEngine();
    final out = engine.infer([
      m('I1', PdSex.male, PdStatus.normal, 0),
      m('I2', PdSex.female, PdStatus.normal, 0),
      m('II1', PdSex.male, PdStatus.affected, 1),
    ], [
      r('I1', 'II1'),
      r('I2', 'II1'),
    ]);
    expect(out.summary, contains('3 名成员'));
    expect(out.summary, contains('1 名患者'));
    var seenExcluded = false;
    for (final c in out.candidates) {
      if (c.excluded) seenExcluded = true;
      if (seenExcluded) {
        expect(c.excluded, isTrue,
            reason: '排序保证：未排除全部排在被排除之前');
      }
    }
  });
}
