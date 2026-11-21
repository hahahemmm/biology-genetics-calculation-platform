// guide_overlay.dart —— 新手引导 overlay 渲染（v2.2）
//
// 罩层（半透明 + evenOdd 挖孔高亮目标）+ 气泡说明卡（自动落在目标
// 上方或下方，clamp 在屏幕内）+ 步骤计数 + 上一步/下一步/跳过。
// 由 HomeShell 在 GuideController.active 时经 OverlayEntry 插入顶层
// Overlay（盖住 Rail/底导/FAB 一切内容）。
//
// 红线：本文件消费 AppColors/AppText 静态 token，所有构建在
// OverlayEntry.builder 内每次重建完成——不得 const 实例化。

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'guide_controller.dart';

class GuideOverlay extends StatelessWidget {
  const GuideOverlay({super.key, required this.wide});

  final bool wide;

  /// 取目标 widget 的全屏矩形；目标缺失（未挂 key / 未渲染）返回 null。
  Rect? _targetRect(GlobalKey? key) {
    final ctx = key?.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    final topLeft = box.localToGlobal(Offset.zero);
    return topLeft & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final g = GuideController.instance;
    final steps = g.stepsFor(wide: wide);
    final step = steps[g.stepIndex.clamp(0, steps.length - 1)];
    final size = MediaQuery.of(context).size;
    final rect = _targetRect(step.target)?.inflate(6); // 挖孔外扩 6px 呼吸感

    // 气泡位置：目标下半屏 → 气泡在上方；否则下方；无目标 → 居中。
    const bubbleW = 320.0;
    double bubbleLeft = (size.width - bubbleW) / 2;
    double bubbleTop;
    if (rect == null) {
      bubbleTop = size.height * 0.32;
    } else if (rect.center.dy > size.height * 0.55) {
      bubbleTop = math.max(16.0, rect.top - 190);
    } else {
      bubbleTop = math.min(size.height - 190, rect.bottom + 14);
    }
    // v2.19.30 兜底：气泡垂直方向统一 clamp 进屏——目标在视口外时
    // （懒构建缓存区 / 滚动动画起点）上面分支可算出屏外 top。
    bubbleTop = bubbleTop.clamp(12.0, math.max(12.0, size.height - 200));
    if (rect != null) {
      // 气泡水平尽量对齐目标中心，但 clamp 在屏幕内
      bubbleLeft = (rect.center.dx - bubbleW / 2)
          .clamp(12.0, math.max(12.0, size.width - bubbleW - 12));
    }

    return Material(
      type: MaterialType.transparency,
      child: SizedBox.expand(
        child: Stack(
          children: [
            // 罩层：点击不前进（防误触），只吸收
            Positioned.fill(
              child: GestureDetector(
                onTap: () {},
                child: CustomPaint(
                  painter: _HolePainter(rect: rect, circle: step.circle),
                ),
              ),
            ),
            Positioned(
              left: bubbleLeft,
              top: bubbleTop,
              width: bubbleW,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                            child:
                                Text(step.title, style: AppText.sectionTitle)),
                        Text('${g.stepIndex + 1} / ${steps.length}',
                            style: AppText.monoSmall
                                .copyWith(color: AppColors.steel)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(step.body, style: AppText.body),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        TextButton(
                          onPressed: g.skip,
                          child: Text('跳过',
                              style: TextStyle(color: AppColors.steel)),
                        ),
                        const Spacer(),
                        if (g.stepIndex > 0)
                          TextButton(
                            onPressed: g.back,
                            child: const Text('上一步'),
                          ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () => g.next(wide: wide),
                          child: Text(g.stepIndex >= steps.length - 1
                              ? '完成'
                              : '下一步'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 半透明罩 + evenOdd 挖孔（目标区透明高亮）。
class _HolePainter extends CustomPainter {
  final Rect? rect;
  final bool circle;
  _HolePainter({required this.rect, required this.circle});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..addRect(Offset.zero & size);
    final r = rect;
    if (r != null) {
      if (circle) {
        path.addOval(r);
      } else {
        path.addRRect(RRect.fromRectAndRadius(r, const Radius.circular(14)));
      }
    }
    path.fillType = PathFillType.evenOdd;
    canvas.drawPath(path, Paint()..color = Colors.black.withValues(alpha: 0.62));
    // 目标描边：teal 细环，让高亮区更醒目
    if (r != null) {
      final ring = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = AppColors.teal;
      if (circle) {
        canvas.drawOval(r, ring);
      } else {
        canvas.drawRRect(
            RRect.fromRectAndRadius(r, const Radius.circular(14)), ring);
      }
    }
  }

  @override
  bool shouldRepaint(_HolePainter old) =>
      old.rect != rect || old.circle != circle;
}
