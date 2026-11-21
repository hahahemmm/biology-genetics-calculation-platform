// pedigree_command_bar.dart —— 系谱页顶部命令栏（2.3 重构阶段 5 抽取）
//
// 从 genetic_pedigree_page.dart 抽出，纯展示组件：页面状态（引擎态 /
// 日志与历史条数 / 杂交面板开关）与动作（日志 / 历史 / 杂交面板 / 问 AI /
// ☰ 导航）由页面持有并显式注入。行为与抽取前逐行一致
// （「日志」「历史」「杂交计算」「问 AI」等文案是测试依赖）。

import 'package:flutter/material.dart';

import '../../theme.dart';

/// v3.1 命令栏（替掉默认 AppBar）：左 = 页面标题 + 状态摘要 chip；
/// 右 = 控制面板开合按钮 + 页面级动作（问 AI）。
class PedigreeCommandBar extends StatelessWidget {
  const PedigreeCommandBar({
    super.key,
    required this.onNavPressed,
    required this.computed,
    required this.maxGeneration,
    required this.logCount,
    required this.historyCount,
    required this.crossOpen,
    required this.onShowLog,
    required this.onShowHistory,
    required this.onToggleCrossPanel,
    required this.onAskAi,
    this.onExportSvg,
  });

  /// v3.3 ☰：HomeShell 注入时显示（折叠导航侧栏 / 打开抽屉）。
  final VoidCallback? onNavPressed;

  /// 已计算（引擎存在）：宽屏显示「已展开至 FN」chip。
  final bool computed;
  final int maxGeneration;

  /// 日志条数（不含第 0 步初始态）与历史条数。
  final int logCount;
  final int historyCount;

  /// 杂交面板开合状态（图标/文案着色）。
  final bool crossOpen;

  final VoidCallback onShowLog;
  final VoidCallback onShowHistory;
  final VoidCallback onToggleCrossPanel;
  final VoidCallback onAskAi;

  /// v2.12.0+2 hotfix：宽屏「复制 SVG」入口（板书 PDF 链路补全）。
  /// 仅在宽屏渲染（窄屏不放，避免命令栏挤断）。
  final VoidCallback? onExportSvg;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          // v3.3 ☰：HomeShell 注入时显示（折叠导航侧栏 / 打开抽屉）
          if (onNavPressed != null) ...[
            appNavButton(onNavPressed)!,
            const SizedBox(width: 6),
          ],
          // v2.1：窄屏（<640）命令栏放不下 4 个文字按钮，日志/历史
          // 降级为纯图标（tooltip 承载说明）。
          // v2.19.26 手机 9:16 实修（47px 右溢出）：390 宽下
          // ☰+标题+3 图标+问AI 共 ~412px 超限——动作组改
          // Expanded+横向滚动（与本文件宽屏分支同款模式），
          // 放得下贴右缘、放不下滚动承接，绝不溢出。
          if (MediaQuery.sizeOf(context).width < 640) ...[
            Text('遗传图谱计算',
                style: AppText.pageTitle.copyWith(fontSize: 15)),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: '操作日志',
                        onPressed: computed ? onShowLog : null,
                        icon: Icon(Icons.history,
                            size: 19, color: AppColors.ink),
                      ),
                      IconButton(
                        tooltip: '计算历史（$historyCount）',
                        onPressed: onShowHistory,
                        icon: Icon(Icons.auto_stories_outlined,
                            size: 19, color: AppColors.ink),
                      ),
                      IconButton(
                        tooltip: '杂交计算（9331 面板）',
                        onPressed: onToggleCrossPanel,
                        icon: Icon(Icons.calculate_outlined,
                            size: 19,
                            color: crossOpen ? AppColors.teal : AppColors.ink),
                      ),
                      TextButton.icon(
                        // v3.5 多模态：先截图再开面板（画布内容 ROI 随当前视图）
                        onPressed: onAskAi,
                        icon: Icon(Icons.psychology_outlined,
                            size: 18, color: AppColors.teal),
                        label: Text('问 AI',
                            style: TextStyle(
                                color: AppColors.teal,
                                fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ] else ...[
            Text('遗传图谱计算',
                style: AppText.pageTitle.copyWith(fontSize: 17)),
            if (computed) ...[
              const SizedBox(width: 12),
              AppChip('已展开至 F$maxGeneration',
                  icon: Icons.account_tree_outlined),
            ],
            // v2.18 R7 老师走查 #3：画布操作唯一事实源 = 底部操作条
            // （v2.17 课堂可达性重做）。顶栏不再承载画布控件——
            // 大屏上顶栏恰是老师够不着的上半屏。
            // v2.12.0+2 fix（回归 21px overflow）：右侧动作区套
            // Expanded + Align 右锚定 + 横向滚动。不能用 Spacer+Flexible：
            // 两者同 flex:1 会把空间对半分，动作组被挤进半个视口被裁剪
            // （tap 脱靶、按钮不可见）。Expanded 独占全部剩余空间，
            // 放得下时动作组贴右缘（视觉与原样一致），放不下时滚动承接、
            // 绝不溢出。
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                    // v3.4 日志入口常驻命令栏（用户反馈：日志按钮随左面板折叠
                    // 被藏没——折叠无关的高频功能不许进可折叠面板）。
                    TextButton.icon(
                      onPressed: computed ? onShowLog : null,
                      icon: Icon(Icons.history,
                          size: 17, color: AppColors.ink),
                      label: Text('日志（$logCount）',
                          style: TextStyle(
                              color: AppColors.ink,
                              fontWeight: FontWeight.w600)),
                    ),
                    // v2.1 计算历史：自动记录每次计算的基因型/家族/产出；
                    // 对话框含「保存当前并开新对话」（新白板隔离）。
                    TextButton.icon(
                      onPressed: onShowHistory,
                      icon: Icon(Icons.auto_stories_outlined,
                          size: 17, color: AppColors.ink),
                      label: Text('历史（$historyCount）',
                          style: TextStyle(
                              color: AppColors.ink,
                              fontWeight: FontWeight.w600)),
                    ),
                    TextButton.icon(
                      onPressed: onToggleCrossPanel,
                      icon: Icon(Icons.calculate_outlined,
                          size: 17,
                          color: crossOpen ? AppColors.teal : AppColors.ink),
                      label: Text('杂交计算',
                          style: TextStyle(
                              color: crossOpen ? AppColors.teal : AppColors.ink,
                              fontWeight: FontWeight.w600)),
                    ),
                    TextButton.icon(
                      // v3.5 多模态：先截图再开面板（画布内容 ROI 随当前视图）
                      onPressed: onAskAi,
                      icon: Icon(Icons.psychology_outlined,
                          size: 18, color: AppColors.teal),
                      label: Text('问 AI',
                          style: TextStyle(
                              color: AppColors.teal,
                              fontWeight: FontWeight.w600)),
                    ),
                    // v2.12.0+2 hotfix：宽屏「复制 SVG」按钮（板书 PDF
                    // 链路补全——v2.12 落 svg_export.dart 但未挂入口）。
                    // 阈值 900：命令栏在 800 时 5 个 text-button 触底 overflow，
                    // 加本按钮需 94px 空间，所以只在 >=900 才放；窄屏与中等宽
                    // 由全屏 Dialog 悬浮面板承接。
                    // v2.12.0+2 fix（回归）：900-1039 降级为 icon-only
                    // （tooltip 承载说明，与窄屏图标位同模式），>=1040 才放
                    // 文字标签——否则宽屏含导航 Rail 时内容区仅 ~887px，
                    // 5 个 text-button 溢出 21px（全测 3 截图 + ☰ 用例回归）。
                    if (onExportSvg != null &&
                        MediaQuery.sizeOf(context).width >= 900)
                      MediaQuery.sizeOf(context).width >= 1040
                          ? TextButton.icon(
                              onPressed: computed ? onExportSvg : null,
                              icon: Icon(Icons.copy_all_outlined,
                                  size: 18, color: AppColors.ink),
                              label: Text('复制 SVG',
                                  style: TextStyle(
                                      color: AppColors.ink,
                                      fontWeight: FontWeight.w600)),
                            )
                          : IconButton(
                              tooltip: '复制 SVG',
                              onPressed: computed ? onExportSvg : null,
                              icon: Icon(Icons.copy_all_outlined,
                                  size: 18, color: AppColors.ink),
                            ),
                  ],
                ),
              ),
            ),
          ),
        ],
        ],
      ),
    );
  }
}
