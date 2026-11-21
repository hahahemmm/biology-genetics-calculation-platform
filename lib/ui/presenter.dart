// presenter.dart —— 通用全屏放映壳（v2.7 课堂讲解优化；v2.8 内嵌聚光灯）
//
// 从板书放映（cross_board.dart）抽出的通用壳：暗底 + 纯净内容区
// （InteractiveViewer 双指缩放/拖动）+ 右上工具（聚光灯 + 关闭）
// + 点空白/Esc 退出。任意内容都可放映：
//   - showWidgetPresenter：活 widget（板书棋盘等矢量内容，缩放不糊）
//   - showImagePresenter：PNG 位图（系谱画布等截图放映）
//
// v2.8 白板教鞭适配：放映内嵌聚光灯（对象化 SpotlightLayer——点哪亮哪、
// 按住拖动、边缘调大小，对齐希沃/ViewSonic 白板惯例）。放映+聚光灯构成
// 讲课核心闭环：全屏呈现 → 教鞭点哪 → 全班注意力压到该处。
// 放映内聚光灯是对话框局部状态，与画布聚光灯（全局 spotlightOn）互不干扰。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../pages/widgets/spotlight_layer.dart';
import '../theme.dart';

/// 通用全屏放映壳（widget 版）。内容区可双指缩放/平移。
Future<void> showWidgetPresenter(BuildContext context,
    {required Widget child}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '退出放映',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    pageBuilder: (ctx, anim, secondary) => _PresenterDialog(child: child),
  );
}

/// 全屏放映（PNG 位图版）：系谱画布等截图放映用。
/// 位图经 InteractiveViewer 缩放，2.5x 截图在 1080p 白板上足够清晰。
Future<void> showImagePresenter(BuildContext context,
    {required Uint8List pngBytes}) {
  return showWidgetPresenter(
    context,
    child: Image.memory(pngBytes, fit: BoxFit.contain),
  );
}

class _PresenterDialog extends StatefulWidget {
  final Widget child;
  const _PresenterDialog({required this.child});

  @override
  State<_PresenterDialog> createState() => _PresenterDialogState();
}

class _PresenterDialogState extends State<_PresenterDialog> {
  /// 放映内聚光灯（对话框局部状态，v2.8 白板教鞭对象化）。
  bool _spotlight = false;

  /// v2.13 UI 走查 P0：首次进入放映浮出退出提示（3 秒自动消失）——
  /// 大屏触屏老师不用键盘，ESC 提示不可见，3 秒内找不到退出路径。
  bool _showHint = true;
  Timer? _hintTimer;

  @override
  void initState() {
    super.initState();
    _hintTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showHint = false);
    });
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.canvas,
      child: SafeArea(
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.of(context).pop(),
          },
          child: Focus(
            autofocus: true,
            child: Stack(
              children: [
                Positioned.fill(
                  child: InteractiveViewer(
                    maxScale: 3,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(48),
                        child: widget.child,
                      ),
                    ),
                  ),
                ),
                // v2.8：放映内聚光灯（对象化：点哪亮哪/按住拖动/边缘调大小；
                // 只吃亮区抓取区手势，不影响内容区缩放平移）
                Positioned.fill(child: SpotlightLayer(active: _spotlight)),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Row(
                    children: [
                      IconButton.filled(
                        tooltip: _spotlight ? '关闭聚光灯' : '聚光灯：点哪亮哪，拖边缘调大小',
                        onPressed: () =>
                            setState(() => _spotlight = !_spotlight),
                        icon: Icon(
                            _spotlight
                                ? Icons.highlight
                                : Icons.highlight_outlined,
                            size: 20),
                        style: IconButton.styleFrom(
                            backgroundColor:
                                _spotlight ? AppColors.armed : AppColors.steel,
                            // v2.12 单一事实源: 浅色 white / 暗色墨绿,
                            // 与 ColorScheme.onPrimary 对齐
                            foregroundColor: AppColors.onTeal),
                      ),
                      const SizedBox(width: 8),
                      // 文字按钮（非纯图标）：大屏上「退出」二字比 × 图标
                      // 一眼可辨，降低误点聚光灯当退出的概率（UI 走查 P1）。
                      // Tooltip 包裹（FilledButton.icon 无 tooltip 参数）。
                      Tooltip(
                        message: '退出放映',
                        child: FilledButton.icon(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close, size: 22),
                          label: const Text('退出'),
                          style: FilledButton.styleFrom(
                              backgroundColor: AppColors.teal,
                              // v2.12 单一事实源: 浅色 white / 暗色墨绿,
                              // 与 ColorScheme.onPrimary 对齐
                              foregroundColor: AppColors.onTeal),
                        ),
                      ),
                    ],
                  ),
                ),
                // v2.13：首入退出提示（3 秒自动淡出；IgnorePointer 不挡手势）。
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 24,
                  child: AnimatedOpacity(
                    opacity: _showHint ? 1 : 0,
                    duration: const Duration(milliseconds: 400),
                    child: IgnorePointer(
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(20),
                            border:
                                Border.all(color: AppColors.border),
                          ),
                          child: Text(
                            '点空白处或右上角「退出」离开放映',
                            style: AppText.caption
                                .copyWith(color: AppColors.ink),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
