// restriction_lab_test.dart —— 限制酶切实验（第 5 页签）守卫网
//
// 网型：① 自包含形态（输入+结果同屏）逐条钉住「点示例就出结果」，
// 因为白板上课没有键盘；② 错误必须看得见且清掉旧结果；
// ③ 页面接线：第 5 页签左栏注入 + 深链 tab=4 合法 + 旧 4 页签不回归。
import 'package:biology/pages/molecular_page.dart';
import 'package:biology/engine/restriction_engine.dart';
import 'package:biology/pages/widgets/restriction_lab.dart';
import 'package:biology/ui/module_fill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 宽高给足：本实验是「输入区 + 4 个结果分区」的长列，视口太矮会把
/// 示例 chip 挤出可点区域（`tester.tap` 命中不了屏外节点）。
Future<void> _pumpLab(
  WidgetTester tester, {
  GlobalKey<RestrictionLabState>? hostKey,
  bool showInputs = true,
  Size size = const Size(1100, 2200),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: RestrictionLab(key: hostKey, showInputs: showInputs),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// 当前页签下标：走 TabBar 的 controller（结构化读数，不靠屏上文字）。
int _tabIndex(WidgetTester tester) =>
    tester.widget<TabBar>(find.byType(TabBar)).controller!.index;

void main() {
  group('自包含形态：点示例即出结果（无需键盘）', () {
    testWidgets('出厂默认题：EcoRI 2 个位点 → 3 段，长度核算为 19 bp', (tester) async {
      await _pumpLab(tester);

      expect(find.textContaining('长度核算：3 + 9 + 7 = 19 bp'), findsOneWidget,
          reason: '片段长度之和必须等于原序列 19 bp');
      expect(find.textContaining('位点 2 个'), findsOneWidget);
      expect(find.text('3 段'), findsOneWidget, reason: '结果区徽标给出段数');
      // 双链切点示意（教材式两行；2 个位点 ⇒ 两张示意）
      expect(find.textContaining('5′-G↓AATTC-3′'), findsNWidgets(2),
          reason: '每个位点各画一张双链示意');
      expect(find.textContaining('教学简化模型'), findsOneWidget,
          reason: '模型边界必须印在屏上');
      expect(tester.takeException(), isNull);
    });

    testWidgets('标尺：10/20/30 右对齐，切口标在左侧碱基且不盖位点括号', (tester) async {
      final key = GlobalKey<RestrictionLabState>();
      await _pumpLab(tester, hostKey: key);
      final state = key.currentState!;
      final lines = state.debugRulerLines(
        restrictionDigest(
            sequence: RestrictionLabState.kDefaultSequence, enzyme: kEcoRI),
      );
      expect(lines, hasLength(4));
      expect(lines[0], hasLength(19));
      expect(lines[0].substring(8, 10), '10',
          reason: '里程碑 10 占第 9–10 列，不是把 11 放到第 1 列');
      expect(lines[0].startsWith('11'), isFalse);
      expect(lines[1], RestrictionLabState.kDefaultSequence);
      expect(lines[2][2], '[');
      expect(lines[2][7], ']');
      expect(lines[3][2], '|', reason: '第一处切在第 3 位 G 之后，竖线落在 G 下');
      expect(lines[3][11], '|', reason: '第二处切在第 12 位 G 之后');

      final long = state.debugRulerLines(
        restrictionDigest(sequence: 'A' * 30, enzyme: kEcoRI),
      );
      expect(long[0].substring(8, 10), '10');
      expect(long[0].substring(18, 20), '20');
      expect(long[0].substring(28, 30), '30');
    });

    testWidgets('BamHI 示例 chip：一按就切（3 + 7 = 10 bp）', (tester) async {
      await _pumpLab(tester);

      await tester.tap(find.text('示例·BamHI 单位点'));
      await tester.pumpAndSettle();

      expect(find.textContaining('长度核算：3 + 7 = 10 bp'), findsOneWidget);
      expect(find.textContaining('位点 1 个'), findsOneWidget);
      expect(find.textContaining('5′-G↓GATCC-3′'), findsOneWidget,
          reason: '换酶后切点示意必须跟着换');
      expect(tester.takeException(), isNull);
    });

    testWidgets('HindIII 示例 chip：4 + 8 = 12 bp', (tester) async {
      await _pumpLab(tester);

      await tester.tap(find.text('示例·HindIII 单位点'));
      await tester.pumpAndSettle();

      expect(find.textContaining('长度核算：4 + 8 = 12 bp'), findsOneWidget);
      expect(find.textContaining('A↓AGCTT'), findsOneWidget);
    });

    testWidgets('无位点示例：不切开，仍是 1 段，并说明没有位点', (tester) async {
      await _pumpLab(tester);

      await tester.tap(find.text('示例·无位点'));
      await tester.pumpAndSettle();

      expect(find.text('12 bp'), findsOneWidget, reason: '整段长度');
      expect(find.textContaining('不被切开'), findsOneWidget);
      expect(find.text('没有位点：本序列不含 GAATTC。'), findsOneWidget);
      expect(find.textContaining('未被切开：两端都是原序列末端'), findsOneWidget);
      expect(find.textContaining('没有位点，因此没有切口'), findsOneWidget);
    });

    testWidgets('酶选项整块可点：从 EcoRI 换到 BamHI 后按新酶重算', (tester) async {
      await _pumpLab(tester);

      // 选项块里的「识别序列 · 顶链记号」全页只此一处，点它即点中整块。
      await tester.tap(find.textContaining('GGATCC · G^GATCC'));
      await tester.pumpAndSettle();

      expect(find.textContaining('没有该位点'), findsOneWidget,
          reason: '默认序列里没有 BamHI 位点');
      expect(find.text('1 段'), findsOneWidget,
          reason: '换酶后按新酶重算：无位点 ⇒ 1 段');
      expect(find.textContaining('未被切开'), findsOneWidget);
    });
  });

  group('输入错误必须看得见', () {
    testWidgets('非法字符：lethal 横幅 + 旧结果清空', (tester) async {
      await _pumpLab(tester);

      await tester.enterText(find.byType(TextField), 'GAATTCX');
      await tester.tap(find.text('计算切点与片段'));
      await tester.pumpAndSettle();

      expect(find.textContaining('四种碱基'), findsOneWidget);
      expect(find.textContaining('「X」'), findsOneWidget);
      expect(find.textContaining('3 + 9 + 7'), findsNothing,
          reason: '非法输入时不许把旧结果留在屏上充数');
    });

    testWidgets('空输入：提示请输入序列', (tester) async {
      await _pumpLab(tester);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('计算切点与片段'));
      await tester.pumpAndSettle();

      expect(find.textContaining('请输入 DNA 序列'), findsOneWidget);
    });

    testWidgets('改好输入后错误消失、结果回来', (tester) async {
      await _pumpLab(tester);

      await tester.enterText(find.byType(TextField), 'GAATTCX');
      await tester.tap(find.text('计算切点与片段'));
      await tester.pumpAndSettle();
      expect(find.textContaining('四种碱基'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'GGGAATTCGG');
      await tester.tap(find.text('计算切点与片段'));
      await tester.pumpAndSettle();

      expect(find.textContaining('四种碱基'), findsNothing);
      expect(find.textContaining('长度核算：3 + 7 = 10 bp'), findsOneWidget);
    });
  });

  group('isPristine（父页脏页守卫的判据）', () {
    testWidgets('出厂为 true；点示例或换酶后为 false', (tester) async {
      final key = GlobalKey<RestrictionLabState>();
      await _pumpLab(tester, hostKey: key);

      expect(key.currentState!.isPristine, isTrue, reason: '出厂 = 没被学生动过');

      await tester.tap(find.text('示例·HindIII 单位点'));
      await tester.pumpAndSettle();
      expect(key.currentState!.isPristine, isFalse,
          reason: '换了示例 = 学生自己出了题');
    });

    testWidgets('只在输入框里改字也算 dirty', (tester) async {
      final key = GlobalKey<RestrictionLabState>();
      await _pumpLab(tester, hostKey: key);

      await tester.enterText(find.byType(TextField), 'GAATTC');
      await tester.pumpAndSettle();

      expect(key.currentState!.isPristine, isFalse);
    });
  });

  group('showInputs=false（页面里的用法）', () {
    testWidgets('只出结果，输入区不重复渲染', (tester) async {
      await _pumpLab(tester, showInputs: false);

      expect(find.text('计算切点与片段'), findsNothing);
      expect(find.text('DNA 序列（顶链 5′→3′）'), findsNothing);
      expect(find.textContaining('长度核算：3 + 9 + 7 = 19 bp'), findsOneWidget,
          reason: '结果照常出（出厂默认题已算过）');
    });
  });

  group('窄屏（390）', () {
    testWidgets('自包含形态 390 宽零溢出', (tester) async {
      await _pumpLab(tester, size: const Size(390, 3000));

      expect(tester.takeException(), isNull);
      expect(find.textContaining('长度核算：3 + 9 + 7 = 19 bp'), findsOneWidget);
    });
  });

  group('分子页接线（第 5 页签）', () {
    Future<void> pumpPage(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 1100);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: MolecularPage()));
      await tester.pumpAndSettle();
    }

    testWidgets('5 个页签都在；切到「基因工程」左栏注入输入面板，点示例即出结果',
        (tester) async {
      await pumpPage(tester);

      for (final label in ['碱基组成', '复制与标记', '基因表达', '配子种类', '基因工程']) {
        expect(find.text(label), findsWidgets, reason: '页签「$label」必须还在');
      }
      expect(_tabIndex(tester), 0);

      await tester.tap(find.text('基因工程'));
      await tester.pumpAndSettle();

      expect(_tabIndex(tester), 4);
      expect(find.text('限制酶'), findsOneWidget,
          reason: '宽屏左栏必须注入本实验的输入面板');
      expect(find.text('计算切点与片段'), findsOneWidget);

      await tester.tap(find.text('示例·BamHI 单位点'));
      await tester.pumpAndSettle();

      expect(find.textContaining('长度核算：3 + 7 = 10 bp'), findsOneWidget,
          reason: '左栏点 chip 的结果必须出现在右栏');
      expect(tester.takeException(), isNull);
    });

    testWidgets('旧 4 个页签逐个切换仍正常（无回归）', (tester) async {
      await pumpPage(tester);

      const markers = <String, String>{
        '碱基组成': '计算碱基组成',
        '复制与标记': '计算复制结果',
        '基因表达': '推出各链',
        '配子种类': '计算配子种类',
      };
      for (final entry in markers.entries) {
        await tester.tap(find.text(entry.key));
        await tester.pumpAndSettle();
        expect(find.text(entry.value), findsOneWidget,
            reason: '页签「${entry.key}」的左栏面板仍是它自己的');
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('离开再回基因工程：学生当前酶与片段结果保持', (tester) async {
      await pumpPage(tester);
      await tester.tap(find.text('基因工程'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('示例·HindIII 单位点'));
      await tester.pumpAndSettle();
      expect(find.textContaining('长度核算：4 + 8 = 12 bp'), findsOneWidget);

      await tester.tap(find.text('碱基组成'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('基因工程'));
      await tester.pumpAndSettle();

      expect(find.textContaining('长度核算：4 + 8 = 12 bp'), findsOneWidget,
          reason: 'TabBarView 往返不得把学生的实验重置成出厂题');
    });

    testWidgets('390 窄屏：切到「基因工程」输入面板回落到结果区上方，零溢出',
        (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: MolecularPage()));
      await tester.pumpAndSettle();

      // 5 个页签后 TabBar 变为可滚动 ⇒ 先滚到本页签再点（鼠标/触屏通道）。
      await tester.ensureVisible(find.text('基因工程'));
      await tester.pump();
      await tester.tap(find.text('基因工程'));
      await tester.pumpAndSettle();

      expect(_tabIndex(tester), 4);
      expect(find.text('计算切点与片段'), findsOneWidget,
          reason: '窄屏：sidePanel 回落在结果区上方');
      expect(find.textContaining('长度核算：3 + 9 + 7 = 19 bp'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('深链 tab=4 直达第 5 页签（合法范围 0..4）', (tester) async {
      ModuleFillBus.resetForTest();
      ModuleFillBus.navigator = (_) {};
      addTearDown(ModuleFillBus.resetForTest);

      await pumpPage(tester);
      expect(_tabIndex(tester), 0);

      final ok = ModuleFillBus.fill('molecular', const {'tab': '4'});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(ok, isTrue);
      expect(_tabIndex(tester), 4, reason: 'tab 参数 0..4 都应被认领');
    });

    testWidgets('越界深链 tab=5 不认领（不切页签）', (tester) async {
      ModuleFillBus.resetForTest();
      ModuleFillBus.navigator = (_) {};
      addTearDown(ModuleFillBus.resetForTest);

      await pumpPage(tester);

      ModuleFillBus.fill('molecular', const {'tab': '5'});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(_tabIndex(tester), 0, reason: '越界页签必须原样让路');
    });
  });
}
