// pedigree_chip_tooltips.dart —— 系谱页 chip / IconButton tooltip 文案共用常量。
//
// v2.19.6 polish（老师 🔴1）：底栏 O-6 IconButton 与侧栏 ⋯ chip 都
// 用同一段「后果导向」 tooltip 文字——避免两处措辞微差让用户在两入口
// 切换时怀疑按钮行为有别。常量抽到独立顶层文件，杜绝
// PedigreeBottomBar ↔ PedigreeSidePanel ↔ GeneticPedigreePage 三方
// 互相 import 循环（GeneticPedigreePage 同时 import 前两者，bottom
// / side 再 import 反向 = part-of 不可解析）。

/// 同性交配「开」tooltip（chip + IconButton 共用）：
/// 明确告知适用物种场景，让用户知道这不是 bug 而是能力扩展。
const String sameSexTooltipOn =
    '允许两个同性个体（♂♂ / ♀♀）连线（雌雄同体 / 同配生殖物种）';

/// 同性交配「关」tooltip（chip + IconButton 共用）：
/// 明确告知默认适用场景 + 「关闭会移除既有同性边」副作用，避免盲切。
const String sameSexTooltipOff =
    '禁止同性个体连线（一雄一雌场景默认；关闭时移除既有同性边）';
