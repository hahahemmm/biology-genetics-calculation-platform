// svg_export.dart —— 系谱图板书 SVG 导出（v2.12 Wave 3-A 板书 PDF 基础件）
//
// 场景：老师在课堂演示模式画完系谱图后，把当前节点/边序列化成
// 标准 SVG XML，可直接：①在浏览器打开查看；②在 headless Chromium
// 渲染打印为 PDF；③嵌入 LaTeX/Word 板书。
//
// 设计要点：
// - 纯字符串拼接，**不依赖 Flutter / dart:io**。三端通用（Web
//   也能直接拿到字符串再交给 dart:html 或 JS PDF 库）。
// - viewBox 自适应：横向按「最宽一代节点数 + 边距」算；纵向按
//   「代际行高 + 边距」算。无节点时输出占位 viewBox = "0 0 100 60"
//   + 一行提示文字，不抛异常。
// - 配色独立于 UI 主题（PDF 跨设备/打印稳定，色值不随明暗变）：
//     节点填充    white (#FFFFFF)        — 墨色 (#35322C) 描边
//     群体桶      tealWash (#E6EBE2)     — teal (#5C7265) 描边
//     lethal 描边 #FF8585（= theme.lethalD 0xFFFF8585）— 按任务
//              要求「lethal 用 stroke 标记」实现：在节点主描边
//              外再叠一层 lethal 描边 + ✕ 字符。
//     mating 边   ink (#35322C)
//     lineage 边  graphite (#5D594F)
//     文字        ink (#35322C)
// - 节点形状按 gender/种类区分（参考 PedigreeNodeKind）：
//     male    → 32×32 方形
//     female  → r=16 圆形
//     group   → 40×28 圆角矩形（r=6）
// - 布局：水平 = 同代内平铺（从左到右按 id 排序，稳定可复现）；
//         垂直 = 世代从上到下（gen=0 在顶，gen=max 在底）。
//   与系谱图传统一致，学生课后看图无认知负担。
// - 节点标签 = 基因型（mono 字体族；浏览器/PDF 渲染按系统 mono
//   fallback）。group 桶的标签在基因型后追加「: p%」（4 位小数
//   → 截 1 位 0% 精度，例如 0.25 → 25.0%）。
// - 边绘制顺序在节点之前——保证节点覆盖线段端点，视觉无毛刺。
//   严格按 (mating 先, lineage 后) 顺序：lineage 从父节点底部到
//   子节点顶部，mating 是同代节点间水平横线。
//
// 不引入第三方 XML 库（无意义开销），手写转义保证 SVG 合法。

import '../engine/pedigree_graph.dart';

/// 板书 SVG 导出工具。
class PedigreeSvg {
  PedigreeSvg._();

  // ── 几何常量（与 pedigree_painter 的视觉密度对齐）────────
  static const double _nodeSize = 32.0; // 方形/圆形主体尺寸
  static const double _groupW = 40.0; // 圆角矩形宽
  static const double _groupH = 28.0; // 圆角矩形高
  static const double _hGap = 48.0; // 同代节点水平间距
  static const double _vGap = 96.0; // 代际垂直间距（够 lineage 折线）
  static const double _margin = 32.0; // 画布外边距

  // 颜色 token（PDF 独立调色，不走 AppColors）
  static const String _ink = '#35322C';
  static const String _graphite = '#5D594F';
  static const String _white = '#FFFFFF';
  static const String _teal = '#5C7265';
  static const String _tealWash = '#E6EBE2';
  static const String _lethalStroke = '#FF8585'; // = theme.lethalD

  /// 节点 → SVG 元素。
  /// 计算节点外接矩形中心点坐标（同代均分水平 + 代际居中垂直）。
  /// [colIndex]：同代内列号（已由调用方按 id 排序写入）。
  static ({double cx, double cy, double w, double h, String shape}) _rect(
    PedigreeNode n,
    int colIndex,
    int generation,
  ) {
    final xSpacing = _nodeSize + _hGap;
    // 水平：同代均分；colIndex 从 0 起；第一格中点 = margin + xSpacing/2。
    final cx = _margin + xSpacing / 2 + colIndex * xSpacing;
    final cy = _margin + _nodeSize / 2 + generation * _vGap;
    switch (n.kind) {
      case PedigreeNodeKind.male:
        return (cx: cx, cy: cy, w: _nodeSize, h: _nodeSize, shape: 'rect');
      case PedigreeNodeKind.female:
        return (cx: cx, cy: cy, w: _nodeSize, h: _nodeSize, shape: 'circle');
      case PedigreeNodeKind.group:
        return (cx: cx, cy: cy, w: _groupW, h: _groupH, shape: 'group');
    }
  }

  /// 将 [nodes]/[edges] 序列化为标准 SVG XML。
  ///
  /// 始终返回合法 XML 字符串（即使 [nodes] 为空：返回占位 viewBox
  /// + 提示文字，绝不抛异常）。
  static String toSvg(
    List<PedigreeNode> nodes,
    List<PedigreeEdge> edges,
  ) {
    if (nodes.isEmpty) {
      return '<?xml version="1.0" encoding="UTF-8"?>\n'
          '<svg xmlns="http://www.w3.org/2000/svg" '
          'viewBox="0 0 100 60" width="100" height="60">\n'
          '  <text x="50" y="35" font-size="10" text-anchor="middle" '
          'fill="#5D594F" font-family="monospace">（空系谱）</text>\n'
          '</svg>\n';
    }

    // 1) 按 generation 分组 + 同代内按 id 排序（稳定可复现）。
    //    把「同代内列号」写进 colIndexOf：Map<id, colIndex>，
    //    不污染 PedigreeNode 不可变结构。
    final byGen = <int, List<PedigreeNode>>{};
    for (final n in nodes) {
      byGen.putIfAbsent(n.generation, () => <PedigreeNode>[]).add(n);
    }
    final colIndexOf = <String, int>{};
    byGen.forEach((_, list) {
      list.sort((a, b) => a.id.compareTo(b.id));
      for (var i = 0; i < list.length; i++) {
        colIndexOf[list[i].id] = i;
      }
    });

    // 2) 几何预计算。
    final maxNodesInGen =
        byGen.values.map((l) => l.length).reduce((a, b) => a > b ? a : b);
    final maxGen =
        byGen.keys.reduce((a, b) => a > b ? a : b);
    final width = _margin * 2 +
        maxNodesInGen * (_nodeSize + _hGap) -
        _hGap;
    final height = _margin * 2 + (maxGen + 1) * _vGap;

    // 3) 节点几何：缓存供边绘制复用。
    final geom = <String, ({double cx, double cy, double w, double h})>{};
    byGen.forEach((gen, list) {
      for (final n in list) {
        final r = _rect(n, colIndexOf[n.id] ?? 0, gen);
        geom[n.id] = (cx: r.cx, cy: r.cy, w: r.w, h: r.h);
      }
    });

    final buf = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
        '<svg xmlns="http://www.w3.org/2000/svg" '
        'viewBox="0 0 ${_num(width)} ${_num(height)}" '
        'width="${_num(width)}" height="${_num(height)}" '
        'font-family="monospace">',
      );

    // 4) 背景（白底，便于 PDF 嵌入无背景场景）。
    buf.writeln(
      '  <rect x="0" y="0" width="${_num(width)}" height="${_num(height)}" '
      'fill="#FFFFFF" stroke="none"/>',
    );

    // 5) 边：mating 在前（同代水平横线），lineage 在后（跨代纵向连线）。
    //    按 (kind 优先序, fromId 字母序) 排序，保证 SVG diff 稳定。
    final sortedEdges = [...edges]..sort((a, b) {
        final k = a.kind.index.compareTo(b.kind.index);
        if (k != 0) return k;
        final f = a.fromId.compareTo(b.fromId);
        if (f != 0) return f;
        return a.toId.compareTo(b.toId);
      });
    for (final e in sortedEdges) {
      final a = geom[e.fromId], b = geom[e.toId];
      if (a == null || b == null) continue; // 边端点缺失：跳过
      // v2.19：SVG 板书导出固定正交折线——屏幕上的「曲线连线」
      // （蜘蛛网手感）不镜像到板书（打印/手绘板书 crisp 优先，
      // 见 pedigree_side_panel 的「曲线连线」chip tooltip）。
      switch (e.kind) {
        case PedigreeEdgeKind.mating:
          // 水平横线：取两点 cy 平均作 y 坐标。
          final y = (a.cy + b.cy) / 2;
          final x1 = a.cx + a.w / 2;
          final x2 = b.cx - b.w / 2;
          buf.writeln(
            '  <line x1="${_num(x1)}" y1="${_num(y)}" '
            'x2="${_num(x2)}" y2="${_num(y)}" '
            'stroke="$_ink" stroke-width="1.5"/>',
          );
          break;
        case PedigreeEdgeKind.lineage:
          // 折线：父底 → 子顶，分两段（垂直下到中线 + 水平到子 cx + 垂直下到子顶）。
          final y1 = a.cy + a.h / 2; // 父节点底边
          final y2 = b.cy - b.h / 2; // 子节点顶边
          final midY = (y1 + y2) / 2;
          final pts = [
            [a.cx, y1],
            [a.cx, midY],
            [b.cx, midY],
            [b.cx, y2],
          ];
          final polyPoints = pts
              .map((p) => '${_num(p[0])},${_num(p[1])}')
              .join(' ');
          buf.writeln(
            '  <polyline points="$polyPoints" '
            'fill="none" stroke="$_graphite" stroke-width="1.5"/>',
          );
          break;
      }
    }

    // 6) 节点：先形状再标签；lethal 节点在主描边外再叠一层
    //    lethal 描边 + ✕ 字符。
    //    按 (generation, colIndex) 排序渲染，保证 SVG diff 稳定。
    final renderList = <PedigreeNode>[];
    byGen.forEach((_, list) => renderList.addAll(list));
    renderList.sort((a, b) {
      final g = a.generation.compareTo(b.generation);
      if (g != 0) return g;
      return (colIndexOf[a.id] ?? 0).compareTo(colIndexOf[b.id] ?? 0);
    });
    for (final n in renderList) {
      final g = geom[n.id]!;
      final cx = g.cx, cy = g.cy;
      final isLethal = n.isLethal;
      // 主形状
      switch (n.kind) {
        case PedigreeNodeKind.male:
          buf.writeln(_shapeRect(
              cx: cx, cy: cy, w: _nodeSize, h: _nodeSize, lethal: isLethal));
          break;
        case PedigreeNodeKind.female:
          buf.writeln(_shapeCircle(
              cx: cx, cy: cy, r: _nodeSize / 2, lethal: isLethal));
          break;
        case PedigreeNodeKind.group:
          buf.writeln(_shapeGroup(
              cx: cx, cy: cy, w: _groupW, h: _groupH, lethal: isLethal));
          break;
      }
      // lethal 叠层：再画一层 lethal 描边的同形状 + ✕
      if (isLethal) {
        switch (n.kind) {
          case PedigreeNodeKind.male:
            buf.writeln(
              '  <rect x="${_num(cx - _nodeSize / 2)}" '
              'y="${_num(cy - _nodeSize / 2)}" '
              'width="$_nodeSize" height="$_nodeSize" '
              'fill="none" stroke="$_lethalStroke" stroke-width="2.5" '
              'stroke-dasharray="3,2"/>',
            );
            break;
          case PedigreeNodeKind.female:
            buf.writeln(
              '  <circle cx="${_num(cx)}" cy="${_num(cy)}" '
              'r="${_num(_nodeSize / 2)}" '
              'fill="none" stroke="$_lethalStroke" stroke-width="2.5" '
              'stroke-dasharray="3,2"/>',
            );
            break;
          case PedigreeNodeKind.group:
            buf.writeln(
              '  <rect x="${_num(cx - _groupW / 2)}" '
              'y="${_num(cy - _groupH / 2)}" '
              'width="$_groupW" height="$_groupH" '
              'rx="6" ry="6" '
              'fill="none" stroke="$_lethalStroke" stroke-width="2.5" '
              'stroke-dasharray="3,2"/>',
            );
            break;
        }
        // 中心 ✕ 字符标记：与 painter 上「对角 X」语义一致；
        // SVG 用字符更易在浏览器/PDF 渲染保真。
        // 字号 = 节点半径 0.6 倍（与屏上 painter 的对角线视觉密度对齐）。
        // group 桶用 min(w,h)/2 兜底「半径」概念。
        final r = n.kind == PedigreeNodeKind.group
            ? (_groupW < _groupH ? _groupW : _groupH) / 2
            : _nodeSize / 2;
        final fontSize = r * 0.6;
        buf.writeln(
          '  <text x="${_num(cx)}" y="${_num(cy)}" '
          'font-size="${_num(fontSize)}" font-weight="700" '
          'text-anchor="middle" dominant-baseline="central" '
          'fill="$_lethalStroke" font-family="monospace">✕</text>',
        );
      }
      // 标签：基因型居中；group 追加概率。
      String label = _esc(n.genotype);
      if (n.kind == PedigreeNodeKind.group) {
        // 概率：0 概率（外来样本）显示 "-"，否则百分比 1 位小数。
        final p = n.probability;
        if (p <= 0) {
          label = '$label : -';
        } else {
          label = '$label : ${(p * 100).toStringAsFixed(1)}%';
        }
      }
      buf.writeln(
        '  <text x="${_num(cx)}" y="${_num(cy + 4)}" '
        'font-size="11" font-weight="600" '
        'text-anchor="middle" fill="$_ink" '
        'font-family="monospace">$label</text>',
      );
    }

    // 7) 代际标题（左侧 "P / F1 / F2 / …"）。
    for (var gen = 0; gen <= maxGen; gen++) {
      final y = _margin + _nodeSize / 2 + gen * _vGap;
      buf.writeln(
        '  <text x="2" y="${_num(y + 4)}" '
        'font-size="10" fill="$_graphite" '
        'font-family="monospace">${_genLabel(gen)}</text>',
      );
    }

    buf.writeln('</svg>');
    return buf.toString();
  }

  // ── 形状 helper ──────────────────────────────────────
  static String _shapeRect({
    required double cx,
    required double cy,
    required double w,
    required double h,
    required bool lethal,
  }) {
    final x = cx - w / 2, y = cy - h / 2;
    final stroke = lethal ? _lethalStroke : _ink;
    final width = lethal ? 2.5 : 1.5;
    return '  <rect x="${_num(x)}" y="${_num(y)}" '
        'width="$w" height="$h" '
        'fill="$_white" stroke="$stroke" stroke-width="$width"/>';
  }

  static String _shapeCircle({
    required double cx,
    required double cy,
    required double r,
    required bool lethal,
  }) {
    final stroke = lethal ? _lethalStroke : _ink;
    final width = lethal ? 2.5 : 1.5;
    return '  <circle cx="${_num(cx)}" cy="${_num(cy)}" '
        'r="$r" fill="$_white" stroke="$stroke" stroke-width="$width"/>';
  }

  static String _shapeGroup({
    required double cx,
    required double cy,
    required double w,
    required double h,
    required bool lethal,
  }) {
    final x = cx - w / 2, y = cy - h / 2;
    final stroke = lethal ? _lethalStroke : _teal;
    final fill = lethal ? '#FFE0E0' : _tealWash; // lethal 群桶用淡红
    final width = lethal ? 2.5 : 1.5;
    return '  <rect x="${_num(x)}" y="${_num(y)}" '
        'width="$w" height="$h" rx="6" ry="6" '
        'fill="$fill" stroke="$stroke" stroke-width="$width"/>';
  }

  /// 代际标题：0=P，1..=F1, F2, ...
  static String _genLabel(int gen) {
    if (gen == 0) return 'P';
    return 'F$gen';
  }

  /// XML 文本转义：& < > " ' 全部转义，避免基因型含特殊字符
  /// 破坏 SVG 合法性。
  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  /// 数字 → 字符串（保留 2 位小数，去尾零）。保证 SVG 紧凑可读。
  static String _num(double v) {
    final s = v.toStringAsFixed(2);
    // 去尾零：12.30 → 12.3；12.00 → 12
    if (!s.contains('.')) return s;
    var trimmed = s;
    while (trimmed.endsWith('0')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    if (trimmed.endsWith('.')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }
}

/// 顶层便捷函数：把 [nodes]/[edges] 序列化为 SVG XML。
///
/// 任务 v2.12 Wave 3-A 板书 PDF 导出的主入口。语义等价
/// [PedigreeSvg.toSvg]，但作为顶层函数更便于 PDF 转换层
/// （headless Chromium / svg-to-pdfk 库）直接调用：
///   final svg = pedigreeToSvg(engine.nodes, engine.edges);
///   // 之后交给 PDF 库：Pisa / printing / dart:html 等。
String pedigreeToSvg(
  List<PedigreeNode> nodes,
  List<PedigreeEdge> edges,
) =>
    PedigreeSvg.toSvg(nodes, edges);
