// strand_single_from_ct_test.dart —— v2.19.47 「空格留给你推」引擎扩展守卫。
//
// 双链 DNA 互补配对（A₁=T₂、T₁=A₂、G₁=C₂、C₁=G₂）⇒ 已知链1/链2 的 C、T
// 就能推出每条链的 A、G。这是 [StrandCTResult] 没给的四格（单链 A/G），
// 由互补配对直接推得（非新数据）。这条守卫断：推导正确、判据完备、
// ⛔ 推导值与全分子总量自洽（a1+a2 == aTotal）。
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/engine/dna_strand_engine.dart';

void main() {
  group('strandSingleFromCT（互补配对推单链 A/G）', () {
    test('S1 基本推导：A₁=T₂、G₁=C₂、A₂=T₁、G₂=C₁', () {
      final r = strandSingleFromCT(c1: 10, t1: 20, c2: 15, t2: 25);
      expect(r.a1, 25, reason: 'A₁=T₂（互补配对）');
      expect(r.g1, 15, reason: 'G₁=C₂');
      expect(r.a2, 20, reason: 'A₂=T₁');
      expect(r.g2, 10, reason: 'G₂=C₁');
    });

    test('S2 与全分子总量自洽：a1+a2 == aTotal、g1+g2 == gTotal', () {
      const c1 = 10, t1 = 20, c2 = 15, t2 = 25;
      final single = strandSingleFromCT(c1: c1, t1: t1, c2: c2, t2: t2);
      final total = strandCountsFromCT(c1: c1, t1: t1, c2: c2, t2: t2);
      // ⛔ 单链之和必须等于全分子总量（引擎的 aTotal/gTotal），否则推导自相矛盾。
      expect(single.a1 + single.a2, total.aTotal,
          reason: '两条链的 A 之和 == 全分子 A 总数（引擎 aTotal）');
      expect(single.g1 + single.g2, total.gTotal,
          reason: '两条链的 G 之和 == 全分子 G 总数（引擎 gTotal）');
      // 链1 自身的 A+T+G+C 应等于链1 碱基数（= 全分子 total/2）。
      final strand1Total = single.a1 + t1 + single.g1 + c1;
      expect(strand1Total * 2, total.total,
          reason: '链1 四种碱基之和 × 2 == 全分子碱基总数');
    });

    test('S3 负数守卫：任一输入为负抛错（与 strandCountsFromCT 同源）', () {
      expect(
          () => strandSingleFromCT(c1: -1, t1: 20, c2: 15, t2: 25),
          throwsArgumentError);
      expect(
          () => strandSingleFromCT(c1: 10, t1: 20, c2: 15, t2: -25),
          throwsArgumentError);
    });

    test('S4 与 strandCountsFromCT 同源：同一输入两函数不矛盾', () {
      // 多组随机-ish 输入（覆盖边界 0、大数）。
      for (final inp in [
        (c1: 0, t1: 0, c2: 0, t2: 0),
        (c1: 1, t1: 2, c2: 3, t2: 4),
        (c1: 100, t1: 200, c2: 300, t2: 400),
      ]) {
        final single = strandSingleFromCT(
            c1: inp.c1, t1: inp.t1, c2: inp.c2, t2: inp.t2);
        final total = strandCountsFromCT(
            c1: inp.c1, t1: inp.t1, c2: inp.c2, t2: inp.t2);
        expect(single.a1 + single.a2, total.aTotal, reason: 'input $inp');
        expect(single.g1 + single.g2, total.gTotal, reason: 'input $inp');
      }
    });
  });
}
