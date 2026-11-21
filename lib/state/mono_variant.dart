// mono_variant.dart —— v2.19.65：复习会话「练道变式」的**纯函数**内核
// （创新提案 #2 的克制首刀，mono 限定）。
//
// ## 这一刀做什么
// 复习会话揭示区给 mono 错题一枚「练道变式」：从**已存错题**的溯源参数
// （`srcModule == 'cross_mono'` + `srcParams['p1'/'p2']`）**确定性**地推出一道
// 同族变式（换一个亲本的大小写），答案**当场用引擎算**，绝不由 AI 生成。
// 学生点一次 ⇒ 变式入库 ⇒ 今晚待复习里就有这道变式（复用既有复习闭环）。
//
// ## ⛔ 本刀**不做**（留给后续版本，别顺手加）
//   · 测交变式（不另走 `CrossEngine.testcross`；测交条目当作普通杂交变式处
//     理——它的 `srcParams` 是 p1 / `'${rec}${rec}'` 两字母基因型，本文件的
//     通用规则即可覆盖，⛔ 不为它单开一条「× 隐性纯合」的变式路径）；
//   · 多基因（双基因 / 三对基因）变式——只认 2 字母单基因基因型；
//   · 变式乱序 / 随机化（`⛔ 不许随机`：同一错题每次生成的变式**逐字相同**，
//     判据是 [monoVariantOf] 对 `e.id` 的稳定 hash——见 [_stableHash]）；
//   · AI 自动生成未校验答案（答案**只**能来自引擎；AI 包装题面是 v2 方向，
//     见 `mistake_book_page.dart` 的 `_addVariantOfCurrent` 头注）。
//
// ## 为什么答案必须过引擎
// 学生把变式存进错题本后，它会和手存的题走**同一条**复习链路——错一个答案
// 就是错一个知识点。`singleGeneCross` 是本仓遗传计算的唯一真接口（9331 /
// 单基因 / 测交诸页全走它），这里直接调**同一个类**，⛔ 不复制任何比例推
// 导逻辑（复制一份 = 两套口径迟早分叉）。

import '../engine/cross_engine.dart';
import 'mistake_book.dart';

/// 单基因杂交错题的**来源模块** id（与 `mono_cross_widget.dart` 存题时写进
/// `srcModule` 的那个字面量同源）。⛔ 这是本仓 `cross_mono` 的**唯一常量定义**
/// 处——写点 / 判点都引用它，别再各写一份字面量。
const String kMonoVariantSrcModule = 'cross_mono';

/// 基因型判据：两个字母（大小写均可）。**逐字照抄** `mono_cross_widget.dart`
/// 的 `_monoSrcParams` 判据 `^[A-Za-z]{2}$`——它同时是回程 `_applyMonoFill`
/// 的准入线：参数过不了这道门，回程就填不进计算器，错题本里会多一枚点不动
/// 的死按钮（比不生成变式更糟）。两处判据一旦分叉，生成出「存得进、回不去」
/// 的变式，正是这条线要防的事故。
final RegExp _kGenotype2 = RegExp(r'^[A-Za-z]{2}$');

/// 一道变式（纯数据，供 UI 入库 + 守卫逐字比对）。
class MonoVariant {
  /// 变式亲本 1 的基因型（已换过大小写）。
  final String parent1;

  /// 变式亲本 2 的基因型。
  final String parent2;

  /// 题干（点名亲本，字母用**变式后**的）。
  final String stem;

  /// 引擎算出的 F₂ 表型比文本（如 `3:1` / `1:1`），作 `correctAnswer`。
  final String answer;

  const MonoVariant({
    required this.parent1,
    required this.parent2,
    required this.stem,
    required this.answer,
  });
}

/// 从一条错题推它的变式；不是 mono 杂交题 / 参数非法 ⇒ null（调用方据此
/// 一个像素都不加）。
///
/// 确定性来源是 `e.id` 的稳定 hash（[ _stableHash]）：同一错题每次得到**同一
/// 条**变式；不同错题先从哪个亲本下手会被 hash 轮转（见下），但**绝不随机**。
MonoVariant? monoVariantOf(MistakeEntry e) {
  // 门①：只认单基因杂交的存题口径。
  if (e.srcModule != kMonoVariantSrcModule) return null;
  final params = e.srcParams;
  if (params == null) return null;
  final p1 = (params['p1'] ?? '').trim();
  final p2 = (params['p2'] ?? '').trim();
  // 门②：两个亲本都必须是 2 字母基因型（同 `_monoSrcParams` 口径）。
  if (!_kGenotype2.hasMatch(p1) || !_kGenotype2.hasMatch(p2)) return null;

  // 变式候选（按规格优先级：**先**动 p1 首字母大小写，**再**动 p2 首字母）。
  // 「从 e.id 的 hash 选」= 用 id 的稳定 hash 轮转起点：让不同错题先动哪个亲
  // 本不同（同一题始终一致），而候选队列本身仍以 p1 为先。
  final candidates = <List<String>>[
    [_flipFirstCase(p1), p2], // 优先：p1 首字母大小写翻转（A↔a）
    [p1, _flipFirstCase(p2)], // 次选：p2 首字母大小写翻转
  ];
  final start = _stableHash(e.id) % candidates.length;
  for (var k = 0; k < candidates.length; k++) {
    final c = candidates[(start + k) % candidates.length];
    // 「翻转后与原题等价」= 翻转成了空操作（新亲本对与原来逐字相同）⇒ 换下一
    // 个候选；两个都等价 ⇒ 无变式（null）。
    // ⚠️ 在 `^[A-Za-z]{2}$` 门下，首字母大小写翻转把 AA/aA/Aa/aa 四态互转、
    // 必定改串 ⇒ 对合法输入这一判据是**总函数兜底**（守卫 V4 期望的 null 来自
    // 上面两道门）；放宽基因型或将来加入别种变式时它才真正生效，先写死在这里
    // 省得那时漏判。
    if (c[0] == p1 && c[1] == p2) continue;
    return _build(c[0], c[1]);
  }
  return null;
}

/// 组一道变式：定显/隐字母 → 喂**同一个**引擎 → 取表型比文本。
MonoVariant _build(String vp1, String vp2) {
  final dom = _dominantAlleleOf(vp1, vp2);
  final rec = dom.toLowerCase();
  final r = CrossEngine()
      .singleGeneCross(vp1, vp2, dominant: dom, recessive: rec);
  // 表型比文本：与 `mono_cross_widget.dart` 的结果区**同一算法**——按引擎返回
  // 顺序取各表型的份数，gcd 约分后 `:` 连接。⛔ 不另立一套比例拼法。
  final counts = r.phenotypeRatios.map((e) => e.count).toList();
  final g = counts.fold<int>(0, (a, b) => a == 0 ? b : _gcd(a, b));
  final ratio =
      g > 1 ? counts.map((c) => c ~/ g).join(':') : counts.join(':');
  return MonoVariant(
    parent1: vp1,
    parent2: vp2,
    stem: '亲本 $vp1 × $vp2 杂交，F₂ 表型比是？',
    answer: ratio,
  );
}

/// 翻转 2 字母基因型**首字母**的大小写（`AA` → `aA`、`Aa` → `aa`、
/// `aA` → `AA`、`aa` → `Aa`）。四种单基因基因型互不相同 ⇒ 翻转必得一道新题。
String _flipFirstCase(String g) {
  final c = g[0];
  final flipped = c == c.toUpperCase() ? c.toLowerCase() : c.toUpperCase();
  return flipped + g.substring(1);
}

/// 从变式两亲本里定「显性等位基因字母」：取扫描到的第一个大写字母；两亲本
/// 都是小写（如 `aa × aa`）时回落到第一个字母的大写形。本仓单基因题的亲本
/// 共用同一字母基（`Aa`/`AA`/`aa`），故这是一对字母的唯一解。
String _dominantAlleleOf(String a, String b) {
  for (final s in [a, b]) {
    for (final ch in s.split('')) {
      if (ch == ch.toUpperCase() && ch != ch.toLowerCase()) return ch;
    }
  }
  return a[0].toUpperCase();
}

/// 稳定 hash（FNV-1a 32 位）：只依赖字符码点 ⇒ 跨进程 / 跨平台**恒定**。
/// ⛔ 不用 `String.hashCode`——本函数是「同一错题每次同一变式」的**唯一**
/// 确定性来源，不能赌某个实现的抗随机化保证。
int _stableHash(String s) {
  var h = 0x811c9dc5;
  for (final c in s.codeUnits) {
    h ^= c;
    h = (h * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

/// 最大公约数（比例约分用；`mono_cross_widget.dart` 同款语义）。
int _gcd(int a, int b) {
  var x = a.abs();
  var y = b.abs();
  while (y != 0) {
    final t = y;
    y = x % y;
    x = t;
  }
  return x;
}
