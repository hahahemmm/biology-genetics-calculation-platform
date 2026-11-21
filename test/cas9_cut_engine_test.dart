import 'package:biology/engine/cas9_cut_engine.dart';
import 'package:biology/engine/restriction_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const proto = 'ACGTACGTACGTACGTACGT';

  group('SpCas9 手算位点', () {
    test('上链 NGG：取 PAM 同链 5′ 侧 20 nt，切在 PAM 前 3 bp 边界', () {
      final result = analyzeSpCas9Cuts('TTTTT${proto}TGGTTT');

      expect(result.topSequence, 'TTTTT${proto}TGGTTT');
      expect(result.bottomSequence, complementDna('TTTTT${proto}TGGTTT'));
      expect(result.pamMotifCount, 1);
      expect(result.sites, hasLength(1));
      final site = result.sites.single;
      expect(site.pamStrand, Cas9PamStrand.displayedTop);
      expect(site.pam, 'TGG');
      expect(site.protospacer, proto);
      expect(site.pamStart, 25); // 0-based，仅供程序定位。
      expect(site.pamStart1Based, 26);
      expect(site.pamEnd1Based, 28);
      expect(site.cutBoundary, 22); // 顶链 0-based 右边界。
      expect(site.cutLeft1Based, 22);
      expect(site.cutRight1Based, 23);
      expect(site.protospacer, hasLength(20));
    });

    test('互补链 NGG：上链 CCN 右侧 20 nt 反向互补，切点方向不镜像错', () {
      final result = analyzeSpCas9Cuts('AAAACCG${proto}TT');

      expect(result.pamMotifCount, 1);
      expect(result.sites, hasLength(1));
      final site = result.sites.single;
      expect(site.pamStrand, Cas9PamStrand.complementaryBottom);
      expect(site.pam, 'CGG');
      expect(site.protospacer, reverseComplementDna(proto));
      expect(site.pamStart, 4);
      expect(site.pamStart1Based, 5);
      expect(site.pamEnd1Based, 7);
      expect(site.cutBoundary, 10);
      expect(site.cutLeft1Based, 10);
      expect(site.cutRight1Based, 11);
    });

    test('23 nt 最小上链例题接受小写与空白，切在第 17 与 18 位之间', () {
      final result = analyzeSpCas9Cuts('aaaa aaaa aaaa aaaa aaaa agg');

      expect(result.topSequence, '${'A' * 20}AGG');
      expect(result.sites.single.protospacer, 'A' * 20);
      expect(result.sites.single.pam, 'AGG');
      expect(result.sites.single.cutLeft1Based, 17);
      expect(result.sites.single.cutRight1Based, 18);
    });

    test('23 nt 最小互补链例题切在上链第 6 与 7 位之间', () {
      final result = analyzeSpCas9Cuts('CCT$proto');

      expect(result.sites.single.pamStrand, Cas9PamStrand.complementaryBottom);
      expect(result.sites.single.pam, 'AGG');
      expect(result.sites.single.cutLeft1Based, 6);
      expect(result.sites.single.cutRight1Based, 7);
    });

    test('同一序列同时报告两条链的完整位点并按上链坐标排序', () {
      final result = analyzeSpCas9Cuts('${'A' * 20}AGGCCT$proto');

      expect(result.pamMotifCount, 2);
      expect(result.sites, hasLength(2));
      expect(result.sites.map((site) => site.pamStrand), <Cas9PamStrand>[
        Cas9PamStrand.displayedTop,
        Cas9PamStrand.complementaryBottom,
      ]);
      expect(result.sites.map((site) => site.pamStart), <int>[20, 23]);
    });

    test('无 NGG／CCN 与 PAM 旁不足 20 nt 是可区分的空结果', () {
      final noMotif = analyzeSpCas9Cuts('A' * 23);
      expect(noMotif.pamMotifCount, 0);
      expect(noMotif.sites, isEmpty);

      final insufficient = analyzeSpCas9Cuts('AGG${'A' * 20}');
      expect(insufficient.pamMotifCount, 1);
      expect(insufficient.sites, isEmpty);
    });
  });

  group('SpCas9 输入边界', () {
    test('空序列与非法碱基给出可读错误', () {
      expect(() => analyzeSpCas9Cuts('  \n'), throwsArgumentError);
      expect(
        () => analyzeSpCas9Cuts('ACGTNACGTACGTACGTACGTACGT'),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains('只能含 A、T、C、G'),
          ),
        ),
      );
    });

    test('22 nt 拒绝，120 nt 接受，121 nt 拒绝', () {
      expect(() => analyzeSpCas9Cuts('A' * 22), throwsArgumentError);
      expect(analyzeSpCas9Cuts('A' * 120).sites, isEmpty);
      expect(
        () => analyzeSpCas9Cuts('A' * 121),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains('上限 120 bp'),
          ),
        ),
      );
    });

    test('Unicode 连字按非法字符处理，不触发未捕获范围异常', () {
      final raw = List.filled(121, '\uFB03').join();

      expect(
        () => analyzeSpCas9Cuts(raw),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains('只能含 A、T、C、G'),
          ),
        ),
      );
    });
  });
}
