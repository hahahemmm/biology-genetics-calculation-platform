// kaoji_calc_auto_test.dart —— crossAuto（n 对基因 + 倍性自适应）纯 Dart 测试。
import 'package:flutter_test/flutter_test.dart';
import 'package:biology/engine/kaoji_calc.dart';

void main() {
  final calc = KaojiCalc();

  int sumParts(List<int> parts) => parts.fold(0, (a, b) => a + b);

  group('crossAuto 二倍体', () {
    test('2 对 AaBb×AaBb → 9:3:3:1，与 dihybrid9331 一致', () {
      final r = calc.crossAuto(p1: 'AaBb', p2: 'AaBb');
      expect(r.error, isNull);
      expect(r.ploidy, 2);
      expect(r.loci, 2);
      expect(r.result, isNotNull);
      expect(r.result!.phenotypeRatio.toString(), '9:3:3:1');
      expect(r.result!.variantName, '标准 9:3:3:1');
      // 与既有 dihybrid9331 结果完全一致
      final ref = calc.dihybrid9331(p1: 'AaBb', p2: 'AaBb');
      expect(
        r.result!.phenotypeRatio.toString(),
        ref.phenotypeRatio.toString(),
      );
    });

    test('3 对 AaBbCc×AaBbCc → 27:9:9:9:3:3:3:1，总份数 64', () {
      final r = calc.crossAuto(p1: 'AaBbCc', p2: 'AaBbCc');
      expect(r.error, isNull);
      expect(r.ploidy, 2);
      expect(r.loci, 3);
      expect(r.result!.phenotypeRatio.toString(), '27:9:9:9:3:3:3:1');
      expect(sumParts(r.result!.phenotypeRatio.parts), 64);
      expect(r.result!.phenotypeLabels.length, 8);
    });

    test('4 对 AaBbCcDd×AaBbCcDd → 总份数 256，16 类，最大 81 最小 1', () {
      final r = calc.crossAuto(p1: 'AaBbCcDd', p2: 'AaBbCcDd');
      expect(r.error, isNull);
      expect(r.loci, 4);
      final parts = r.result!.phenotypeRatio.parts;
      expect(sumParts(parts), 256);
      expect(parts.length, 16);
      expect(parts.first, 81);
      expect(parts.last, 1);
    });
  });

  group('crossAuto 一倍体', () {
    test('AB×ab → ploidy=1，子代仅 AaBb，表型 AB 占全部', () {
      final r = calc.crossAuto(p1: 'AB', p2: 'ab');
      expect(r.error, isNull);
      expect(r.ploidy, 1);
      expect(r.loci, 2);
      expect(r.result!.variantName, '单倍体杂交');
      expect(r.result!.genotypeLabels, ['AaBb']);
      expect(r.result!.phenotypeLabels, ['AB']);
      expect(sumParts(r.result!.phenotypeRatio.parts), 1);
      expect(sumParts(r.result!.genotypeRatio.parts), 1);
    });
  });

  group('crossAuto 三倍体', () {
    test('AAaBbb×AaaBBb → notice 含「联会紊乱」，result 为 null', () {
      final r = calc.crossAuto(p1: 'AAaBbb', p2: 'AaaBBb');
      expect(r.result, isNull);
      expect(r.error, isNull);
      expect(r.ploidy, 3);
      expect(r.loci, 2);
      expect(r.notice, isNotNull);
      expect(r.notice, contains('联会紊乱'));
    });
  });

  group('crossAuto 错误分支', () {
    test('空串/纯空格 → 基因型不能为空', () {
      expect(calc.crossAuto(p1: '', p2: 'AaBb').error, '基因型不能为空');
      expect(calc.crossAuto(p1: 'AaBb', p2: '   ').error, '基因型不能为空');
    });

    test('非字母 → 仅支持字母 A-Z', () {
      final r = calc.crossAuto(p1: 'Aa1', p2: 'AaBb');
      expect(r.error, '仅支持字母 A-Z');
      expect(r.result, isNull);
    });

    test('ABab 同字母非相邻 → 等位基因必须相邻书写', () {
      final r = calc.crossAuto(p1: 'ABab', p2: 'aabb');
      expect(r.error, '同一对基因的等位基因必须相邻书写（如 AaBb）');
      expect(r.result, isNull);
    });

    test('AaB 位点组大小不齐 → 位点数与倍性须一致', () {
      final r = calc.crossAuto(p1: 'AaB', p2: 'AaB');
      expect(r.error, '两个亲本的位点数与倍性须一致（如 AaBb × AaBb）');
      expect(r.result, isNull);
    });

    test('AaBb×AaBbCc 两亲本位点数不一致 → 报错', () {
      final r = calc.crossAuto(p1: 'AaBb', p2: 'AaBbCc');
      expect(r.error, '两个亲本的位点数与倍性须一致（如 AaBb × AaBb）');
      expect(r.result, isNull);
      expect(r.ploidy, 2);
    });

    test('7 对超限 → 暂支持 1~6 对基因', () {
      const g = 'AaBbCcDdEeFfGg';
      final r = calc.crossAuto(p1: g, p2: g);
      expect(r.error, '暂支持 1~6 对基因（当前输入 7 对）');
      expect(r.result, isNull);
      expect(r.loci, 7);
    });

    test('四倍体 → 暂不支持四倍体及以上', () {
      final r = calc.crossAuto(p1: 'AAaa', p2: 'Aaaa');
      expect(r.error, '暂不支持四倍体及以上');
      expect(r.ploidy, 4);
      expect(r.result, isNull);
    });
  });
}
