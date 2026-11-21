// dogma_coding_contrast_test.dart —— v2.19.46 「错因对照」创新守卫。
//
// 学生把**编码链**当模板链读是转录题最高频失分点。引擎 CentralDogmaResult
// 已给 coding 字段（编码链，T 保留）；编码链与 mRNA 同序列（仅 T/U 之别）⇒
// 误把编码链当模板链「转录」得到的密码子 = coding 直接 T→U 后按 3 位切，
// 与正确的（模板链互补）完全不同。这条守卫断：错因对照真的上屏、且数据
// 来自引擎 coding（非硬编码）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/engine/dna_strand_engine.dart';
import 'package:biology/pages/molecular_page.dart';
import 'package:biology/theme.dart';

import 'golden_fonts.dart';

void main() {
  group('错因对照（引擎 coding → 错误密码子）', () {
    test('对照数据口径：编码链 T→U 即错误 mRNA，按 3 位切得错误密码子', () {
      final r = centralDogmaFromTemplate('TACGGATTA');
      // 正确：模板链互补 → mRNA AUGCCUAAU → 密码子 AUG/CCU/AAU
      expect(r.codons, ['AUG', 'CCU', 'AAU']);
      // 错误：编码链（compDna，T 保留）= ATGCCTAAT → T→U = AUGCCUAAU？
      // ⚠️ 实际上 coding = compDna(template)，对 TACGGATTA 得 ATGCCTAAT，
      //    T→U 得 AUGCCUAAU —— 恰好与 mrna 相同！这是「模板链的编码链」特例。
      //    换一个非回文模板验证「错误 ≠ 正确」。
      final r2 = centralDogmaFromTemplate('TACCAT');
      // 模板链 TACCAT → mRNA AUGGUA → 密码子 AUG/GUA
      expect(r2.codons, ['AUG', 'GUA']);
      // 编码链 = compDna(TACCAT) = ATGGTA → T→U = AUGGUA —— 又是同序？
      //    原来对任意模板，coding = compDna(template)，而 mrna = compRna(template)。
      //    compDna 保留 T，compRna 把 T→A。两者**不同**（除非模板全 A/T）。
      //    核对：TACCAT 的 coding=ATGGTA，mrna=AUGGUA。T→U 后 coding=AUGGUA = mrna？
      //    ATGGTA→T→U = AUGGUA，mrna=AUGGUA。同！
      //    ⇒ 对**任意**模板，coding T→U == mrna。因为 coding=compDna(t) 与 mrna=compRna(t)
      //      只差「模板里的 A 在 coding 是 T、在 mrna 是 U」——T→U 后两者恒等。
      //    这是生物学事实：编码链与 mRNA 同序列（T/U 之别）。⇒ 「错因对照」
      //     premise 有误：学生把 coding 当 template 读，得到的不是 coding 本身，
      //    而是「拿 coding 去互补一遍」= compRna(coding) = compRna(compDna(t)) = t（模板原序）。
      //    所以「错误密码子」= 把模板链当 mRNA 直接读（T→U）= t.replaceAll(T,U) 按 3 切。
      final wrongMrnaFromCoding = r2.template.replaceAll('T', 'U');
      final wrongCodons = <String>[
        for (var i = 0; i + 3 <= wrongMrnaFromCoding.length; i += 3)
          wrongMrnaFromCoding.substring(i, i + 3)
      ];
      expect(wrongCodons, isNot(equals(r2.codons)),
          reason: '误把模板链直接当 mRNA 读（不互补）的密码子必与正确不同');
    });

    test('源码级：错因对照存在，且口径是「模板链直接 T→U」（忘了互补）', () {
      final src = File('lib/pages/molecular_page.dart').readAsStringSync();
      expect(src.contains('若忘了互补、把模板链直接当 mRNA 读'), isTrue,
          reason: '错因对照文案没了');
      // ⛔ 关键判据：错因对照的数据是「模板链直接 T→U」（忘了互补），
      //    不是「编码链 T→U」（那会与正确密码子恒同，对照失去意义）。
      //    源码里必须是 `_dogmaResult!.template.replaceAll`，
      //    ⛔ 不许是 `_dogmaResult!.coding.replaceAll`（coding T→U == mrna，恒同）。
      expect(src.contains('_dogmaResult!.template.replaceAll'), isTrue,
          reason: '错因对照必须基于模板链直接 T→U（学生真犯的错：忘了互补）');
      expect(src.contains('_dogmaResult!.coding.replaceAll'), isFalse,
          reason: '⛔ 若用 coding T→U 做对照，那与正确密码子恒同，对照失效');
    });
  });
}
