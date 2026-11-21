// preset_genotypes.dart —— 图谱页「预置」亲本组合库（v2.1）
//
// 纯数据文件，与引擎无依赖：遗传图谱页左面板「亲本」分区的「预置」
// 对话框填充 ♂/♀ 输入框。9 条教学常用组合，首位是两对基因自交，
// 其余覆盖三对基因 9331、测交、变化比例、全隐性对照与多倍体场景。

/// 一条预置杂交组合。
class PresetCross {
  final String name; // 题名（对话框列表主行）
  final String male; // ♂ 基因型（上方输入框）
  final String female; // ♀ 基因型（下方输入框）
  final String note; // 一句话说明（多倍体/适用场景）
  const PresetCross(this.name, this.male, this.female, this.note);
}

/// 预置亲本组合（9 条；第 9 条为多倍体，需开启「多倍体」开关）。
const List<PresetCross> presetCrosses = [
  // 两对基因自交是老师最常手算的一道题（AaBb × AaBb），排第一位；
  // 说明用直白口径（表型比 + 基因型种数），不写「F1 自交 F2 呈…」。
  PresetCross('双杂合自交（两对基因）', 'AaBb', 'AaBb',
      '子代表型 9:3:3:1，基因型 9 种'),
  // v2.19.68 P2-3（学科性修正）：AABBCC × aabbcc 是**三对**基因——
  // F1(AaBbCc) 自交的 F2 表型比是 27:9:9:9:3:3:3:1（3ⁿ 项），不是两对
  // 基因的 9:3:3:1。旧文案「（9331 基础）… F2 呈 9:3:3:1」是学科错误，
  // 看官走查实锤；名字与说明一并改口径。
  PresetCross('纯合显性 × 纯合隐性（三对基因）', 'AABBCC', 'aabbcc',
      'F1 全为 AaBbCc，F1 自交 F2 呈 27:9:9:9:3:3:3:1（三对基因自由组合）'),
  PresetCross('双杂合自交（F1 自交）', 'AaBbCc', 'AaBbCc',
      '三对基因杂合自交，观察多种基因型分布'),
  PresetCross('测交（三对基因）', 'AaBbCc', 'aabbcc',
      '杂合子与隐性纯合测交，检验配子类型与比例'),
  PresetCross('单显性纯合 × 单隐性纯合', 'AABBcc', 'aaBBcc',
      '仅第一对位点呈杂合（F1 全 AaBBcc），F1 自交呈 3:1 单基因比例'),
  // v2.19.68 P2-3 顺带核口径：AaBbCc × AaBbcc 三位点是 (3:1)(3:1)(1:1)
  // ——子代表型比恰为 9:3:3:1（与两杂合自交同形，但来源不同），
  // 旧文案「较 9331 简化」口径不清。
  PresetCross('三杂合 × 两杂合一纯合（变化比例）', 'AaBbCc', 'AaBbcc',
      '第三对位点杂合×纯合（Cc×cc → 1:1），子代表型比恰为 9:3:3:1'),
  PresetCross('AaBBCc × AABbCc（逐位点变化）', 'AaBBCc', 'AABbCc',
      '各对位点杂合/纯合交错，观察不同分离组合'),
  PresetCross('全隐性 × 全隐性', 'aabbcc', 'aabbcc',
      '子代恒为 aabbcc 全隐性，适合基线对照'),
  PresetCross('三倍体示例（需开启多倍体）', 'AaaBbbCcc', 'aaabbbccc',
      '3n 双亲杂交（每对位点 3 份等位），需先打开「多倍体」开关'),
];