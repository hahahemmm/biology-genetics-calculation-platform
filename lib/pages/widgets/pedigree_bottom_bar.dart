// pedigree_bottom_bar.dart —— 系谱页底部操作条（2.3 重构阶段 5 抽取）
//
// 从 genetic_pedigree_page.dart 抽出，纯展示组件：删除整代 / 计算下一代 /
// 「计算」主按钮的可用态与动作由页面注入。行为与抽取前逐行一致
// （「删除整代」「计算下一代」「计算」文案与 GuideKeys.pedigreeCalc
// 高亮 key 是测试/新手引导依赖）。

import 'package:flutter/material.dart';

import '../../guide/guide_keys.dart';
import '../../theme.dart';
import 'pedigree_chip_tooltips.dart';

/// v3.2 底部操作条：页面最底端、与「问 AI」FAB 同层。
/// v2.17 课堂白板可达性重做：学校白板几米长，老师几乎够不到屏幕
/// 上半部——所有高频操作必须落在底缘可达区。画布编辑操作
/// （模式 segmented / 添加家族 / 添加样本）从顶栏/侧栏统一收编到
/// 本底栏左组；左 =「删除整代」（破坏性，离主操作最远）；
/// 右 =「计算下一代」+「计算」主按钮（最靠右缘 = 最顺手，
/// 与全局「问 AI」FAB 同侧）。右侧预留 FAB 悬浮区（约 128px）。
class PedigreeBottomBar extends StatelessWidget {
  const PedigreeBottomBar({
    super.key,
    required this.engineAlive,
    required this.onDeleteGeneration,
    required this.onExpandNext,
    required this.onDerive,
    // v2.17：画布编辑组（>=1200 逻辑宽收编：文字版 + 全屏；更窄由
    // 侧栏 legacy 区承接——空间测算见 build 注释）。
    required this.wireModeOn,
    required this.onToggleWireMode,
    required this.selecting,
    required this.focusing,
    required this.pickedCount,
    // v2.19.6 菜单化：选择元素（持续选择）/ 只看所选（应用聚焦）/
    // 显示全部（恢复全部）。
    required this.onEnterSelect,
    required this.onApplyFocus,
    required this.onShowAll,
    // v3.6 智能密线：「全部连线」视图开关（默认关 = 只留主干与选中相关边）。
    required this.allEdgesOn,
    required this.onToggleAllEdges,
    // v2.19.2 R8 教师走查 #1：「曲线连线」开关原在侧栏 chip 堆
    // （白板左缘中段够不到 + 紧邻「回交线」易误触）——并入底栏
    // 模式 segmented（≥1200 时同排），白板抬手即触。
    required this.curveLinesOn,
    required this.onToggleCurveLines,
    required this.onAddFamily,
    required this.onAddSample,
    required this.onFullscreen,
    // v2.18 R8 老师走查 #6：顶栏四按钮（日志/历史/杂交计算/复制 SVG）
    // 在大屏白板上物理不可达且无第二入口——底栏 ⋯ 收纳为底缘
    // second entry（>=720 渲染；桌面顶栏保留原样）。
    required this.onShowLog,
    required this.onShowHistory,
    required this.onToggleCrossPanel,
    required this.onExportSvg,
    // O-6 同性交配开关底栏第二入口（白板可达 + 触屏即按）：>=1280 渲染
    // IconButton（图标+tooltip，无 Text 控件 → 不与侧栏同 label 的
    // find.text('同性交配') 冲突）；<1280 由侧栏 ⋯ chip 承接。
    // 阈值 1280 是 O-6 实测：1200 viewport 下底栏左编辑组（>=1200
    // 才显示）+ 右簇相加 ≈ 1052.7 px，已溢出 0.7 px 触发黄黑斜条
    // 覆盖侧栏 chip 导致 R18/R21 hit test 失败。
    required this.allowSameSex,
    required this.onToggleSameSex,
  });

  /// 引擎存在（未计算时「删除整代」「计算下一代」「添加家族/样本」禁用）。
  final bool engineAlive;
  final VoidCallback onDeleteGeneration;
  final VoidCallback onExpandNext;
  final VoidCallback onDerive;

  // ── v2.17 画布编辑组 ──
  final bool wireModeOn;
  final VoidCallback onToggleWireMode;
  final bool selecting;
  final bool focusing;
  final int pickedCount;
  /// v2.19.6 菜单化：选择元素（持续选择）/ 只看所选（应用聚焦）/
  /// 显示全部（恢复全部）。
  final VoidCallback onEnterSelect;
  final VoidCallback onApplyFocus;
  final VoidCallback onShowAll;

  /// v3.6 智能密线开关（true = 全部自动连线原样铺开）。
  final bool allEdgesOn;
  final VoidCallback onToggleAllEdges;
  final bool curveLinesOn;
  final ValueChanged<bool> onToggleCurveLines;
  final VoidCallback onAddFamily;
  final VoidCallback onAddSample;
  final VoidCallback onFullscreen;

  // ── v2.18 R8：⋯ 更多（顶栏四按钮的底缘第二入口） ──
  final VoidCallback onShowLog;
  final VoidCallback onShowHistory;
  final VoidCallback onToggleCrossPanel;
  final VoidCallback onExportSvg;

  // ── O-6：同性交配开关底栏第二入口（白板可达） ──
  final bool allowSameSex;
  final ValueChanged<bool> onToggleSameSex;

  @override
  Widget build(BuildContext context) {
    // v2.18 R7 老师走查 #1/#2：课堂模式全局主题把按钮抬到 52px
    // （main.dart 白板增强），底栏固定 62/44 内容区会溢出、写死的
    // 40px minimumSize 又顶掉主题反而更小。高度随 textScaler 伸缩
    // （课堂 ×1.3 → ~81，内容区 ~63 ≥ 52），全部按钮删显式尺寸
    // 让主题统一接管（标准 40 / 课堂 52）。
    final barH = 62 * MediaQuery.textScalerOf(context).scale(1.0);
    return Container(
      height: barH,
      padding: const EdgeInsets.fromLTRB(20, 9, 128, 9),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
        // v2.21.0：只加顶部圆角；高度、按钮、阈值与滚动不变。
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppTheme.radiusCard)),
      ),
      child: Row(
        children: [
          // ── 左簇：可滚动画布编辑区 ──
          // v2.19.13（老师找茬 🔴1）：52px 加肉 + O-6 挪入后左簇在
          // 课堂模式 1280 下超宽 ~144px，原实现无溢出兜底 → release
          // 无声裁掉右侧计算按钮（debug 黄黑条老师/学生看不见）。
          // 改 Expanded + 横向滚动：左簇超宽可拖滚，右簇计算按钮
          // 永远完整可见。删除整代并入左簇。
          // v2.19.15（DeepSeek 找茬 🟡4 尝试记录）：Scrollbar 提示可滚
          // 曾在此实现，但底栏是 StatelessWidget 无法持有 ScrollController
          // （默认 PrimaryScrollController 被全 app 竖向 ScrollView 共享
          // → thumbVisibility 断言崩溃、52 测试连带红）；改 Stateful
          // 重构收益不抵风险，本项降级不修——「删除整代」滚出后可用
          // 底缘横拖找回，记为已知限制。
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
              // >=1200 逻辑宽才收编（实测全组 ~910px：1080p@150% 缩放
              // =1280 逻辑 ✓ 可容纳；再窄会让「计算」主按钮没位置）。
              if (MediaQuery.sizeOf(context).width >= 1200) ...[
                _modeSegmented(),
                const SizedBox(width: 10),
                // v2.19.13（老师找茬 🟡6）：O-6 同性交配开关从右簇（计算
                // 下一代旁）挪到左簇编辑区——原位置与「计算下一代」共享
                // 按钮主题可点区，12px 缓冲被溢出侵入，误触后果 = 整图
                // 同性边被清；挪到编辑区后远离计算簇，且语义上属「规则」
                // 与模式 segmented 同类。
                if (MediaQuery.sizeOf(context).width >= 1280) ...[
                  _sameSexToggleCompact(),
                  const SizedBox(width: 10),
                ],
                FilledButton.icon(
                  onPressed: engineAlive ? onAddFamily : null,
                  icon: const Icon(Icons.groups_outlined, size: 17),
                  label: const Text('添加家族'),
                  // 不写 minimumSize——课堂主题自动抬到 52（R7 #2）。
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                ),
                const SizedBox(width: 6),
                OutlinedButton.icon(
                  onPressed: engineAlive ? onAddSample : null,
                  icon: const Icon(Icons.person_add_alt, size: 16),
                  label: const Text('添加样本'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  tooltip: '全屏',
                  onPressed: onFullscreen,
                  icon: Icon(Icons.fullscreen,
                      size: 20, color: AppColors.graphite),
                ),
                const SizedBox(width: 8),
                Container(width: 1, height: 26, color: AppColors.border),
                const SizedBox(width: 12),
              ] else ...[
                // <1200：底栏不塞编辑组（空间不够），画布操作由侧栏
                // legacy 区承接（PedigreeSidePanel，<1200 && computed）。
              ],
              if (MediaQuery.sizeOf(context).width >= 560)
                OutlinedButton.icon(
                  onPressed: engineAlive ? onDeleteGeneration : null,
                  icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                  label: const Text('删除整代'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.lethal,
                    side: BorderSide(color: AppColors.lethal),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                )
              else
                IconButton(
                  tooltip: '删除整代',
                  onPressed: engineAlive ? onDeleteGeneration : null,
                  icon: Icon(Icons.delete_sweep_outlined,
                      size: 20, color: AppColors.lethal),
                ),
              // v2.19.3 重排：破坏性按钮孤立左区，「计算下一代」并入右侧
              // 计算簇（计算类相邻，R7 #12 的 graphite 描边与主按钮拉开）。

                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (MediaQuery.sizeOf(context).width >= 480)
            OutlinedButton.icon(
              onPressed: engineAlive ? onExpandNext : null,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('计算下一代'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.graphite,
                side: BorderSide(color: AppColors.graphite),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
            )
          else
            IconButton(
              onPressed: engineAlive ? onExpandNext : null,
              icon: Icon(Icons.add, size: 20, color: AppColors.graphite),
              tooltip: '计算下一代',
            ),
          const SizedBox(width: 8),
          // v2.19.13（老师找茬 🟡6）：O-6 开关已挪到左簇编辑区（远离
          // 计算簇），右簇不再渲染。原 12px 缓冲方案废弃（按钮可点区
          // 溢出侵入缓冲，治标不治本）。
          // R8 老师走查 #6：⋯ 更多 = 日志/历史/杂交计算/复制 SVG 的
          // 底缘第二入口（顶栏在几米白板够不到）。>=720 才有空间。
          if (MediaQuery.sizeOf(context).width >= 720)
            IconButton(
              tooltip: '更多（日志 / 历史 / 杂交计算 / 复制 SVG）',
              onPressed: () => _showMoreSheet(context),
              icon: Icon(Icons.more_horiz,
                  size: 22, color: AppColors.graphite),
            ),
          const SizedBox(width: 8),
          FilledButton.icon(
            key: GuideKeys.pedigreeCalc, // 新手引导高亮目标
            onPressed: onDerive,
            icon: const Icon(Icons.account_tree, size: 18),
            label: const Text('计算'),
          ),
        ],
      ),
    );
  }

  /// ⋯ 更多：顶栏四动作的底缘收纳（白板可达——底部弹出抬手即触）。
  /// O-6 同性交配开关（紧凑 IconButton 版，v2.19.13 从右簇挪到左簇
  /// 编辑区——远离计算簇防误触）。开关态由 allowSameSex 注入，teal =
  /// 激活态（与「曲线」开态色一致；不取 armed 避免「开」画成告警色）。
  Widget _sameSexToggleCompact() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: allowSameSex ? AppColors.tealWash : Colors.transparent,
        border: Border.all(
          color: allowSameSex ? AppColors.teal : AppColors.border,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: IconButton(
        // v2.19.6 polish：tooltip 与侧栏 chip 同源后果导向文案。
        tooltip: allowSameSex ? sameSexTooltipOn : sameSexTooltipOff,
        onPressed: () => onToggleSameSex(!allowSameSex),
        icon: Icon(
          Icons.transgender,
          size: 20,
          color: allowSameSex ? AppColors.teal : AppColors.graphite,
        ),
      ),
    );
  }

  void _showMoreSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.history, size: 20, color: AppColors.ink),
              title: const Text('操作日志'),
              onTap: () {
                Navigator.of(ctx).pop();
                onShowLog();
              },
            ),
            ListTile(
              leading: Icon(Icons.auto_stories_outlined,
                  size: 20, color: AppColors.ink),
              title: const Text('计算历史'),
              onTap: () {
                Navigator.of(ctx).pop();
                onShowHistory();
              },
            ),
            ListTile(
              leading: Icon(Icons.calculate_outlined,
                  size: 20, color: AppColors.teal),
              title: const Text('杂交计算（9331 面板）'),
              onTap: () {
                Navigator.of(ctx).pop();
                onToggleCrossPanel();
              },
            ),
            ListTile(
              leading: Icon(Icons.copy_all_outlined,
                  size: 20, color: AppColors.ink),
              title: const Text('复制 SVG（板书）'),
              onTap: () {
                Navigator.of(ctx).pop();
                onExportSvg();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// v2.19.6 模式 segmented：连线 / 选择元素（持续选择，菜单化）/
  /// 只看所选（应用聚焦）/ 显示全部（恢复全部）/ 全部连线（密线开关）。
  /// 「选择元素」选择中再点 = 保持（不打断）；文案 '连线'/'选择元素' 是
  /// 测试依赖。
  Widget _modeSegmented() {
    final wireOn = wireModeOn;
    final selLabel =
        selecting && pickedCount > 0 ? '选择元素（$pickedCount）' : '选择元素';
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.surfaceLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          FilterChip(
            // v3.7 新手引导高亮目标（底栏「连线」；<1200 宽由左栏模式区
            // 的同名 chip 承接，见 PedigreeSidePanel._wireModeChip）。
            key: GuideKeys.pedigreeWireBtn,
            label: const Text('连线'),
            selected: wireOn,
            onSelected: (_) => onToggleWireMode(),
            backgroundColor: Colors.transparent,
            selectedColor: AppColors.armed,
            labelStyle: TextStyle(
                color: wireOn ? AppColors.onTeal : AppColors.ink,
                fontWeight: FontWeight.w600),
            side: const BorderSide(color: Colors.transparent),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
            elevation: 0,
          ),
          const SizedBox(width: 2),
          FilterChip(
            label: Text(selLabel),
            tooltip: '选择元素：进入后可持续加选/取消，不会被中断；'
                '选好后点「只看所选」应用聚焦',
            selected: selecting,
            onSelected: (_) => onEnterSelect(),
            backgroundColor: Colors.transparent,
            selectedColor: AppColors.teal,
            labelStyle: TextStyle(
                color: selecting ? AppColors.onTeal : AppColors.ink,
                fontWeight: FontWeight.w600),
            side: const BorderSide(color: Colors.transparent),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
            elevation: 0,
          ),
          // v3.6 语义拆分：有勾选才出现「只看所选（N）」= 应用聚焦。
          // ⛔ 选择空集时没有这颗按钮（不再出现「显示全部」却把东西藏起来）。
          if (selecting && pickedCount > 0) ...[
            const SizedBox(width: 2),
            FilterChip(
              label: Text('只看所选（$pickedCount）'),
              tooltip: '应用聚焦：只显示所选元素；聚焦后点「显示全部」恢复',
              selected: false,
              onSelected: (_) => onApplyFocus(),
              backgroundColor: Colors.transparent,
              selectedColor: AppColors.teal,
              labelStyle: TextStyle(
                  color: AppColors.ink, fontWeight: FontWeight.w600),
              side: const BorderSide(color: Colors.transparent),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7)),
              elevation: 0,
            ),
          ],
          // 聚焦中才出现「显示全部」= 只清聚焦集合（不展开各代）。
          if (focusing) ...[
            const SizedBox(width: 2),
            FilterChip(
              label: const Text('显示全部'),
              tooltip: '恢复全部元素可见（各代折叠状态保持不变）',
              selected: true,
              onSelected: (_) => onShowAll(),
              backgroundColor: Colors.transparent,
              selectedColor: AppColors.teal,
              labelStyle: TextStyle(
                  color: AppColors.onTeal, fontWeight: FontWeight.w600),
              side: const BorderSide(color: Colors.transparent),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7)),
              elevation: 0,
            ),
          ],
          // v3.6 智能密线：与「显示全部」（聚焦恢复）是两个动作——
          // 这里恢复的是被抽稀的自动连线。
          const SizedBox(width: 2),
          FilterChip(
            label: const Text('全部连线'),
            tooltip: allEdgesOn
                ? '当前铺满全部自动连线；点一下回到智能密线'
                : '智能密线：收起未聚焦的自动连线，只留主干与选中相关的线',
            selected: allEdgesOn,
            onSelected: (_) => onToggleAllEdges(),
            backgroundColor: Colors.transparent,
            selectedColor: AppColors.teal,
            labelStyle: TextStyle(
                color: allEdgesOn ? AppColors.onTeal : AppColors.ink,
                fontWeight: FontWeight.w600),
            side: const BorderSide(color: Colors.transparent),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
            elevation: 0,
          ),
          // v2.19.2：曲线开关并入底栏（白板可达）。
          const SizedBox(width: 2),
          FilterChip(
            label: const Text('曲线'),
            tooltip: '曲线连线：配偶线画弧、回交线画 S；主干线保持正交；'
                '板书导出仍为正交',
            selected: curveLinesOn,
            onSelected: onToggleCurveLines,
            backgroundColor: Colors.transparent,
            selectedColor: AppColors.teal,
            labelStyle: TextStyle(
                color: curveLinesOn ? AppColors.onTeal : AppColors.ink,
                fontWeight: FontWeight.w600),
            side: const BorderSide(color: Colors.transparent),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
            elevation: 0,
          ),
        ],
      ),
    );
  }
}
