// ploidy_engine.dart —— 染色体倍性计算引擎（纯 Dart，跨平台）
//
// v2.2 批次3 新增。覆盖高考常考倍性题型：
//   1. 染色体组数判断（形态法：同一形态的染色体有几条 = 几个染色体组；
//      基因型法：控制同一性状的基因〔同一字母不分大小写〕出现几次 = 几个组）
//   2. 单倍体/二倍体/多倍体判定（关键看发育来源：配子发育=单倍体，
//      与染色体组数无关；受精卵发育按组数命名）
//   3. 单倍体育种：花药离体培养 → 单倍体 → 秋水仙素加倍 → 100% 纯合
//   4. 三倍体无子原理：奇数染色体组联会紊乱，配子不育
// 输入输出 int / String / List，无 IO。

/// 染色体组数判断结果（形态法）。
class SetsByMorphology {
  final int totalChromosomes; // 细胞中染色体总条数
  final int distinctForms; // 不同形态种数
  final int sets; // 染色体组数 = total / forms（每种形态每组 1 条）
  final int perSet; // 每个染色体组含染色体条数 = forms
  const SetsByMorphology({
    required this.totalChromosomes,
    required this.distinctForms,
    required this.sets,
    required this.perSet,
  });
}

/// 形态法：已知染色体总条数与形态种数，求染色体组数。
/// 原理：一个染色体组内每条染色体形态各不相同，故
/// 组数 = 总条数 ÷ 形态种数（= 同一形态染色体的条数）。
SetsByMorphology setsByMorphology({
  required int totalChromosomes,
  required int distinctForms,
}) {
  if (totalChromosomes < 1) throw ArgumentError('染色体总条数至少为 1');
  if (distinctForms < 1) throw ArgumentError('形态种数至少为 1');
  if (totalChromosomes % distinctForms != 0) {
    throw ArgumentError('总条数应能被形态种数整除（同一形态每组各 1 条）');
  }
  return SetsByMorphology(
    totalChromosomes: totalChromosomes,
    distinctForms: distinctForms,
    sets: totalChromosomes ~/ distinctForms,
    perSet: distinctForms,
  );
}

/// 基因型法判断结果。
class SetsByGenotype {
  final String genotype;
  final Map<String, int> letterCounts; // 各字母（大写归一）出现次数
  final int sets; // 染色体组数 = 同一字母的最大出现次数
  const SetsByGenotype({
    required this.genotype,
    required this.letterCounts,
    required this.sets,
  });
}

/// 基因型法：同一字母（不分大小写）出现次数 = 控制同一性状的基因数
/// = 染色体组数。如 Aa → 2 组；AaaBBb → 3 组；AAaaBBbb → 4 组。
/// 只统计字母；数字（如 A1）与其他字符忽略。多字母取最大次数。
SetsByGenotype setsByGenotype(String genotype) {
  final counts = <String, int>{};
  for (final ch in genotype.split('')) {
    final u = ch.toUpperCase();
    if (!RegExp(r'[A-Z]').hasMatch(u)) continue;
    counts[u] = (counts[u] ?? 0) + 1;
  }
  if (counts.isEmpty) throw ArgumentError('基因型中未找到字母（如 AaBb）');
  final sets = counts.values.reduce((a, b) => a > b ? a : b);
  return SetsByGenotype(
    genotype: genotype,
    letterCounts: Map.unmodifiable(counts),
    sets: sets,
  );
}

/// 个体发育来源。
enum PloidyOrigin {
  zygote, // 受精卵发育
  gamete, // 配子（花药/卵细胞）直接发育
}

/// 倍性判定结果。
class PloidyJudgment {
  final int sets;
  final PloidyOrigin origin;
  final String name; // '单倍体' / '二倍体' / '三倍体' / '四倍体' / '多倍体'
  final bool fertile; // 可育性（奇数组联会紊乱 → 不育；单倍体高度不育）
  final String reason; // 判定理由（思维链展示用）
  const PloidyJudgment({
    required this.sets,
    required this.origin,
    required this.name,
    required this.fertile,
    required this.reason,
  });
}

/// 倍性判定：先看发育来源，再看染色体组数。
/// - 配子直接发育 → 单倍体（无论含几个染色体组；高度不育）
/// - 受精卵发育 → 2 组=二倍体，3 组=三倍体，…≥3 组通称多倍体
/// 可育性：偶数组（2/4/6…）通常可育；奇数组（3/5…）联会紊乱不育；
/// 单倍体高度不育（无同源染色体或组数不成对）。
PloidyJudgment judgePloidy({required int sets, required PloidyOrigin origin}) {
  if (sets < 1) throw ArgumentError('染色体组数至少为 1');
  if (origin == PloidyOrigin.gamete) {
    return PloidyJudgment(
      sets: sets,
      origin: origin,
      name: '单倍体',
      fertile: false,
      reason: '由配子直接发育而来，无论含 $sets 个染色体组均为单倍体；'
          '减数分裂时同源染色体联会困难，高度不育。',
    );
  }
  const names = {1: '一倍体', 2: '二倍体', 3: '三倍体', 4: '四倍体', 5: '五倍体', 6: '六倍体', 8: '八倍体'};
  final name = names[sets] ?? (sets >= 3 ? '多倍体($sets组)' : '$sets倍体');
  final fertile = sets % 2 == 0;
  return PloidyJudgment(
    sets: sets,
    origin: origin,
    name: sets >= 3 && !names.containsKey(sets) ? '多倍体' : name,
    fertile: fertile,
    reason: fertile
        ? '受精卵发育，含 $sets 个染色体组（偶数）→ $name；同源染色体能正常联会，可育。'
        : '受精卵发育，含 $sets 个染色体组（奇数）→ $name；减数分裂联会紊乱，不能产生正常配子，不育（如三倍体无子西瓜）。',
  );
}

/// 单倍体育种结果：亲本基因型 → 花粉（配子）类型 → 秋水仙素加倍后的
/// 纯合二倍体类型。每种类型比例均等（各 1/n）。
class HaploidBreedingResult {
  final String parentGenotype;
  final List<String> gametes; // 花药（配子）基因型
  final List<String> doubled; // 加倍后的纯合基因型
  final double pureRatio; // 纯合子比例 = 1.0（100%）
  const HaploidBreedingResult({
    required this.parentGenotype,
    required this.gametes,
    required this.doubled,
    required this.pureRatio,
  });
}

/// 单倍体育种计算：输入杂合亲本基因型（如 AaBb，各对基因自由组合），
/// 列出全部花药基因型与秋水仙素加倍后的纯合个体基因型。
/// 支持 1–3 对基因（每对两个字母：一显一隐，如 Aa）。
/// 要点（高考结论）：单倍体育种后代 100% 纯合，明显缩短育种年限。
HaploidBreedingResult haploidBreeding(String parentGenotype) {
  // 解析为基因对：[('A','a'), ('B','b')...]（相邻两个同字母字符为一对）
  final pairs = <List<String>>[];
  final chars = parentGenotype.split('').where((c) => RegExp(r'[A-Za-z]').hasMatch(c)).toList();
  var i = 0;
  while (i < chars.length) {
    final u = chars[i].toUpperCase();
    var j = i + 1;
    final pair = <String>[chars[i]];
    while (j < chars.length && chars[j].toUpperCase() == u && pair.length < 2) {
      pair.add(chars[j]);
      j++;
    }
    if (pair.length == 2) {
      pairs.add(pair);
      i = j;
    } else {
      i = j > i ? j : i + 1;
    }
  }
  if (pairs.isEmpty) throw ArgumentError('未识别到基因对（示例格式：AaBb）');
  if (pairs.length > 3) throw ArgumentError('最多支持 3 对基因（自由组合）');
  // 笛卡尔积生成配子
  var gametes = <String>[''];
  for (final pair in pairs) {
    final next = <String>[];
    for (final g in gametes) {
      for (final allele in pair.toSet()) {
        next.add(g + allele);
      }
    }
    gametes = next;
  }
  gametes = gametes.toSet().toList()..sort();
  final doubled = [
    for (final g in gametes) g.split('').map((c) => '$c$c').join(),
  ];
  return HaploidBreedingResult(
    parentGenotype: parentGenotype,
    gametes: gametes,
    doubled: doubled,
    pureRatio: 1.0,
  );
}

/// 四倍体（同源四倍体）配子比例结果：4 条同源染色体随机两两进入
/// 配子（C(4,2)=6 种等概率组合），按基因型统计计数。
class TetraploidGametes {
  final String genotype; // 如 AAaa（4 个同字母等位基因）
  final Map<String, int> counts; // {'AA':1,'Aa':4,'aa':1}（合计 6）
  const TetraploidGametes({required this.genotype, required this.counts});

  /// 比例描述，如 'AA : Aa : aa = 1 : 4 : 1'。
  String get ratioText {
    final ks = counts.keys.toList();
    return '${ks.join(' : ')} = ${ks.map((k) => counts[k]).join(' : ')}';
  }
}

/// 同源四倍体配子比例：输入 4 字符基因型（同一字母、大小写区分显隐，
/// 如 AAaa / AAAa / Aaaa），4 条同源染色体减数分裂随机 2 条进配子，
/// 枚举 C(4,2)=6 种等概率组合统计。
/// 经典结论：AAaa → AA:Aa:aa = 1:4:1；AAAa → AA:Aa = 1:1；
/// Aaaa → Aa:aa = 1:1。
TetraploidGametes tetraploidGametes(String genotype) {
  final chars = genotype.split('').where((c) => RegExp(r'[A-Za-z]').hasMatch(c)).toList();
  if (chars.length != 4) throw ArgumentError('四倍体基因型应为 4 个字母（如 AAaa）');
  final up = chars.map((c) => c.toUpperCase()).toSet();
  if (up.length != 1) throw ArgumentError('4 个字母应为同一基因（如 AAaa，不分大小写）');
  final counts = <String, int>{};
  for (var i = 0; i < 4; i++) {
    for (var j = i + 1; j < 4; j++) {
      var g = chars[i] + chars[j];
      // 统一写法：大写在前小写在后（如 aA → Aa）
      final sorted = g.split('')..sort((x, y) => x.compareTo(y));
      g = sorted.join();
      counts[g] = (counts[g] ?? 0) + 1;
    }
  }
  final sortedKeys = counts.keys.toList()..sort();
  return TetraploidGametes(
    genotype: genotype,
    counts: {for (final k in sortedKeys) k: counts[k]!},
  );
}

/// 杂交育种流程结果：杂合亲本自交 → 分离世代选目标表型 →
/// 连续自交逐代筛选至纯合率 ≥99%（高考/月考「育种年限」高频题）。
class HybridBreedingResult {
  final String parentGenotype; // 亲本（杂种）基因型，如 AaBb
  final String targetGenotype; // 目标纯合基因型，如 AABB
  final int genePairs; // 基因对数（1 或 2，独立分配）
  final int segregatingTotal; // 分离世代组合总数 = 4^k（k=杂合位点数）
  final int targetPhenotypeCount; // 分离世代中目标表型份数
  final int targetPureCount; // 其中目标纯合基因型份数
  final int genotypeKinds; // 分离世代基因型种数 = 3^k
  final bool pureAtSelection; // 目标位点全为隐性 → 选出目标表型即 100% 纯合
  final int selfingGenerations; // 连续自交代数 n（纯合率 ≥99%；0=无需再自交）
  final double pureRateAfterN; // n 代连续自交后的目标纯合率
  final int estimatedYears; // 估计年限（一年一代：自交分离 1 年 + 连续自交 n 年）
  final List<String> notes; // 教学要点
  const HybridBreedingResult({
    required this.parentGenotype,
    required this.targetGenotype,
    required this.genePairs,
    required this.segregatingTotal,
    required this.targetPhenotypeCount,
    required this.targetPureCount,
    required this.genotypeKinds,
    required this.pureAtSelection,
    required this.selfingGenerations,
    required this.pureRateAfterN,
    required this.estimatedYears,
    required this.notes,
  });
}

/// 解析基因型为基因对列表（相邻两个同字母字符为一对，如 AaBb →
/// [['A','a'],['B','b']]）。与 haploidBreeding 同款规则，独立实现不动既有逻辑。
List<List<String>> _parseGenePairs(String genotype) {
  final pairs = <List<String>>[];
  final chars =
      genotype.split('').where((c) => RegExp(r'[A-Za-z]').hasMatch(c)).toList();
  var i = 0;
  while (i < chars.length) {
    final u = chars[i].toUpperCase();
    var j = i + 1;
    final pair = <String>[chars[i]];
    while (j < chars.length && chars[j].toUpperCase() == u && pair.length < 2) {
      pair.add(chars[j]);
      j++;
    }
    if (pair.length == 2) {
      pairs.add(pair);
      i = j;
    } else {
      i = j > i ? j : i + 1;
    }
  }
  return pairs;
}

/// 杂交育种流程推算：输入杂合亲本基因型（1–2 对基因，独立分配，
/// 如 AaBb）与目标纯合基因型（如 AABB / AAbb / aabb），输出：
/// 分离世代目标表型占比、目标纯合份数、连续自交纯化代数与估计年限。
///
/// 模型约定（高考通用近似，逐年一代）：
/// - 亲本自交一代得分离世代；每位点 Aa×Aa → 1/4 AA : 1/2 Aa : 1/4 aa
/// - 目标位点为显性（如 AA）时，目标表型个体中杂合占 2/3，
///   须连续自交并逐代淘汰非目标表型个体：杂合率 h₀=2/3，
///   hₙ = 2/(2^(n+1)+1)（hₙ₊₁=(hₙ/2)/(1−hₙ/4)）
/// - 目标位点为隐性（如 aa）时，分离世代表现出目标性状即纯合，
///   该位点无需纯化
/// - 多位点纯合率按独立分配取乘积 (1−hₙ)^k（k=显性目标杂合位点数）
/// 输入非法（无基因对 / 超过 2 对 / 目标非纯合 / 目标等位基因亲本
/// 不具备）一律抛 ArgumentError。
HybridBreedingResult hybridBreeding(
    String parentGenotype, String targetGenotype) {
  final parentPairs = _parseGenePairs(parentGenotype);
  if (parentPairs.isEmpty) {
    throw ArgumentError('未识别到基因对（示例格式：AaBb）');
  }
  if (parentPairs.length > 2) {
    throw ArgumentError('杂交育种流程最多支持 2 对基因（独立分配）');
  }
  final targetPairs = _parseGenePairs(targetGenotype);
  if (targetPairs.length != parentPairs.length) {
    throw ArgumentError('目标基因型应与亲本基因对数一致（如 AaBb → AABB）');
  }
  // 逐位点校验：位点字母一致；目标纯合；目标等位基因须来自亲本
  for (var i = 0; i < parentPairs.length; i++) {
    final p = parentPairs[i];
    final t = targetPairs[i];
    final letter = p[0].toUpperCase();
    if (t[0].toUpperCase() != letter) {
      throw ArgumentError('目标基因型位点顺序应与亲本一致（第 ${i + 1} 对应为 $letter）');
    }
    if (t[0] != t[1]) {
      throw ArgumentError('目标应为纯合基因型（如 AABB），第 ${i + 1} 对 ${t.join()} 不是纯合');
    }
    if (!p.contains(t[0])) {
      throw ArgumentError('亲本 $letter 位点不含等位基因 ${t[0]}，'
          '无法育出目标 $targetGenotype');
    }
  }

  var total = 1;
  var targetPheno = 1;
  var hetCount = 0;
  var dominantHetCount = 0; // 目标为显性且亲本杂合的位点数（需要纯化的位点）
  for (var i = 0; i < parentPairs.length; i++) {
    final p = parentPairs[i];
    final t = targetPairs[i];
    final isHet = p[0] != p[1];
    if (!isHet) continue; // 亲本已纯合固定位点：后代该位点必然为目标
    hetCount++;
    total *= 4;
    final targetDominant = t[0].toUpperCase() == t[0];
    targetPheno *= targetDominant ? 3 : 1; // 显性目标占 3/4，隐性占 1/4
    if (targetDominant) dominantHetCount++;
  }
  final targetPure = 1; // 每个杂合位点的目标纯合基因型各 1 份

  // 连续自交纯化：h₀=2/3，每代 hₙ₊₁=(hₙ/2)/(1−hₙ/4)，
  // 纯合率=(1−hₙ)^k ≥ 99% 的最小 n
  var n = 0;
  var pureRate = 1.0;
  if (dominantHetCount > 0) {
    var h = 2 / 3;
    pureRate = _pow1mh(h, dominantHetCount);
    while (pureRate < 0.99) {
      h = (h / 2) / (1 - h / 4);
      n++;
      pureRate = _pow1mh(h, dominantHetCount);
    }
  }
  final pureAtSelection = dominantHetCount == 0;
  final years = 1 + n; // 第 1 年自交得分离世代并选种，再连续自交 n 年

  final pct = (pureRate * 100).toStringAsFixed(1);
  final notes = <String>[
    '分离世代目标表型占 $targetPheno/$total，'
        '其中纯合 $targetGenotype 仅 $targetPure/$total',
    if (pureAtSelection)
      '目标性状全为隐性：分离世代中表现出目标性状的个体即纯合子，'
          '选出即可，无需连续自交'
    else ...[
      '目标含显性性状：选出的目标表型个体中杂合占 2/3，'
          '须连续自交并逐代淘汰非目标表型个体',
      '每自交一代杂合率减半，连续自交 $n 代后纯合率约 $pct%（≥99%）',
    ],
    '杂交育种年限长（约 $years 年）是其主要缺点；'
        '可用单倍体育种明显缩短育种年限',
  ];

  return HybridBreedingResult(
    parentGenotype: parentGenotype,
    targetGenotype: targetGenotype,
    genePairs: parentPairs.length,
    segregatingTotal: total,
    targetPhenotypeCount: targetPheno,
    targetPureCount: targetPure,
    genotypeKinds: hetCount == 0 ? 1 : (hetCount == 1 ? 3 : 9),
    pureAtSelection: pureAtSelection,
    selfingGenerations: n,
    pureRateAfterN: pureRate,
    estimatedYears: years,
    notes: notes,
  );
}

/// (1−h)^k（k≥1）。
double _pow1mh(double h, int k) {
  var v = 1.0;
  for (var i = 0; i < k; i++) {
    v *= 1 - h;
  }
  return v;
}

/// 三倍体无子西瓜（三倍体育种）计算结果。
/// 高考经典模型：二倍体×四倍体 → 三倍体种子；三倍体植株减数分裂
/// 联会紊乱 → 高度不育 → 无子；需二倍体花粉刺激子房发育成果实。
class TriploidSeedlessResult {
  final int x; // 基本染色体数（一个染色体组的条数，如西瓜 x=11）
  final int motherPloidy; // 母本倍数（2 或 4）
  final int fatherPloidy; // 父本倍数（4 或 2）
  final int embryoSets; // 种子胚的染色体组数 = 3
  final int endospermSets; // 胚乳组数 = 2×母本配子组数 + 父本精细胞组数
  final int fruitSets; // 果实（果皮=子房壁）组数 = 母本植株倍数
  final int embryoChromosomes; // 胚染色体总数
  final String sterility; // 不育原理
  final String pollenRole; // 二倍体花粉作用
  const TriploidSeedlessResult({
    required this.x,
    required this.motherPloidy,
    required this.fatherPloidy,
    required this.embryoSets,
    required this.endospermSets,
    required this.fruitSets,
    required this.embryoChromosomes,
    required this.sterility,
    required this.pollenRole,
  });
}

/// 三倍体无子西瓜模型：母本倍数 × 父本倍数（一个为 2、一个为 4），
/// 基本染色体数 x（默认西瓜 x=11，2n=22）。
/// 高考判据：
/// - 胚 = 母本配子 + 父本精细胞 → 组数 = 母/2 + 父/2 = 3（三倍体）
/// - 胚乳 = 2 个极核（各与母本配子同组数）+ 1 精细胞：
///   四倍体母本时 2×2+1 = 5（五倍体）；二倍体母本时 2×1+2 = 4（四倍体）
/// - 果皮（子房壁）是母本体细胞 → 组数 = 母本倍数（易错点！）
/// - 三倍体减数分裂同源染色体联会紊乱 → 几乎不产生正常配子 → 无子
/// - 二倍体花粉仅提供生长素刺激子房发育，不参与受精
TriploidSeedlessResult triploidSeedless({
  int x = 11,
  int motherPloidy = 4,
  int fatherPloidy = 2,
}) {
  if (!((motherPloidy == 4 && fatherPloidy == 2) ||
      (motherPloidy == 2 && fatherPloidy == 4))) {
    throw ArgumentError('亲本须为四倍体×二倍体（或反向），当前：'
        '$motherPloidy×$fatherPloidy');
  }
  if (x < 1) throw ArgumentError('基本染色体数 x 须 ≥1');
  final embryoSets = motherPloidy ~/ 2 + fatherPloidy ~/ 2;
  final endospermSets = 2 * (motherPloidy ~/ 2) + fatherPloidy ~/ 2;
  return TriploidSeedlessResult(
    x: x,
    motherPloidy: motherPloidy,
    fatherPloidy: fatherPloidy,
    embryoSets: embryoSets,
    endospermSets: endospermSets,
    fruitSets: motherPloidy,
    embryoChromosomes: embryoSets * x,
    sterility: '三倍体($embryoSets 组)减数分裂时同源染色体联会紊乱，'
        '几乎不能形成正常配子 → 高度不育 → 无子',
    pollenRole: '二倍体花粉只刺激子房壁发育成果实（提供生长素），'
        '不参与受精——故仍需每年制种',
  );
}
