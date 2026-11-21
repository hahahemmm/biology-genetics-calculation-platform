// classroom_quick_bar.dart —— 课堂快捷条（v2.7 课堂讲解优化；v2.19.68 收起把手）
//
// 场景：老师大屏讲课中需要开关聚光灯/高对比/激光笔时，不用离开当前页
// 钻设置页——课堂模式开启期间，内容区常驻一个紧凑浮条，教鞭一键够到。
//
// 仅课堂模式（PresentModeController.enabled）渲染；学生模式/课堂关闭时
// 完全不挂载（学生模式像素级不变硬门禁，golden 零 diff）。
// 与设置页开关同源同 controller（ListenableBuilder），双处操作状态一致。
//
// 挂载：HomeShell 内容区真正右下贴底（FAB 列正上方，main.dart）。
//
// v2.19.68（GUI 看官 P1）：条上加「收起」按钮——收起后只剩一枚 40px 级
// 半透明小圆把手，点击展开回完整条；展开/收起是会话内状态（不持久化，
// 下次进课堂默认展开）。聚光灯/高对比/激光笔/系谱推断/退出课堂五个
// 功能按钮全部保留不动。

import 'package:flutter/material.dart';

import '../state/present_mode_controller.dart';
import '../theme.dart';

/// 课堂快捷条。[spotlightAvailable] = 当前页是系谱页（聚光灯只在
/// 系谱画布生效）；false 时聚光灯按钮禁用并说明。
class ClassroomQuickBar extends StatefulWidget {
  final bool spotlightAvailable;

  /// 系谱推断（人类遗传病页）入口——由 main.dart 注入 push 动作，
  /// 本组件保持页面无关（ui/ 不依赖 pages/）。课堂大屏下一键直达
  /// 推断器（老师走查：原入口 5+ 步）。
  final VoidCallback? onOpenInference;

  const ClassroomQuickBar({
    super.key,
    required this.spotlightAvailable,
    this.onOpenInference,
  });

  /// 收起把手锚点 key（widget 测试定位；不影响 golden 像素）。
  @visibleForTesting
  static const ValueKey handleKey = ValueKey('classroomQuickBarHandle');

  /// 收起按钮锚点 key（同上）。
  @visibleForTesting
  static const ValueKey collapseKey = ValueKey('classroomQuickBarCollapse');

  @override
  State<ClassroomQuickBar> createState() => _ClassroomQuickBarState();
}

class _ClassroomQuickBarState extends State<ClassroomQuickBar> {
  /// 收起态（会话内变量，不持久化——下次进课堂默认展开）。
  bool _collapsed = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: PresentModeController.instance,
      builder: (context, _) {
        final pm = PresentModeController.instance;
        if (!pm.enabled) return const SizedBox.shrink();
        // 收起态：只剩一枚半透明小圆把手（40px 级），点击展开回完整条。
        if (_collapsed) return _buildHandle();
        return Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(24),
          color: AppColors.surface,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.teal.withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _btn(
                  icon: pm.spotlightOn
                      ? Icons.highlight
                      : Icons.highlight_outlined,
                  tooltip: !widget.spotlightAvailable
                      ? '聚光灯仅在系谱页画布生效'
                      : (pm.spotlightOn ? '关闭聚光灯' : '聚光灯：亮区跟随手指，其余压暗'),
                  active: pm.spotlightOn,
                  onPressed: widget.spotlightAvailable
                      ? () => pm.setSpotlightOn(!pm.spotlightOn)
                      : null,
                ),
                _btn(
                  icon: Icons.contrast_outlined,
                  tooltip: pm.highContrast ? '关闭高对比配色' : '高对比配色（投影仪泛白时用）',
                  active: pm.highContrast,
                  onPressed: () => pm.setHighContrast(!pm.highContrast),
                ),
                _btn(
                  icon: Icons.gps_fixed_outlined,
                  tooltip: pm.laserEnabled ? '关闭画布激光笔' : '画布激光笔（教鞭场景默认关）',
                  active: pm.laserEnabled,
                  onPressed: () => pm.setLaserEnabled(!pm.laserEnabled),
                ),
                if (widget.onOpenInference != null)
                  _btn(
                    icon: Icons.account_tree_outlined,
                    tooltip: '系谱推断（给系谱图判遗传方式）',
                    active: false,
                    onPressed: widget.onOpenInference,
                  ),
                SizedBox(
                    height: 22,
                    child: VerticalDivider(
                        width: 10, color: AppColors.border)),
                _btn(
                  icon: Icons.school_outlined,
                  tooltip: '退出课堂大屏（回标准）',
                  active: false,
                  onPressed: () => pm.setEnabled(false),
                ),
                // v2.19.68：收起成小把手——条不再常驻遮内容，需要时一键展开。
                _btn(
                  key: ClassroomQuickBar.collapseKey,
                  icon: Icons.chevron_right,
                  tooltip: '收起快捷条（点击把手展开）',
                  active: false,
                  onPressed: () => setState(() => _collapsed = true),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 收起态小圆把手：40px 级、半透明 surface 底 + teal 描边，视觉轻量
  /// 不抢内容；点击展开回完整条。功能零损失（展开即回到五个功能键）。
  Widget _buildHandle() {
    return Tooltip(
      message: '展开课堂快捷条',
      child: Material(
        elevation: 2,
        // 消费 AppColors token 的实例禁 const（主题切换需 rebuild 刷新）。
        color: AppColors.surface.withValues(alpha: 0.82),
        shape: CircleBorder(
            side: BorderSide(color: AppColors.teal, width: 1)),
        child: InkWell(
          key: ClassroomQuickBar.handleKey,
          customBorder: const CircleBorder(),
          onTap: () => setState(() => _collapsed = false),
          // 禁 const：Icon 消费 AppColors.teal 实时 token（主题切换须刷新）。
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(Icons.tune, size: 20, color: AppColors.teal),
          ),
        ),
      ),
    );
  }

  Widget _btn({
    Key? key,
    required IconData icon,
    required String tooltip,
    required bool active,
    required VoidCallback? onPressed,
  }) {
    // 触控目标纪律：课堂快捷条服务大屏触屏/教鞭场景，须保持 IconButton
    // 默认 48px 触控面——VisualDensity.compact 会压缩到 ~32px（鼠标密集
    // UI 专用），教鞭点按命中过难（design-taste 走查 P1）。
    return IconButton(
      key: key,
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      color: active ? AppColors.teal : AppColors.steel,
      onPressed: onPressed,
    );
  }
}
