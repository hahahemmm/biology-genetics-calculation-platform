// restriction_engine.dart —— 基因工程·限制酶切（纯 Dart，确定性计算）
//
// 课标依据：教育部《普通高中生物学课程标准（2017 年版 2020 年修订）》
// 把**限制性内切核酸酶**列为 DNA 重组的基本工具之一 ⇒ 本切片只讲这条链：
// 识别序列 → 切点 → 片段 → 黏性末端。
//
// ⛔ 这是**教学简化模型**，不是实验设计工具（屏上原话见
// `pages/widgets/restriction_lab.dart` 的 kRestrictionDisclaimer）：
//   · 只按**顶链 5′→3′** 扫描。三酶识别序列都是回文序列
//     （`RestrictionEnzyme.isPalindrome` 现算自证，⛔ 不靠注释担保），
//     所以底链读出来的位点与顶链完全一致，扫一条链就是全部信息；
//   · 按**线性** DNA 计：切 n 刀得 n+1 段。环状质粒切 n 刀得 n 段，
//     本模型不涉及（不猜学生手里是质粒还是线性片段）；
//   · 一次一种酶；不做双酶切、不查甲基化保护、不查星号活性；
//   · 「识别序列长度」（6 bp）与「切后片段数」是两个不同的量——
//     片段数只由位点数决定，⛔ 任何地方不许把 6 读成段数。
//
// 切点约定（本文件唯一口径，屏上与测试都按它读）：
//   start    —— 位点首碱基的 **1-based** 位置（与屏上「第 N 位」一致）
//   end      —— 位点末碱基的 1-based 位置（= start + 位点长 − 1）
//   cutAfter —— 顶链切口竖线**左侧紧邻**碱基的 1-based 位置
//               （切口落在 cutAfter 与 cutAfter+1 之间；EcoRI 的
//                G^AATTC ⇒ cutAfter = start）
//   底链切口在「3′→5′」书写下的第（位点长 − cutOffset）个碱基之后，
//   两条链的错位长度 = 位点长 − 2×cutOffset = 黏性末端突出的碱基数。

/// 一种限制性内切核酸酶（教学三酶）。
class RestrictionEnzyme {
  const RestrictionEnzyme({
    required this.name,
    required this.recognition,
    required this.cutOffset,
    required this.note,
  });

  /// 酶名（屏上标签），如 `EcoRI`。
  final String name;

  /// 顶链 5′→3′ 的识别序列（6 bp 回文）。
  final String recognition;

  /// 顶链切口在识别序列内的位置：切口落在第 [cutOffset] 个碱基**之后**
  /// （EcoRI `G^AATTC` ⇒ 1）。
  final int cutOffset;

  /// 一句教学备忘（屏上一行说明，⛔ 不写来源门牌号之类无法自证的东西）。
  final String note;

  /// 识别序列长度（bp）。⚠️ 这个数**不是**切后片段数。
  int get siteLength => recognition.length;

  /// 切口错位长度 = 黏性末端突出的碱基数（= 位点长 − 2×cutOffset）。
  int get overhangLength => siteLength - 2 * cutOffset;

  /// 切口是否错位（错位 = 黏性末端；本模型三酶都是错位切口）。
  bool get hasStickyEnd => overhangLength > 0;

  /// 黏性末端（5′ 突出）的单链序列，如 EcoRI `AATT`；平末端为空串。
  String get overhang => hasStickyEnd
      ? recognition.substring(cutOffset, cutOffset + overhangLength)
      : '';

  /// 经典顶链记号：EcoRI `G^AATTC`、BamHI `G^GATCC`、HindIII `A^AGCTT`。
  String get cutNotation =>
      '${recognition.substring(0, cutOffset)}^'
      '${recognition.substring(cutOffset)}';

  /// 回文自证：反向互补等于自身（真 ⇒ 只看顶链就够了）。
  bool get isPalindrome => reverseComplementDna(recognition) == recognition;

  /// 黏性末端的人类可读表达。
  String get overhangText => hasStickyEnd
      ? '5′-$overhang 突出 $overhangLength 个碱基（黏性末端）'
      : '平末端';

  @override
  String toString() => '$name（$cutNotation）';
}

/// EcoRI：`G^AATTC`，黏性末端 `AATT`。
const RestrictionEnzyme kEcoRI = RestrictionEnzyme(
  name: 'EcoRI',
  recognition: 'GAATTC',
  cutOffset: 1,
  note: '大肠杆菌来源，最经典的教学酶',
);

/// BamHI：`G^GATCC`，黏性末端 `GATC`。
const RestrictionEnzyme kBamHI = RestrictionEnzyme(
  name: 'BamHI',
  recognition: 'GGATCC',
  cutOffset: 1,
  note: '芽孢杆菌来源，切出 GATC 黏性末端',
);

/// HindIII：`A^AGCTT`，黏性末端 `AGCT`。
const RestrictionEnzyme kHindIII = RestrictionEnzyme(
  name: 'HindIII',
  recognition: 'AAGCTT',
  cutOffset: 1,
  note: '流感嗜血杆菌来源，切出 AGCT 黏性末端',
);

/// 本模型支持的全部酶（顺序即屏上顺序）。
const List<RestrictionEnzyme> kRestrictionEnzymes = <RestrictionEnzyme>[
  kEcoRI,
  kBamHI,
  kHindIII,
];

/// 教学模型的序列上限（超过就不是「黑板上的例题」了，且屏上画不动）。
const int kRestrictionMaxLength = 300;

/// 按名字取酶（大小写不敏感、忽略首尾空白）；不认识的名字返回 null。
RestrictionEnzyme? restrictionEnzymeByName(String name) {
  final key = name.trim().toLowerCase();
  for (final e in kRestrictionEnzymes) {
    if (e.name.toLowerCase() == key) return e;
  }
  return null;
}

/// 顶链的逐位互补链（**同一方向**逐位替换：A↔T、C↔G）。
///
/// 底链按 3′→5′ 书写时正好与顶链同列对齐，故本函数只做替换、不反转；
/// 要拿「反向互补」请用 [reverseComplementDna]。
String complementDna(String sequence) {
  final out = StringBuffer();
  for (var i = 0; i < sequence.length; i++) {
    final ch = sequence[i];
    // 非 A/T/C/G：原样保留（本函数也用于用户输入之外的固定序列）。
    out.write(_complementTable[ch] ?? ch);
  }
  return out.toString();
}

const Map<String, String> _complementTable = <String, String>{
  'A': 'T',
  'T': 'A',
  'C': 'G',
  'G': 'C',
};

/// 反向互补（5′→3′ 顶链 ↔ 5′→3′ 底链）。
String reverseComplementDna(String sequence) =>
    complementDna(sequence).split('').reversed.join();

/// 清洗并校验用户输入：去空白 → 转大写 → 只接受 A/T/C/G。
///
/// 抛 [ArgumentError] 的三种情形（错误文案直接上屏，⛔ 不含星号）：
///   · 清洗后为空；· 出现 A/T/C/G 以外的字符；· 超过 [kRestrictionMaxLength]。
String normalizeDnaSequence(String raw) {
  final out = StringBuffer();
  final upper = raw.toUpperCase();
  for (var i = 0; i < upper.length; i++) {
    final ch = upper[i];
    // 半角/全角空格、制表与换行都当分隔符（老师从文档里粘过来常带它们）。
    if (ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' ||
        ch == '\u3000' || ch == '\u00A0') {
      continue;
    }
    if (ch != 'A' && ch != 'T' && ch != 'C' && ch != 'G') {
      throw ArgumentError(
          '序列只能含 A、T、C、G 四种碱基：第 ${out.length + 1} 个碱基位置出现了「$ch」');
    }
    out.write(ch);
  }
  final seq = out.toString();
  if (seq.isEmpty) {
    throw ArgumentError('请输入 DNA 序列（只能含 A、T、C、G）');
  }
  if (seq.length > kRestrictionMaxLength) {
    throw ArgumentError('序列过长（本教学模型上限 $kRestrictionMaxLength bp）');
  }
  return seq;
}

/// 一个识别位点（1-based，见文件头的切点约定）。
class RestrictionSite {
  const RestrictionSite({required this.enzyme, required this.start});

  final RestrictionEnzyme enzyme;

  /// 位点首碱基的 1-based 位置。
  final int start;

  /// 位点末碱基的 1-based 位置。
  int get end => start + enzyme.siteLength - 1;

  /// 顶链切口左侧紧邻碱基的 1-based 位置。
  int get cutAfter => start + enzyme.cutOffset - 1;

  /// 如「第 3–8 位」。
  String get rangeText => '第 $start–$end 位';

  /// 如「顶链切口在第 3 位与第 4 位之间」。
  String get cutText => '顶链切口在第 $cutAfter 位与第 ${cutAfter + 1} 位之间';

  /// 位点内的经典记号（与位置无关，如 `G^AATTC`）。
  String get notation => enzyme.cutNotation;

  /// 双链示意：上行顶链 5′→3′、下行底链 3′→5′，同列逐位对齐。
  ///
  /// EcoRI 得到：
  /// ```
  /// 5′-G↓AATTC-3′
  /// 3′-CTTAA↑G-5′
  /// ```
  /// 两行的切口竖线错开 [RestrictionEnzyme.overhangLength] 列——那 4 个
  /// 碱基的错位就是黏性末端本身。
  String get doubleStrandSketch {
    final top = enzyme.recognition;
    // 底链按 3′→5′ 书写 = 顶链逐位互补（同列对齐）。
    final bottom = complementDna(top);
    final topLine = _insertMarker(top, enzyme.cutOffset, '↓');
    // 底链的切口在「3′→5′」书写的第（位点长 − cutOffset）个碱基之后。
    final bottomLine =
        _insertMarker(bottom, enzyme.siteLength - enzyme.cutOffset, '↑');
    return '5′-$topLine-3′\n3′-$bottomLine-5′';
  }

  /// 在 [s] 的第 [after] 个字符之后插入 [mark]。
  static String _insertMarker(String s, int after, String mark) =>
      '${s.substring(0, after)}$mark${s.substring(after)}';

  @override
  String toString() => '${enzyme.name}@$rangeText';
}

/// 切出的一段 DNA（线性 DNA，1-based）。
class RestrictionFragment {
  const RestrictionFragment({
    required this.index,
    required this.start,
    required this.end,
    required this.enzyme,
    required this.cutAtLeft,
    required this.cutAtRight,
  });

  /// 片段序号（1-based，自左向右）。
  final int index;
  final int start;
  final int end;
  final RestrictionEnzyme enzyme;

  /// 左端是不是「本次酶切切出来的口」（false = 原序列的末端）。
  final bool cutAtLeft;

  /// 右端是不是「本次酶切切出来的口」。
  final bool cutAtRight;

  /// 片段长度（bp）。
  int get length => end - start + 1;

  String get rangeText => '第 $start–$end 位';

  /// 两端的人类可读表达（区分「酶切末端」与「原始末端」）。
  String get endsText {
    final sticky = '5′-${enzyme.overhang} 黏性末端';
    if (cutAtLeft && cutAtRight) return '两端都是切口（各为 $sticky）';
    if (cutAtLeft) return '左端是切口（$sticky），右端是原序列末端（未切）';
    if (cutAtRight) return '左端是原序列末端（未切），右端是切口（$sticky）';
    return '未被切开：两端都是原序列末端';
  }

  @override
  String toString() => '#$index $rangeText = $length bp';
}

/// 一次单酶切的完整结果。
class RestrictionDigest {
  RestrictionDigest({
    required this.enzyme,
    required this.sequence,
    required this.sites,
  }) : fragments = _buildFragments(enzyme, sequence, sites);

  final RestrictionEnzyme enzyme;

  /// 清洗后的顶链序列（大写、无空白）。
  final String sequence;

  /// 识别位点（按位置升序）。
  final List<RestrictionSite> sites;

  /// 切出的片段（按位置升序；无位点时是唯一的一整段）。
  final List<RestrictionFragment> fragments;

  static List<RestrictionFragment> _buildFragments(
    RestrictionEnzyme enzyme,
    String sequence,
    List<RestrictionSite> sites,
  ) {
    // 切口把序列切成「左界 0 / 各切口 / 右界 length」这些边界之间的段。
    final bounds = <int>[0, for (final s in sites) s.cutAfter, sequence.length];
    return <RestrictionFragment>[
      for (var i = 0; i < bounds.length - 1; i++)
        RestrictionFragment(
          index: i + 1,
          start: bounds[i] + 1,
          end: bounds[i + 1],
          enzyme: enzyme,
          // 左界 0 / 右界 length 不是酶切产生的口。
          cutAtLeft: i > 0,
          cutAtRight: i < sites.length,
        ),
    ];
  }

  int get sequenceLength => sequence.length;

  int get siteCount => sites.length;

  /// 切后片段数（线性 DNA：位点数 + 1）。
  int get fragmentCount => fragments.length;

  bool get hasSite => sites.isNotEmpty;

  /// 序列本身短于识别序列 ⇒ 不可能有位点（这是**合法输入**，只是没结果）。
  bool get shorterThanSite => sequenceLength < enzyme.siteLength;

  List<int> get fragmentLengths =>
      <int>[for (final f in fragments) f.length];

  /// 如 `3 + 9 + 7`。
  String get lengthsText => fragmentLengths.join(' + ');

  int get fragmentLengthSum =>
      fragments.fold<int>(0, (sum, f) => sum + f.length);

  /// 片段长度守恒：各段之和必须等于原序列长度（自检，不变量）。
  bool get lengthConserved => fragmentLengthSum == sequenceLength;

  /// 屏上一句话结论（⛔ 不写星号，裸 Text 不解析 markdown）。
  String get summary {
    final head = '识别序列 ${enzyme.recognition}'
        '（${enzyme.siteLength} bp，回文）';
    if (!hasSite) {
      if (shorterThanSite) {
        return '$head；序列只有 $sequenceLength bp，短于识别序列，'
            '不可能有该位点，因此不切开。';
      }
      return '$head；没有该位点，因此线性 DNA 不被切开，'
          '仍是 1 段（$sequenceLength bp）。';
    }
    return '$head；位点 $siteCount 个，线性 DNA 切成 $fragmentCount 段'
        '（$lengthsText = $fragmentLengthSum bp）。'
        '注意：识别序列长度 ${enzyme.siteLength} bp 与切后片段数 '
        '$fragmentCount 个是两个量——片段数只由位点数决定'
        '（切 n 刀得 n+1 段）。';
  }

  @override
  String toString() =>
      '${enzyme.name}: $siteCount 位点 / $fragmentCount 段 / '
      '$lengthsText（$fragmentLengthSum bp）';
}

/// 找出某个酶在 [sequence] 上的全部位点（1-based）。
///
/// ⚠️ 扫描步长按 1 推进即可：三酶的 6 bp 回文序列**不可能自我重叠**
/// （首字母 ≠ 末字母 ⇒ 任何错位都要求前缀等于后缀，例如 EcoRI 的 `G` 与
/// `C`），所以「重叠位点被漏掉」这件事在本模型不会发生。
List<RestrictionSite> findRestrictionSites(
  String sequence,
  RestrictionEnzyme enzyme,
) {
  final sites = <RestrictionSite>[];
  final site = enzyme.recognition;
  for (var i = 0; i + site.length <= sequence.length; i++) {
    if (sequence.startsWith(site, i)) {
      sites.add(RestrictionSite(enzyme: enzyme, start: i + 1));
    }
  }
  return sites;
}

/// 单酶切：清洗输入 → 找位点 → 切片段。
///
/// 输入非法抛 [ArgumentError]；**没有位点不是错误**——返回
/// `fragmentCount == 1` 的结果（屏上照常展示「没被切开」）。
RestrictionDigest restrictionDigest({
  required String sequence,
  required RestrictionEnzyme enzyme,
}) {
  final seq = normalizeDnaSequence(sequence);
  return RestrictionDigest(
    enzyme: enzyme,
    sequence: seq,
    sites: findRestrictionSites(seq, enzyme),
  );
}

/// 同上，按酶名取酶（不认识的酶名抛 [ArgumentError]，点名现有三酶）。
RestrictionDigest restrictionDigestByName({
  required String sequence,
  required String enzymeName,
}) {
  final enzyme = restrictionEnzymeByName(enzymeName);
  if (enzyme == null) {
    final names = kRestrictionEnzymes.map((e) => e.name).join(' / ');
    throw ArgumentError('未知的限制酶「$enzymeName」（本模型只有 $names）');
  }
  return restrictionDigest(sequence: sequence, enzyme: enzyme);
}
