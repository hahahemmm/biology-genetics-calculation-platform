// laser_pointer_layer.dart —— 课堂模式激光笔光标层（v2.3）
//
// 面向教师在教室大屏/电子白板讲课：指针（鼠标/触控笔/手指）划过画布时，
// 留下红色光点 + 约 0.8 秒渐隐轨迹（GoodNotes 演示模式同款交互），
// 帮助全班学生跟随讲解者视线。
//
// 设计要点：
// - 独立 StatefulWidget 自管轨迹与渐隐定时器——指针移动只重绘本层的
//   小 CustomPaint，不触发下层系谱画布的 _computeLayout 重算。
// - Listener(behavior: translucent)：只"旁听"指针事件，不消费，
//   下层 GestureDetector 的点按/拖线/缩放手势完全不受影响。
// - 触控白板适配（用户场景 2026-08-29：2~3 平米吸墨白板，老师用手指
//   直接点，指针不是连续移动的鼠标而是"随机瞬移"）：轨迹是离散圆点
//   序列、**从不连线插值**——手指瞬移到新位置只在新位置出现一个光点，
//   不会拖出横贯屏幕的轨迹线；手指抬起（onPointerUp）后最后一个光点
//   随轨迹一起 0.8s 渐隐，屏幕自动恢复干净。
// - 由父级在课堂模式且激光笔开关开启时才挂入 Stack（关闭时零开销）。

import 'dart:async';

import 'package:flutter/material.dart';

class LaserPointerLayer extends StatefulWidget {
  const LaserPointerLayer({super.key});

  @override
  State<LaserPointerLayer> createState() => _LaserPointerLayerState();
}

class _LaserPointerLayerState extends State<LaserPointerLayer> {
  /// 轨迹点：视口坐标 + 记录时刻。
  final List<({Offset pos, DateTime t})> _trail = [];

  /// 渐隐驱动：有轨迹时才跑的 33ms 定时器；轨迹清空后自停。
  Timer? _fadeTimer;

  /// 轨迹寿命（GoodNotes 激光笔轨迹约 1 秒消失）。
  static const Duration _lifetime = Duration(milliseconds: 800);

  @override
  void dispose() {
    _fadeTimer?.cancel();
    super.dispose();
  }

  void _addPoint(Offset pos) {
    _trail.add((pos: pos, t: DateTime.now()));
    // 上限保护：快速乱划时轨迹最多 120 点。
    if (_trail.length > 120) _trail.removeAt(0);
    _fadeTimer ??= Timer.periodic(const Duration(milliseconds: 33), (_) {
      final now = DateTime.now();
      _trail.removeWhere(
          (p) => now.difference(p.t).compareTo(_lifetime) > 0);
      if (_trail.isEmpty) {
        _fadeTimer?.cancel();
        _fadeTimer = null;
      }
      if (mounted) setState(() {});
    });
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent, // 只旁听，不消费手势
      onPointerHover: (e) => _addPoint(e.localPosition),
      onPointerMove: (e) => _addPoint(e.localPosition),
      onPointerDown: (e) => _addPoint(e.localPosition),
      // 手指/笔抬起：补最后一个落点光点（白板触控没有 hover，
      // down/up 是主要事件），随后随轨迹自然渐隐。
      onPointerUp: (e) => _addPoint(e.localPosition),
      child: CustomPaint(
        foregroundPainter: _LaserPainter(_trail, _lifetime),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _LaserPainter extends CustomPainter {
  _LaserPainter(this.trail, this.lifetime);

  final List<({Offset pos, DateTime t})> trail;
  final Duration lifetime;

  @override
  void paint(Canvas canvas, Size size) {
    if (trail.isEmpty) return;
    final now = DateTime.now();
    final paint = Paint()..style = PaintingStyle.fill;

    // 轨迹：越早的点越小越透明。
    // v2.3.4 大屏投影可视性：希沃/鸿合白板几平米大、投影仪吃亮度，
    // 光点整体放大一档（10→13 / 16→22 / 5.5→7），轨迹不透明度上调。
    for (final p in trail) {
      final age = now.difference(p.t).inMilliseconds / lifetime.inMilliseconds;
      if (age >= 1) continue;
      final alpha = (1 - age) * 0.5;
      final radius = 13 * (1 - age * 0.6);
      paint
        ..color = const Color(0xFFFF3B30).withValues(alpha: alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
      canvas.drawCircle(p.pos, radius, paint);
    }

    // 头部光点：亮核 + 外圈光晕，醒目但不遮内容。
    final head = trail.last.pos;
    paint
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12)
      ..color = const Color(0xFFFF3B30).withValues(alpha: 0.6);
    canvas.drawCircle(head, 22, paint);
    paint
      ..maskFilter = null
      ..color = const Color(0xFFFF3B30);
    canvas.drawCircle(head, 7, paint);
    paint.color = Colors.white.withValues(alpha: 0.9);
    canvas.drawCircle(head, 2.8, paint);
  }

  @override
  bool shouldRepaint(covariant _LaserPainter oldDelegate) => true;
}
