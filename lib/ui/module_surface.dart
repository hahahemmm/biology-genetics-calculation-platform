// module_surface.dart —— v2.21.0 模块化工作台薄壳
//
// 只负责统一排版：Surface、细边框、14px 圆角、标题层级与间距。
// 不负责导航、路由、滚动或业务状态；不得用它层层套卡，也不得给画布
// 增加 maxWidth/滚动约束。所有颜色在 build 时读取，调用方不得 const 缓存。
//
// v2.23 标题层（仍是纯排版薄壳，几何契约不动）：
//  - 无标题路径**逐字不变**（直接 child，绝不新增 Column）；
//  - 有标题：简洁 19px Sage 图标 + 共享 AppText.sectionTitle（16px）+
//    标题下同色系 1px 发丝线。**不用图标底瓦**——tealWash 对 surface 仅
//    ~1.2:1 几乎不可见，却把标题行从 21 抬到 26、吃掉 fillRemaining 5px
//    （M3.1 复核），不可见装饰不许换高度；
//  - 发丝线占位与原 Divider 逐像素相同（12 + 1 + 14），左实右淡出但
//    右端不归零；高对比投影档整条不透明（淡出端在泛白投影上会消失）。
import 'package:flutter/material.dart';

import '../theme.dart';

class ModuleSurface extends StatelessWidget {
  const ModuleSurface({
    super.key,
    required this.child,
    this.title,
    this.icon,
    this.trailing,
    this.padding = const EdgeInsets.all(20),
    this.margin = EdgeInsets.zero,
    this.fillRemaining = false,
  });

  /// 内容。无标题时直接使用，不在其上额外包 Column，故 TabBarView、
  /// InteractiveViewer 等有界画布可以保持原有尺寸与命中语义。
  final Widget child;
  final String? title;
  final IconData? icon;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  /// 有标题且子内容需要占满剩余高度（例如工具输入滚动区）时置 true。
  /// 文档流保持 false，避免把长内容强制撑成视口高度。
  final bool fillRemaining;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppTheme.radiusCard);
    // 发丝线右端 alpha 端值（见下方发丝线注释）。
    final hairlineEnd = AppColors.isHighContrast ? 1.0 : 0.4;
    final body = Padding(
      padding: padding,
      child: title == null
          ? child
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (icon != null) ...[
                      // v2.23：简洁图标（19px Sage），不再套 tealWash 底瓦。
                      Icon(icon, size: 19, color: AppColors.teal),
                      const SizedBox(width: 8),
                    ],
                    Expanded(child: Text(title!, style: AppText.sectionTitle)),
                    ?trailing,
                  ],
                ),
                const SizedBox(height: 12),
                // 发丝线同色系浅层过渡：结构灰自左向右淡出，但右端保留
                // alpha 端值——标准/深色 0.4（淡出不归零），高对比投影档
                // 1.0 整条不透明（渐变淡出在泛白投影上会整条消失）。
                // 高度仍 1px，占位与原 Divider 逐像素相同；token 在 build
                // 期读取，深浅主题即时生效。
                Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        AppColors.border,
                        AppColors.border,
                        AppColors.border.withValues(alpha: hairlineEnd),
                      ],
                      stops: const [0, 0.35, 1],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (fillRemaining) Expanded(child: child) else child,
              ],
            ),
    );
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: radius,
      ),
      clipBehavior: Clip.antiAlias,
      child: body,
    );
  }
}
