// spotlight_layer.dart —— 课堂模式聚光灯层（v2.3 初版；v2.8 白板教鞭对象化重做）
//
// 场景：教师在巨型触控白板讲课，需要把全班注意力压到当前讲解的局部
// 区域（一只桶、一条连线）。
//
// v2.8 重做原因（用户实锤 + 业界调研对齐希沃/ViewSonic）：
// 白板触控没有可持续跟踪的指针——教鞭点击映射成的"鼠标"是瞬移的，
// 「跟随 hover/pointer」模型在白板上不成立。业界标准做法：聚光灯是一个
// **可操作对象**——点哪亮哪、按住拖动、拖边缘调大小、不关就一直停住。
//
// 交互模型（对齐希沃白板/ViewSonic myViewBoard）：
//   - 亮区圆内按住拖动 → 移动亮区（手指真实轨迹，非瞬移鼠标跟随）
//   - 亮区边缘环带（±22px）按住拖动 → 调半径（径向分量增减）
//   - 亮区以外手势完全穿透给画布（点节点/拖画布不受聚光灯影响）
//   - hover 不再移动亮区（桌面鼠标划过错位的旧行为根除）
//   - 松手停住；关闭走画布缩放条/课堂快捷条的开关（双击退出不做）
//
// 实现：视觉层 IgnorePointer 不吃手势；只有亮区外接正方形挂
// GestureDetector(opaque) 吃手势——这是与旧版 translucent 全场旁听
// （画布每次点按都把亮区拽跑）的关键区别。

import 'dart:math' as math;

import 'package:flutter/material.dart';

class SpotlightLayer extends StatefulWidget {
  const SpotlightLayer({super.key, required this.active});

  /// 聚光灯是否生效（课堂模式开关 × 画布工具栏开关在父级相与）。
  final bool active;

  @override
  State<SpotlightLayer> createState() => SpotlightLayerState();
}

class SpotlightLayerState extends State<SpotlightLayer> {
  /// 亮区圆心（视口坐标）；null = 默认居中。
  Offset? _center;

  /// 亮区半径；null = 默认画布短边 22%。
  double? _radius;

  /// 当前拖动模式：true=拖边缘调半径，false=拖圆内移动。
  bool _resizing = false;

  /// 调半径时按下点的径向单位向量（半径增减 = delta 在该方向的分量）。
  Offset _radialDir = Offset.zero;

  /// 边缘环带判定宽度（白板手指/教鞭的容错，约等于 52px 触控目标的一半）。
  /// 基值 22；实际宽度按 textScaler 缩放——课堂 ×1.3 下教鞭点按容错须
  /// 与全局字号同步放大（v2.13 UI 走查 P0：硬编码逻辑像素导致 ×1.3 下
  /// 抓取区相对变小）。
  static const double _rimBand = 22;

  /// 半径下限（再小就装不下一个格子的内容）与上限系数。基值 48，同上缩放。
  static const double _minRadius = 48;
  static const double _maxRadiusFactor = 0.48;

  /// 测试/调试：当前亮区圆心与半径。
  Offset? get debugCenter => _center;
  double? get debugRadius => _radius;

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        // v2.13：环带/半径下限/默认半径随 textScaler 缩放（课堂 ×1.3
        // 下教鞭容错同步放大）；标准模式 scaler=1.0 行为不变。
        final scaler = MediaQuery.textScalerOf(ctx);
        final rimBand = scaler.scale(_rimBand);
        final minRadius = scaler.scale(_minRadius);
        final c = _center ?? size.center(Offset.zero);
        final r = _radius ?? scaler.scale(size.shortestSide * 0.22);
        // 手势抓取区 = 亮区半径 + 环带宽度外扩——边缘环带的外半侧必须也在
        // 抓取区内（否则点按正好落在圆边界上的拖动会漏出命中盒）。
        final grab = r + rimBand;
        return Stack(
          children: [
            // 视觉层：不吃手势（亮区移动/缩放由下面的手势区负责）
            IgnorePointer(
              child: CustomPaint(
                painter: _SpotlightPainter(c, r, scaler.scale(1.0)),
                child: const SizedBox.expand(),
              ),
            ),
            // 手势区：只有亮区外接正方形（含环带）吃手势；画布其余区域手势穿透
            Positioned(
              left: c.dx - grab,
              top: c.dy - grab,
              width: grab * 2,
              height: grab * 2,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (d) {
                  final local = d.localPosition - Offset(grab, grab);
                  final dist = local.distance;
                  _resizing = (dist - r).abs() <= rimBand;
                  _radialDir =
                      dist > 0 ? local / dist : const Offset(1, 0);
                },
                onPanUpdate: (d) {
                  setState(() {
                    if (_resizing) {
                      final delta = d.delta.dx * _radialDir.dx +
                          d.delta.dy * _radialDir.dy;
                      _radius = (r + delta).clamp(
                          minRadius, size.shortestSide * _maxRadiusFactor);
                    } else {
                      _center = c + d.delta;
                    }
                  });
                },
                child: Container(color: Colors.transparent),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  _SpotlightPainter(this.center, this.radius, this.strokeScale);

  final Offset center;
  final double radius;

  /// v2.13：描边/刻度随 textScaler 的缩放系数（标准模式 = 1.0 不变）。
  final double strokeScale;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.saveLayer(rect, Paint());
    // 压暗全场（54% 黑，内容仍隐约可辨，不会迷路）。
    canvas.drawRect(rect, Paint()..color = Colors.black.withValues(alpha: 0.54));
    // 挖亮区：clear 混合 + 大羽化边缘（柔和光圈，不是生硬圆孔）。
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..blendMode = BlendMode.clear
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.35),
    );
    canvas.restore();
    // 亮区描一圈细细的光边，帮学生定位光圈边界。
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 * strokeScale
        ..color = Colors.white.withValues(alpha: 0.65),
    );
    // 边缘环带视觉提示：光边外侧四点小刻度（示意"拖边缘可调大小"）。
    final tickPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3 * strokeScale
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.8);
    for (final deg in [45.0, 135.0, 225.0, 315.0]) {
      final rad = deg * math.pi / 180;
      final dir = Offset(math.cos(rad), math.sin(rad));
      final tickLen = 7 * strokeScale;
      canvas.drawLine(center + dir * (radius - tickLen),
          center + dir * (radius + tickLen), tickPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) =>
      oldDelegate.center != center || oldDelegate.radius != radius;
}
