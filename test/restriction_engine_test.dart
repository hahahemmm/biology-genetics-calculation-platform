// restriction_engine_test.dart —— 限制酶切引擎守卫网
//
// 钉住三件事（⛔ 少一件都会让「科学语义」漂）：
//   1. 三酶的识别序列 / 顶链切点 / 黏性末端与教材一致（回文自证在引擎里）；
//   2. 位点位置一律 1-based、切口落在 cutAfter 与 cutAfter+1 之间；
//   3. **识别序列长度（6 bp）≠ 切后片段数**：片段数只由位点数决定，
//      且各片段长度之和恒等于原序列长度（长度守恒，不变量）。
import 'package:biology/engine/restriction_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('三酶基本事实', () {
    test('EcoRI：GAATTC / G^AATTC / 黏性末端 AATT', () {
      expect(kEcoRI.recognition, 'GAATTC');
      expect(kEcoRI.cutNotation, 'G^AATTC');
      expect(kEcoRI.overhang, 'AATT');
      expect(kEcoRI.siteLength, 6);
      expect(kEcoRI.overhangLength, 4);
      expect(kEcoRI.isPalindrome, isTrue, reason: '回文 ⇒ 只看顶链就够');
    });

    test('BamHI：GGATCC / G^GATCC / 黏性末端 GATC', () {
      expect(kBamHI.recognition, 'GGATCC');
      expect(kBamHI.cutNotation, 'G^GATCC');
      expect(kBamHI.overhang, 'GATC');
      expect(kBamHI.isPalindrome, isTrue);
    });

    test('HindIII：AAGCTT / A^AGCTT / 黏性末端 AGCT', () {
      expect(kHindIII.recognition, 'AAGCTT');
      expect(kHindIII.cutNotation, 'A^AGCTT');
      expect(kHindIII.overhang, 'AGCT');
      expect(kHindIII.isPalindrome, isTrue);
    });

    test('本模型只有三酶；按名字取酶大小写不敏感', () {
      expect(kRestrictionEnzymes.map((e) => e.name).toList(),
          ['EcoRI', 'BamHI', 'HindIII']);
      expect(restrictionEnzymeByName('ecori'), same(kEcoRI));
      expect(restrictionEnzymeByName(' HindIII '), same(kHindIII));
      expect(restrictionEnzymeByName('XhoI'), isNull);
    });

    test('不认识的酶名抛错并点名现有三酶', () {
      expect(
        () => restrictionDigestByName(sequence: 'GAATTC', enzymeName: 'XhoI'),
        throwsA(isA<ArgumentError>().having(
            (e) => e.message.toString(), 'message', contains('未知的限制酶'))),
      );
    });
  });

  group('输入清洗与错误', () {
    test('大写 + 去空白（空格 / 制表 / 换行 / 全角空格）', () {
      expect(normalizeDnaSequence('  gaa\tttc\n'), 'GAATTC');
      expect(normalizeDnaSequence('ga a\u3000ttc'), 'GAATTC');
    });

    test('空输入（含只有空白）抛错', () {
      for (final raw in ['', '   ', '\n\t ', '\u3000']) {
        expect(() => normalizeDnaSequence(raw),
            throwsA(isA<ArgumentError>()), reason: '「$raw」应被拒');
      }
      expect(
        () => normalizeDnaSequence('  '),
        throwsA(isA<ArgumentError>().having(
            (e) => e.message.toString(), 'message', contains('请输入 DNA 序列'))),
      );
    });

    test('非 ATCG 字符抛错，并指到第几个碱基位置', () {
      expect(
        () => restrictionDigest(sequence: 'GAAT CX', enzyme: kEcoRI),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message.toString(),
          'message',
          allOf(contains('四种碱基'), contains('「X」')),
        )),
      );
      // 数字、连字符、RNA 的 U 都不是 DNA 碱基。
      expect(() => normalizeDnaSequence('GAA1TTC'), throwsArgumentError);
      expect(() => normalizeDnaSequence('GAA-TTC'), throwsArgumentError);
      expect(() => normalizeDnaSequence('GAAUTTC'), throwsArgumentError);
    });

    test('超过 300 bp 抛错；正好 300 bp 合法', () {
      expect(() => normalizeDnaSequence('C' * (kRestrictionMaxLength + 1)),
          throwsArgumentError);
      expect(normalizeDnaSequence('C' * kRestrictionMaxLength).length,
          kRestrictionMaxLength);
    });
  });

  group('单酶切：位点 / 切点 / 片段', () {
    test('EcoRI 单位点：GG|GAATTC|GG → 位点第 3–8 位，切成 3 + 7', () {
      final d = restrictionDigest(sequence: 'GGGAATTCGG', enzyme: kEcoRI);
      expect(d.siteCount, 1);
      final site = d.sites.single;
      expect(site.start, 3);
      expect(site.end, 8);
      expect(site.cutAfter, 3, reason: 'G^AATTC：切口在第 3 位与第 4 位之间');
      expect(site.cutText, '顶链切口在第 3 位与第 4 位之间');
      expect(d.fragmentLengths, [3, 7]);
      expect(d.fragmentLengthSum, 10);
      expect(d.lengthConserved, isTrue);
      // 末端归属：左段只有右端是切口，右段只有左端是切口。
      expect(d.fragments[0].cutAtLeft, isFalse);
      expect(d.fragments[0].cutAtRight, isTrue);
      expect(d.fragments[1].cutAtLeft, isTrue);
      expect(d.fragments[1].cutAtRight, isFalse);
    });

    test('BamHI 单位点：TA|GGATCC|CT → 位点第 3–8 位，3 + 7', () {
      final d = restrictionDigest(sequence: 'TAGGATCCCT', enzyme: kBamHI);
      expect(d.sites.single.start, 3);
      expect(d.sites.single.cutAfter, 3);
      expect(d.fragmentLengths, [3, 7]);
      expect(d.lengthConserved, isTrue);
    });

    test('HindIII 单位点：CCC|AAGCTT|GGG → 4 + 8', () {
      final d = restrictionDigest(sequence: 'CCCAAGCTTGGG', enzyme: kHindIII);
      expect(d.sites.single.start, 4);
      expect(d.sites.single.cutAfter, 4);
      expect(d.fragmentLengths, [4, 8]);
      expect(d.fragmentLengthSum, 12);
    });

    test('位点在序列开头（第 1 位）：GAATTC → 1 + 5', () {
      final d = restrictionDigest(sequence: 'GAATTC', enzyme: kEcoRI);
      expect(d.sites.single.start, 1);
      expect(d.sites.single.cutAfter, 1);
      expect(d.fragmentLengths, [1, 5]);
      expect(d.fragmentLengths.fold<int>(0, (a, b) => a + b), 6);
    });

    test('多位点：2 个位点 → 3 段（3 + 9 + 7 = 19），中间段两端都是切口', () {
      final d = restrictionDigest(
          sequence: 'GCGAATTCCGGGAATTCAA', enzyme: kEcoRI);
      expect(d.sites.map((s) => s.start).toList(), [3, 12]);
      expect(d.siteCount, 2);
      expect(d.fragmentCount, 3, reason: '线性 DNA：切 2 刀得 3 段');
      expect(d.fragmentLengths, [3, 9, 7]);
      expect(d.lengthConserved, isTrue);
      expect(d.fragments[0].cutAtLeft, isFalse);
      expect(d.fragments[0].cutAtRight, isTrue);
      expect(d.fragments[1].cutAtLeft, isTrue);
      expect(d.fragments[1].cutAtRight, isTrue);
      expect(d.fragments[2].cutAtLeft, isTrue);
      expect(d.fragments[2].cutAtRight, isFalse);
      expect(d.fragments[1].endsText, contains('两端都是切口'));
      expect(d.fragments[2].endsText, contains('右端是原序列末端'));
    });

    test('无位点不是错误：不被切开，仍是 1 段（全长）', () {
      final d = restrictionDigest(sequence: 'CCCGGGCCCGGG', enzyme: kEcoRI);
      expect(d.hasSite, isFalse);
      expect(d.siteCount, 0);
      expect(d.fragmentCount, 1);
      expect(d.fragmentLengths, [12]);
      expect(d.fragments.single.endsText, contains('未被切开'));
      expect(d.summary, contains('没有该位点'));
      expect(d.lengthConserved, isTrue);
    });

    test('比识别序列还短的输入：合法但不可能有位点', () {
      final d = restrictionDigest(sequence: 'GAA', enzyme: kEcoRI);
      expect(d.shorterThanSite, isTrue);
      expect(d.hasSite, isFalse);
      expect(d.fragmentCount, 1);
      expect(d.summary, contains('短于识别序列'));
    });

    test('换一种酶就没位点：同一序列 EcoRI 有 2 个位点、BamHI 一个也没有', () {
      const seq = 'GCGAATTCCGGGAATTCAA';
      expect(restrictionDigest(sequence: seq, enzyme: kEcoRI).siteCount, 2);
      expect(restrictionDigest(sequence: seq, enzyme: kBamHI).siteCount, 0);
      expect(restrictionDigest(sequence: seq, enzyme: kHindIII).siteCount, 0);
    });

    test('小写 + 空白的输入与大写等价', () {
      final a = restrictionDigest(sequence: 'gcgaattccgggaattcaa', enzyme: kEcoRI);
      final b = restrictionDigest(
          sequence: 'GCG AAT TCC GGG AAT TCA A', enzyme: kEcoRI);
      expect(a.fragmentLengths, b.fragmentLengths);
      expect(a.sequence, b.sequence);
    });
  });

  group('识别序列长度 ≠ 切后片段数', () {
    test('识别序列 6 bp，但只切 1 刀 → 2 段；位点数才决定段数', () {
      final d = restrictionDigest(sequence: 'GGGAATTCGG', enzyme: kEcoRI);
      expect(d.enzyme.siteLength, 6);
      expect(d.fragmentCount, 2);
      expect(d.fragmentCount, isNot(d.enzyme.siteLength));
      expect(d.fragmentCount, d.siteCount + 1);
    });

    test('位点数与段数逐一对应（0→1、1→2、2→3）', () {
      final cases = <String, int>{
        'CCCGGGCCCGGG': 1, // 无位点
        'GGGAATTCGG': 2, // 1 刀
        'GCGAATTCCGGGAATTCAA': 3, // 2 刀
      };
      cases.forEach((seq, expected) {
        final d = restrictionDigest(sequence: seq, enzyme: kEcoRI);
        expect(d.fragmentCount, expected, reason: seq);
        expect(d.fragmentCount, d.siteCount + 1, reason: seq);
        expect(d.fragmentLengthSum, seq.length, reason: seq);
      });
    });

    test('summary 同时写出「识别序列 6 bp」和「切后片段数」，且点明两者不同', () {
      final d = restrictionDigest(
          sequence: 'GCGAATTCCGGGAATTCAA', enzyme: kEcoRI);
      expect(d.summary, contains('6 bp'));
      expect(d.summary, contains('3 段'));
      expect(d.summary, contains('两个量'));
    });
  });

  group('双链切点示意（顶链 5′→3′ / 底链 3′→5′，切口错开 4 列）', () {
    test('EcoRI：5′-G↓AATTC-3′ / 3′-CTTAA↑G-5′', () {
      final site = restrictionDigest(sequence: 'GAATTC', enzyme: kEcoRI)
          .sites
          .single;
      expect(site.doubleStrandSketch, '5′-G↓AATTC-3′\n3′-CTTAA↑G-5′');
    });

    test('BamHI：5′-G↓GATCC-3′ / 3′-CCTAG↑G-5′', () {
      final site = restrictionDigest(sequence: 'GGATCC', enzyme: kBamHI)
          .sites
          .single;
      expect(site.doubleStrandSketch, '5′-G↓GATCC-3′\n3′-CCTAG↑G-5′');
    });

    test('HindIII：5′-A↓AGCTT-3′ / 3′-TTCGA↑A-5′', () {
      final site = restrictionDigest(sequence: 'AAGCTT', enzyme: kHindIII)
          .sites
          .single;
      expect(site.doubleStrandSketch, '5′-A↓AGCTT-3′\n3′-TTCGA↑A-5′');
    });

    test('两行等长（等宽字体下才能逐列对齐）', () {
      final site = restrictionDigest(sequence: 'GAATTC', enzyme: kEcoRI)
          .sites
          .single;
      final lines = site.doubleStrandSketch.split('\n');
      expect(lines.length, 2);
      expect(lines[0].length, lines[1].length);
    });
  });

  group('辅助函数', () {
    test('complementDna 同向替换；reverseComplementDna 反转后再替换', () {
      expect(complementDna('GAATTC'), 'CTTAAG');
      expect(reverseComplementDna('GAATTC'), 'GAATTC', reason: '回文自证');
      expect(reverseComplementDna('ATGC'), 'GCAT');
    });

    test('片段长度守恒遍历：所有上例都成立', () {
      for (final seq in [
        'GAATTC',
        'GGGAATTCGG',
        'GCGAATTCCGGGAATTCAA',
        'CCCGGGCCCGGG',
        'GAA',
      ]) {
        final d = restrictionDigest(sequence: seq, enzyme: kEcoRI);
        expect(d.lengthConserved, isTrue, reason: '「$seq」片段之和必须等于全长');
      }
    });
  });
}
