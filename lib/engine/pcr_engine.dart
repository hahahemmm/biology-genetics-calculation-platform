// pcr_engine.dart —— 基因工程·PCR 扩增与琼脂糖凝胶电泳示意（纯 Dart）
//
// 课标依据：教育部《普通高中生物学课程标准（2017 年版 2020 年修订）》
// 把 **PCR** 与**电泳**列为基因工程的基本操作 ⇒ 本切片只讲这条链：
// 模板 + 一对引物 → 结合区 → 扩增子 → 循环数与拷贝数 → 凝胶上的条带位置。
//
// ⛔ 这是**教学简化模型**，不是引物设计工具（屏上原话见
// `pages/widgets/pcr_lab.dart` 的 kPcrDisclaimer）：
//   · 模板只输入**顶链 5′→3′**（与限制酶切同一口径，复用
//     [normalizeDnaSequence] 清洗；底链不单独输入）；
//   · 引物按**完全互补**配对：正向引物与顶链某段**完全相同**；反向引物
//     按 5′→3′ 输入，它的**反向互补**才是顶链上的结合区；
//   · 每条引物在模板上必须**唯一**匹配（0 处 / 多处都是错，⛔ 不静默取
//     第一个匹配——那会把「引物对设计错了」伪装成「扩增成功」）；
//   · 拷贝数按**理想 2ⁿ** 计（0 次循环 = 1 份），不评估扩增效率、平台期；
//   · 不评估 GC 含量 / 退火温度 / 二聚体 / 非特异扩增。
//
// 位置口径（本文件唯一真相，屏上与测试都按它读）：一律 **1-based**，
// 「第 start 位」= 第几个碱基（从 1 数）。扩增子顶链 = 顶链上
// [forwardBinding.start] 到 [reverseBinding.end]（含两端）这一段。

import 'dart:math' as math;

import 'restriction_engine.dart'
    show normalizeDnaSequence, reverseComplementDna;

/// 引物长度的教学允许范围（nt）。中学例题里的引物多为 18–25 nt，
/// 这里放宽到 [kPcrMinPrimerLength]–[kPcrMaxPrimerLength]，
/// ⛔ 屏上必须写明范围——学生填 40 nt 时要知道为什么被拒。
const int kPcrMinPrimerLength = 10;
const int kPcrMaxPrimerLength = 30;

/// 循环数的教学允许范围（0 次 = 不扩增，仍是 1 份模板）。
const int kPcrMinCycles = 0;
const int kPcrMaxCycles = 30;

/// 理想 PCR 产物份数：`N = N₀ × 2ⁿ`。
///
/// [initialTemplates] 是起始目标 DNA 分子份数，[cycles] 是循环数。
/// 这是假设每个目标分子每轮都加倍的**教学理想模型**，不是实际产量、
/// 浓度、荧光或条带亮度预测。用 [BigInt] 保持大整数精确。
BigInt pcrIdealProductCount({int initialTemplates = 1, required int cycles}) {
  if (initialTemplates <= 0) {
    throw ArgumentError('初始模板份数必须是正整数（现在是 $initialTemplates）');
  }
  if (cycles < kPcrMinCycles || cycles > kPcrMaxCycles) {
    throw ArgumentError('循环数应在 $kPcrMinCycles–$kPcrMaxCycles 之间（现在是 $cycles）');
  }
  return BigInt.from(initialTemplates) * BigInt.two.pow(cycles);
}

/// 恒定效率假设下的 PCR 产物份数：`N = N₀ × (1 + E)ⁿ`。
///
/// [efficiency] 是每轮效率 E，取值 0–1：100% 表示每轮加倍，90% 表示
/// 每轮变为 1.9 倍。这只是与理想模型对照的假设模型，不模拟效率变化、
/// 平台期或真实终点产量。
double pcrConstantEfficiencyProduct({
  int initialTemplates = 1,
  required int cycles,
  required double efficiency,
}) {
  if (initialTemplates <= 0) {
    throw ArgumentError('初始模板份数必须是正整数（现在是 $initialTemplates）');
  }
  if (cycles < kPcrMinCycles || cycles > kPcrMaxCycles) {
    throw ArgumentError('循环数应在 $kPcrMinCycles–$kPcrMaxCycles 之间（现在是 $cycles）');
  }
  if (!efficiency.isFinite || efficiency < 0 || efficiency > 1) {
    throw ArgumentError('每轮效率必须是 0–1 之间的有限数（现在是 $efficiency）');
  }
  return initialTemplates * math.pow(1 + efficiency, cycles).toDouble();
}

/// 凝胶 marker 的分档（bp，从大到小）——**分档示意**，不是真实分子量标准。
///
/// 选值覆盖中学例题常见的几十到一千 bp；位置按对数换算（见
/// [gelPositionFor]），短片段迁移更远。
const List<int> kGelMarkerBps = <int>[1000, 700, 500, 300, 200, 100, 50];

/// 各档在凝胶上的相对位置：0 = 加样孔一侧（上端），1 = 迁移最远端（下端）。
///
/// 口径：**对数**换算——`pos = (log(max) − log(bp)) / (log(max) − log(min))`，
/// 再夹到 0..1。⇒ ① 短片段 pos 更大（更靠下，迁移更远）；
/// ② 等长必然等距（同一 bp 只有唯一 pos，不做回归、不做亮度/浓度换算）。
///
/// 抛 [ArgumentError]（公开 API 不能把 NaN / log(0) 漏到屏上）：
/// 片段长度 ≤ 0、marker 分档为空、marker 里出现非正数。
/// ⚠️ marker 只有一档时跨度 = 0，全部长度都落在 0（等价于「只有一个参照点」），
/// 这是**合法**输入，不报错。
double gelPositionFor(int bp, {List<int> markerBps = kGelMarkerBps}) {
  _checkGelInputs(bp, markerBps);
  final hi = markerBps.reduce(math.max);
  final lo = markerBps.reduce(math.min);
  final span = math.log(hi.toDouble()) - math.log(lo.toDouble());
  if (span <= 0) return 0;
  final pos = (math.log(hi.toDouble()) - math.log(bp.toDouble())) / span;
  return pos.clamp(0.0, 1.0).toDouble();
}

/// 该长度是否落在 marker 的分档范围内（超出只会被夹到端点，屏上要说明）。
///
/// 入参校验与 [gelPositionFor] 同口径（长度 ≤ 0、marker 空、marker 含非正数
/// 一律抛 [ArgumentError]）。
bool gelInMarkerRange(int bp, {List<int> markerBps = kGelMarkerBps}) {
  _checkGelInputs(bp, markerBps);
  return bp <= markerBps.reduce(math.max) && bp >= markerBps.reduce(math.min);
}

/// 凝胶示意的入参守卫：⛔ 不许让 log(0)/NaN 或空的 reduce 冒到 UI 层。
void _checkGelInputs(int bp, List<int> markerBps) {
  if (bp <= 0) {
    throw ArgumentError('片段长度必须是正整数 bp（收到 $bp）');
  }
  if (markerBps.isEmpty) {
    throw ArgumentError('marker 分档不能为空：凝胶示意至少要有一档长度');
  }
  if (markerBps.any((m) => m <= 0)) {
    throw ArgumentError('marker 分档必须是正整数 bp：分档里出现了非正数（${markerBps.join('、')}）');
  }
}

/// 一条引物在**模板顶链**上的结合区（1-based，含两端）。
class PcrBinding {
  const PcrBinding({
    required this.start,
    required this.end,
    required this.sequence,
  });

  /// 结合区首碱基的 1-based 位置。
  final int start;

  /// 结合区末碱基的 1-based 位置。
  final int end;

  /// 结合区在**顶链**上的实际序列（反向引物那条也按顶链方向写）。
  final String sequence;

  /// 结合区长度（nt）。
  int get length => end - start + 1;

  /// 如「第 4–23 位」。
  String get rangeText => '第 $start–$end 位';

  @override
  String toString() => '$rangeText（$length nt）';
}

/// 一次 PCR 的完整结果（教学简化模型）。
class PcrResult {
  PcrResult({
    required this.template,
    required this.forwardPrimer,
    required this.reversePrimer,
    required this.forwardBinding,
    required this.reverseBinding,
    required this.amplicon,
    required this.cycles,
  });

  /// 清洗后的模板顶链（大写、无空白）。
  final String template;

  /// 正向引物（清洗后，5′→3′；与顶链某段完全相同）。
  final String forwardPrimer;

  /// 反向引物（清洗后，5′→3′；其反向互补 = 顶链上的反向结合区）。
  final String reversePrimer;

  /// 正向引物结合区（顶链）。
  final PcrBinding forwardBinding;

  /// 反向引物结合区（顶链；与反向引物互为反向互补）。
  final PcrBinding reverseBinding;

  /// 扩增子**顶链**序列（从正向结合区起点到反向结合区终点，含两端）。
  final String amplicon;

  /// 循环数（0..30）。
  final int cycles;

  /// 产物起点（1-based，= 正向结合区起点）。
  int get productStart => forwardBinding.start;

  /// 产物终点（1-based，= 反向结合区终点）。
  int get productEnd => reverseBinding.end;

  /// 产物长度（bp）——直接取序列长度，⛔ 不另算一遍再与它对账。
  int get ampliconLength => amplicon.length;

  /// 如「第 4–67 位」。
  String get productRangeText => '第 $productStart–$productEnd 位';

  /// 长度守恒（自检，不变量）：区间跨度必须是产物长度。
  bool get lengthConserved => ampliconLength == productEnd - productStart + 1;

  /// 单份初始模板的理想拷贝数 = 2ⁿ（0 次 = 1 份），与理论扩增卡共用计算真源。
  BigInt get idealCopies => pcrIdealProductCount(cycles: cycles);

  /// 屏上一句话结论（⛔ 不写星号，裸 Text 不解析 markdown）。
  String get summary =>
      '模板 ${template.length} bp；正向结合区 ${forwardBinding.rangeText}、'
      '反向结合区 ${reverseBinding.rangeText}；'
      '扩增子 $productRangeText = $ampliconLength bp；'
      '循环 $cycles 次 ⇒ 理想拷贝数 $idealCopies 份';

  @override
  String toString() => 'PCR $ampliconLength bp / $productRangeText / n=$cycles';
}

/// 清洗单条引物：去空白 → 转大写 → 只接受 A/T/C/G → 长度在教学范围内。
///
/// 抛 [ArgumentError]（文案直接上屏，[label] 决定是哪一条引物）：
///   · 清洗后为空；· 出现 A/T/C/G 以外的字符；· 长度超出
///   [kPcrMinPrimerLength]–[kPcrMaxPrimerLength]。
String normalizePrimer(String raw, {required String label}) {
  final out = StringBuffer();
  final upper = raw.toUpperCase();
  for (var i = 0; i < upper.length; i++) {
    final ch = upper[i];
    if (ch == ' ' ||
        ch == '\t' ||
        ch == '\n' ||
        ch == '\r' ||
        ch == '\u3000' ||
        ch == '\u00A0') {
      continue;
    }
    if (ch != 'A' && ch != 'T' && ch != 'C' && ch != 'G') {
      throw ArgumentError(
        '$label只能含 A、T、C、G 四种碱基：第 ${out.length + 1} 个碱基位置出现了「$ch」',
      );
    }
    out.write(ch);
  }
  final seq = out.toString();
  if (seq.isEmpty) {
    throw ArgumentError('请输入$label（5′→3′）');
  }
  if (seq.length < kPcrMinPrimerLength || seq.length > kPcrMaxPrimerLength) {
    throw ArgumentError(
      '$label长度 ${seq.length} nt 超出教学范围'
      '（$kPcrMinPrimerLength–$kPcrMaxPrimerLength nt）',
    );
  }
  return seq;
}

/// [pattern] 在 [sequence] 上的全部起点（0-based；重叠也算，逐位推进）。
List<int> _allStarts(String sequence, String pattern) {
  final starts = <int>[];
  if (pattern.isEmpty) return starts;
  for (var i = 0; i + pattern.length <= sequence.length; i++) {
    if (sequence.startsWith(pattern, i)) starts.add(i);
  }
  return starts;
}

/// 「第 4、48 位」式的位置清单（0-based 入参，1-based 出参）。
String _startsText(List<int> starts) =>
    '第 ${starts.map((s) => s + 1).join('、')} 位';

/// 解析一条引物的结合区。
///
/// ⛔ 两条匹配路径必须分开判断（正向看「引物本身」，反向看「引物反向
/// 互补」），否则「正向引物写成底链方向」会被反向路径悄悄认领，
/// 两条路径的匹配就混成一条，学生永远看不到「方向错了」这句提示。
PcrBinding _resolveBinding({
  required String template,
  required String primer,
  required String label,
  required bool forward,
}) {
  final rc = reverseComplementDna(primer);
  final direct = _allStarts(template, primer);
  // 正向：引物本身 = 顶链片段；反向：引物的反向互补 = 顶链片段。
  final wanted = forward ? direct : _allStarts(template, rc);
  final other = forward ? _allStarts(template, rc) : direct;

  if (wanted.isEmpty) {
    if (other.length == 1) {
      // 另一条路径恰好唯一匹配 ⇒ 100% 是方向写反了（不是「没匹配」）。
      throw ArgumentError(
        forward
            ? '$label方向写反了：给出的序列与顶链不匹配，但它的反向互补在模板'
                  '${_startsText(other)}有唯一匹配 ⇒ 这说明你写的是底链方向。'
                  '正向引物要与模板顶链完全相同（5′→3′）。'
            : '$label方向写反了：给出的序列本身在模板${_startsText(other)}有唯一匹配，'
                  '但反向引物要按 5′→3′ 书写——它与结合区互为反向互补，'
                  '引擎给它的反向互补找位置。',
      );
    }
    if (other.length > 1) {
      throw ArgumentError(
        '$label在模板上没有匹配，但它的反向互补出现了 '
        '${other.length} 次（${_startsText(other)}）⇒ 方向存疑且不唯一，'
        '请换一段只出现一次的序列。',
      );
    }
    throw ArgumentError(
      forward
          ? '$label在模板上没有匹配：正向引物必须与模板顶链某一段完全相同'
                '（5′→3′），请检查是否抄错碱基。'
          : '$label在模板上没有匹配：反向引物的反向互补必须与模板顶链某一段完全相同，'
                '请检查是否抄错碱基或方向。',
    );
  }
  if (wanted.length > 1) {
    throw ArgumentError(
      '$label在模板上出现了 ${wanted.length} 次'
      '（${_startsText(wanted)}），无法确定唯一结合位点：'
      '教学模型要求每条引物只结合一处，请换一段唯一的序列。',
    );
  }
  final start0 = wanted.single;
  return PcrBinding(
    start: start0 + 1,
    end: start0 + primer.length,
    sequence: template.substring(start0, start0 + primer.length),
  );
}

/// 教学简化 PCR：模板顶链 + 一对引物 + 循环数 ⇒ 结合区 / 扩增子 / 拷贝数。
///
/// 抛 [ArgumentError]（文案直接上屏）：模板非法（见 [normalizeDnaSequence]）、
/// 引物非法（见 [normalizePrimer]）、引物 0 处或多处匹配、方向写反、
/// 两条引物结合区重叠或反向结合区不在下游、循环数越界。
PcrResult pcrAmplify({
  required String template,
  required String forwardPrimer,
  required String reversePrimer,
  int cycles = 25,
}) {
  if (cycles < kPcrMinCycles || cycles > kPcrMaxCycles) {
    throw ArgumentError('循环数应在 $kPcrMinCycles–$kPcrMaxCycles 之间（现在是 $cycles）');
  }
  final seq = normalizeDnaSequence(template);
  final fwd = normalizePrimer(forwardPrimer, label: '正向引物');
  final rev = normalizePrimer(reversePrimer, label: '反向引物');

  final fwdBind = _resolveBinding(
    template: seq,
    primer: fwd,
    label: '正向引物',
    forward: true,
  );
  final revBind = _resolveBinding(
    template: seq,
    primer: rev,
    label: '反向引物',
    forward: false,
  );

  // 方向与重叠：反向结合区必须在正向结合区**下游**，且两段不重叠。
  if (revBind.start <= fwdBind.start) {
    throw ArgumentError(
      '引物对方向不对：反向引物结合区（${revBind.rangeText}）'
      '必须位于正向引物结合区（${fwdBind.rangeText}）的下游，'
      '当前两者相同或反向结合区在上游——请对调两条引物或检查方向。',
    );
  }
  if (revBind.start <= fwdBind.end) {
    throw ArgumentError(
      '两条引物的结合区重叠：正向 ${fwdBind.rangeText}、'
      '反向 ${revBind.rangeText}，无法界定扩增子边界。',
    );
  }

  return PcrResult(
    template: seq,
    forwardPrimer: fwd,
    reversePrimer: rev,
    forwardBinding: fwdBind,
    reverseBinding: revBind,
    // 扩增子顶链：正向结合区起点 → 反向结合区终点（含两端）。
    amplicon: seq.substring(fwdBind.start - 1, revBind.end),
    cycles: cycles,
  );
}
