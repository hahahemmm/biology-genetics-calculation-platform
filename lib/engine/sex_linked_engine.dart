// sex_linked_engine.dart —— 伴性遗传引擎（纯 Dart，精确分数）
//
// 支持伴 X 遗传（高考核心：红绿色盲、抗维生素 D 佝偻病模型）。
//
// 基因型记法（教学通用写法）：
//   雌性：XAXA / XAXa / XaXa（X 后紧跟等位基因字母，大写=显性）
//   雄性：XAY  / XaY（Y 上无等位基因）
//
// 核心规则：
//   雌性配子：各 X 染色体以 1/2 概率进入配子
//   雄性配子：X 与 Y 各 1/2
//   表型：雌性看两个 X（有显性即显性）；雄性只看唯一的 X（半合子）
//
// 输出全程 Fraction 精确分数，如「女儿患病 1/4」。

import 'fraction.dart';

/// 子代一个个体的结果。
class SexLinkedOffspring {
  final String genotype; // 如 XAXa
  final String sex; // '雌性' / '雄性'
  final String phenotype; // '显性' / '隐性'
  final Fraction probability; // 占全部子代的比例

  const SexLinkedOffspring({
    required this.genotype,
    required this.sex,
    required this.phenotype,
    required this.probability,
  });
}

/// 伴 X 杂交结果。
class SexLinkedResult {
  /// 全部子代（按基因型合并，概率为占全体子代的分数）。
  final List<SexLinkedOffspring> offspring;

  /// 雌性亲本基因型 / 雄性亲本基因型（标准化后）。
  final String femaleParent;
  final String maleParent;

  const SexLinkedResult({
    required this.offspring,
    required this.femaleParent,
    required this.maleParent,
  });

  /// 按性别+表型聚合：key 如 '雌性·显性'。
  Map<String, Fraction> get phenotypeBySex {
    final map = <String, Fraction>{};
    for (final o in offspring) {
      final key = '${o.sex}·${o.phenotype}';
      map[key] = (map[key] ?? Fraction.zero) + o.probability;
    }
    return map;
  }

  /// 某性别内的表型条件概率：P(表型 | 性别)。
  /// 返回 { '显性': 1/2, '隐性': 1/2 } 形式。
  Map<String, Fraction> phenotypeGivenSex(String sex) {
    final inSex = offspring.where((o) => o.sex == sex).toList();
    final total =
        inSex.fold(Fraction.zero, (s, o) => s + o.probability);
    final map = <String, Fraction>{};
    if (total.isZero) return map;
    for (final o in inSex) {
      map[o.phenotype] =
          (map[o.phenotype] ?? Fraction.zero) + o.probability / total;
    }
    return map;
  }
}

/// 伴 X 遗传引擎。
class SexLinkedEngine {
  /// 解析并校验基因型。返回 (x1Allele, x2Allele 或 null 表示 Y)。
  /// [expectFemale] true 要求 X?X? 形式，false 要求 X?Y 形式。
  static List<String> parseGenotype(String genotype, {required bool expectFemale}) {
    // 只把染色体字母 x 归一为 X；等位基因必须保留大小写（大写=显性）。
    final s = genotype.trim().replaceAll(' ', '').replaceAll('x', 'X');
    if (expectFemale) {
      final m = RegExp(r'^X([A-Za-z])X([A-Za-z])$').firstMatch(s);
      if (m == null) {
        throw ArgumentError('雌性基因型应为 XAXA / XAXa / XaXa 形式：$genotype');
      }
      final a = m.group(1)!, b = m.group(2)!;
      if (a.toLowerCase() != b.toLowerCase()) {
        throw ArgumentError('同一对位点等位基因字母必须一致（如 XAXa）：$genotype');
      }
      return [a, b];
    } else {
      final m = RegExp(r'^X([A-Za-z])Y$').firstMatch(s);
      if (m == null) {
        throw ArgumentError('雄性基因型应为 XAY / XaY 形式：$genotype');
      }
      return [m.group(1)!];
    }
  }

  /// 标准化基因型写法：等位基因按显性在前排列（XaXA → XAXa）。
  static String normalizeFemale(String genotype) {
    final alleles = parseGenotype(genotype, expectFemale: true);
    final a = alleles[0], b = alleles[1];
    // 大写（显性）在前
    final dom = a.toUpperCase();
    final isADom = a == dom;
    final isBDom = b == dom;
    final ordered = isADom == isBDom ? [a, b] : (isADom ? [a, b] : [b, a]);
    return 'X${ordered[0]}X${ordered[1]}';
  }

  static String normalizeMale(String genotype) {
    final alleles = parseGenotype(genotype, expectFemale: false);
    return 'X${alleles[0]}Y';
  }

  /// 雌性配子：两个 X 各 1/2（纯合时合并为 1）。
  static Map<String, Fraction> femaleGametes(String genotype) {
    final alleles = parseGenotype(genotype, expectFemale: true);
    final map = <String, Fraction>{};
    for (final a in alleles) {
      map['X$a'] = (map['X$a'] ?? Fraction.zero) + Fraction.half;
    }
    return map;
  }

  /// 雄性配子：X 与 Y 各 1/2。
  static Map<String, Fraction> maleGametes(String genotype) {
    final alleles = parseGenotype(genotype, expectFemale: false);
    return {'X${alleles[0]}': Fraction.half, 'Y': Fraction.half};
  }

  /// 伴 X 杂交：雌性 × 雄性 → 子代分布（精确分数）。
  SexLinkedResult cross(String female, String male) {
    final f = normalizeFemale(female);
    final m = normalizeMale(male);
    final fg = femaleGametes(f);
    final mg = maleGametes(m);

    final byGenotype = <String, SexLinkedOffspring>{};
    fg.forEach((fG, fp) {
      mg.forEach((mG, mp) {
        final prob = fp * mp;
        late final String genotype;
        late final String sex;
        late final String phenotype;
        if (mG == 'Y') {
          // 雄性子代：X 来自母本
          final allele = fG.substring(1);
          genotype = 'X${allele}Y';
          sex = '雄性';
          // 半合子：唯一的 X 决定表型
          phenotype =
              allele == allele.toUpperCase() ? '显性' : '隐性';
        } else {
          // 雌性子代：母本 X + 父本 X
          final a = fG.substring(1), b = mG.substring(1);
          final dom = a.toUpperCase();
          final isADom = a == dom;
          final isBDom = b == dom;
          final ordered =
              isADom == isBDom ? [a, b] : (isADom ? [a, b] : [b, a]);
          genotype = 'X${ordered[0]}X${ordered[1]}';
          sex = '雌性';
          phenotype = (isADom || isBDom) ? '显性' : '隐性';
        }
        final existing = byGenotype[genotype];
        byGenotype[genotype] = SexLinkedOffspring(
          genotype: genotype,
          sex: sex,
          phenotype: phenotype,
          probability:
              (existing?.probability ?? Fraction.zero) + prob,
        );
      });
    });

    final list = byGenotype.values.toList()
      ..sort((a, b) => b.probability.compareTo(a.probability));
    return SexLinkedResult(
      offspring: list,
      femaleParent: f,
      maleParent: m,
    );
  }

  /// 经典教学案例（红绿色盲模型，伴 X 隐性）。
  static const presets = <({String name, String female, String male, String note})>[
    (name: '携带者母亲 × 正常父亲', female: 'XAXa', male: 'XAY',
        note: '女儿全部正常（1/2 携带），儿子 1/2 患病——交叉遗传'),
    (name: '携带者母亲 × 患病父亲', female: 'XAXa', male: 'XaY',
        note: '儿女各 1/2 患病；女儿 1/2 携带'),
    (name: '正常纯合母亲 × 患病父亲', female: 'XAXA', male: 'XaY',
        note: '女儿全部携带但正常，儿子全部正常'),
    (name: '患病母亲 × 正常父亲', female: 'XaXa', male: 'XAY',
        note: '女儿全部携带（正常），儿子全部患病'),
  ];
}
