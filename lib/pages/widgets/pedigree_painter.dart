// pedigree_painter.dart —— 系谱画布绘制器（2.3 重构阶段 7 从
// pedigree_canvas.dart 抽出）。布局 / 手势 / 缩放条留在
// pedigree_canvas.dart，本文件只有 CustomPainter 与其绘制私有 helper。
// part of 同一库：import 与顶层工具函数（halfTapId/parseTapId/halfRectOf/
// backcrossEdgeKey/backcrossEdgeColor/PedigreeCanvasState.kBannerH 等布局
// 常量）全部共享，行为与抽取前逐行一致。

part of 'pedigree_canvas.dart';

/// 绘制器：视口裁剪（R7）+ 性别语义节点（R2）+ 边缘锚定连线（R10）。
/// v2.19 连线样式：正交折线（默认，板书感）↔ 曲线（蜘蛛网手感，
/// 屏幕-only——SVG 板书导出固定正交，见 svg_export.dart 注释）。
/// 方案出处：docs/spider_curve_plan.md（project-graph 源码级调研）。
enum PdEdgeStyle { orthogonal, curve }

class PedigreePainter extends CustomPainter {
  /// R23 相连元素柔光主色（功能语义 token：区分 armed 紫 / selected 红 /
  /// flash 金）。v2 起走 AppColors.connect（明暗两模式亮度自适应）。
  static Color get _connectedBlue => AppColors.connect;

  /// R24 选中高亮主色。v2 起走 AppColors.select。
  static Color get _selectedRed => AppColors.select;

  /// v2.12 画布文字自适应：按「实际背景」相对亮度返回 WCAG AA
  /// 4.5:1+ 对比色。不能用 Brightness 切——家族调色板 8 色横跨深
  /// 浅（琥珀/黄绿 luminance > 0.5 必须用暗字），主题色（teal）
  /// 又会随 Brightness 翻转；唯独「看背景说话」才稳。
  ///
  /// 修法（VerC1 code review P0）：
  /// 旧实现 `bg.computeLuminance() > 0.5 ? DARK : WHITE` 是 **错的** —
  /// Dart Color 默认不预乘，bg.computeLuminance() 用的是 RGB 通道
  /// 算 luminance（不参与 alpha 调制），但画布实际渲染走 srcOver
  /// 合成：result = src.rgb * src.a + canvas.rgb * (1 - src.a)，
  /// **眼睛看到的实际颜色** 跟 RGB 通道不是一回事。
  ///
  /// 实测旧版：alpha 0.88 的 8 色 RGB luminance 全部 < 0.5，所以
  /// 8/8 都选 WHITE；但 WHITE 在 8 色画布实际混合色上的对比度：
  /// - LIGHT canvasL 上 8/8 FAIL（1.86-3.61，全 < 4.5）
  /// - DARK canvasD 上 7/8 FAIL（蓝 4.33 / 红 4.47 都 < 4.5）
  ///
  /// 新规则（方案 1）：
  ///   1. 调用方把 banner alpha 从 0.88 降到 0.80（line 137），
  ///      让画布混合色更接近 canvas 背景，混合后所有 8 色都能让
  ///      WHITE 或 DARK 之一达到 WCAG AA 4.5:1。
  ///   2. helper 内部用 srcOver 公式模拟预乘算出"眼睛实际看到的
  ///      颜色"（effective），再算 WHITE vs effective 的对比度，
  ///      >= 4.5 选 WHITE，否则选 DARK(0xFF1A1A1A)。
  ///   3. 8 色 × 2 mode 实测 8/8 PASS（alpha 0.80 是 Step 5 验算
  ///      结果：alpha 0.75/0.80 都能 8/8 PASS，0.80 视觉最接近
  ///      旧 0.88 饱和度）。
  static Color _onForBg(Color bg) =>
      onForBgCore(bg, AppColors.canvas);

  /// v2.19.30（DeepSeek P2-3）：纯函数化抽出——family banner 文字色
  /// 判定（8 色 × 2 模式）由此进测试钉死（test/theme/ 下家族横幅
  /// 对比度用例），杜绝「未来调 palette 色或 banner alpha 后对比度
  /// 静默破 AA 无报警」。
  static Color onForBgCore(Color bg, Color canvas) {
    // 模拟画布 srcOver 预乘：实际眼睛看到的颜色 =
    //   bg.rgb * bg.a + canvas.rgb * (1 - bg.a)
    // Dart Color.r/g/b 是 0..1 浮点。
    final a = bg.a;
    final r = (bg.r * a + canvas.r * (1 - a));
    final g = (bg.g * a + canvas.g * (1 - a));
    final b = (bg.b * a + canvas.b * (1 - a));
    final effective = Color.from(
      alpha: 1.0,
      red: r,
      green: g,
      blue: b,
    );
    final whiteContrast = _contrast(Colors.white, effective);
    if (whiteContrast >= 4.5) return Colors.white;
    return const Color(0xFF1A1A1A);
  }

  /// WCAG 2.1 对比度（4.5:1 是 AA 文本阈值）。
  static double _contrast(Color fg, Color bg) {
    final l1 = fg.computeLuminance();
    final l2 = bg.computeLuminance();
    final lighter = l1 > l2 ? l1 : l2;
    final darker = l1 > l2 ? l2 : l1;
    return (lighter + 0.05) / (darker + 0.05);
  }

  final List<PedigreeNode> nodes;
  final List<PedigreeEdge> edges;
  final Map<String, Rect> rects;
  final String? selectedId;
  final Matrix4 viewTransform;
  final Size viewportSize;

  /// 折叠 (家族:世代) + 隐藏桶数 + 芯片矩形（由 State 布局时算好传入）。
  final Set<String> collapsedKeys;
  final Map<String, int> hiddenCounts;
  final Map<String, Rect> genChipRects;

  /// 世代 → 顶部世界 y（多行网格布局的世代高度可变）。
  final Map<int, double> genTop;

  /// 伴性遗传标注配置（null = 关闭）。
  final SexLinkedConfig? sexLinked;

  /// R12：待命节点 id（紫罗兰光晕）+ 连线成功闪光节点（金色光晕）。
  final String? armedId;
  final Set<String> flashIds;

  /// 线路可见性：主干线（lineage 灰总线）/ 回交线（跨代 mating 彩色）。
  final bool showLineage;

  /// v2.19 连线样式（正交/曲线）。必须参与构造比较——shouldRepaint
  /// 恒 true 故无需额外处理，但字段缺省值要显式。
  final PdEdgeStyle edgeStyle;
  final bool showBackcross;

  /// 逐条隐藏的回交边 key 集合。
  final Set<String> hiddenBackcrossKeys;

  /// 家族分栏背景矩形 + 显示名（R14；>1 家族时绘制分栏与横幅）。
  final Map<int, Rect> familyStripRects;
  final Map<int, String> familyLabels;

  /// R15 组合桶渲染开关（与 State 侧 sexSplitView 同步）。
  final bool sexSplitView;

  /// R15 选择模式勾选集合（可含半边合成 id）。
  final Set<String> pickedIds;

  /// R23/R25 相连元素弱光：baseId -> 相连那侧 kind 集合（粒度到性别
  /// 半边；组合桶只给对应半边柔光，普通节点整节点）。
  final Map<String, Set<PedigreeNodeKind>> connectedIds;

  /// R24 组合桶半边专注（同 widget 参数，见上）。
  final Map<String, PedigreeNodeKind> soloHalfIds;

  /// v2.19.5 连线性别互斥：待命起点已定时，不可连接的节点 base id
  /// 集合（如同性，未开同性交配时）——整节点弱化变暗，只留可连接
  /// 目标亮起，从视觉上杜绝选错。空集 = 不弱化（待命未定点/同性已开）。
  final Set<String> dimIds;

  /// v2.19.6 性能：当前 zoom（painter 实例字段，paint() 开头赋值）。
  /// 复用进 _kStroke 做"世界度量线宽→屏幕像素"的换算。重复 paint()
  /// 时 painter 实例可能被复用（shouldRepaint 返回 false 仍可能复用），
  /// 因此**不能**用 `late final`——会触发 LateInitializationError。
  double _z = 1.0;

  PedigreePainter({
    required this.nodes,
    required this.edges,
    required this.rects,
    required this.selectedId,
    required this.viewTransform,
    required this.viewportSize,
    this.collapsedKeys = const {},
    this.hiddenCounts = const {},
    this.genChipRects = const {},
    this.genTop = const {},
    this.sexLinked,
    this.armedId,
    this.flashIds = const {},
    this.showLineage = true,
    this.showBackcross = true,
    this.edgeStyle = PdEdgeStyle.orthogonal,
    this.hiddenBackcrossKeys = const {},
    this.familyStripRects = const {},
    this.familyLabels = const {},
    this.sexSplitView = false,
    this.pickedIds = const {},
    this.connectedIds = const {},
    this.soloHalfIds = const {},
    this.dimIds = const {},
  });

  /// v2.19.6 性能：按当前 zoom 把世界度量线宽转成屏幕像素——缩到 0.2x
  /// 时线不会细如发丝，放到 3x 时不会粗成扁担。clamp 范围限制视觉退化
  /// 极值。`_z` 在 paint() 开头由 viewTransform.getMaxScaleOnAxis() 算得。
  /// 世界度量线宽 → 屏幕像素换算：返回 **世界线宽** = worldWidth ÷
  /// clamp(z, lo, hi)。屏幕线宽 = 返回值 × z ≈ worldWidth（恒定）。
  /// v2.19.11（老师走查 🟡#4）：clamp 上界 3.0 → 5.0——讲课缩到
  //  0.2-0.3x 时旧上界把线宽过度放大成粗描边。
  /// v2.19.12（老师验证 🟡2）：下界 0.5 → 0.25——深放大端 <1 屏幕
  /// px 断线。
  /// v2.19.13（老师找茬 🟡4 修正）：上界收回 3.0（= _maxScale，5.0
  /// 是死代码永不触发）+ 注释公式纠错——此前注释写「屏幕线宽 =
  /// worldWidth × z ÷ clamp」是错的（那是×不是÷），实际推导：
  /// 屏幕宽 = 世界宽 × z，令屏幕宽 = worldWidth → 世界宽 = worldWidth
  /// ÷ z；clamp 只是给极端 z 兜底（z<下界时世界宽封顶，屏幕不细过
  /// 0.8×worldWidth；z>上界同理）。z=3 特写时屏幕线宽仍 = worldWidth
  /// 1.6px，不是亚像素。
  double _kStroke(double worldWidth) {
    final z = _z.clamp(0.25, 3.0);
    return worldWidth / z;
  }

  @override
  bool shouldRepaint(PedigreePainter old) {
    bool setEq<T>(Set<T>? a, Set<T>? b) {
      if (identical(a, b)) return true;
      if (a == null || b == null) return false;
      if (a.length != b.length) return false;
      for (final v in a) {
        if (!b.contains(v)) return false;
      }
      return true;
    }

    bool mapSetEq<K>(Map<K, Set<PedigreeNodeKind>>? a, Map<K, Set<PedigreeNodeKind>>? b) {
      if (identical(a, b)) return true;
      if (a == null || b == null) return false;
      if (a.length != b.length) return false;
      for (final k in a.keys) {
        if (!b.containsKey(k)) return false;
        if (!setEq(a[k], b[k])) return false;
      }
      return true;
    }

    bool mapKindEq(Map<String, PedigreeNodeKind>? a, Map<String, PedigreeNodeKind>? b) {
      if (identical(a, b)) return true;
      if (a == null || b == null) return false;
      if (a.length != b.length) return false;
      for (final k in a.keys) {
        if (b[k] != a[k]) return false;
      }
      return true;
    }

    return nodes != old.nodes ||
        edges != old.edges ||
        rects != old.rects ||
        selectedId != old.selectedId ||
        viewTransform != old.viewTransform ||
        viewportSize != old.viewportSize ||
        !setEq(collapsedKeys, old.collapsedKeys) ||
        hiddenCounts != old.hiddenCounts ||
        genChipRects != old.genChipRects ||
        genTop != old.genTop ||
        sexLinked != old.sexLinked ||
        armedId != old.armedId ||
        !setEq(flashIds, old.flashIds) ||
        showLineage != old.showLineage ||
        showBackcross != old.showBackcross ||
        edgeStyle != old.edgeStyle ||
        !setEq(hiddenBackcrossKeys, old.hiddenBackcrossKeys) ||
        familyStripRects != old.familyStripRects ||
        familyLabels != old.familyLabels ||
        sexSplitView != old.sexSplitView ||
        !setEq(pickedIds, old.pickedIds) ||
        !mapSetEq(connectedIds, old.connectedIds) ||
        !mapKindEq(soloHalfIds, old.soloHalfIds) ||
        !setEq(dimIds, old.dimIds);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // R7：由当前变换矩阵反推可见世界矩形，屏外跳过
    final inv = Matrix4.inverted(viewTransform);
    _z = viewTransform.getMaxScaleOnAxis();
    final visible = MatrixUtils.transformRect(
            inv, Rect.fromLTWH(0, 0, viewportSize.width, viewportSize.height))
        .inflate(160);

  bool visibleNode(String id) {
      final r = rects[id];
      return r != null && r.overlaps(visible);
    }

    // ── 家族分栏底色 + 横幅（R14，>1 家族时绘制，压在最底层） ──
    // 思维导图式分组：每个家族一块圆角底色 + 栏顶实色横幅「家族 X」，
    // 多家族并排行一眼分清边界；跨家族连线因此 visibly 跨栏。
    if (familyStripRects.length > 1) {
      familyStripRects.forEach((f, r) {
        if (!r.overlaps(visible)) return;
        final color =
            AppColors.familyPalette[f % AppColors.familyPalette.length];
        final rr = RRect.fromRectAndRadius(r, const Radius.circular(18));
        canvas.drawRRect(rr, Paint()..isAntiAlias = true..color = color.withValues(alpha: 0.05));
        canvas.drawRRect(
            rr,
            Paint()..isAntiAlias = true
              ..color = color.withValues(alpha: 0.30)
              ..style = PaintingStyle.stroke
              ..strokeWidth = _kStroke(1.2));
        // 横幅：栏顶居中实色胶囊
        final label = familyLabels[f] ?? '$f';
        // v2.12: 横幅背景是 familyPalette 调色板色(8 色深浅跨度大),
        // 必须按"实际画布混合色"算对比度选文字色(琥珀/黄绿等亮色用
        // 暗字)。alpha 0.80 是验算后唯一能让 8 色 × 2 mode 都达
        // WCAG AA 4.5+ 的最低饱和度（0.75 也行但更透；0.88 则
        // 蓝/品红/红 DARK 模式硬 FAIL）。详见 _onForBg 注释。
        final bannerBg = color.withValues(alpha: 0.80);
        final tp = TextPainter(
          text: TextSpan(
            text: '家族 $label',
            style: AppText.caption.copyWith(
                color: _onForBg(bannerBg), fontWeight: FontWeight.w700),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final bc =
            Offset(r.center.dx, r.top + PedigreeCanvasState.kBannerH / 2);
        final bg = RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: bc, width: tp.width + 20, height: tp.height + 10),
            const Radius.circular(12));
        canvas.drawRRect(bg, Paint()..isAntiAlias = true..color = bannerBg);
        tp.paint(
            canvas, Offset(bc.dx - tp.width / 2, bc.dy - tp.height / 2));
      });
    }

    // 边一律细线（stroke）。此前漏写 style 导致 drawPath 走默认 fill，
    // 连线被填充成大色块糊成一团 —— 已修复，勿回退。
    // R12 颜色分类：主干 lineage=中性灰（可隐藏）；同代交配=teal；
    // 回交（跨代 mating）=逐条异色调色板（可隐藏），密集系谱里可区分。
    final edgePaint = Paint()..isAntiAlias = true
      ..color = AppColors.graphite
      ..style = PaintingStyle.stroke
      ..strokeWidth = _kStroke(1.6);
    final matingPaint = Paint()..isAntiAlias = true
      ..color = AppColors.teal
      ..style = PaintingStyle.stroke
      ..strokeWidth = _kStroke(2.0);

    final byId = {for (final n in nodes) n.id: n};

    // R15 组合桶：SPLIT 半桶不单独渲染，其边端点路由到父桶内对应
    // 性别半边 glyph 的矩形；普通节点返回自身 rect。父桶被隐藏时
    // 返回 null（该边跳过不画）。
    Rect? anchorRect(String id) {
      final n = byId[id];
      if (n == null) return null;
      if (sexSplitView && n.id.startsWith('SPLIT#')) {
        for (final e in edges) {
          if (e.kind == PedigreeEdgeKind.lineage && e.toId == id) {
            final pr = rects[e.fromId];
            if (pr != null) return halfRectOf(pr, n.kind);
          }
        }
        return null;
      }
      return rects[id];
    }

    // 回交肘部分车道（ordered bundles / metro-map 思想简化版）：
    // 同一年代间隙（olderGen→youngerGen）里的多条回交线按起点 x 排序，
    // 肘部 y 均分间隙，消灭「多条回交线同高度重叠、标签叠字」。
    final bcLanes = <String, double>{}; // edgeKey → 肘部在间隙中的归一化位置
    final bcGroups = <String, List<PedigreeEdge>>{};
    for (final e in edges) {
      if (e.kind != PedigreeEdgeKind.mating) continue;
      final a = byId[e.fromId], b = byId[e.toId];
      if (a == null || b == null || a.generation == b.generation) continue;
      final lo =
          a.generation < b.generation ? a.generation : b.generation;
      final hi =
          a.generation < b.generation ? b.generation : a.generation;
      bcGroups.putIfAbsent('$lo-$hi', () => []).add(e);
    }
    bcGroups.forEach((_, list) {
      list.sort((e1, e2) {
        final x1 = anchorRect(e1.fromId)?.center.dx ?? 0;
        final x2 = anchorRect(e2.fromId)?.center.dx ?? 0;
        return x1.compareTo(x2);
      });
      for (var i = 0; i < list.length; i++) {
        bcLanes[backcrossEdgeKey(list[i])] = (i + 1) / (list.length + 1);
      }
    });

    // ── lineage：按「子代世代×家族」分组的「总线」布线（NSGC 三段正交细线） ──
    // 池交配的子代桶共享同一批贡献者，逐边画必然糊成团；改为：
    // 贡献者底边短竖线 → 收集横线 → 主干下垂 → 同胞横线 → 子女 tick。
    // R14 修复：分组键必须带家族——否则多家族时收集横线会把两个独立
    // 家族捆进同一根总线（跨栏横线，视觉上像两家族连在了一起）。
    // 跨家族交配的子代进合并家族，其贡献者天然跨栏，横线跨栏是正确的。
    if (showLineage) {
      // v2.19.9：XY 开启时 group 桶的 lineage 锚点收缩到 glyph 列
      // （雄□~雌○ 的横向范围）——线从 □○ 正上/正下方出入，而非大框
      // 任意位置（drawio「connection points」原则：连线吸附在形状的
      // 连接点上，不是轮廓任意处）。SPLIT 半边已由 anchorRect 路由
      // 到 glyph，此处天然不受影响。
      Rect? lRect(String id) {
        final r = anchorRect(id);
        final n = byId[id];
        if (r == null || n == null) return r;
        if (sexSplitView &&
            n.kind == PedigreeNodeKind.group &&
            !n.id.startsWith('SPLIT#')) {
          final hm = halfRectOf(r, PedigreeNodeKind.male);
          final hf = halfRectOf(r, PedigreeNodeKind.female);
          return Rect.fromLTRB(
              math.min(hm.left, hf.left),
              r.top,
              math.max(hm.right, hf.right),
              r.bottom);
        }
        return r;
      }

      final grpChildren = <String, List<PedigreeNode>>{};
      final grpContrib = <String, Set<String>>{};
      for (final e in edges) {
        if (e.kind != PedigreeEdgeKind.lineage) continue;
        final child = byId[e.toId];
        if (child == null || !byId.containsKey(e.fromId)) continue;
        // R15：父桶→SPLIT 半边的结构边不画（半边在组合桶内展示）
        if (sexSplitView && child.id.startsWith('SPLIT#')) continue;
        final key = '${child.generation}|${child.familyId}';
        final list = grpChildren.putIfAbsent(key, () => []);
        if (!list.any((n) => n.id == child.id)) list.add(child);
        grpContrib.putIfAbsent(key, () => {}).add(e.fromId);
      }

      grpChildren.forEach((key, kids) {
        final parents = [
          for (final id in grpContrib[key]!)
            if (byId[id] != null && lRect(id) != null) byId[id]!
        ];
        if (parents.isEmpty || kids.isEmpty) return;
        if (!parents.any((n) => visibleNode(n.id)) &&
            !kids.any((n) => visibleNode(n.id))) {
          return;
        }
        double cx(PedigreeNode n) => lRect(n.id)!.center.dx;
        parents.sort((a, b) => cx(a).compareTo(cx(b)));
        kids.sort((a, b) => cx(a).compareTo(cx(b)));

        if (edgeStyle == PdEdgeStyle.curve) {
          // 用户裁定（2026-09-19 截图）：曲线模式 = 全部点对点直连贝塞尔
          // （像图中蓝色回交线那样一根顺滑弧线直达），不走正交 bus 骨架
          // 的「竖-横-竖」阶梯——微弓版仍残留 Z/U 字形折角，观感混杂。
          // 同家族代际链是垂直的，直连天然不穿越节点本体；多父母 × 多
          // 子女为扇形 fully-connected，弓向按 (i+j) 交替错开防重叠。
          final pVis =
              parents.where((n) => visibleNode(n.id)).toList();
          final kVis = kids.where((n) => visibleNode(n.id)).toList();
          var i = 0;
          for (final p in pVis) {
            final pr = lRect(p.id)!;
            final a = Offset(pr.center.dx, pr.bottom);
            var j = 0;
            for (final k in kVis) {
              final kr = lRect(k.id)!;
              final b = Offset(kr.center.dx, kr.top);
              final d = (b - a).distance;
              if (d < 1) {
                j++;
                continue;
              }
              final bow = (d * 0.10).clamp(5.0, 26.0);
              final dir = ((i + j) % 2 == 0) ? 1.0 : -1.0;
              final nx = -(b.dy - a.dy) / d * dir;
              final ny = (b.dx - a.dx) / d * dir;
              final mid =
                  Offset((a.dx + b.dx) / 2 + nx * bow, (a.dy + b.dy) / 2 + ny * bow);
              canvas.drawPath(
                Path()
                  ..moveTo(a.dx, a.dy)
                  ..quadraticBezierTo(mid.dx, mid.dy, b.dx, b.dy),
                edgePaint,
              );
              j++;
            }
            i++;
          }
          return; // 曲线模式：bus 正交骨架（收集线/主干/tick）全部跳过
        }

        // R22 跨家族总线分段：贡献者可能分属多个家族，且各家族可被
        // 整体拖动（y 互不相同）。旧实现把收集横线放在全局 max(bottom)
        // 处，会把没拖动的家族竖线长距离拽到别人家的高度并撞进他家
        // 垂直线上（拖动后连线指向错乱的根因）。现改为：每个家族组
        // 各画一条收集线（y 相对该组自身 bottom），各组再水平汇到
        // 主干 trunk——各组随各自家族移动，不再互相拉扯。
        final kidsTop =
            kids.map((n) => lRect(n.id)!.top).reduce(math.min);
        final famGroups = <int, List<PedigreeNode>>{};
        for (final p in parents) {
          famGroups.putIfAbsent(p.familyId, () => []).add(p);
        }
        final minPcx = cx(parents.first), maxPcx = cx(parents.last);
        // R23/R24：多个合并家族总线（A×B、B×C…）可能共用同一栏间中点，
        // trunk 竖线会重叠成「一条线分叉」/「贴进别家主干」的错视觉——
        // 按 familyId 错开 trunkX（±24px，逐 id 拉开），独立可读。
        final fid = int.tryParse(key.split('|')[1] ?? '') ?? 0;
        // v2.19.1：baseTrunkX 提前到 stub 绘制前（曲线模式的父母接入
        // 段要向它弓起）。
        final baseTrunkX =
            (minPcx + maxPcx) / 2 + ((fid % 7) - 3) * 8.0;

        // 各家族组：竖线 → 组内收集线（barY 相对组内 max bottom）
        final famBarY = <int, double>{};
        var barMax = -double.infinity;
        var barMin = double.infinity;
        famGroups.forEach((f, group) {
          group.sort((a, b) => cx(a).compareTo(cx(b)));
          final bottom =
              group.map((n) => lRect(n.id)!.bottom).reduce(math.max);
          final gap = kidsTop - bottom;
          // R26：间隙不足/反向（子代被拖到父母上方，gap<=8）时不再
          // return（否则整条总线夭折、亲子线"断裂在节点上方"）。改为
          // 向下探出 22px 再上接——保持"从节点下方出发"的语义，反向时
          // 形成 U 形连接（用户要求：本该向下延伸的线向上接一下）。
          final barY = gap > 8 ? bottom + gap * 0.32 : bottom + 22;
          famBarY[f] = barY;
          if (barY > barMax) barMax = barY;
          if (barY < barMin) barMin = barY;
          for (final p in group) {
            final r = lRect(p.id)!;
            if (edgeStyle == PdEdgeStyle.curve) {
              // v2.19.3 全曲化：单一贝塞尔（无直线拼接），两端切线
              // 垂直（与父母底边 / 收集横线顺接），中段向 trunk 弓起
              // 25%——有机须感但不穿越邻段。用户裁定：曲线模式只
              // 出现曲线。
              final h = barY - r.bottom;
              final bowX = r.center.dx + (baseTrunkX - r.center.dx) * 0.25;
              canvas.drawPath(
                Path()
                  ..moveTo(r.center.dx, r.bottom)
                  ..cubicTo(r.center.dx, r.bottom + h * 0.3, bowX,
                      r.bottom + h * 0.7, r.center.dx, barY),
                edgePaint,
              );
            } else {
              canvas.drawLine(Offset(r.center.dx, r.bottom),
                  Offset(r.center.dx, barY), edgePaint);
            }
          }
          // 组内收集线：曲线模式为微弓（单一贝塞尔，端点不变）。
          if (edgeStyle == PdEdgeStyle.curve) {
            final x1 = cx(group.first), x2 = cx(group.last);
            canvas.drawPath(
              Path()
                ..moveTo(x1, barY)
                ..quadraticBezierTo(
                    (x1 + x2) / 2, barY - 8, x2, barY),
              edgePaint,
            );
          } else {
            canvas.drawLine(Offset(cx(group.first), barY),
                Offset(cx(group.last), barY), edgePaint);
          }
        });
        if (famBarY.isEmpty) return;

        // 主干下垂：从最下方收集线到同胞横线。**不再因 barMax>bar2Y 而
        // return**——那样会留下「收集线段已画、主干/子女段未画」的半截
        // 悬空线（家族被拖乱后常见）。始终闭合：bar2Y 取子女上方固定
        // 偏移；即使父母被拖到子女下方（barMax 更低），trunk 向上画也
        // 保证整条总线连通，端点始终固定在节点上。
        final bar2Y = kidsTop - 6;

        // R30.2：trunk 竖线区间必须覆盖**最下方组 barY 到子女线**
        //（max(barMax,bar2Y)）与最上方组/反向（min(barMin,bar2Y)）。
        // 此前只从 barMin 起——被拖低的组（barY > bar2Y）横段画到了
        // 竖线范围之外 → "横段右端悬空"（用户截图）。现在整区间
        // [min(barMin,bar2Y), max(barMax,bar2Y)] 都画，任意组可汇接。
        final trunkLo = math.min(math.min(barMin, bar2Y), barMax);
        final trunkHi = math.max(math.max(barMin, bar2Y), barMax);

        bool trunkBlocked(double x) {
          for (final n in nodes) {
            final rr = rects[n.id];
            if (rr == null) continue;
            if (x >= rr.left - 3 &&
                x <= rr.right + 3 &&
                trunkLo < rr.bottom + 2 &&
                trunkHi > rr.top - 2) {
              return true;
            }
          }
          return false;
        }

        var trunkX = baseTrunkX;
        // R29（调研结论：正交路由避让）：单侧探测范围从 ±220 扩到
        // ±656、步进 16——世界尺寸有限时基本总能找到不穿卡的落点；
        // 找不到时 _drawTrunkSegments 的裁剪分段仍作兜底（不穿卡、
        // 视觉闭合）。
        if (trunkBlocked(trunkX)) {
          var step = 16.0;
          var sign = 1;
          while (trunkBlocked(trunkX) && step < 656) {
            trunkX = baseTrunkX + step * sign;
            sign = -sign;
            step += 16;
          }
        }

        // 组内收集线 → 主干 trunkX（trunkX 不在组横线内时才补水平段；
        // 曲线模式为微弓贝塞尔——全曲化）。
        famGroups.forEach((f, group) {
          final barY = famBarY[f];
          if (barY == null) return;
          if (trunkX < cx(group.first)) {
            if (edgeStyle == PdEdgeStyle.curve) {
              canvas.drawPath(
                Path()
                  ..moveTo(trunkX, barY)
                  ..quadraticBezierTo((trunkX + cx(group.first)) / 2,
                      barY - 6, cx(group.first), barY),
                edgePaint,
              );
            } else {
              canvas.drawLine(Offset(trunkX, barY),
                  Offset(cx(group.first), barY), edgePaint);
            }
          } else if (trunkX > cx(group.last)) {
            if (edgeStyle == PdEdgeStyle.curve) {
              canvas.drawPath(
                Path()
                  ..moveTo(cx(group.last), barY)
                  ..quadraticBezierTo((cx(group.last) + trunkX) / 2, barY - 6,
                      trunkX, barY),
                edgePaint,
              );
            } else {
              canvas.drawLine(Offset(cx(group.last), barY),
                  Offset(trunkX, barY), edgePaint);
            }
          }
        });

        // R30：无法避让时不再"裁剪断口"——改用绕卡路由（竖线遇卡
        // 水平绕行后继续，全程连续，任何高度的组段都能汇接）。
        // v2.19.3 全曲化：曲线模式主干本体也微弓（±10px，按 fid
        // 交替方向），整条主干无直线段。
        if (edgeStyle == PdEdgeStyle.curve) {
          final bowX = trunkX + ((fid % 2 == 0) ? 10.0 : -10.0);
          canvas.drawPath(
            Path()
              ..moveTo(trunkX, trunkLo)
              ..quadraticBezierTo(
                  bowX, (trunkLo + trunkHi) / 2, trunkX, trunkHi),
            edgePaint,
          );
        } else {
          _drawRoutedTrunk(canvas, trunkX, trunkLo, trunkHi);
        }

        // 同胞横线（须覆盖主干落点与所有子女；曲线模式为微弓）。
        final minKcx = cx(kids.first), maxKcx = cx(kids.last);
        final bar2L = math.min(minKcx, trunkX);
        final bar2R = math.max(maxKcx, trunkX);
        if (edgeStyle == PdEdgeStyle.curve) {
          canvas.drawPath(
            Path()
              ..moveTo(bar2L, bar2Y)
              ..quadraticBezierTo(
                  (bar2L + bar2R) / 2, bar2Y - 6, bar2R, bar2Y),
            edgePaint,
          );
        } else {
          canvas.drawLine(Offset(bar2L, bar2Y), Offset(bar2R, bar2Y), edgePaint);
        }

        // 子女 tick：同胞线 → 子节点顶边中点（R27：偶数个 rect 缺失时
        // 跳过该子女，其余照常——不因个别隐藏节点整条断线）。
        // v2.19.3 全曲化：单一贝塞尔，末端切线垂直（顺接子节点顶边），
        // 中段向 trunk 弓起 25%。
        for (final k in kids) {
          final r = lRect(k.id);
          if (r == null) continue;
          if (edgeStyle == PdEdgeStyle.curve) {
            final h = r.top - bar2Y;
            final bowX = cx(k) + (trunkX - cx(k)) * 0.25;
            canvas.drawPath(
              Path()
                ..moveTo(cx(k), bar2Y)
                ..cubicTo(bowX, bar2Y + h * 0.3, cx(k), bar2Y + h * 0.7,
                    cx(k), r.top),
              edgePaint,
            );
          } else {
            canvas.drawLine(
                Offset(cx(k), bar2Y), Offset(cx(k), r.top),
                edgePaint);
          }
        }
      });
    }

    // ── 世代标签（R20：每家族独立一套，随家族拖动跟随） ──────
    // 各家族代数深度可能不同（A 到 F1、B 到 F3）且可整体拖动，全局
    // 左缘单套 P/F1/F2 会错位/不跟随——改为画在各自分栏左缘外侧，
    // y 取该家族该代节点顶部（节点矩形带偏移，标签天然跟随）。
    final famGenTop = <int, Map<int, double>>{};
    for (final n in nodes) {
      final r = rects[n.id];
      if (r == null) continue;
      final t = famGenTop.putIfAbsent(n.familyId, () => {});
      final cur = t[n.generation];
      if (cur == null || r.top < cur) t[n.generation] = r.top;
    }
    famGenTop.forEach((f, genTops) {
      final strip = familyStripRects[f];
      if (strip == null) return;
      final x = strip.left - 26;
      genTops.forEach((g, top) {
        if (top < visible.top - 40 || top > visible.bottom + 40) return;
        _paintText(
          canvas,
          g == 0 ? 'P' : 'F$g',
          Offset(x, top + 6),
          AppText.monoSmall.copyWith(
              color: AppColors.steel, fontWeight: FontWeight.w700),
        );
      });
    });

    // ── 节点（R2） ──────────────────────────────────────
    for (final n in nodes) {
      final r = rects[n.id];
      if (r == null || !r.overlaps(visible)) continue; // 视口裁剪
      // R12 光晕 + R15 合成 id：armed/flash/selected/picked 均可能携带
      // '::male/::female' 半边后缀，命中组合桶时只点亮对应半边。
      Color? glow;
      PedigreeNodeKind? glowHalf;
      for (final fid in flashIds) {
        final (base, half) = parseTapId(fid);
        if (base == n.id) {
          glow = AppColors.flash;
          glowHalf = half;
          break;
        }
      }
      if (glow == null && armedId != null) {
        final (base, half) = parseTapId(armedId!);
        if (base == n.id) {
          glow = AppColors.armed;
          glowHalf = half;
        }
      }
      var selected = false;
      PedigreeNodeKind? selHalf;
      if (selectedId != null) {
        final (base, half) = parseTapId(selectedId!);
        if (base == n.id) {
          selected = true;
          selHalf = half;
        }
      }
      var picked = false;
      PedigreeNodeKind? pickedHalf;
      for (final pid in pickedIds) {
        final (base, half) = parseTapId(pid);
        if (base == n.id) {
          picked = true;
          pickedHalf = half;
          break;
        }
      }
      // R23/R25 相连元素：与选中/待命节点有边相连 → 柔光高亮，粒度到
      // 性别半边（组合桶只亮对应半边；普通节点亮整节点）。
      final connKinds = connectedIds[n.id];
      final connected =
          connKinds != null && connKinds.isNotEmpty;
      // R24：组合桶半边专注（XY 存证开启 + 选择模式勾选单个半边）
      final solo = soloHalfIds[n.id];
      // v2.19.5 性别互斥弱化：待命起点已定时，不可连接节点整节点变暗。
      final dim = dimIds.contains(n.id);
      _drawNode(canvas, n, r,
          selected: selected,
          selHalf: selHalf,
          glow: glow,
          glowHalf: glowHalf,
          picked: picked,
          pickedHalf: pickedHalf,
          connected: connected,
          soloHalf: solo,
          dim: dim);
    }

    // ── mating 边（v2.19.8 层级提升：绘制在节点层之上——端点深入
    // glyph 内部，穿入部分不被节点遮盖；lineage 总线保持底层） ──
    // v2.19.8 防打结预扫：同一端点（id|性别）的多条 mating 边，锚点
    // 沿元素边缘错开分布（用户反馈：一个元素连好几条线时在头顶打结
    // 成一团）。degree=1 偏移恒 0——单线视觉不变。
    final endpointEdges = <String, List<PedigreeEdge>>{};
    for (final e0 in edges) {
      if (e0.kind != PedigreeEdgeKind.mating) continue;
      endpointEdges
          .putIfAbsent('${e0.fromId}|${e0.fromSex?.name ?? 'g'}', () => [])
          .add(e0);
      endpointEdges
          .putIfAbsent('${e0.toId}|${e0.toSex?.name ?? 'g'}', () => [])
          .add(e0);
    }
    (int, int) slotOf(String id, PedigreeNodeKind? sex, PedigreeEdge self) {
      // 键回退：渲染端性别可能是推断值（XY 关期间连的线无记录性别），
      // 预扫键是 'g'——推断键查不到时回落 'g'，再兜底 (0,1) 不错开。
      var list = endpointEdges['$id|${sex?.name ?? 'g'}'];
      list ??= endpointEdges['$id|g'];
      if (list == null) return (0, 1);
      return (list.indexOf(self), list.length);
    }

    for (final e in edges) {
      if (e.kind != PedigreeEdgeKind.mating) continue;
      // v2.19.7：XY 开启（sexSplitView）时，组合桶端点落到性别半边
      // glyph（halfRectOf），而非整个大框——配偶线/回交线直指节点
      // 本体（用户反馈"线指到大框"）。性别来源优先级：边记录
      // （fromSex/toSex）→ 按另一端异性推断（覆盖「XY 关闭期间连的
      // 线」：当时 sexOf(group)=null 无记录，开 XY 后按配偶关系推断
      // 半边，连线随开关重算不残留大框锚点）→ 都未知才回落大框。
      // XY 关闭后 sexSplitView=false 自然回落大框；锚点渲染时按当前
      // 开关动态解析，切换即重算，无额外失效逻辑。
      Rect? matingAnchor(
          String id, PedigreeNodeKind? sex, PedigreeNodeKind? otherSex) {
        final r = anchorRect(id);
        final n = byId[id];
        if (r == null || n == null) return r;
        if (sexSplitView && n.kind == PedigreeNodeKind.group) {
          final eff = sex ??
              (otherSex == PedigreeNodeKind.male
                  ? PedigreeNodeKind.female
                  : otherSex == PedigreeNodeKind.female
                      ? PedigreeNodeKind.male
                      : null);
          if (eff != null) return halfRectOf(r, eff);
        }
        return r;
      }

      final effASex = e.fromSex ??
          (e.toSex == PedigreeNodeKind.male
              ? PedigreeNodeKind.female
              : e.toSex == PedigreeNodeKind.female
                  ? PedigreeNodeKind.male
                  : null);
      final effBSex = e.toSex ??
          (e.fromSex == PedigreeNodeKind.male
              ? PedigreeNodeKind.female
              : e.fromSex == PedigreeNodeKind.female
                  ? PedigreeNodeKind.male
                  : null);
      final ra = matingAnchor(e.fromId, e.fromSex, e.toSex);
      final rb = matingAnchor(e.toId, e.toSex, e.fromSex);
      if (ra == null || rb == null) continue;
      if (!ra.overlaps(visible) && !rb.overlaps(visible)) continue;
      final na = byId[e.fromId]!;
      final nb = byId[e.toId]!;
      if (na.generation == nb.generation) {
        // 同世代婚配线：雄出右边 / 雌进左边，group 朝对方侧边
        // （v2.19.7：sex 明确时按性别定侧——组合桶半边锚点不再靠
        // center 比较猜侧）。
        Offset anchor(PedigreeNode n, Rect r, Rect other,
            PedigreeNodeKind? sex,
            {double inset = 0, double dyOff = 0}) {
          final cy = r.center.dy + dyOff;
          if (sex == PedigreeNodeKind.male) {
            return Offset(r.right - inset, cy);
          }
          if (sex == PedigreeNodeKind.female) {
            return Offset(r.left + inset, cy);
          }
          switch (n.kind) {
            case PedigreeNodeKind.male:
              return Offset(r.right - inset, cy);
            case PedigreeNodeKind.female:
              return Offset(r.left + inset, cy);
            case PedigreeNodeKind.group:
              return r.center.dx <= other.center.dx
                  ? Offset(r.right - inset, cy)
                  : Offset(r.left + inset, cy);
          }
        }

        // v2.19.8 深入：端点穿入 glyph 内部 4px（线在节点上层绘制，
        // 端点没入元素内，视觉扎进而非擦边）。
        final (oa, da) = slotOf(e.fromId, effASex, e);
        final (ob, db) = slotOf(e.toId, effBSex, e);
        double spreadY(int order, int deg) =>
            deg > 1 ? (order - (deg - 1) / 2) * 10.0 : 0.0;
        final aRaw =
            anchor(na, ra, rb, effASex, inset: 4, dyOff: spreadY(oa, da));
        final bRaw =
            anchor(nb, rb, ra, effBSex, inset: 4, dyOff: spreadY(ob, db));
        // R24 修复（用户反馈"线没贴到元素"）：旧实现把两端 y 拉平到
        // 中线一条直线——两节点存在高度差（家族拖动后）时端点悬空。
        // 改为 Z 字形正交：各端沿节点边缘水平伸出 → 垂直落到中线 →
        // 水平相连 → 垂直回升 → 贴对方边缘。等高时竖直段为零长，
        // 退化为一条水平直线（与原视觉一致）。
        Offset sepTo(double myCx, Rect other) =>
            Offset((other.center.dx >= myCx ? 1.0 : -1.0) * 16, 0);
        final sa = sepTo(aRaw.dx, rb);
        final sb = sepTo(bRaw.dx, ra);
        final ax1 = aRaw.dx + sa.dx;
        final bx1 = bRaw.dx + sb.dx;
        final mid = (aRaw.dy + bRaw.dy) / 2;
        // v2.19.6 polish（学生走查 #2）：端点任一 dim 则整边压暗 0.4
        // alpha——与暗框/暗字协调，避免「暗节点带亮边」误导。
        // 合并修正：worktree 版直接改共享 matingPaint 会永久污染后续
        // 非 dim 边（color 被改不还原）——dim 时新建克隆 Paint。
        final edgeDim =
            dimIds.contains(e.fromId) || dimIds.contains(e.toId);
        final mPaint = edgeDim
            ? (Paint()
                ..isAntiAlias = true
                ..color = matingPaint.color.withValues(alpha: 0.4)
                ..style = PaintingStyle.stroke
                ..strokeWidth = matingPaint.strokeWidth)
            : matingPaint;
        // R8 教师走查 #3：原 |dy|≤8 门槛让配偶线在家族拖动后静默
        // 跳回 Z 字（同图曲线/折线混排且无提示）。二次贝塞尔对
        // 任意高差都自然（弧随高差倾斜）——曲线模式不设门槛。
        if (edgeStyle == PdEdgeStyle.curve) {
          // v2.19 曲线模式（蜘蛛网手感）：配偶间画**弓形曲线**——
          // 二次贝塞尔，控制点 = 中点 + 法向（垂直）偏移。
          // R 修：曾按 project-graph「控制点 = 端点 + 端点法向 × k」
          // 实现成沿水平（切向）偏移——四点共线时贝塞尔精确退化为
          // 直线（数学事实），普通系谱里开关零视觉反馈（学生走查
          // P0）。垂直弓起才是真弧：bow = |dx|×0.15 钳 [10,36]。
          // 有高度差（家族拖动）仍走下方 Z 字——Z 本就为高度差设计。
          final midX = (aRaw.dx + bRaw.dx) / 2;
          final midY = (aRaw.dy + bRaw.dy) / 2;
          final bow = ((aRaw.dx - bRaw.dx).abs() * 0.15).clamp(10.0, 36.0);
          final path = Path()
            ..moveTo(aRaw.dx, aRaw.dy)
            ..quadraticBezierTo(midX, midY - bow, bRaw.dx, bRaw.dy);
          canvas.drawPath(path, mPaint);
        } else {
        canvas.drawLine(aRaw, Offset(ax1, aRaw.dy), mPaint);
        canvas.drawLine(Offset(ax1, aRaw.dy), Offset(ax1, mid), mPaint);
        canvas.drawLine(Offset(ax1, mid), Offset(bx1, mid), mPaint);
        canvas.drawLine(Offset(bx1, mid), Offset(bx1, bRaw.dy), mPaint);
        canvas.drawLine(Offset(bx1, bRaw.dy), bRaw, mPaint);
        }
      } else {
        // 跨世代（回交）：年长者底边中点 → 下探 → 水平 → 进入年轻者顶边中点，
        // 肘形线 + 「回交」标注；R12 起每条回交线按端点散列取调色板异色，
        // R13 起同间隙多条肘部分车道 + 支持逐条隐藏。
        if (!showBackcross) continue;
        if (hiddenBackcrossKeys.contains(backcrossEdgeKey(e))) continue;
        final bc = backcrossEdgeColor(e);
        final bcPaint = Paint()
          ..color = bc
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0;
        // v2.19.6 polish（学生走查 #2）：端点任一 dim 则回交边压暗
        // 0.4 alpha（bcPaint 每边新建，直接改色安全）。
        if (dimIds.contains(e.fromId) || dimIds.contains(e.toId)) {
          bcPaint.color = bcPaint.color.withValues(alpha: 0.4);
        }
        final older = na.generation < nb.generation ? na : nb;
        final younger = na.generation < nb.generation ? nb : na;
        // v2.19.9：回交端点同样对齐性别半边 glyph（上一版漏改此分支，
        // 用户截图：两根回交线扎在桶顶大框边缘，未到 □○）。roHalf/
        // ryHalf = 半边 glyph（x 来源）；roBox/ryBox = 大框（y 来源，
        // 线从容器边界出入）。
        final olderSex = older.id == e.fromId ? e.fromSex : e.toSex;
        final youngerSex = younger.id == e.fromId ? e.fromSex : e.toSex;
        final roHalf = matingAnchor(older.id, olderSex, youngerSex);
        final ryHalf = matingAnchor(younger.id, youngerSex, olderSex);
        final roBox = anchorRect(older.id);
        final ryBox = anchorRect(younger.id);
        if (roHalf == null || ryHalf == null || roBox == null || ryBox == null) {
          continue;
        }
        // v2.19.8：端点穿入元素 4px（底边内侧出发/顶边内侧进入）+
        // 同端点多边沿边横向错开（防打结）。
        // v2.19.9 修正：x 取性别半边 glyph 的中线（哪个小元素发出的线），
        // y 仍取大框底/顶边（线从容器边界出入，不横穿桶内空白）。
        final (oa2, da2) = slotOf(older.id, null, e);
        final (ob2, db2) = slotOf(younger.id, null, e);
        double spreadX(int order, int deg) =>
            deg > 1 ? (order - (deg - 1) / 2) * 12.0 : 0.0;
        final from = Offset(
            roHalf.center.dx + spreadX(oa2, da2), roBox.bottom - 4);
        final to = Offset(
            ryHalf.center.dx + spreadX(ob2, db2), ryBox.top + 4);
        if (edgeStyle == PdEdgeStyle.curve) {
          // v2.19 曲线模式：回交长线画垂直 S 曲线（d0=向下、d3=向上；
          // B(0.5) 恒为中点，「回交」标签落点不变）。
          // R 修：原 clamp(24, dy*0.5) 在 dy<48 时下界>上界 →
          // num.clamp 抛 ArgumentError（paint 内崩溃，学生走查 #3）。
          // 下界改为 min(24, half) 恒 ≤ 上界。
          final dy = (to.dy - from.dy).abs();
          final half = dy * 0.5;
          final bend =
              (dy * 0.4).clamp(math.min(24.0, half), half);
          // R8 教师走查 #4：曲线模式此前不消费 bcLanes——多条回交线
          // 只由端点决定，x 顺序交叉时互相穿越且标签叠字（正交模式
          // 分车道修过的问题复活）。车道值映射为控制点横向偏移
          // （端点不动、曲线中段错开），标签同步让位。
          final lane = bcLanes[backcrossEdgeKey(e)] ?? 0.5;
          final laneShift = (lane - 0.5) * 96;
          final path = Path()
            ..moveTo(from.dx, from.dy)
            ..cubicTo(from.dx + laneShift, from.dy + bend,
                to.dx + laneShift, to.dy - bend, to.dx, to.dy);
          canvas.drawPath(path, bcPaint);
          _paintLabelPill(
              canvas,
              '回交',
              Offset((from.dx + to.dx) / 2 + laneShift * 0.6,
                  (from.dy + to.dy) / 2),
              bc);
          continue; // 不是 return——paint() 里 return 会掐掉后续世代标签等全部绘制
        }
        // 肘部 y：按车道比例落在间隙 15%..85% 区间
        final lane = bcLanes[backcrossEdgeKey(e)] ?? 0.5;
        final elbowY = from.dy + (to.dy - from.dy) * (0.15 + 0.7 * lane);
        canvas.drawLine(from, Offset(from.dx, elbowY), bcPaint);
        canvas.drawLine(
            Offset(from.dx, elbowY), Offset(to.dx, elbowY), bcPaint);
        canvas.drawLine(Offset(to.dx, elbowY), to, bcPaint);
        _paintLabelPill(
            canvas, '回交', Offset((from.dx + to.dx) / 2, elbowY), bc);
      }
    }

    // ── 世代 展开/收起 芯片 ─────────────────────────────
    for (final entry in genChipRects.entries) {
      final key = entry.key;
      final r = entry.value;
      if (!r.overlaps(visible)) continue;
      final collapsed = collapsedKeys.contains(key);
      final n = hiddenCounts[key] ?? 0;
      if (n <= 0) continue;
      // v2.19.14（找茬报告 R1 + E 方案）：canvas 侧已过滤 chipRects
      // （折叠组 ∪ 选中组）。本侧按选中分两种形态：
      //   · 选中组（折叠或展开）→ 大胶囊（原 104×34；展开态 label =
      //     「收起」，承接 R1 修复后展开组的收起入口）
      //   · 未选中折叠组 → 小徽标 56×22 "+N"——默认低密度不遮视野
      //     （用户截图 8 个全量大胶囊遮挡的真根因是 R1：展开组常驻
      //     「收起」胶囊；本版展开未选中直接不画）
      // selectedId 可能带 ::male/::female 半桶后缀，parseTapId 取 base。
      final selChipKey = () {
        final sel = selectedId;
        if (sel == null) return null;
        final (base, _) = parseTapId(sel);
        final nd = byId[base];
        return nd == null ? null : '${nd.familyId}:${nd.generation}';
      }();
      final selected = key == selChipKey;
      // v2.23.2：展开未选中同样出芯片（小徽标「收起」）——展开是双向
      // 操作，收起入口必须常驻；旧版靠「选中该组才浮现大胶囊」承接，
      // 用户实测「展开了就回不去」。

      if (!selected) {
        // ── 小徽标：直接说明折叠的是基因型，而不是无法理解的裸 +N ──
        // v2.23.1（2026-11-03 徽标交互优化）：宽度按实测文本自适应
        // （上限 104 = 命中矩形宽，不越家族预留区），右侧加下三角
        // 明示「可点击展开」——用户反馈看不懂 +N 能点。
        final btp = TextPainter(
          text: TextSpan(
              text: collapsed ? '+$n 种基因型' : '收起',
              style: AppText.caption.copyWith(
                  color: AppColors.teal, fontWeight: FontWeight.w600)),
          textDirection: TextDirection.ltr,
        )..layout();
        // '收起' 只有两个字，下限压到 72 少占视野（折叠态文本更宽照旧）
        final badgeW = (btp.width + 34).clamp(72.0, 104.0);
        final badge = Rect.fromCenter(
            center: r.center, width: badgeW, height: 22);
        final badgeScreenH = 22.0 * viewTransform.getMaxScaleOnAxis();
        final bboost = badgeScreenH < 28.0
            ? (28.0 / badgeScreenH).clamp(1.0, 2.5)
            : 1.0;
        canvas.save();
        if (bboost > 1.0) {
          canvas.translate(badge.center.dx, badge.center.dy);
          canvas.scale(bboost);
          canvas.translate(-badge.center.dx, -badge.center.dy);
        }
        final br =
            RRect.fromRectAndRadius(badge, const Radius.circular(11));
        canvas.drawRRect(
            br, Paint()..isAntiAlias = true..color = AppColors.tealWash);
        canvas.drawRRect(
            br,
            Paint()..isAntiAlias = true
              ..color = AppColors.teal.withValues(alpha: 0.7)
              ..style = PaintingStyle.stroke
              ..strokeWidth = _kStroke(1.0));
        // 文本整体左移 7，把右侧空间留给展开箭头
        final bTextCx = badge.center.dx - 7;
        btp.paint(
            canvas,
            Offset(bTextCx - btp.width / 2,
                badge.center.dy - btp.height / 2));
        // 折叠=下三角（点我展开）；展开=上三角（点我收起）
        _paintCaret(canvas,
            Offset(bTextCx + btp.width / 2 + 7, badge.center.dy), collapsed);
        canvas.restore();
        continue;
      }

      // ── 选中组：大胶囊（原绘制逻辑） ──
      // v2.19.11（老师走查 H5）：画布缩小后屏幕尺寸跟着缩——屏幕高
      // <36px 时以中心为锚放大绘制；命中区在 canvas._hitGenChip 按
      // 屏幕 ≥48px 钳制。
      // v2.19.13：boost 封顶 2.5（3.5 倍时世界宽 364px 越家族间隙）。
      final chipScreenH = r.height * viewTransform.getMaxScaleOnAxis();
      final boost = chipScreenH < 36.0
          ? (36.0 / chipScreenH).clamp(1.0, 2.5)
          : 1.0;
      canvas.save();
      if (boost > 1.0) {
        canvas.translate(r.center.dx, r.center.dy);
        canvas.scale(boost);
        canvas.translate(-r.center.dx, -r.center.dy);
      }
      final rr = RRect.fromRectAndRadius(r, const Radius.circular(17));
      canvas.drawRRect(rr, Paint()..isAntiAlias = true..color = AppColors.tealWash);
      canvas.drawRRect(
          rr,
          Paint()..isAntiAlias = true
            ..color = AppColors.teal
            ..style = PaintingStyle.stroke
            ..strokeWidth = _kStroke(1.2));
      final label = collapsed ? '+$n 种基因型' : '收起';
      final tp = TextPainter(
        text: TextSpan(
            text: label,
            style: AppText.caption.copyWith(
                color: AppColors.teal, fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: r.width - 28);
      // 状态区分：折叠=下三角（点我展开），展开=上三角（点我收起）
      final tTextCx = r.center.dx - 7;
      tp.paint(canvas,
          Offset(tTextCx - tp.width / 2, r.center.dy - tp.height / 2));
      _paintCaret(canvas,
          Offset(tTextCx + tp.width / 2 + 7, r.center.dy), collapsed);
      canvas.restore();
    }
  }

    void _drawNode(Canvas canvas, PedigreeNode n, Rect r,
      {required bool selected,
      PedigreeNodeKind? selHalf,
      Color? glow,
      PedigreeNodeKind? glowHalf,
      bool picked = false,
      PedigreeNodeKind? pickedHalf,
      bool connected = false,
      PedigreeNodeKind? soloHalf,
      bool dim = false}) {
    // v2.19.5 性别互斥弱化：不可连接节点变暗——光环全灭、底色/边框
    // 降到 30%/40% alpha。形状/基因型文字保留（不删信息），只压暗。
    if (dim) {
      glow = null;
      connected = false;
      picked = false;
      selected = false;
    }
    // R15：trackSex 下 group 桶渲染为组合体（大矩形内含雄□雌○），
    // 半边可独立点选/连线；文字行移到矩形下方，避免挤压 glyph。
    if (sexSplitView && n.kind == PedigreeNodeKind.group) {
      _drawComboNode(canvas, n, r,
          selected: selected,
          selHalf: selHalf,
          glow: glow,
          glowHalf: glowHalf,
          picked: picked,
          pickedHalf: pickedHalf,
          connected: connected,
          soloHalf: soloHalf);
      return;
    }
    final bool male = n.kind == PedigreeNodeKind.male;
    final bool female = n.kind == PedigreeNodeKind.female;

    // 配色全走 token：male=teal 系，female=sand 系，group=中性灰系；
    // v2.1i 致死子代：边框 lethal 红，填充 lethal 浅色（alpha 0.12），
    // 末尾再画对角 ✕ 与概率文字「致死」。
    final Color fill = n.isLethal
        ? AppColors.lethal.withValues(alpha: 0.12)
        : male
            ? AppColors.tealWash
            : female
                ? AppColors.surface
                : AppColors.canvas;
    final Color border = n.isLethal
        ? AppColors.lethal
        : male
            ? AppColors.teal
            : female
                ? AppColors.sand
                : AppColors.border;
    // v2.19.5 dim：底色/边框压暗（组合桶半边 dim 已有 isSoloDim 体系，
    // 此处为整节点粒度）。
    final Color fillF =
        dim ? AppColors.canvas.withValues(alpha: 0.30) : fill;
    final Color borderF =
        dim ? AppColors.border.withValues(alpha: 0.4) : border;

    // R12 光晕：待命（armed 紫罗兰）/ 连线成功（flash 金色），
    // 高斯模糊外发光 + 同色描边环，任何主题下都醒目。
    if (glow != null) {
      final halo = Paint()..isAntiAlias = true
        ..color = glow.withValues(alpha: 0.85)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      final hr = r.inflate(7);
      if (male) {
        canvas.drawRect(hr, halo);
      } else if (female) {
        canvas.drawOval(hr, halo);
      } else {
        canvas.drawRRect(
            RRect.fromRectAndRadius(hr, const Radius.circular(14)), halo);
      }
    } else if (connected) {
      // R23 相连元素柔光：**醒目亮蓝**（用户反馈浅青绿不够明显）——
      // 外发光 + 亮蓝描边，与 armed(紫)/selected(青实框)/flash(金) 区分
      final halo = Paint()..isAntiAlias = true
        ..color = _connectedBlue.withValues(alpha: 0.40)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      final hr = r.inflate(6);
      if (male) {
        canvas.drawRect(hr, halo);
      } else if (female) {
        canvas.drawOval(hr, halo);
      } else {
        canvas.drawRRect(
            RRect.fromRectAndRadius(hr, const Radius.circular(14)), halo);
      }
      final soft = Paint()..isAntiAlias = true
        ..color = _connectedBlue
        ..style = PaintingStyle.stroke
        ..strokeWidth = _kStroke(2.8);
      final out = r.inflate(3);
      if (male) {
        canvas.drawRect(out, soft);
      } else if (female) {
        canvas.drawOval(out, soft);
      } else {
        canvas.drawRRect(
            RRect.fromRectAndRadius(out, const Radius.circular(12)), soft);
      }
    }

    final fillPaint = Paint()..isAntiAlias = true..color = fillF;

    final borderPaint = Paint()..isAntiAlias = true
      ..color = borderF
      ..style = PaintingStyle.stroke
      ..strokeWidth = _kStroke(1.6);

    if (male) {
      canvas.drawRect(r, fillPaint);
      canvas.drawRect(r, borderPaint);
    } else if (female) {
      canvas.drawOval(r, fillPaint);
      canvas.drawOval(r, borderPaint);
    } else {
      final rr = RRect.fromRectAndRadius(r, const Radius.circular(10));
      canvas.drawRRect(rr, fillPaint);
      canvas.drawRRect(rr, borderPaint);
    }

    // R1：选中框与节点形状严格对齐（世界坐标同一 rect 外扩 3px）
    // R24：选中 = 显眼红「外发光 + 同色描边环」，无动画
    if (selected) {
      final halo = Paint()..isAntiAlias = true
        ..color = _selectedRed.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      final hr = r.inflate(7);
      if (male) {
        canvas.drawRect(hr, halo);
      } else if (female) {
        canvas.drawOval(hr, halo);
      } else {
        canvas.drawRRect(
            RRect.fromRectAndRadius(hr, const Radius.circular(14)), halo);
      }
      final selPaint = Paint()..isAntiAlias = true
        ..color = _selectedRed
        ..style = PaintingStyle.stroke
        ..strokeWidth = _kStroke(2.6);
      final out = r.inflate(3.5);
      if (male) {
        canvas.drawRect(out, selPaint);
      } else if (female) {
        canvas.drawOval(out, selPaint);
      } else {
        canvas.drawRRect(
            RRect.fromRectAndRadius(out, const Radius.circular(12)), selPaint);
      }
    }

    if (glow != null) {
      final ring = Paint()..isAntiAlias = true
        ..color = glow
        ..style = PaintingStyle.stroke
        ..strokeWidth = _kStroke(3.0);
      final rr = r.inflate(4);
      if (male) {
        canvas.drawRect(rr, ring);
      } else if (female) {
        canvas.drawOval(rr, ring);
      } else {
        canvas.drawRRect(
            RRect.fromRectAndRadius(rr, const Radius.circular(13)), ring);
      }
    }

    // R15 选择模式勾选高亮：teal 粗环 + 右上角 ✓ 徽章
    if (picked) {
      final pk = Paint()..isAntiAlias = true
        ..color = AppColors.teal
        ..style = PaintingStyle.stroke
        ..strokeWidth = _kStroke(3.0);
      final out = r.inflate(6.5);
      if (male) {
        canvas.drawRect(out, pk);
      } else if (female) {
        canvas.drawOval(out, pk);
      } else {
        canvas.drawRRect(
            RRect.fromRectAndRadius(out, const Radius.circular(12)), pk);
      }
      _paintCheckBadge(canvas, Offset(r.right, r.top));
    }

    // 节点内：基因型（等宽；伴性染色走共用 helper，组合桶复用）
    final geno = _genoPainter(n, r.width - 6,
        fontSize: n.kind == PedigreeNodeKind.group ? 13 : 12);
    final annotTp = _annotPainter(n, r.width - 6);

    final String sub = n.isExternal
        ? '外来'
        : '${(n.probability * 100).toStringAsFixed(1)}%';
    final subTp = TextPainter(
      text: TextSpan(
          text: sub,
          style: AppText.monoSmall.copyWith(
              fontSize: 10,
              color: n.isExternal ? AppColors.sand : AppColors.steel)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: r.width - 6);

    // XY 性别存证：桶内雌雄比（标准 XY 决定 = 1:1），
    // 并配合 形状语义（X=圆圈 / Y=方块）——但桶本身是中性群体节点，
    // 这里只画「○X/●Y」图例提示性别组成，桶形状保持圆角矩形不变。
    TextPainter? sexTp;
    if (n.maleFraction != null) {
      final m = (n.maleFraction! * 100).round();
      sexTp = TextPainter(
        text: TextSpan(
            text: '○X $m%  ●Y ${100 - m}%',
            style:
                AppText.monoSmall.copyWith(fontSize: 9, color: AppColors.graphite)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout(maxWidth: r.width - 6);
    }

    // v2.19.6 polish（学生走查 #1）：dim 状态下文本压暗 0.4 alpha——
    // saveLayer 包裹后续 paint 至 ✕ 致死角标之前（致死标不在 dim 影响
    // 范围）。helper 返回的多 TextSpan color 无需逐个改签名。
    bool hasDimLayer = false;
    if (dim) {
      canvas.saveLayer(r.inflate(8),
          Paint()..color = const Color(0x66666666));
      hasDimLayer = true;
    }

    final totalH = geno.height +
        2 +
        subTp.height +
        (sexTp != null ? 2 + sexTp.height : 0) +
        (annotTp != null ? 2 + annotTp.height : 0);
    final startY = r.center.dy - totalH / 2;
    geno.paint(canvas, Offset(r.center.dx - geno.width / 2, startY));
    subTp.paint(
        canvas, Offset(r.center.dx - subTp.width / 2, startY + geno.height + 2));
    var nextY = startY + geno.height + 2 + subTp.height;
    if (sexTp != null) {
      nextY += 2;
      sexTp.paint(canvas, Offset(r.center.dx - sexTp.width / 2, nextY));
      nextY += sexTp.height;
    }
    if (annotTp != null) {
      nextY += 2;
      annotTp.paint(canvas, Offset(r.center.dx - annotTp.width / 2, nextY));
    }
    if (hasDimLayer) canvas.restore();
    // v2.1i 致死子代：对角 ✕ + 「致死」角标
    if (n.isLethal) {
      final xPaint = Paint()..isAntiAlias = true
        ..color = AppColors.lethal
        ..strokeWidth = _kStroke(2.4)
        ..strokeCap = StrokeCap.round;
      final pad = 4.0;
      canvas.drawLine(
          Offset(r.left + pad, r.top + pad), Offset(r.right - pad, r.bottom - pad),
          xPaint);
      canvas.drawLine(
          Offset(r.right - pad, r.top + pad), Offset(r.left + pad, r.bottom - pad),
          xPaint);
      // 「致死」徽标（节点右下角小标签）
      const badge = '致死';
      final badgeTp = TextPainter(
        text: TextSpan(
            text: badge,
            // v2.19.32：CustomPainter 内无 BuildContext，裸 TextStyle 不会
            // 继承主题字体 → golden 里「致死」渲染成方框（golden_font_guard
            // C 组实测病灶）。以 AppText.caption 为底子补家族。
            style: AppText.caption.copyWith(
                color: AppColors.canvas,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5)),
        textDirection: TextDirection.ltr,
      )..layout();
      final badgeW = badgeTp.width + 8;
      final badgeH = badgeTp.height + 3;
      final badgeRect = RRect.fromRectAndRadius(
          Rect.fromLTWH(r.right - badgeW + 2, r.bottom - badgeH + 2, badgeW, badgeH),
          const Radius.circular(4));
      canvas.drawRRect(badgeRect, Paint()..isAntiAlias = true..color = AppColors.lethal);
      badgeTp.paint(canvas,
          Offset(r.right - badgeW + 6, r.bottom - badgeH + 3.5));
    }
  }

  /// 基因型 TextPainter（伴性染色：X 大写蓝 / x 小写黄，Y 同规则）。
  TextPainter _genoPainter(PedigreeNode n, double maxWidth,
      {double fontSize = 12}) {
    final genoStyle =
        AppText.genotype.copyWith(fontSize: fontSize, height: 1.1);
    final cfg = sexLinked;
    if (cfg != null && !cfg.isEmpty) {
      final segs = cfg.annotate(n.genotype);
      return TextPainter(
        text: TextSpan(
          children: [
            for (final s in segs)
              TextSpan(
                text: s.allele,
                style: !s.isSexLinked
                    ? genoStyle
                    : genoStyle.copyWith(
                        fontWeight: FontWeight.w700,
                        color: s.isUpper
                            ? AppColors.sexUpper
                            : AppColors.sexLower),
              ),
          ],
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        textAlign: TextAlign.center,
      )..layout(maxWidth: maxWidth);
    }
    return TextPainter(
      text: TextSpan(text: n.genotype, style: genoStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      textAlign: TextAlign.center,
    )..layout(maxWidth: maxWidth);
  }

  /// 标注行：基因缺失（R18，基因型含 '-' 时「基因缺失」警示）+
  /// 伴性表型标注（「X=病 x=正常」）；两者可同现，均无返回 null。
  TextPainter? _annotPainter(PedigreeNode n, double maxWidth) {
    final spans = <TextSpan>[];
    void gap() => spans.add(
        TextSpan(text: ' ', style: AppText.monoSmall.copyWith(fontSize: 9)));

    // R18 基因缺失：缺失位点以 '-' 落在基因型里，节点上给出显性标注
    if (n.genotype.contains('-')) {
      spans.add(TextSpan(
        text: '基因缺失',
        style: AppText.monoSmall.copyWith(
            fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.armed),
      ));
    }

    final cfg = sexLinked;
    if (cfg != null && !cfg.isEmpty) {
      final labeled = cfg
          .annotate(n.genotype)
          .where((s) => s.isSexLinked && (s.label?.isNotEmpty ?? false))
          .toList();
      for (var i = 0; i < labeled.length; i++) {
        if (spans.isNotEmpty) gap();
        spans.add(TextSpan(
          text: '${labeled[i].allele}=${labeled[i].label}',
          style: AppText.monoSmall.copyWith(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color:
                  labeled[i].isUpper ? AppColors.sexUpper : AppColors.sexLower),
        ));
      }
    }
    if (spans.isEmpty) return null;
    return TextPainter(
      text: TextSpan(children: spans),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      textAlign: TextAlign.center,
    )..layout(maxWidth: maxWidth);
  }

  /// R15 组合桶：group 桶 = 大圆角矩形内含 雄□（左，teal 系）+
  /// 雌○（右，sand 系）；基因型置顶，概率/雌雄比/伴性标注行移到矩形
  /// 下方（内部留给 glyph）。半边可单独发光/选中/勾选。
  void _drawComboNode(Canvas canvas, PedigreeNode n, Rect r,
      {required bool selected,
      PedigreeNodeKind? selHalf,
      Color? glow,
      PedigreeNodeKind? glowHalf,
      required bool picked,
      PedigreeNodeKind? pickedHalf,
      bool connected = false,
      PedigreeNodeKind? soloHalf}) {
    final connKinds = connectedIds[n.id];
    // 整桶光晕（glowHalf 为 null = 光晕作用于整个组合体）
    if (glow != null && glowHalf == null) {
      final halo = Paint()..isAntiAlias = true
        ..color = glow.withValues(alpha: 0.85)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      canvas.drawRRect(
          RRect.fromRectAndRadius(r.inflate(7), const Radius.circular(14)),
          halo);
    }

    // 外大圆角矩形（中性灰系，与普通 group 桶一致）
    final outer = RRect.fromRectAndRadius(r, const Radius.circular(10));
    canvas.drawRRect(outer, Paint()..isAntiAlias = true..color = AppColors.canvas);
    canvas.drawRRect(
        outer,
        Paint()..isAntiAlias = true
          ..color = AppColors.border
          ..style = PaintingStyle.stroke
          ..strokeWidth = _kStroke(1.6));
    if (selected && selHalf == null && soloHalf == null) {
      // R24：整桶选中 = 红色外发光 + 红描边（无跑马灯动画）
      final halo = Paint()..isAntiAlias = true
        ..color = _selectedRed.withValues(alpha: 0.55)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      canvas.drawRRect(
          RRect.fromRectAndRadius(r.inflate(7), const Radius.circular(14)),
          halo);
      canvas.drawRRect(
          RRect.fromRectAndRadius(r.inflate(3.5), const Radius.circular(12)),
          Paint()..isAntiAlias = true
            ..color = _selectedRed
            ..style = PaintingStyle.stroke
            ..strokeWidth = _kStroke(2.6));
    }
    if (glow != null && glowHalf == null) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(r.inflate(4), const Radius.circular(13)),
          Paint()..isAntiAlias = true
            ..color = glow
            ..style = PaintingStyle.stroke
            ..strokeWidth = _kStroke(3.0));
    } else if (connected) {
      // R30.2（用户反馈修正）：相连高亮**永不作用于整框**——只有两个
      // glyph（雄□/雌○）亮蓝。整桶相连（group 端 / 双 half）时两个
      // glyph 都亮；单 half 只亮对应 glyph（见下方循环）。
    }

    // 顶部基因型（伴性染色共用 helper）
    final geno = _genoPainter(n, r.width - 8, fontSize: 11);
    geno.paint(canvas, Offset(r.center.dx - geno.width / 2, r.top + 4));

    // 雄□ / 雌○ 半边 glyph
    for (final sex in const [PedigreeNodeKind.male, PedigreeNodeKind.female]) {
      final hr = halfRectOf(r, sex);
      final male = sex == PedigreeNodeKind.male;
      // R24 半边专注：非专注半边只画淡占位（不响应任何高亮/勾选）；
      // 选中明确半边时，另一半联动淡化（"我只圈了这个小方块"）
      final isSoloDim = (soloHalf != null && sex != soloHalf) ||
          (selected && selHalf != null && sex != selHalf);
      // R30.2 半边粒度相连柔光：整桶相连（group 端/双 half）→ 两个
      // glyph 都亮；单 half → 只亮对应半边（重命名 halfConnected →
      // glyphConnected 覆盖两种）
      final wholeConn = connected &&
          connKinds != null &&
          (connKinds.contains(PedigreeNodeKind.group) ||
              (connKinds.contains(PedigreeNodeKind.male) &&
                  connKinds.contains(PedigreeNodeKind.female)));
      final glyphConnected = connected &&
          connKinds != null &&
          (wholeConn || connKinds.contains(sex));
      if (glyphConnected && !isSoloDim) {
        final halo = Paint()..isAntiAlias = true
          ..color = _connectedBlue.withValues(alpha: 0.45)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
        final hh = hr.inflate(5);
        if (male) {
          canvas.drawRect(hh, halo);
        } else {
          canvas.drawOval(hh, halo);
        }
        final soft = Paint()..isAntiAlias = true
          ..color = _connectedBlue
          ..style = PaintingStyle.stroke
          ..strokeWidth = _kStroke(2.6);
        final so = hr.inflate(2.5);
        if (male) {
          canvas.drawRect(so, soft);
        } else {
          canvas.drawOval(so, soft);
        }
      }
      final halfGlow =
          isSoloDim ? null : (glow != null && glowHalf == sex ? glow : null);
      if (halfGlow != null) {
        final halo = Paint()..isAntiAlias = true
          ..color = halfGlow.withValues(alpha: 0.85)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
        if (male) {
          canvas.drawRect(hr.inflate(5), halo);
        } else {
          canvas.drawOval(hr.inflate(5), halo);
        }
      }
      final fillPaint = Paint()..isAntiAlias = true
        ..color = isSoloDim
            ? AppColors.canvas.withValues(alpha: 0.30)
            : male
                ? AppColors.tealWash
                : AppColors.surface;
      final borderPaint = Paint()..isAntiAlias = true
        ..color = isSoloDim
            ? AppColors.border.withValues(alpha: 0.4)
            : male
                ? AppColors.teal
                : AppColors.sand
        ..style = PaintingStyle.stroke
        ..strokeWidth = _kStroke(1.6);
      if (male) {
        canvas.drawRect(hr, fillPaint);
        canvas.drawRect(hr, borderPaint);
      } else {
        canvas.drawOval(hr, fillPaint);
        canvas.drawOval(hr, borderPaint);
      }
      if (selected && selHalf == sex && !isSoloDim) {
        // R24：半边选中 = 红色外发光 + 红描边（绕小方块/小圆圈）
        final halo = Paint()..isAntiAlias = true
          ..color = _selectedRed.withValues(alpha: 0.55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
        final hh = hr.inflate(6);
        if (male) {
          canvas.drawRect(hh, halo);
        } else {
          canvas.drawOval(hh, halo);
        }
        final sp = Paint()..isAntiAlias = true
          ..color = _selectedRed
          ..style = PaintingStyle.stroke
          ..strokeWidth = _kStroke(2.6);
        final so = hr.inflate(3);
        if (male) {
          canvas.drawRect(so, sp);
        } else {
          canvas.drawOval(so, sp);
        }
      }
      if (halfGlow != null && !isSoloDim) {
        final ring = Paint()..isAntiAlias = true
          ..color = halfGlow
          ..style = PaintingStyle.stroke
          ..strokeWidth = _kStroke(2.8);
        final ro = hr.inflate(3.5);
        if (male) {
          canvas.drawRect(ro, ring);
        } else {
          canvas.drawOval(ro, ring);
        }
      }
      if (picked && !isSoloDim && (pickedHalf == sex || pickedHalf == null)) {
        final pk = Paint()..isAntiAlias = true
          ..color = AppColors.teal
          ..style = PaintingStyle.stroke
          ..strokeWidth = _kStroke(2.8);
        final po = hr.inflate(5.5);
        if (male) {
          canvas.drawRect(po, pk);
        } else {
          canvas.drawOval(po, pk);
        }
        _paintCheckBadge(canvas, Offset(hr.right, hr.top));
      }
    }

    // 矩形下方：概率 + 雌雄比合并行；伴性标注再一行
    final pct = (n.probability * 100).toStringAsFixed(1);
    final m = n.maleFraction;
    final subText = m != null
        ? '$pct%  ○${(m * 100).round()}% ●${(100 - m * 100).round()}%'
        : '$pct%';
    final subTp = TextPainter(
      text: TextSpan(
          text: subText,
          style:
              AppText.monoSmall.copyWith(fontSize: 9, color: AppColors.steel)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: r.width + 60);
    subTp.paint(
        canvas, Offset(r.center.dx - subTp.width / 2, r.bottom + 3));
    final annot = _annotPainter(n, r.width + 60);
    if (annot != null) {
      annot.paint(
          canvas, Offset(r.center.dx - annot.width / 2, r.bottom + 16));
    }
  }

  /// R30：总线主干竖线——**绕卡路由**（替代 R28 裁剪断口，用户反馈
  /// "裁剪后组段汇接不到竖线=断"）。从 y0 到 y1（可反向）扫描：遇到
  /// 与当前 x 相交的节点矩形，在该卡片上下边缘水平绕行到无冲突的
  /// x'，竖线绕过卡片后回到原 x 继续。全程连续、任何高度的组横线
  /// 都能与竖线汇接；找不到绕行位时退化为裁剪分段（罕见兜底）。
  void _drawRoutedTrunk(
      Canvas canvas, double x, double y0, double y1) {
    if (y0 == y1) return;
    final paint = Paint()..isAntiAlias = true
      ..color = AppColors.graphite
      ..style = PaintingStyle.stroke
      ..strokeWidth = _kStroke(1.6);
    final dir = y1 >= y0 ? 1.0 : -1.0;

    Rect? cardAt(double cx, double from, double to) {
      Rect? best;
      for (final n in nodes) {
        final rr = rects[n.id];
        if (rr == null) continue;
        if (cx >= rr.left - 1 && cx <= rr.right + 1 &&
            rr.top < to && rr.bottom > from) {
          if (best == null || rr.top < best.top) best = rr;
        }
      }
      return best;
    }

    var cy = y0;
    var guard = 0;
    // v2.18 连线断层修复：原 guard < 40——密集系谱（家族分栏很宽时
    // 每代每个桶都被 cardAt 计入） easily 超 40 次迭代，循环提前
    // 退出后 [cy, y1] 剩余段再也不画 → 主干悬空断层（用户实测偶发，
    // 点「计算」重排后消失）。guard 提到 10000（循环本就会因 cy
    // 严格递增而自然终止），且退出后强制补画尾段——闭合保证。
    while ((dir > 0 ? cy < y1 - 0.5 : cy > y1 + 0.5) && guard++ < 10000) {
      final from = math.min(cy, y1);
      final to = math.max(cy, y1);
      final card = cardAt(x, from, to);
      if (card == null) {
        canvas.drawLine(Offset(x, cy), Offset(x, y1), paint);
        break;
      }
      // 画到卡片上缘，水平绕到无冲突 x'，竖线过卡，水平回原 x
      final stopY = card.top;
      if ((dir > 0 && stopY > cy) || (dir < 0 && stopY < cy)) {
        canvas.drawLine(Offset(x, cy), Offset(x, stopY), paint);
      }
      double? xp;
      // 搜索半径 340 → 1200：大家族密集区原半径内无处可绕就走
      // 「跳卡兜底」留下可见断口。
      for (var step = 8.0; step < 1200.0 && xp == null; step += 12) {
        for (final sign in <double>[1, -1]) {
          final cand = x + step * sign;
          if (cardAt(cand, card.top, card.bottom) == null) {
            xp = cand;
            break;
          }
        }
      }
      if (xp == null) {
        // R30 原则「始终闭合」优于「不穿卡」：无处可绕时穿卡直连——
        // 连续的线条穿过半透明卡片，比凭空消失好（断层是用户明报
        // 的 bug，穿卡只是可接受的视觉妥协）。
        canvas.drawLine(Offset(x, cy), Offset(x, card.bottom), paint);
        cy = card.bottom;
        continue;
      }
      canvas.drawLine(Offset(x, stopY), Offset(xp, stopY), paint);
      canvas.drawLine(Offset(xp, stopY), Offset(xp, card.bottom), paint);
      canvas.drawLine(Offset(xp, card.bottom), Offset(x, card.bottom), paint);
      cy = card.bottom;
    }
    // 闭合兜底：任何路径退出后若未画到 y1，强制补尾段（防悬空）。
    if ((dir > 0 && cy < y1 - 0.5) || (dir < 0 && cy > y1 + 0.5)) {
      canvas.drawLine(Offset(x, cy), Offset(x, y1), paint);
    }
  }

  void _paintCheckBadge(Canvas canvas, Offset at) {
    canvas.drawCircle(at, 8, Paint()..isAntiAlias = true..color = AppColors.teal);
    // v2.12: 背景固定为 AppColors.teal(主题色),用 onTeal 单一事实源
    // (浅色 white / 暗色 #16211B 墨绿)与 ColorScheme.onPrimary 对齐。
    final tp = TextPainter(
      text: TextSpan(
          text: '✓',
          // 同「致死」徽标：painter 内裸 style 会渲染成方框，补家族。
          style: AppText.caption.copyWith(
              color: AppColors.onTeal,
              fontSize: 10,
              fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(at.dx - tp.width / 2, at.dy - tp.height / 2));
  }

  /// 带底色的边标签（R13）：画布色底 + 同色细边框，
  /// 压在交错的线上也可读——回交标签专用。
  void _paintLabelPill(Canvas canvas, String text, Offset center, Color color) {
    final tp = TextPainter(
      text: TextSpan(
          text: text,
          style: AppText.monoSmall
              .copyWith(fontSize: 10, color: color, fontWeight: FontWeight.w600)),
      textDirection: TextDirection.ltr,
    )..layout();
    final rect = Rect.fromCenter(
        center: center, width: tp.width + 12, height: tp.height + 6);
    final rr = RRect.fromRectAndRadius(rect, const Radius.circular(8));
    canvas.drawRRect(rr, Paint()..isAntiAlias = true..color = AppColors.canvas);
    canvas.drawRRect(
        rr,
        Paint()..isAntiAlias = true
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = _kStroke(1.0));
    tp.paint(
        canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  /// 展开/收起指示三角：[down] 为 true 画下三角（可展开），
  /// false 画上三角（可收起）——表达「此徽标可点击」。
  void _paintCaret(Canvas canvas, Offset center, bool down) {
    const w = 5.0, h = 8.0;
    final path = Path();
    if (down) {
      path
        ..moveTo(center.dx - w, center.dy - h / 2)
        ..lineTo(center.dx + w, center.dy - h / 2)
        ..lineTo(center.dx, center.dy + h / 2);
    } else {
      path
        ..moveTo(center.dx - w, center.dy + h / 2)
        ..lineTo(center.dx + w, center.dy + h / 2)
        ..lineTo(center.dx, center.dy - h / 2);
    }
    path.close();
    canvas.drawPath(
        path, Paint()..isAntiAlias = true..color = AppColors.teal);
  }

  void _paintText(Canvas canvas, String text, Offset at, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }
}
