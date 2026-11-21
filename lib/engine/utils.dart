// engine/utils.dart —— 引擎层公共数学工具（v2.11 M11）
//
// v2.10 之前：`_gcd` 在 5 个文件里各写一份：
//   - lib/engine/fraction.dart:31           — 无 abs() 兜底
//   - lib/engine/genetics_env.dart:240      — 无 abs() 兜底
//   - lib/engine/linkage_engine.dart:91     — 无 abs() 兜底
//   - lib/engine/models.dart:189            — 有 abs() 但无 0 守卫
//   - lib/pages/widgets/mono_cross_widget.dart:287, 391  — 同 models
//
// 行为不一致是隐藏 bug 风险：
// 1. fraction/genetics_env/linkage_engine 三处对负数输入返回负数 gcd
//    （约分时虽 n.abs() 兜底但风格不统一）
// 2. models / mono_cross_widget 两处（带 abs 但无 0 守卫）当 a 和 b
//    都为 0 时返回 0 而非 1，可能导致下游 ratio 整除抛异常
//
// 抽公共 `_gcd` 后用**带 abs() 兜底 + 0 守卫**版本（最严格，行为正确），
// 替换 5 处实现后所有比例约分都走同一逻辑，行为收敛。
//
// 修复效果（2 个隐藏 bug 顺手修）：
// - 负数输入行为统一（abs 兜底）
// - gcd(0, 0) = 1（之前 models/mono_cross_widget 返回 0）
library;

/// 最大公约数（Greatest Common Divisor），欧几里得算法。
///
/// 行为契约（v2.11 统一后）：
/// 1. 对入参 a, b 取绝对值（防御负数输入；与 v2.10 之前
///    models / mono_cross_widget 的本地实现一致）
/// 2. 循环 `a, b = b, a % b`，直到 b == 0
/// 3. a == 0 时返回 1（约定：gcd(0, x) = x，gcd(0, 0) = 1）
///
/// 例子：
/// ```
/// gcd(12, 8) == 4
/// gcd(-12, 8) == 4      // 负数也走 abs 兜底
/// gcd(0, 5) == 5
/// gcd(0, 0) == 1        // 不返 0，避免下游 ratio ~/g 抛 NaN
/// ```
int gcd(int a, int b) {
  a = a.abs();
  b = b.abs();
  while (b != 0) {
    final t = a % b;
    a = b;
    b = t;
  }
  return a == 0 ? 1 : a;
}

/// 最小公倍数（Least Common Multiple）。
///
/// 行为契约：
/// 1. 任意一个参数为 0 返回 0（约定：lcm(0, x) = 0，
///    与 v2.10 之前 genetics_env / linkage_engine 的本地实现一致）
/// 2. 否则 `a ~/ gcd(a, b) * b`（先除后乘避免中间溢出）
///
/// 例子：
/// ```
/// lcm(4, 6) == 12
/// lcm(0, 5) == 0
/// lcm(5, 0) == 0
/// ```
int lcm(int a, int b) {
  if (a == 0 || b == 0) return 0;
  return a ~/ gcd(a, b) * b;
}

/// v2.11 M3：基因型输入校验（公共）。
///
/// 5 个 parseGenotype 实现（genetics_env / genetic_disease_engine /
/// kaoji_calc / sex_linked_engine / pedigree_engine）都有相同的
/// 预校验逻辑：trim + 偶数长度 + 字母 A-Z + 抛出 ArgumentError。
/// 行为契约（v2.11 统一后）：
/// 1. 自动 trim 字符串
/// 2. 空字符串抛 ArgumentError('基因型不能为空')
/// 3. 非纯 A-Z 抛 ArgumentError('仅支持字母 A-Z：$raw')
/// 4. 偶数长度要求由调用方决定（不统一检查，因 sex_linked_engine 用
///    XA Xa 2+1 字符、kaoji_calc 用相邻同字母分组不同长度）
///
/// 返回 trim 后的字符串供调用方继续处理。
String validateGenotypeInput(String raw) {
  final s = raw.trim();
  if (s.isEmpty) {
    throw ArgumentError('基因型不能为空');
  }
  if (!_genotypePattern.hasMatch(s)) {
    throw ArgumentError('仅支持字母 A-Z：$raw');
  }
  return s;
}

/// 基因型字母校验的复用正则（顶层 lazy final，避免每次调用重建）。
final _genotypePattern = RegExp(r'^[A-Za-z]+$');

/// 快速判断字符串是否含 ASCII 大写字母（A-Z）。
///
/// 语义等价于 `s.contains(RegExp('[A-Z]'))`，但零正则零分配——
/// 供引擎热路径（如 crossAuto 的逐基因型表型归并）使用。
bool hasUpperAscii(String s) {
  for (final u in s.codeUnits) {
    if (u >= 0x41 && u <= 0x5A) return true;
  }
  return false;
}
