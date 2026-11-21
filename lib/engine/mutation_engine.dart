// mutation_engine.dart —— 变异引擎（纯 Dart，跨平台，无 Flutter 依赖）
//
// 课标覆盖：必修2《遗传与进化》3.3.1（碱基替换/插入/缺失 → 序列改变）、
// 3.3.2（序列改变 → 蛋白质功能可能改变甚至致命）、3.3.3（诱变因素）、
// 3.3.5（染色体组数判断：等位基因总数取最大值 = 组数）。
// 契约见 docs/PLAN_2.0.md 批次 4：变异模块。

/// 基因突变模拟结果（替换/插入/缺失 → 序列变化 + 受影响密码子对比）。
class MutatedSequence {
  final String original; // 原序列（大写）
  final String mutated; // 突变后序列（大写）
  final String type; // '替换' / '插入' / '缺失'
  final int position; // 突变位置（0 起点）
  final int codonIndex; // 受影响密码子索引（转录框从 0 起，3 碱基/密码子）
  final String originalCodon; // 受影响密码子（原）
  final String mutatedCodon; // 受影响密码子（突变后）
  final bool silent; // 同义突变（原/新密码子相同）
  const MutatedSequence({
    required this.original,
    required this.mutated,
    required this.type,
    required this.position,
    required this.codonIndex,
    required this.originalCodon,
    required this.mutatedCodon,
    required this.silent,
  });
}

/// 诱变因素条目（课标 3.3.3 教学卡用）。
class MutationFactor {
  final String category; // '物理' / '化学' / '生物'
  final String factor; // 诱变因素名
  final String note; // 一句作用说明
  const MutationFactor({
    required this.category,
    required this.factor,
    required this.note,
  });
}

/// 诱变因素（物理 / 化学 / 生物 三大类，供页面分组渲染）。
const List<MutationFactor> mutationFactors = [
  // ── 物理 ──
  MutationFactor(
      category: '物理', factor: 'X 射线', note: '电离辐射，可断裂 DNA 链或改变碱基结构'),
  MutationFactor(
      category: '物理', factor: 'γ 射线', note: '穿透力强，诱导 DNA 损伤（辐射诱变育种常用）'),
  MutationFactor(
      category: '物理', factor: '紫外线', note: '主要引起嘧啶二聚体，造成复制错误'),
  MutationFactor(
      category: '物理', factor: '激光', note: '高能光辐射，可定向诱导基因突变'),
  // ── 化学 ──
  MutationFactor(
      category: '化学', factor: '亚硝酸', note: '使碱基脱氨基，改变配对性质（如 C→U）'),
  MutationFactor(
      category: '化学',
      factor: '碱基类似物',
      note: '如 5-溴尿嘧啶，掺入 DNA 后引起复制配对错误'),
  MutationFactor(
      category: '化学', factor: '烷化剂', note: '如硫酸二乙酯，使碱基烷基化导致错配'),
  MutationFactor(
      category: '化学', factor: '羟胺', note: '修饰碱基结构，改变其配对能力'),
  // ── 生物 ──
  MutationFactor(
      category: '生物', factor: '病毒', note: '某些病毒基因插入宿主基因组，打乱基因结构'),
  MutationFactor(
      category: '生物', factor: '某些细菌', note: '代谢产物或毒素可造成 DNA 损伤'),
];

/// 碱基替换时从 A/T/G/C 中取一个与 [original] 不同的碱基。
/// 显式传入 [requested] 时优先使用（仍保证与原位不同，绝不"无变化"）。
String _pickOtherBase(String original, String? requested) {
  const candidates = ['A', 'T', 'G', 'C'];
  final want = (requested ?? '').trim().toUpperCase();
  if (want.isNotEmpty) {
    if (!candidates.contains(want)) {
      throw ArgumentError('替换碱基只能是 A/T/G/C');
    }
    if (want != original) return want;
  }
  return candidates.firstWhere((c) => c != original);
}

/// 基因突变模拟：碱基替换 / 插入 / 缺失 → 新序列 + 受影响密码子对比。
///
/// - [sequence]：只允许 A/T/G/C（大小写不敏感，输出统一大写）；空或含
///   其它字母抛 [ArgumentError]('序列只能包含 A/T/G/C')。
/// - [type]：'sub'（替换）/ 'ins'（插入）/ 'del'（缺失）。
/// - [position]：sub/del ∈ [0, len)；ins ∈ [0, len]（插入到位置前，可等于
///   len 表示末尾追加）。越界抛 [ArgumentError]('位置越界')。
/// - [newBase]：sub 时替换成该碱基（缺省或与原位相同 → 自动换另一不同
///   碱基，保证发生改变）；ins 时插入该碱基（缺省 'A'）。
/// - 教学简化：密码子框从位置 0 起，每 3 碱基一个；受影响密码子 = 原框内
///   包含 position 的那个（插入/缺失按新序列对应位置取 3 个碱基对比，
///   不计移码后的新框）。silent = 原/新密码子相同。
MutatedSequence mutateSequence({
  required String sequence,
  required String type,
  required int position,
  String? newBase,
}) {
  const valid = ['A', 'T', 'G', 'C'];
  final upper = sequence.trim().toUpperCase();
  if (upper.isEmpty) throw ArgumentError('序列只能包含 A/T/G/C');
  for (final c in upper.split('')) {
    if (!valid.contains(c)) throw ArgumentError('序列只能包含 A/T/G/C');
  }
  if (type != 'sub' && type != 'ins' && type != 'del') {
    throw ArgumentError('突变类型必须是 sub / ins / del');
  }

  final len = upper.length;
  final maxPos = type == 'ins' ? len : len - 1;
  if (position < 0 || position > maxPos) throw ArgumentError('位置越界');

  final String mutated;
  final String typeZh;
  switch (type) {
    case 'sub':
      final base = _pickOtherBase(upper[position], newBase);
      mutated = upper.replaceRange(position, position + 1, base);
      typeZh = '替换';
    case 'ins':
      final base = (newBase ?? 'A').trim().toUpperCase();
      if (!valid.contains(base)) throw ArgumentError('插入碱基只能是 A/T/G/C');
      mutated = upper.replaceRange(position, position, base);
      typeZh = '插入';
    case 'del':
      mutated = upper.replaceRange(position, position + 1, '');
      typeZh = '缺失';
    default:
      throw ArgumentError('突变类型必须是 sub / ins / del');
  }

  // 受影响密码子：原框内包含 position 的那个（clamp 防短序列越界）。
  final codonIndex = position ~/ 3;
  final oStart = (codonIndex * 3).clamp(0, upper.length);
  final oEnd = (codonIndex * 3 + 3).clamp(0, upper.length);
  final originalCodon = upper.substring(oStart, oEnd);
  final mStart = (codonIndex * 3).clamp(0, mutated.length);
  final mEnd = (codonIndex * 3 + 3).clamp(0, mutated.length);
  final mutatedCodon = mutated.substring(mStart, mEnd);

  return MutatedSequence(
    original: upper,
    mutated: mutated,
    type: typeZh,
    position: position,
    codonIndex: codonIndex,
    originalCodon: originalCodon,
    mutatedCodon: mutatedCodon,
    silent: originalCodon == mutatedCodon,
  );
}

/// 染色体组数判断（课标 3.3.5）：
/// 同字母（不分大小写）视为同一基因座，等位基因出现总数最大的基因座
/// 的数目 = 染色体组数。
/// 'Aa'→2，'AaaBbb'→3，'AAAaBBbb'→4，'ABCD'→1，'AAaa'→4。
/// 空或含非字母字符抛 [ArgumentError]。
int chromosomeSets({required String genotype}) {
  final g = genotype.trim();
  if (g.isEmpty) throw ArgumentError('基因型不能为空');
  final counts = <String, int>{};
  for (final c in g.split('')) {
    if (!RegExp(r'[a-zA-Z]').hasMatch(c)) {
      throw ArgumentError('基因型只能包含字母（等位基因用字母表示）');
    }
    final key = c.toLowerCase();
    counts[key] = (counts[key] ?? 0) + 1;
  }
  var maxCount = 0;
  for (final v in counts.values) {
    if (v > maxCount) maxCount = v;
  }
  return maxCount;
}