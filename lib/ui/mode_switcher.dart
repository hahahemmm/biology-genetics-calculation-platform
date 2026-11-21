// mode_switcher.dart —— 标准显示 / 课堂大屏 二选一切换器（v2.3；v2.13 改名）
//
// 用户裁定（2026-08-29）：课堂模式和学生模式分别做——软件不只给老师用，
// 学生用不上课堂模式。两个模式是并列入口，老师上课前一键切换。
//
// v2.13 改名（用户截图实锤「两个身份选择器」困惑）：原标签「学生模式/
// 课堂模式」与角色 chip（学生/老师）撞语义——用户看到「学生模式 ✓」
// 却找不到学生功能（错题本被角色隐藏）。本组件是**显示维度**
// （字号/激光笔/快捷条），不是身份；改名「标准 / 课堂大屏」消除假重名。
//
// 底层仍是 PresentModeController.enabled（bool），本组件只做呈现：
// 标准 = 关闭（默认，日常学习/刷题布局）；
// 课堂大屏 = 开启（全场大字号 + 画布激光笔，面向大屏讲课）。
//
// v2.20.0 窄窗自适应（真窗发现）：窗口 500×1500 + 课堂模式时，首页这一行
//（前置图标 + 本切换器）出现「RIGHT OVERFLOWED BY 4.1 PIXELS」。根因不是
// 窗口逻辑宽 500 而是系统 150% 缩放：500 物理 ⇒ 逻辑 ≈333，行内实得
// 333 - 66（页边距 40 + 前置图标 18 + 间距 8）= 267，而课堂档把两段
//「图标 + 全称」撑到 268.8 ⇒ 右溢 4.1px（逐像素吻合）。
// 修法：按「行内可用宽 vs 三档固有宽（实测线性模型）」选最小降级档——
// full（图标 + 全称，宽窗原样）→ labelsOnly（去图标）→ compact（短标签）。
// ≥600 逻辑宽的桌面/平板/投影一律 full，外观零变化。
// 启动恢复由 PresentModeController 负责：enabled 仅当次会话有效，冷启动
// 一律标准模式；本组件只负责当次切换与窄窗布局，不自行持久化模式。

import 'package:flutter/material.dart';

import '../state/present_mode_controller.dart';
import '../theme.dart';

/// 窄窗降级档位（详见文件头 v2.20.0 注释）。
enum ModeSwitcherDensity {
  /// 图标 + 全称「课堂大屏」（宽窗原样）。
  full,

  /// 去图标 + 全称（省两枚图标与间距，文字信息不丢）。
  labelsOnly,

  /// 去图标 + 短标签「课堂」+ 收紧内边距（390 手机档课堂字号兜底）。
  compact,
}

class ModeSwitcher extends StatelessWidget {
  const ModeSwitcher({super.key});

  /// 行内被别的前置元素吃掉的宽度：页边距 20×2 + 前置图标 18 + 间距 8。
  /// 实测来源（2026-10-25 真窗 500×1500 + 150% 系统缩放 ⇒ 逻辑宽 ≈333）：
  /// 行内实得 333-66 = 267，而「图标 + 全称」需 268.8 → 右溢 4.1px，
  /// 与用户截图的「RIGHT OVERFLOWED BY 4.1 PIXELS」逐像素吻合。
  /// 设置页的卡片内边距更小 ⇒ 该处估算偏保守（只会多降一档，不会溢出）。
  static const double _chromeWidth = 66;

  /// 各档位固有宽模型（逻辑像素；textScale=1.0 常量 + 随字号线性项）。
  ///
  /// 全部在**真实 App 壳**里量（不是拼常数）：课堂档 ×1.75 时
  ///   full      = 268.8（图标 + 「课堂大屏」+ 选中 check）
  ///   labelsOnly= 232.8（去图标 + 全称；check 一并关掉——check 也占图标位，
  ///              不关的话实测仍是 268.8，等于白降一档）
  ///   compact   = 114.4（去图标 + 「课堂」）
  /// 标准档 ×1.0：full = 220.8。两点连线得下列线性式，再加 [_safety] 余量：
  /// 窄窗里宁可早降一档，也不要贴着 0.几 px 打摆子（真窗就是 4.1px 溢）。
  static const double _safety = 4;
  static double _needFullWidth(double scale) => 156.8 + 64.0 * scale + _safety;
  static double _needLabelsOnlyWidth(double scale) =>
      73.2 + 91.2 * scale + _safety;
  // compact 档固有宽（114.4 @×1.75 / 164.4 @×1.0，线性式 156.4 + 8×scale）
  // 只做文档：兜底档不再参与档位选择，故不保留取值函数（原 assert 已删，
  // 见 densityFor 末尾注释）。

  /// 按「行内可用宽」选降级档位：从最不降级的一档开始，谁能放下用谁。
  ///
  /// 实测锚点：逻辑 390/500 课堂档（×1.75）都还放得下 full（268.8 ≤ 324/434）；
  /// 真正需要降级的是「物理 500 + 150% 缩放 ⇒ 逻辑 333」这类窗口
  /// （实得 267 → labelsOnly 232.8 才有余量），更窄则用 compact（114.4）。
  static ModeSwitcherDensity densityFor({
    required double screenWidth,
    required double textScale,
  }) {
    final scale = textScale <= 0 ? 1.0 : textScale;
    final available = screenWidth - _chromeWidth;
    if (available >= _needFullWidth(scale)) return ModeSwitcherDensity.full;
    if (available >= _needLabelsOnlyWidth(scale)) {
      return ModeSwitcherDensity.labelsOnly;
    }
    // compact 是**无条件兜底档**：114.4 宽，逻辑宽 ≥200 的窗口都放得下
    //（真正会再挤的是页面其它元素，不在本组件职责内）。
    // ⛔ 不要再加 `compact < labelsOnly` 之类的档位序 assert：固有宽模型里
    //    compact（156.4 + 8×scale）在小字号档（≤0.95，如 0.85 时 163.2）
    //    会**大于** labelsOnly（73.2 + 91.2×scale + 4 = 154.7）——两档的
    //    宽窄关系随字号翻转，而 compact 靠的是「短标签 + 收紧内边距」，
    //    不是「比 labelsOnly 更窄」，该序关系本就不成立。
    return ModeSwitcherDensity.compact;
  }

  /// 组装一段按钮（图标/标签按当前降级档位取）。
  ButtonSegment<bool> _segment({
    required bool value,
    required String label,
    required String tooltip,
    required IconData icon,
    required bool withIcons,
  }) {
    return ButtonSegment<bool>(
      value: value,
      tooltip: tooltip,
      icon: withIcons ? Icon(icon) : null,
      // ⛔ 不缩字号：课堂档的大字号是刚需，省宽度只靠「去图标 / 短标签 /
      // 收内边距」（见文件头 v2.20.0）。
      label: Text(label, maxLines: 1, softWrap: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PresentModeController.instance,
      builder: (context, _) {
        final density = densityFor(
          screenWidth: MediaQuery.sizeOf(context).width,
          textScale: MediaQuery.textScalerOf(context).scale(1.0),
        );
        final compact = density == ModeSwitcherDensity.compact;
        final withIcons = density == ModeSwitcherDensity.full;
        return SegmentedButton<bool>(
          // 降级档关掉 M3 的「选中 check 图标」：那枚 check 也是图标位，
          // 不关就白丢自定义图标（实测 333 逻辑宽下 labelsOnly 仍是 268.8
          // ——check 占位把那点宽度又吃回去了）。选中态本身仍有
          // tealWash 底 + teal 文字，可辨识性不降。
          showSelectedIcon: withIcons,
          // v2.3 门面美化：选中态用品牌 teal（原默认 secondaryContainer
          // 淡紫，与全站灰绿莫兰迪不搭——AI 评审实锤突兀）。
          style: ButtonStyle(
            backgroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? AppColors.tealWash
                    : null),
            foregroundColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? AppColors.teal
                    : null),
            // 紧凑档收紧内边距（3 米外仍能点，宽度省 ~16 设计单位）。
            padding: compact
                ? const WidgetStatePropertyAll<EdgeInsetsGeometry>(
                    EdgeInsets.symmetric(horizontal: 4))
                : null,
            visualDensity:
                compact ? const VisualDensity(horizontal: -4) : null,
          ),
          segments: <ButtonSegment<bool>>[
            _segment(
              value: false,
              label: '标准',
              tooltip: '标准显示',
              icon: Icons.school_outlined,
              withIcons: withIcons,
            ),
            _segment(
              value: true,
              // 紧凑档只写短标签，全称退到 tooltip（语义不丢，宽度省一半）。
              label: compact ? '课堂' : '课堂大屏',
              tooltip: '课堂大屏',
              icon: Icons.co_present_outlined,
              withIcons: withIcons,
            ),
          ],
          selected: {PresentModeController.instance.enabled},
          onSelectionChanged: (sel) =>
              PresentModeController.instance.setEnabled(sel.first),
        );
      },
    );
  }
}
