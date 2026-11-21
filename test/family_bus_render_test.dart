// family_bus_render_test.dart —— R14/R15 多家族 lineage 总线回归
//
// 复现场景：两个家族各自独立迭代、无任何跨家族连线。修复前 lineage
// 总线按「子代世代」分组，收集横线横跨两栏，视觉上像两家族连在一起；
// 修复后按「子代世代×家族」分组，各家族总线收在自己栏内。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/engine/pedigree_graph.dart';
import 'package:biology/pages/widgets/pedigree_canvas.dart';
import 'golden_fonts.dart';

// 跑马灯动画在 widget 测试中禁用（常驻 repeat 会让 pumpAndSettle 永不 settle）
void main() {
  testWidgets('两家族独立迭代：栏间无跨家族总线横线', (tester) async {
    await loadGoldenFonts();
    assertMaterialIconsLoaded();
    assertMonoLoaded();

    const nodes = [
      // 家族 A
      PedigreeNode(
          id: 'P-father',
          kind: PedigreeNodeKind.male,
          genotype: 'AABBCC',
          generation: 0,
          probability: 1.0,
          isExternal: false),
      PedigreeNode(
          id: 'P-mother',
          kind: PedigreeNodeKind.female,
          genotype: 'aabbcc',
          generation: 0,
          probability: 1.0,
          isExternal: false),
      PedigreeNode(
          id: 'F1#0',
          kind: PedigreeNodeKind.group,
          genotype: 'AaBbCc',
          generation: 1,
          probability: 1.0,
          isExternal: false,
          maleFraction: 0.5),
      // 家族 B
      PedigreeNode(
          id: 'P1-father',
          kind: PedigreeNodeKind.male,
          genotype: 'AABBCC',
          generation: 0,
          probability: 1.0,
          isExternal: false,
          familyId: 1),
      PedigreeNode(
          id: 'P1-mother',
          kind: PedigreeNodeKind.female,
          genotype: 'AABBCC',
          generation: 0,
          probability: 1.0,
          isExternal: false,
          familyId: 1),
      PedigreeNode(
          id: 'F1#1',
          kind: PedigreeNodeKind.group,
          genotype: 'AABBCC',
          generation: 1,
          probability: 1.0,
          isExternal: false,
          maleFraction: 0.5,
          familyId: 1),
    ];
    const edges = [
      PedigreeEdge('P-father', 'P-mother', PedigreeEdgeKind.mating),
      PedigreeEdge('P1-father', 'P1-mother', PedigreeEdgeKind.mating),
      PedigreeEdge('P-father', 'F1#0', PedigreeEdgeKind.lineage),
      PedigreeEdge('P-mother', 'F1#0', PedigreeEdgeKind.lineage),
      PedigreeEdge('P1-father', 'F1#1', PedigreeEdgeKind.lineage),
      PedigreeEdge('P1-mother', 'F1#1', PedigreeEdgeKind.lineage),
    ];
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 560,
            height: 380,
            child: PedigreeCanvas(
              nodes: nodes,
              edges: edges,
              familyLabels: {0: '家族 A', 1: '家族 B'},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(PedigreeCanvas),
      matchesGoldenFile('goldens/two_families_bus.png'),
    );
  });

  testWidgets('Z 形婚配线特写：两个节点存在高度差时正交连接端点贴元素', (tester) async {
    await loadGoldenFonts();
    assertMaterialIconsLoaded();
    assertMonoLoaded();

    // 两家族 P 代节点，家族 1 被拖低（familyOffsets）→ 同代婚配线
    // 一端点高、一端点低。旧实现把两端 y 拉平导致悬空；R24 改
    // Z 字形正交后两端必须仍然贴在节点边缘。
    const nodes = [
      PedigreeNode(
          id: 'P-father',
          kind: PedigreeNodeKind.male,
          genotype: 'Aa',
          generation: 0,
          probability: 1.0,
          isExternal: false,
          familyId: 0),
      PedigreeNode(
          id: 'P-mother',
          kind: PedigreeNodeKind.female,
          genotype: 'aa',
          generation: 0,
          probability: 1.0,
          isExternal: false,
          familyId: 1),
    ];
    const edges = [PedigreeEdge('P-father', 'P-mother', PedigreeEdgeKind.mating)];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 320,
          height: 260,
          child: PedigreeCanvas(
            nodes: nodes,
            edges: edges,
            familyLabels: const {0: 'A', 1: 'B'},
            familyOffsets: const {1: Offset(0, 90)}, // 家族 B 被拖低
            sexSplitView: false,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(PedigreeCanvas),
      matchesGoldenFile('goldens/mating_z_line.png'),
    );
  });

  testWidgets('跨家族合计总线：家族高度错位时各组汇接段闭合不悬空（R27）',
      (tester) async {
    await loadGoldenFonts();
    assertMaterialIconsLoaded();
    assertMonoLoaded();

    // 家族 B 被拖低（familyOffsets）→ 两个父母组的收集线高度不同。
    // 修复前 trunk 从最下方收集线开始，较高的组汇接段悬空断裂
    //（截图显示"中间缺一段"）。R27 后 trunk 从最上方收集线贯穿，
    // 各组段全闭合。
    const nodes = [
      PedigreeNode(
          id: 'P-father',
          kind: PedigreeNodeKind.male,
          genotype: 'Aa',
          generation: 0,
          probability: 1.0,
          isExternal: false,
          familyId: 0),
      PedigreeNode(
          id: 'P-mother',
          kind: PedigreeNodeKind.female,
          genotype: 'aa',
          generation: 0,
          probability: 1.0,
          isExternal: false,
          familyId: 1),
      PedigreeNode(
          id: 'C1#0',
          kind: PedigreeNodeKind.group,
          genotype: 'Aa',
          generation: 1,
          probability: 1.0,
          isExternal: false,
          maleFraction: 0.5,
          familyId: 2), // 合并家族 A×B
    ];
    const edges = [
      PedigreeEdge('P-father', 'C1#0', PedigreeEdgeKind.lineage),
      PedigreeEdge('P-mother', 'C1#0', PedigreeEdgeKind.lineage),
    ];
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 420,
          height: 320,
          child: PedigreeCanvas(
            nodes: nodes,
            edges: edges,
            familyLabels: {0: 'A', 1: 'B', 2: 'A×B'},
            familyOffsets: {1: Offset(0, 70)}, // 家族 B 拖低
            sexSplitView: false,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(PedigreeCanvas),
      matchesGoldenFile('goldens/cross_family_bus_gap.png'),
    );
  });

  testWidgets('深反向拖拽：贡献者被拖到子女下方 150 时总线闭合不穿卡（R28）',
      (tester) async {
    await loadGoldenFonts();
    assertMaterialIconsLoaded();
    assertMonoLoaded();

    // 贡献者（家族A）被大幅拖低 → 子女（合并家族 A×B）相对在上方，
    // barMin > bar2Y（反向）。R28 前 trunk 竖线区间反转导致 blocker
    // 不生效、竖线直穿卡片=视觉断线；R28 后按节点矩形裁剪分段、
    // blocker 区间归正，总线闭合。
    const nodes = [
      PedigreeNode(
          id: 'P-father',
          kind: PedigreeNodeKind.male,
          genotype: 'Aa',
          generation: 0,
          probability: 1.0,
          isExternal: false,
          familyId: 0),
      PedigreeNode(
          id: 'P-mother',
          kind: PedigreeNodeKind.female,
          genotype: 'aa',
          generation: 0,
          probability: 1.0,
          isExternal: false,
          familyId: 1),
      PedigreeNode(
          id: 'C1#0',
          kind: PedigreeNodeKind.group,
          genotype: 'Aa',
          generation: 1,
          probability: 1.0,
          isExternal: false,
          maleFraction: 0.5,
          familyId: 2), // 合并家族 A×B（未拖，位置在上方）
    ];
    const edges = [
      PedigreeEdge('P-father', 'C1#0', PedigreeEdgeKind.lineage),
      PedigreeEdge('P-mother', 'C1#0', PedigreeEdgeKind.lineage),
    ];
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 420,
          height: 360,
          child: PedigreeCanvas(
            nodes: nodes,
            edges: edges,
            familyLabels: {0: 'A', 1: 'B', 2: 'A×B'},
            familyOffsets: {0: Offset(0, 150), 1: Offset(120, 150)}, // 父母拖低
            sexSplitView: false,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(PedigreeCanvas),
      matchesGoldenFile('goldens/bus_reverse_deep.png'),
    );
  });
}
