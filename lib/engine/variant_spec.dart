// variant_spec.dart —— 9331 及变式常量表（v2.11 M11b → v2.12 扩 8 个）
//
// v2.10 之前：9331 及变式的 mode 标识符（'9331' / '9_7' / '9_3_4' / '15_1' /
// '1_4_6_4_1'）散落在 5 个文件：
//   - lib/engine/kaoji_calc.dart:91-119      variantRatio switch + knownVariants 列表
//   - lib/engine/kaoji_calc.dart:240,243     variantName 推断（'标准 9:3:3:1'）
//   - lib/pages/cross_calculator_page.dart:752-761  _variantName switch（UI 显示名）
//   - lib/engine/genetics_env.dart:260-292   phenotypeRuleForVariant switch
//   - lib/engine/kaoji_calc.dart:115-119     knownVariants 静态列表
//
// v2.11 M11b：抽公共后集中到本文件的 [VariantSpec] 类（5 个变式）。
// v2.12：扩到 8 个，补「显性上位 12:3:1 / 抑制 13:3 / 积加 9:6:1」三式
// （课标 KD-05/07/09/11/12 五考点变式，原在 genetics_env 仍用字面量）。
// 调用方按 mode 查 ratio / 查显示名。其他命名空间（knowledge_graph tag /
// error_diagnosis 显示比值列表）不在本次范围。
library;

/// 9331 及变式常量表（集中 mode 标识符 + 比例 + 显示名）。
class VariantSpec {
  VariantSpec._(); // 防止实例化（纯静态工具类）

  // ───────── 变式 mode 标识符（v2.12 扩到 8 个）─────────
  // 这些是「变式名」的字符串字面量，原本散落在 kaoji_calc / genetics_env
  // / cross_calculator_page 等多处；现在集中到此处做 single source of truth。
  // v2.12 新增 12_3_1 / 13_3 / 9_6_1 三式（v2.11 时 genetics_env 用字面量）。

  /// 标准 9:3:3:1（双杂合独立分配，无互作）
  static const String standard9331 = '9331';

  /// 9:7 互补作用（双显 vs 其余）
  static const String complement97 = '9_7';

  /// 9:3:4 隐性上位（一对隐性掩盖另一对）
  static const String epistasis934 = '9_3_4';

  /// 15:1 显性叠加（任一显性 vs 双隐）
  static const String dominant151 = '15_1';

  /// 1:4:6:4:1 数量性状（按显性基因数 0..4 分档）
  static const String quantitative14641 = '1_4_6_4_1';

  /// 12:3:1 显性上位（v2.12 新增，课标 KD-05/11）
  /// A 显性上位：含 A 等位基因（含 AaBB/AABb/AABB/AaBb）的全部归为
  /// 一类，B 单独显性另算，aabb 单独。位点字母约定 A 为上位基因。
  static const String dominantEpistasis1231 = '12_3_1';

  /// 13:3 抑制作用（v2.12 新增，课标 KD-07）
  /// B 显性抑制 A：含 B 等位（无论 A 是否存在）与 aabb 合并归为「被抑制」
  /// 一类（9+3+1=13），仅 A_bb（无 B 抑制）时 A 表达（3）。
  static const String inhibition13_3 = '13_3';

  /// 9:6:1 积加作用（v2.12 新增，课标 KD-09）
  /// 双显 9 / 单显合并 6（A_bb + aaB_）/ 双隐 1。
  static const String additive961 = '9_6_1';

  /// 全部 mode 列表（供 UI 展示 / 遍历用）。
  /// 原 kaoji_calc.dart:114-120 KaojiCalc.knownVariants 静态字段；
  /// v2.12 扩到 8 个（含课标 KD-05/07/09/11/12 五考点变式）。
  static const List<String> all = <String>[
    standard9331,
    complement97,
    epistasis934,
    dominant151,
    quantitative14641,
    dominantEpistasis1231,
    inhibition13_3,
    additive961,
  ];

  // ───────── 比例（已约分）─────────
  // 原 kaoji_calc.dart:91-103 variantRatio switch 各 case 的 Ratio(...) 值。
  // 现在用 List<int> 表达，调用方用 Ratio(list) 包装。
  //（List<int> 而非 Ratio 本身是为了避免与 models.dart 形成循环依赖——
  // variant_spec.dart 被 models.dart 不需要，但被 kaoji_calc / genetics_env
  // 等需要 ratio 的文件 import；这些文件自身已 import models.dart。）

  static const List<int> ratioStandard = <int>[9, 3, 3, 1];
  static const List<int> ratioComplement = <int>[9, 7];
  static const List<int> ratioEpistasis = <int>[9, 3, 4];
  static const List<int> ratioDominant = <int>[15, 1];
  static const List<int> ratioQuantitative = <int>[1, 4, 6, 4, 1];
  // v2.12 新增三变式比例
  static const List<int> ratioDominantEpistasis = <int>[12, 3, 1];
  static const List<int> ratioInhibition = <int>[13, 3];
  static const List<int> ratioAdditive = <int>[9, 6, 1];

  /// 根据 [mode] 查比例（已约分）。未知 mode 返回标准 9:3:3:1
  ///（保留 v2.10 之前 kaoji_calc.dart:103 default 行为）。
  static List<int> ratioFor(String mode) {
    switch (mode) {
      case standard9331:
        return ratioStandard;
      case complement97:
        return ratioComplement;
      case epistasis934:
        return ratioEpistasis;
      case dominant151:
        return ratioDominant;
      case quantitative14641:
        return ratioQuantitative;
      case dominantEpistasis1231:
        return ratioDominantEpistasis;
      case inhibition13_3:
        return ratioInhibition;
      case additive961:
        return ratioAdditive;
      default:
        return ratioStandard;
    }
  }

  // ───────── 显示名 ─────────
  // 短名：v2.10 之前 kaoji_calc.dart:240 variantName 推断用
  // 长名：v2.10 之前 cross_calculator_page.dart:752-761 _variantName 用

  /// 短名（如「标准 9:3:3:1」「9:7」），用于卡片 chip / 报告行。
  static const Map<String, String> shortNames = <String, String>{
    standard9331: '标准 9:3:3:1',
    complement97: '9:7',
    epistasis934: '9:3:4',
    dominant151: '15:1',
    quantitative14641: '1:4:6:4:1',
    dominantEpistasis1231: '12:3:1',
    inhibition13_3: '13:3',
    additive961: '9:6:1',
  };

  /// 长名（含教学解释），用于变式速查卡 / 教学辅助面板。
  static const Map<String, String> displayNames = <String, String>{
    standard9331: '标准 9:3:3:1（两对等位基因独立分配）',
    complement97: '9:7（互补作用）',
    epistasis934: '9:3:4（隐性上位）',
    dominant151: '15:1（显性叠加）',
    quantitative14641: '1:4:6:4:1（数量性状，按显性基因数）',
    dominantEpistasis1231: '12:3:1（显性上位）',
    inhibition13_3: '13:3（抑制作用）',
    additive961: '9:6:1（积加作用）',
  };

  /// 短名查（未知 mode 回退 mode 字面量，与 cross_calculator_page.dart:763
  /// `return mode;` 行为一致）。
  static String shortName(String mode) =>
      shortNames[mode] ?? mode;

  /// 长名查（未知 mode 回退 mode 字面量）。
  static String displayName(String mode) =>
      displayNames[mode] ?? mode;
}
