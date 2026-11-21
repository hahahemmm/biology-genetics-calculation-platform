// pcr_engine_test.dart —— PCR 扩增引擎守卫网
//
// 钉住四件事（⛔ 少一件都会让「科学语义」漂）：
//   1. 默认例的正向 / 反向结合区与产物**逐字段独立复算**（不读引擎字段）；
//   2. 循环数 ⇒ 理想拷贝数 2ⁿ（0 次 = 1），整数不溢出；
//   3. 六类错误各有中文可见文案：无匹配 / 多重匹配 / 方向错 / 重叠 /
//      非法字符 / 超范围，⛔ 绝不静默取第一个匹配；
//   4. 产物长度守恒 + 电泳位置口径（短片段更靠下、等长等距）。
import 'package:biology/engine/pcr_engine.dart';
import 'package:biology/engine/restriction_engine.dart'
    show reverseComplementDna;
import 'package:flutter_test/flutter_test.dart';

/// 默认模板（与屏上 [PcrLabState] 的出厂题同源；此处**硬编码**，
/// 防「拿引擎常量去验证引擎」）。
const _template =
    'GGGATGGCATCGATCGTTAGCATGCCGTTAACCGGTTAGCTAGCTTATTACGGATCCTAGCTAGGCATTA';
const _forward = 'ATGGCATCGATCGTTAGCAT';
const _reverse = 'TGCCTAGCTAGGATCCGTAA';

PcrResult _default({int cycles = 25}) => pcrAmplify(
  template: _template,
  forwardPrimer: _forward,
  reversePrimer: _reverse,
  cycles: cycles,
);

void main() {
  group('默认例：逐字段独立复算', () {
    test('正向结合区 = 第 4–23 位（模板顶链与引物完全相同的唯一一段）', () {
      final r = _default();
      // 独立复算：模板里 _forward 第一次出现的下标（人工数：前 3 个碱基 GGG）
      expect(_template.indexOf(_forward), 3);
      expect(r.forwardBinding.start, 4);
      expect(r.forwardBinding.end, 3 + _forward.length);
      expect(r.forwardBinding.sequence, _forward);
      expect(r.forwardBinding.length, 20);
      expect(r.forwardBinding.rangeText, '第 4–23 位');
    });

    test('反向结合区 = 第 48–67 位；其序列与反向引物互为反向互补', () {
      final r = _default();
      expect(r.reverseBinding.start, 48);
      expect(r.reverseBinding.end, 67);
      expect(r.reverseBinding.sequence, 'TTACGGATCCTAGCTAGGCA');
      expect(
        reverseComplementDna(r.reversePrimer),
        r.reverseBinding.sequence,
        reason: '反向引物 5′→3′ 的反向互补才是顶链上的结合区',
      );
      expect(reverseComplementDna(r.reverseBinding.sequence), r.reversePrimer);
    });

    test('扩增子 = 顶链第 4–67 位（含两端），长度 64 bp', () {
      final r = _default();
      // ⛔ 独立复算：自己切一段，再与引擎产物逐字比对
      final expected = _template.substring(3, 67);
      expect(r.amplicon, expected);
      expect(r.ampliconLength, 64);
      expect(r.productStart, 4);
      expect(r.productEnd, 67);
      expect(r.productRangeText, '第 4–67 位');
      expect(
        r.amplicon.startsWith(_forward),
        isTrue,
        reason: '产物 5′ 端就是正向引物本身',
      );
      expect(r.amplicon.endsWith(r.reverseBinding.sequence), isTrue);
      expect(r.lengthConserved, isTrue);
      expect(r.template, _template, reason: '模板原样保留（清洗后仍是它）');
    });

    test('产物长度守恒：区间跨度 = 序列长度 = 模板切片长度', () {
      final r = _default();
      expect(r.ampliconLength, r.productEnd - r.productStart + 1);
      expect(r.ampliconLength, _template.substring(3, 67).length);
    });

    test('小写 + 空白输入与大写等价（模板与引物都清洗）', () {
      final r = pcrAmplify(
        template:
            ' gggATGGCATCGATCGTTAGCAT'
            'GCCGTTAACCGGTTAGCTAGCTTATTACGGATCCTAGCTAGGCATTA ',
        forwardPrimer: ' atggcatcgatcgttagcat ',
        reversePrimer: 'tgcctagctaggatccgtaa',
        cycles: 25,
      );
      final d = _default();
      expect(r.template, d.template);
      expect(r.forwardPrimer, d.forwardPrimer);
      expect(r.amplicon, d.amplicon);
    });
  });

  group('循环数 ⇒ 理想拷贝数（2ⁿ，0 次 = 1）', () {
    test('0/1/3/5 次 = 1/2/8/32 份', () {
      final cases = <int, int>{0: 1, 1: 2, 3: 8, 5: 32};
      cases.forEach((n, expected) {
        final r = _default(cycles: n);
        expect(r.cycles, n);
        expect(r.idealCopies, BigInt.from(expected), reason: 'n=$n');
      });
    });

    test('上限 30 次仍是精确整数（2³⁰，无浮点误差）', () {
      final r = _default(cycles: kPcrMaxCycles);
      expect(r.idealCopies, BigInt.from(1073741824));
      expect(r.cycles, 30);
    });

    test('循环数不影响产物：0 次与 30 次扩增子完全相同', () {
      expect(
        _default(cycles: 0).amplicon,
        _default(cycles: 30).amplicon,
        reason: '循环数只决定拷贝数，不改变产物序列与长度',
      );
    });

    test('越界循环数（-1 / 31）抛错并写出允许范围', () {
      for (final n in [-1, 31]) {
        expect(
          () => _default(cycles: n),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message.toString(),
              'message',
              contains('循环数应在 0–30 之间'),
            ),
          ),
          reason: 'n=$n',
        );
      }
    });
  });

  group('共享理论扩增函数：N = N₀ × 2ⁿ', () {
    test('0/1/4/30 次循环均精确，0 次保留初始模板', () {
      final cases = <int, int>{0: 1, 1: 2, 4: 16, 30: 1073741824};
      cases.forEach((cycles, expected) {
        expect(
          pcrIdealProductCount(cycles: cycles),
          BigInt.from(expected),
          reason: 'n=$cycles',
        );
      });
      expect(
        pcrIdealProductCount(initialTemplates: 3, cycles: 0),
        BigInt.from(3),
      );
      expect(
        pcrIdealProductCount(initialTemplates: 3, cycles: 4),
        BigInt.from(48),
      );
      expect(
        pcrIdealProductCount(initialTemplates: 3, cycles: 30),
        BigInt.parse('3221225472'),
      );
    });

    test('初始模板必须为正整数，循环数沿用 0–30 边界', () {
      for (final initial in [0, -1]) {
        expect(
          () => pcrIdealProductCount(initialTemplates: initial, cycles: 4),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message.toString(),
              'message',
              contains('初始模板份数必须是正整数'),
            ),
          ),
        );
      }
      for (final cycles in [-1, 31]) {
        expect(
          () => pcrIdealProductCount(cycles: cycles),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message.toString(),
              'message',
              contains('循环数应在 0–30 之间'),
            ),
          ),
        );
      }
    });

    test('既有 PcrResult 与共享函数使用同一计算真源', () {
      for (final cycles in [0, 1, 4, 30]) {
        expect(
          _default(cycles: cycles).idealCopies,
          pcrIdealProductCount(cycles: cycles),
        );
      }
    });
  });

  group('引物错误：⛔ 绝不静默取第一个匹配', () {
    test('无匹配（两条引物都不在模板里）抛错', () {
      expect(
        () => pcrAmplify(
          template: 'CCCGGGTTTAACCCGGGTTTAAC',
          forwardPrimer: _forward,
          reversePrimer: _reverse,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            contains('正向引物在模板上没有匹配'),
          ),
        ),
      );
    });

    test('多重匹配：模板里出现两次 ⇒ 报「出现了 2 次」并点名位置', () {
      // 把同一段 DNA 重复两遍：FP 出现两次（第 4 位、第 45 位）
      final twice =
          'GGG${_forward}AACCGGTTAACCGGTTAA'
          'GGG${_forward}TTACGGATCCTAGCTAGGCATTA';
      expect(
        () => pcrAmplify(
          template: twice,
          forwardPrimer: _forward,
          reversePrimer: _reverse,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            allOf(contains('出现了 2 次'), contains('无法确定唯一结合位点')),
          ),
        ),
      );
    });

    test('正向引物方向写反（给成反向互补）：点名「方向写反了」', () {
      final wrongFwd = reverseComplementDna(_forward);
      expect(
        () => pcrAmplify(
          template: _template,
          forwardPrimer: wrongFwd,
          reversePrimer: _reverse,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            contains('正向引物方向写反了'),
          ),
        ),
      );
    });

    test('反向引物方向写反（给成顶链结合区本身）：点名「方向写反了」', () {
      expect(
        () => pcrAmplify(
          template: _template,
          forwardPrimer: _forward,
          reversePrimer: 'TTACGGATCCTAGCTAGGCA',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            allOf(contains('反向引物方向写反了'), contains('第 48 位')),
          ),
        ),
      );
    });

    test('两条引物结合区重叠 ⇒ 报重叠（不硬算一个负长度产物）', () {
      // 模板 = 正向结合区(4–23) 与反向结合区(从第 15 位起) 重叠
      const tpl = 'AAATGGCATCGATCGTTAGCATTTAAAAAAAAAATGCCTAGCTAGGATCCGTAATTT';
      // 反向引物放在正向引物内部：取顶链第 15 位开始的 20 nt 的反向互补
      final revBinding = tpl.substring(14, 34);
      final rp = reverseComplementDna(revBinding);
      expect(
        () => pcrAmplify(
          template: tpl,
          forwardPrimer: _forward,
          reversePrimer: rp,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            anyOf(contains('结合区重叠'), contains('引物对方向不对')),
          ),
        ),
        reason: '重叠或反向在上游，两类文案都合法；关键是必须拒，不能算产物',
      );
    });

    test('反向结合区在正向结合区上游 ⇒ 报「引物对方向不对」', () {
      // 把反向结合区放到模板最前面、正向结合区放后面
      const tpl =
          'TTACGGATCCTAGCTAGGCA'
          'GCCGTTAACCGGTTAGCTAGCTTA'
          'ATGGCATCGATCGTTAGCATTTT';
      expect(
        () => pcrAmplify(
          template: tpl,
          forwardPrimer: _forward,
          reversePrimer: _reverse,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            contains('引物对方向不对'),
          ),
        ),
      );
    });

    test('两条引物写成同一条：走「方向写反」这条路径，不混淆两条匹配路径', () {
      expect(
        () => pcrAmplify(
          template: _template,
          forwardPrimer: _forward,
          reversePrimer: _forward,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            allOf(contains('反向引物'), contains('方向写反了')),
          ),
        ),
      );
    });

    test('回文引物：反向互补等于自身时仍按唯一结合区处理（不与正向路径混）', () {
      // GAATATATTC 是回文（RC 等于自身）⇒ 反向路径找到的就是它自己那一处，
      // 不会因为「两条路径都能匹配」而取错位置。
      const revPalindrome = 'GAATATATTC';
      const tpl = 'GCTAGCTAGCCCCGAATATATTCGTTAA';
      expect(reverseComplementDna(revPalindrome), revPalindrome);
      final r = pcrAmplify(
        template: tpl,
        forwardPrimer: 'GCTAGCTAGC', // 第 1–10 位
        reversePrimer: revPalindrome, // 回文 ⇒ 结合区第 14–23 位
      );
      expect(r.forwardBinding.start, 1);
      expect(r.forwardBinding.end, 10);
      expect(r.reverseBinding.start, 14);
      expect(r.reverseBinding.end, 23);
      expect(r.amplicon, tpl.substring(0, 23));
      expect(r.ampliconLength, 23);
      expect(r.lengthConserved, isTrue);
    });

    test('非法碱基：引物里出现 X ⇒ 点名哪条引物、第几位', () {
      expect(
        () => pcrAmplify(
          template: _template,
          forwardPrimer: 'ATGGCATCXATCGTTAGCAT',
          reversePrimer: _reverse,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            allOf(contains('正向引物只能含 A、T、C、G'), contains('「X」')),
          ),
        ),
      );
      expect(
        () => pcrAmplify(
          template: _template,
          forwardPrimer: _forward,
          reversePrimer: 'TGCCTAGCTA1GATCCGTAA',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            contains('反向引物只能含 A、T、C、G'),
          ),
        ),
      );
    });

    test('模板非法碱基 / 空模板沿用 DNA 清洗文案', () {
      expect(
        () => pcrAmplify(
          template: 'GGGATGGCATCGATCGTTAGCATX',
          forwardPrimer: _forward,
          reversePrimer: _reverse,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            contains('四种碱基'),
          ),
        ),
      );
      expect(
        () => pcrAmplify(
          template: '   ',
          forwardPrimer: _forward,
          reversePrimer: _reverse,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            contains('请输入 DNA 序列'),
          ),
        ),
      );
    });

    test('引物长度上下限：< 10 nt 与 > 30 nt 都拒，文案写出范围', () {
      expect(
        () => pcrAmplify(
          template: _template,
          forwardPrimer: 'ATGGCATCG',
          reversePrimer: _reverse,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            allOf(contains('正向引物长度 9 nt'), contains('10–30 nt')),
          ),
        ),
      );
      expect(
        () => pcrAmplify(
          template: _template,
          forwardPrimer: 'A' * (kPcrMaxPrimerLength + 1),
          reversePrimer: _reverse,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            contains('超出教学范围'),
          ),
        ),
      );
    });

    test('引物为空 ⇒ 「请输入…引物」', () {
      expect(
        () => pcrAmplify(
          template: _template,
          forwardPrimer: '  ',
          reversePrimer: _reverse,
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            contains('请输入正向引物'),
          ),
        ),
      );
    });
  });

  group('凝胶位置口径（只示意方向，不等长换等距）', () {
    test('marker 上限在最上（0）、下限在最下（1）', () {
      expect(gelPositionFor(kGelMarkerBps.first), 0.0);
      expect(gelPositionFor(kGelMarkerBps.last), 1.0);
    });

    test('短片段迁移更远：长度递减 ⇒ 位置单调递增', () {
      final positions = <double>[
        for (final bp in kGelMarkerBps) gelPositionFor(bp),
      ];
      for (var i = 1; i < positions.length; i++) {
        expect(
          positions[i],
          greaterThan(positions[i - 1]),
          reason: '${kGelMarkerBps[i]} bp 必须比 ${kGelMarkerBps[i - 1]} bp 更靠下',
        );
      }
    });

    test('等长等距：同一长度两次调用完全相同，且落在 marker 档间', () {
      expect(gelPositionFor(64), gelPositionFor(64));
      final p64 = gelPositionFor(64);
      expect(
        p64,
        greaterThan(gelPositionFor(100)),
        reason: '64 bp 比 100 bp 更靠下',
      );
      expect(p64, lessThan(gelPositionFor(50)));
      expect(gelInMarkerRange(64), isTrue);
      expect(gelInMarkerRange(2000), isFalse);
      expect(gelInMarkerRange(20), isFalse);
    });

    test('超出分档被夹到端点（不做回归、不外推）', () {
      expect(gelPositionFor(5000), 0.0);
      expect(gelPositionFor(10), 1.0);
    });

    test('bp ≤ 0 抛 ArgumentError（不让 log(0)/NaN 冒到屏上）', () {
      for (final bp in [0, -1, -100]) {
        expect(
          () => gelPositionFor(bp),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message.toString(),
              'message',
              contains('片段长度必须是正整数'),
            ),
          ),
          reason: 'bp=$bp',
        );
        expect(
          () => gelInMarkerRange(bp),
          throwsArgumentError,
          reason: 'bp=$bp',
        );
      }
    });

    test('空 marker 抛 ArgumentError（不给空的 reduce 崩成 StateError）', () {
      const empty = <int>[];
      expect(
        () => gelPositionFor(100, markerBps: empty),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            contains('marker 分档不能为空'),
          ),
        ),
      );
      expect(
        () => gelInMarkerRange(100, markerBps: empty),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            contains('marker 分档不能为空'),
          ),
        ),
      );
    });

    test('marker 含非正数抛 ArgumentError 并回显分档', () {
      for (final bad in [
        <int>[100, 0, 10],
        <int>[-5, 100],
      ]) {
        expect(
          () => gelPositionFor(50, markerBps: bad),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message.toString(),
              'message',
              contains('marker 分档必须是正整数'),
            ),
          ),
          reason: '$bad',
        );
        expect(() => gelInMarkerRange(50, markerBps: bad), throwsArgumentError);
      }
    });

    test('单档 marker：全部落在 0（合法，不算错）', () {
      expect(gelPositionFor(123, markerBps: const <int>[500]), 0.0);
      expect(gelInMarkerRange(123, markerBps: const <int>[500]), isFalse);
      expect(gelInMarkerRange(500, markerBps: const <int>[500]), isTrue);
    });
  });

  group('辅助函数', () {
    test('normalizePrimer：清洗 + 长度校验', () {
      // 12 nt（≥ kPcrMinPrimerLength）：只有空白被吃掉，碱基不变
      expect(
        normalizePrimer(' atg gca tcg tta ', label: '正向引物'),
        'ATGGCATCGTTA',
      );
      expect(
        () => normalizePrimer('', label: '正向引物'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message.toString(),
            'message',
            contains('请输入正向引物'),
          ),
        ),
      );
    });
  });
}
