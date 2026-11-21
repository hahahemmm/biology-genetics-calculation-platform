// combo_bucket_render_test.dart —— R15 组合桶特写金色图
//
// 单桶 1:1 大比例渲染，像素级锁定组合桶结构（大矩形内含 雄□+雌○，
// 半边光晕）。整页截图分辨率太低（节点仅 ~26px），无法回归 glyph 级
// 渲染细节，故单设此特写。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/engine/pedigree_graph.dart';
import 'package:biology/pages/widgets/pedigree_canvas.dart';
import 'golden_fonts.dart';

// 跑马灯动画在 widget 测试中禁用（常驻 repeat 会让 pumpAndSettle 永不 settle）
void main() {

  testWidgets('R30 选中雄 + 相连B雄：A不整蓝、只亮对应半边（用户反馈验证）',
      (tester) async {
    await loadGoldenFonts();
    assertMaterialIconsLoaded();
    assertMonoLoaded();

    const nodes = [
      PedigreeNode(
          id: 'F1A',
          kind: PedigreeNodeKind.group,
          genotype: 'AaBbCc',
          generation: 1,
          probability: 1.0,
          isExternal: false,
          maleFraction: 0.5,
          familyId: 0),
      PedigreeNode(
          id: 'F1B',
          kind: PedigreeNodeKind.group,
          genotype: 'aabbcc',
          generation: 1,
          probability: 1.0,
          isExternal: false,
          maleFraction: 0.5,
          familyId: 1),
    ];
    const connected = <String, Set<PedigreeNodeKind>>{
      'F1B': {PedigreeNodeKind.male}, // 选中 A 雌时，B 只亮雄
    };
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 200,
          child: PedigreeCanvas(
            nodes: nodes,
            edges: [],
            selectedId: 'F1A::male',
            sexSplitView: true,
            familyLabels: {0: 'A', 1: 'B'},
            connectedIds: connected,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(PedigreeCanvas),
      matchesGoldenFile('goldens/combo_selected_connected.png'),
    );
  });
  testWidgets('R15 组合桶特写：雄□雌○ + 雄半边 armed 紫光', (tester) async {
    await loadGoldenFonts();
    assertMaterialIconsLoaded();
    assertMonoLoaded();

    final nodes = [
      const PedigreeNode(
        id: 'F1#1',
        kind: PedigreeNodeKind.group,
        genotype: 'AaBbCc',
        generation: 1,
        probability: 1.0,
        isExternal: false,
        maleFraction: 0.5,
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: PedigreeCanvas(
              nodes: nodes,
              edges: const [],
              sexSplitView: true,
              armedId: halfTapId('F1#1', PedigreeNodeKind.male), // 雄半边紫光
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(PedigreeCanvas),
      matchesGoldenFile('goldens/combo_bucket_closeup.png'),
    );
  });
}
