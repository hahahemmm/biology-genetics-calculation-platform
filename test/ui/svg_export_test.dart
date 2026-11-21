// svg_export_test.dart —— 系谱图板书 SVG 导出单元测试（v2.12 Wave 3-A fix）
//
// 覆盖（任务派工指令 T-A 缺陷 2）：
//   1. 空节点列表 → 返回合法占位 viewBox，不抛
//   2. 单节点 → SVG 含 1 个对应元素，居中
//   3. lethal 节点 → SVG 含 ✕ 文本（缺陷 1 修完的回归测试）
//   4. male 节点 → <rect> 方形
//   5. female 节点 → <circle>
//   6. group 节点 → <rect rx="..."> 圆角矩形
//   7. 多代父子连线 → <line>/<polyline> 折线存在
//   8. 同代多节点列号稳定 → 同输入两次输出 byte-equal
//   9. trait label XSS 防护 → 输入 genotype 含 <script> → 输出 SVG 字符串不含 <script>
//  10. 边端点缺失 → 静默降级不抛
//  11. 父节点缺失 → 边端点缺失静默降级
//  12. 代际 P-F1 标签存在
//  13. mating 边 → <line> 水平横线
//
// 全部用 test('xxx', () { ... }) 直接断言字符串/子串，
// 不依赖 widget tester / PictureRecorder。

import 'package:biology/engine/pedigree_graph.dart';
import 'package:biology/ui/svg_export.dart';
import 'package:flutter_test/flutter_test.dart';

/// 构造一个最小合法 PedigreeNode（lethal 默认为 false）。
PedigreeNode _node({
  required String id,
  required PedigreeNodeKind kind,
  required String genotype,
  required int generation,
  double probability = 0.5,
  bool isLethal = false,
  bool isExternal = false,
  int familyId = 0,
  double? maleFraction,
}) {
  return PedigreeNode(
    id: id,
    kind: kind,
    genotype: genotype,
    generation: generation,
    probability: probability,
    isExternal: isExternal,
    familyId: familyId,
    maleFraction: maleFraction,
    isLethal: isLethal,
  );
}

void main() {
  group('pedigreeToSvg 基本形态', () {
    test('1. 空节点列表 → 返回合法占位 viewBox，不抛', () {
      final svg = pedigreeToSvg(<PedigreeNode>[], <PedigreeEdge>[]);
      // 占位 viewBox 必须存在
      expect(svg, contains('viewBox="0 0 100 60"'));
      // 必须含 SVG 根标签
      expect(svg, contains('<svg'));
      expect(svg, contains('</svg>'));
      // 占位提示文字
      expect(svg, contains('（空系谱）'));
    });

    test('2. 单节点 → SVG 含节点对应元素，居中', () {
      final svg = pedigreeToSvg(
        [
          _node(
            id: 'P-father',
            kind: PedigreeNodeKind.male,
            genotype: 'AA',
            generation: 0,
          ),
        ],
        <PedigreeEdge>[],
      );
      // cx = _margin + (_nodeSize + _hGap)/2 + 0 = 32 + 40 = 72
      // 节点 <rect> 的 x = cx - _nodeSize/2 = 72 - 16 = 56
      expect(svg, contains('x="56"'));
      // 节点 <rect> 的 y = cy - _nodeSize/2 = (32 + 16) - 16 = 32
      expect(svg, contains('y="32"'));
      // 标签居中显示（文本 x = cx = 72）
      expect(svg, contains('>AA</text>'));
      expect(svg, contains('x="72"'));
    });

    test('3. lethal 节点 → SVG 含 ✕ 文本（缺陷 1 回归测试）', () {
      final svg = pedigreeToSvg(
        [
          _node(
            id: 'F1#1',
            kind: PedigreeNodeKind.male,
            genotype: 'aa',
            generation: 1,
            isLethal: true,
          ),
        ],
        <PedigreeEdge>[],
      );
      // ✕ 字符必须以 <text> 形式出现
      expect(svg, contains('>✕</text>'));
      // 填色用 lethal stroke
      expect(svg, contains('fill="#FF8585"'));
      // 字号 = 节点半径 0.6 倍 = 16 * 0.6 = 9.6
      expect(svg, contains('font-size="9.6"'));
      // 居中对齐
      expect(svg, contains('text-anchor="middle"'));
      expect(svg, contains('dominant-baseline="central"'));
    });
  });

  group('节点形状', () {
    test('4. male 节点 → <rect> 方形', () {
      final svg = pedigreeToSvg(
        [
          _node(
            id: 'm1',
            kind: PedigreeNodeKind.male,
            genotype: 'Bb',
            generation: 0,
          ),
        ],
        <PedigreeEdge>[],
      );
      // 应有 <rect>（主形状 male 方形）
      expect(RegExp(r'<rect\b').hasMatch(svg), isTrue);
      // 不应出现 <circle>
      expect(RegExp(r'<circle\b').hasMatch(svg), isFalse);
    });

    test('5. female 节点 → <circle>', () {
      final svg = pedigreeToSvg(
        [
          _node(
            id: 'f1',
            kind: PedigreeNodeKind.female,
            genotype: 'Bb',
            generation: 0,
          ),
        ],
        <PedigreeEdge>[],
      );
      // 应有 <circle>
      expect(RegExp(r'<circle\b').hasMatch(svg), isTrue);
    });

    test('6. group 节点 → <rect rx="..."> 圆角矩形', () {
      final svg = pedigreeToSvg(
        [
          _node(
            id: 'g1',
            kind: PedigreeNodeKind.group,
            genotype: 'AaBb',
            generation: 0,
            probability: 0.25,
          ),
        ],
        <PedigreeEdge>[],
      );
      // group 用 rx=6 圆角矩形
      expect(RegExp(r'<rect[^>]*rx="6"').hasMatch(svg), isTrue);
      // 标签里追加概率
      expect(svg, contains(': 25.0%'));
    });
  });

  group('边', () {
    test('7. 多代父子连线 → <polyline> 折线存在', () {
      final svg = pedigreeToSvg(
        [
          _node(
              id: 'P-father',
              kind: PedigreeNodeKind.male,
              genotype: 'AA',
              generation: 0),
          _node(
              id: 'F1#1',
              kind: PedigreeNodeKind.female,
              genotype: 'Aa',
              generation: 1),
        ],
        const [
          PedigreeEdge('P-father', 'F1#1', PedigreeEdgeKind.lineage),
        ],
      );
      // lineage 边渲染为 <polyline> 折线
      expect(RegExp(r'<polyline\b').hasMatch(svg), isTrue);
    });

    test('13. mating 边 → <line> 水平横线', () {
      final svg = pedigreeToSvg(
        [
          _node(
              id: 'P-father',
              kind: PedigreeNodeKind.male,
              genotype: 'AA',
              generation: 0),
          _node(
              id: 'P-mother',
              kind: PedigreeNodeKind.female,
              genotype: 'aa',
              generation: 0),
        ],
        const [
          PedigreeEdge('P-father', 'P-mother', PedigreeEdgeKind.mating),
        ],
      );
      // mating 边渲染为 <line> 水平横线
      expect(RegExp(r'<line\b').hasMatch(svg), isTrue);
    });
  });

  group('稳定性 + 安全 + 降级', () {
    test('8. 同代多节点列号稳定 → 同输入两次输出 byte-equal', () {
      final nodes = <PedigreeNode>[
        _node(
            id: 'b',
            kind: PedigreeNodeKind.male,
            genotype: 'Bb',
            generation: 0),
        _node(
            id: 'a',
            kind: PedigreeNodeKind.male,
            genotype: 'BB',
            generation: 0),
        _node(
            id: 'c',
            kind: PedigreeNodeKind.male,
            genotype: 'bb',
            generation: 0),
      ];
      final edges = <PedigreeEdge>[];
      final svg1 = pedigreeToSvg(nodes, edges);
      final svg2 = pedigreeToSvg(nodes, edges);
      expect(svg1, svg2, reason: '同输入两次序列化应 byte-equal');
    });

    test('9. genotype 含 <script> → 输出 SVG 字符串不含 <script>（_esc 转义）',
        () {
      final svg = pedigreeToSvg(
        [
          _node(
            id: 'xss1',
            kind: PedigreeNodeKind.male,
            genotype: '<script>alert(1)</script>',
            generation: 0,
          ),
        ],
        <PedigreeEdge>[],
      );
      // 关键防护：原始 <script> 不得以子串形式出现在 SVG 中
      expect(svg, isNot(contains('<script>')));
      expect(svg, isNot(contains('</script>')));
      // _esc 应把 < 替换为 &lt;
      expect(svg, contains('&lt;script&gt;'));
    });

    test('10. 边端点缺失（fromId 不存在）→ 静默降级不抛', () {
      // 仅声明边，节点列表为空：边端点全缺失，必须不抛
      expect(
        () => pedigreeToSvg(
          <PedigreeNode>[],
          const [
            PedigreeEdge('ghost_a', 'ghost_b', PedigreeEdgeKind.mating),
          ],
        ),
        // 空节点会走占位分支；这里再用一个非空节点场景
        returnsNormally,
      );

      // 场景二：节点存在但边的 fromId 指向不存在的节点
      final svg = pedigreeToSvg(
        [
          _node(
              id: 'real',
              kind: PedigreeNodeKind.male,
              genotype: 'AA',
              generation: 0),
        ],
        const [
          PedigreeEdge('ghost', 'real', PedigreeEdgeKind.lineage),
        ],
      );
      // 节点 <rect> 应存在
      expect(RegExp(r'<rect\b').hasMatch(svg), isTrue);
      // 缺失端点的边不应渲染 polyline
      expect(RegExp(r'<polyline\b').hasMatch(svg), isFalse);
    });

    test('11. 父节点缺失（toId 不存在）→ 边静默降级不抛', () {
      final svg = pedigreeToSvg(
        [
          _node(
              id: 'p',
              kind: PedigreeNodeKind.male,
              genotype: 'AA',
              generation: 0),
        ],
        const [
          PedigreeEdge('p', 'ghost_child', PedigreeEdgeKind.lineage),
        ],
      );
      // 边端点不全 → 不渲染 polyline
      expect(RegExp(r'<polyline\b').hasMatch(svg), isFalse);
      // 节点仍正常渲染
      expect(RegExp(r'<rect\b').hasMatch(svg), isTrue);
    });

    test('12. 代际 P-F1 标签存在', () {
      final svg = pedigreeToSvg(
        [
          _node(
              id: 'P-father',
              kind: PedigreeNodeKind.male,
              genotype: 'AA',
              generation: 0),
          _node(
              id: 'P-mother',
              kind: PedigreeNodeKind.female,
              genotype: 'aa',
              generation: 0),
          _node(
              id: 'F1#1',
              kind: PedigreeNodeKind.male,
              genotype: 'Aa',
              generation: 1),
          _node(
              id: 'F2#1',
              kind: PedigreeNodeKind.female,
              genotype: 'AA',
              generation: 2),
        ],
        const [
          PedigreeEdge('P-father', 'P-mother', PedigreeEdgeKind.mating),
          PedigreeEdge('P-father', 'F1#1', PedigreeEdgeKind.lineage),
          PedigreeEdge('P-mother', 'F1#1', PedigreeEdgeKind.lineage),
          PedigreeEdge('F1#1', 'F2#1', PedigreeEdgeKind.lineage),
        ],
      );
      // 代际标题
      expect(svg, contains('>P</text>'));
      expect(svg, contains('>F1</text>'));
      expect(svg, contains('>F2</text>'));
    });
  });
}
