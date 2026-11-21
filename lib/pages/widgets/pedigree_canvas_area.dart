// pedigree_canvas_area.dart —— 系谱页画布区（2.3 重构阶段 6 抽取）
//
// 从 genetic_pedigree_page.dart 抽出，纯展示组件：页面内嵌与全屏
// Dialog 共用（各自独立的视口变换）。折叠过滤/聚焦/solo 半边等
// 派生数据由页面算好注入；画布回调与悬浮面板动作全部显式传入。
// 行为与抽取前逐行一致（悬浮面板「退出全屏」「添加家族」「添加样本」
// 「删除整代」与底部操作提示文案是测试依赖）。

import 'package:flutter/material.dart';

import '../../engine/pedigree_graph.dart';
import '../../guide/guide_keys.dart';
import '../../theme.dart';
import '../../ui/module_surface.dart';
import 'pedigree_canvas.dart';
import 'pedigree_side_panel.dart';

/// 画布区：页面内嵌与全屏 Dialog 共用（各自独立的视口变换）。
/// showFloatingActions：右上悬浮按钮面板是否显示（v3.1 与左控制
/// 面板互斥：全屏 Dialog 无左面板 → 常驻；页面内左面板可见 → 隐藏）。
class PedigreeCanvasArea extends StatelessWidget {
  const PedigreeCanvasArea({
    super.key,
    required this.fullscreen,
    required this.showFloatingActions,
    required this.boundaryKey,
    required this.canvasStateKey,
    required this.nodes,
    required this.edges,
    required this.selectedId,
    required this.onNodeTap,
    required this.onNodeHalfTap,
    required this.onBlankTap,
    required this.onWireDetach,
    required this.armedId,
    required this.flashIds,
    required this.dimIds,
    required this.showLineage,
    this.edgeStyle = PdEdgeStyle.orthogonal,
    required this.showBackcross,
    required this.hiddenBackcrossKeys,
    required this.onBlankSecondaryTap,
    this.onBlankLongPress,
    required this.onNodeSecondaryTap,
    required this.collapsedKeys,
    required this.hiddenCounts,
    required this.onToggleGen,
    required this.sexLinked,
    required this.familyLabels,
    required this.sexSplitView,
    required this.pickedIds,
    required this.locked,
    required this.familyOffsets,
    required this.onToggleLock,
    required this.onFullscreenTap,
    required this.onFamilyDragDelta,
    required this.onFamilyDragEnd,
    required this.connectedIds,
    required this.soloHalfIds,
    required this.hintText,
    required this.onAddFamily,
    required this.onAddSample,
    required this.onDeleteGeneration,
    this.onExportPng,
    this.onExportSvg,
  });

  final bool fullscreen;
  final bool showFloatingActions;

  /// v3.5 多模态截图双 key：仅页面内嵌画布挂载（全屏 Dialog 是
  /// 独立实例，不挂，避免 GlobalKey 冲突）。
  final GlobalKey boundaryKey;
  final GlobalKey<PedigreeCanvasState> canvasStateKey;

  // ── PedigreeCanvas 入参（页面算好的可见集与派生态）──
  final List<PedigreeNode> nodes;
  final List<PedigreeEdge> edges;
  final String? selectedId;
  final ValueChanged<PedigreeNode> onNodeTap;
  final void Function(PedigreeNode group, PedigreeNodeKind sex)
      onNodeHalfTap;
  final VoidCallback onBlankTap;
  final ValueChanged<PedigreeNode> onWireDetach;
  final String? armedId;
  final Set<String> flashIds;

  /// v2.19.5 连线性别互斥：不可连接节点 id 集合（透传画布→画家变暗）。
  final Set<String> dimIds;
  final bool showLineage;

  /// v2.19 连线样式（正交/曲线），透传画家。
  final PdEdgeStyle edgeStyle;
  final bool showBackcross;
  final Set<String> hiddenBackcrossKeys;
  final void Function(int generation, Offset viewportPos)
      onBlankSecondaryTap;

  /// v2.19.10：触屏长按空白 = 快捷菜单（透传画布）。
  final void Function(int generation, Offset viewportPos)? onBlankLongPress;
  final void Function(PedigreeNode node, Offset viewportPos)
      onNodeSecondaryTap;
  final Set<String> collapsedKeys;
  final Map<String, int> hiddenCounts;
  final ValueChanged<String> onToggleGen;
  final SexLinkedConfig? sexLinked;
  final Map<int, String> familyLabels;
  final bool sexSplitView;
  final Set<String> pickedIds;
  final bool locked;
  final Map<int, Offset> familyOffsets;
  final VoidCallback onToggleLock;
  final VoidCallback? onFullscreenTap;
  final void Function(int familyId, Offset worldDelta) onFamilyDragDelta;
  final VoidCallback onFamilyDragEnd;
  final Map<String, Set<PedigreeNodeKind>> connectedIds;
  final Map<String, PedigreeNodeKind> soloHalfIds;

  /// 底部操作提示文案（随画布交互模式三态切换，页面侧选好传入）。
  /// v3.7：空串 = 该状态不需要提示（默认模式已算出子代）——整条胶囊
  /// 连外框/内边距一起不渲染，不占位。
  final String hintText;

  // ── 悬浮面板动作（引擎必存在——画布区只在已计算时渲染）──
  final VoidCallback onAddFamily;
  final VoidCallback onAddSample;
  final VoidCallback onDeleteGeneration;

  /// v2.4 功能 2：画布存为 PNG（插课件用）。仅页面内嵌实例可截
  ///（boundaryKey 挂在内嵌实例上），null = 不显示该按钮。
  final VoidCallback? onExportPng;

  /// v2.12.0+2 hotfix：板书 SVG 复制到剪贴板（与 PNG 并列的悬浮入口）。
  /// null = 不显示该按钮（v2.12 落 svg_export.dart 但未挂入口，
  /// 此次补全）。全屏 Dialog 也提供，方便老师讲解时直接复制。
  final VoidCallback? onExportSvg;

  @override
  Widget build(BuildContext context) {
    // v2.21.0：薄壳只贡献 surface/细边框/圆角；画布坐标与命中层级不变。
    final Widget canvasBody = ColoredBox(
      color: AppColors.canvas,
      child: Stack(
        children: [
          Positioned.fill(
            // v3.5 多模态截图：仅页面内嵌画布挂 RepaintBoundary/State
            // 双 key（全屏 Dialog 是独立实例，不挂，避免 GlobalKey 冲突）。
            child: RepaintBoundary(
              key: fullscreen ? null : boundaryKey,
              child: PedigreeCanvas(
                key: fullscreen ? null : canvasStateKey,
                nodes: nodes,
                edges: edges,
                selectedId: selectedId,
                onNodeTap: onNodeTap,
                onNodeHalfTap: onNodeHalfTap,
                onBlankTap: onBlankTap,
                onWireDetach: onWireDetach,
                armedId: armedId,
                flashIds: flashIds,
                dimIds: dimIds,
                showLineage: showLineage,
                edgeStyle: edgeStyle,
                showBackcross: showBackcross,
                hiddenBackcrossKeys: hiddenBackcrossKeys,
                onBlankSecondaryTap: onBlankSecondaryTap,
                onBlankLongPress: onBlankLongPress,
                onNodeSecondaryTap: onNodeSecondaryTap,
                collapsedKeys: collapsedKeys,
                hiddenCounts: hiddenCounts,
                onToggleGen: onToggleGen,
                sexLinked: sexLinked,
              familyLabels: familyLabels,
              sexSplitView: sexSplitView,
              pickedIds: pickedIds,
              // R18：画布锁 + 家族整体拖动（解决多家族遮挡）
              locked: locked,
              familyOffsets: familyOffsets,
              onToggleLock: onToggleLock,
              // v3.5 全屏移入缩放条（与缩放/锁并列）；全屏 Dialog 里
              // 不渲染（退出全屏走悬浮面板按钮）。
              onFullscreenTap: onFullscreenTap,
              onFamilyDragDelta: onFamilyDragDelta,
              onFamilyDragEnd: onFamilyDragEnd,
              connectedIds: connectedIds,
              soloHalfIds: soloHalfIds,
              ),
            ),
          ),
          // v3 悬浮工具条：右上 2 列网格面板（全屏 / 添加家族 / 添加样本 /
          // 计算下一代 / 删除整代）。仅 fullscreen（全屏 Dialog 无左面板）
          // 或左控制面板折叠时显示；左面板可见时不重复承载。
          // v2.18 R8：悬浮面板同步下沉右下（白板可达；原右上在几米
          // 白板够不到——全屏 Dialog 内编辑/退出全靠它）。
          if (showFloatingActions)
            Positioned(
            bottom: 44,
            right: 10,
            child: Container(
              key: const Key('pedigree-floating-actions'),
              width: 204,
              decoration: BoxDecoration(
                color: AppColors.overlayBar,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
                boxShadow: AppColors.cardShadow,
              ),
              padding: const EdgeInsets.all(4),
              child: Wrap(
                spacing: 2,
                runSpacing: 2,
                children: [
                  // v3.5：全屏入口已移至画布缩放条（与缩放/锁并列）；
                  // 悬浮面板仅在全屏 Dialog 保留「退出全屏」（全屏时
                  // 缩放条上的全屏按钮不渲染）。
                  if (fullscreen)
                    pedigreeBarAction(
                      icon: Icons.fullscreen_exit,
                      label: '退出全屏',
                      tooltip: '退出全屏（Esc）',
                      onTap: () => Navigator.of(context).pop(),
                    ),
                  pedigreeBarAction(
                    icon: Icons.groups_outlined,
                    label: '添加家族',
                    color: AppColors.armed,
                    onTap: onAddFamily,
                  ),
                  pedigreeBarAction(
                    icon: Icons.person_add_alt,
                    label: '添加样本',
                    color: AppColors.teal,
                    onTap: onAddSample,
                  ),
                  if (onExportPng != null)
                    pedigreeBarAction(
                      icon: Icons.image_outlined,
                      label: '存为图片',
                      color: AppColors.steel,
                      // v2.13 R6-P1：补「图片原样保存，不脱敏」提示——
                      // P1 隐私根因中「照片/截图/板书 SVG 不脱敏」
                      // 在画布 PNG 导出的最小缓解。AES-GCM 对像素数据
                      // 加密属重工程，推 R7 路线图；本轮先在 tooltip
                      // 强提示导出前自审。R7 落地后改回中性 tooltip。
                      tooltip: '画布存为 PNG（图片目录）——'
                          '图片原样保存，不做脱敏，导出前请确认不含敏感信息',
                      onTap: onExportPng!,
                    ),
                  // v2.12.0+2 hotfix：与「存为图片」并列的 SVG 复制
                  // 入口（板书 PDF 链路补全）。
                  // v2.13 R6-P1：SVG 同理——SVG 文本里有显式文本节点
                  // （个体 ID / 标注），导出到剪贴板后粘到微信/富文本
                  // 等同于明文传播。tooltip 强提示。
                  if (onExportSvg != null)
                    pedigreeBarAction(
                      icon: Icons.copy_all_outlined,
                      label: '复制 SVG',
                      color: AppColors.steel,
                      tooltip: '板书 SVG 复制到剪贴板（粘到微信/富文本）——'
                          'SVG 原样保存，不做脱敏，导出前请确认不含敏感信息',
                      onTap: onExportSvg!,
                    ),

                  // v3.2：删除整代常驻底部操作条；悬浮面板只在全屏
                  // Dialog（无底部条）时保留该入口，防双入口重复。
                  if (fullscreen)
                    pedigreeBarAction(
                      icon: Icons.delete_sweep_outlined,
                      label: '删除整代',
                      color: AppColors.steel,
                      onTap: onDeleteGeneration,
                    ),
                ],
              ),
            ),
          ),
          // 底部操作提示：胶囊底（v2），纯展示不拦截指针（点击穿透）。
          // 缩放条固定 bottom:44，右下动作面板宽约 204；提示上移到其上方，
          // 课堂大字下也不再遮住缩放/锁/全屏等真实操作入口。
          Positioned(
            left: 12,
            bottom: 124,
            right: showFloatingActions ? 226 : 12,
            child: IgnorePointer(
              child: Center(
                // v3.7 新手引导锚点：hintText 为空时整条收成零尺寸（外框、
                // 内边距、指针层都不占位），但锚点仍留在树上——引导取坐标
                // 不会拿到空 context。有提示时锚点矩形 = 胶囊本体。
                child: KeyedSubtree(
                  // 全屏 Dialog 是第二个实例（内嵌那份仍在树上），同一
                  // GlobalKey 只能挂一处——沿用 boundaryKey 的约定，只给
                  // 页面内嵌实例挂引导锚点。
                  key: fullscreen ? null : GuideKeys.pedigreeHintBar,
                  child: hintText.isEmpty
                      ? const SizedBox.shrink()
                      : Container(
                          key: const Key('pedigree-canvas-hint'),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.overlayBar,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Text(
                            hintText,
                            // v2.19.10（老师走查 L1）：caption(12px steel) 几米外
                            // 不可读——hint 是模式切换的关键反馈，升 body 字号 +
                            // ink 主墨色 + 半透明底浮起。
                            style: AppText.body.copyWith(color: AppColors.ink),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return ModuleSurface(
      margin: fullscreen ? EdgeInsets.zero : const EdgeInsets.all(10),
      padding: EdgeInsets.zero,
      child: canvasBody,
    );
  }
}
