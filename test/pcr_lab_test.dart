// pcr_lab_test.dart —— PCR 扩增 + 凝胶电泳实验（第 5 页签第二个实验）守卫网
//
// 网型：① 自包含形态逐条钉住「点示例就出结果」（白板没有键盘）；
// ② 换循环数只改理想拷贝数、不改产物；③ 错误必须看得见且清掉旧结果；
// ④ 页面接线：实验选择器可触达、两个实验往返各自保活、旧限制酶切不回归。
import 'package:biology/engine/pcr_engine.dart';
import 'package:biology/pages/molecular_page.dart';
import 'package:biology/pages/widgets/pcr_lab.dart';
import 'package:biology/pages/widgets/restriction_lab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 视口给足：输入区 + 4 个结果分区是长列，太矮会把 chip 挤出可点区域。
Future<void> _pumpLab(
  WidgetTester tester, {
  GlobalKey<PcrLabState>? hostKey,
  bool showInputs = true,
  Size size = const Size(1100, 2600),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: PcrLab(key: hostKey, showInputs: showInputs),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// 当前页签下标：走 TabBar 的 controller（结构化读数，不靠屏上文字）。
int _tabIndex(WidgetTester tester) =>
    tester.widget<TabBar>(find.byType(TabBar)).controller!.index;

Future<void> _pumpPage(
  WidgetTester tester, {
  Size size = const Size(1600, 1200),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(const MaterialApp(home: MolecularPage()));
  await tester.pumpAndSettle();
}

/// 切到第 5 页签「基因工程」。
Future<void> _openEngineering(WidgetTester tester) async {
  await tester.ensureVisible(find.text('基因工程'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('基因工程'));
  await tester.pumpAndSettle();
}

/// 在实验选择器里选一个实验。
///
/// ⚠️ 选择器在左栏滚动区顶部：点过下面的 chip 之后它可能被滚出可视区，
/// `tap` 会因为命中不到而「点了没反应」——所以统一先 ensureVisible。
Future<void> _selectLab(WidgetTester tester, String label) async {
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

void main() {
  group('自包含形态：点示例即出结果（无需键盘）', () {
    testWidgets('默认例：结合区第 4–23 / 48–67 位，产物 64 bp，2^25 份', (tester) async {
      await _pumpLab(tester);

      expect(find.textContaining('产物长度核对：67 − 4 + 1 = 64 bp'), findsOneWidget);
      expect(find.textContaining('第 4–23 位'), findsWidgets,
          reason: '正向结合区必须标出位置');
      expect(find.textContaining('第 48–67 位'), findsWidgets,
          reason: '反向结合区必须标出位置');
      expect(find.text('64 bp'), findsOneWidget, reason: '产物徽标给出长度');
      expect(find.text('2^25 = 33554432 份'), findsOneWidget,
          reason: '理想拷贝数必须写出 2ⁿ 与具体数值');
      expect(find.textContaining('教学简化模型'), findsOneWidget,
          reason: '模型边界必须印在屏上');
      expect(find.textContaining('不用于实验设计'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('凝胶图：marker 分档 + 样品条带都在屏上，并写明只示意方向', (tester) async {
      await _pumpLab(tester);

      for (final bp in kGelMarkerBps) {
        expect(find.text('$bp bp'), findsOneWidget,
            reason: 'marker 的 $bp bp 刻du必须可读');
      }
      expect(find.text('样品 64 bp'), findsOneWidget);
      expect(find.textContaining('条带位置仅示意迁移方向，不用于精确定量'),
          findsOneWidget);
      expect(find.textContaining('不是条带亮度或浓度'), findsOneWidget,
          reason: '⛔ 不许把 2ⁿ 读成条带浓度');
    });

    testWidgets('换循环数只改理想拷贝数，产物不变', (tester) async {
      await _pumpLab(tester);
      expect(find.text('2^25 = 33554432 份'), findsOneWidget);

      await tester.tap(find.text('5 次'));
      await tester.pumpAndSettle();

      expect(find.text('2^5 = 32 份'), findsOneWidget);
      expect(find.textContaining('产物长度核对：67 − 4 + 1 = 64 bp'), findsOneWidget,
          reason: '循环数不影响产物序列与长度');
      expect(find.textContaining('当前循环数 n = 5'), findsOneWidget);
    });

    testWidgets('循环 0 次：理想拷贝数 = 1，并说明不扩增', (tester) async {
      await _pumpLab(tester);

      await tester.tap(find.text('0 次'));
      await tester.pumpAndSettle();

      expect(find.text('2^0 = 1 份'), findsOneWidget);
      expect(find.textContaining('0 次循环 = 不扩增'), findsOneWidget);
    });

    testWidgets('无产物示例 chip：一按就给出「没有匹配」的中文错误', (tester) async {
      await _pumpLab(tester);

      await tester.tap(find.text('示例·无产物（引物不匹配）'));
      await tester.pumpAndSettle();

      expect(find.textContaining('正向引物在模板上没有匹配'), findsOneWidget);
      expect(find.textContaining('产物长度核对'), findsNothing,
          reason: '⛔ 出错不许把上一题的产物留在屏上');
      expect(find.textContaining('样品 64 bp'), findsNothing);
    });

    testWidgets('反向引物写反示例 chip：提示方向错，而不是「没匹配」', (tester) async {
      await _pumpLab(tester);

      await tester.tap(find.text('示例·反向引物写反'));
      await tester.pumpAndSettle();

      expect(find.textContaining('反向引物方向写反了'), findsOneWidget);
      expect(find.textContaining('第 48 位'), findsOneWidget,
          reason: '文案要点名它其实匹配在哪里');
    });

    testWidgets('点回标准扩增示例：结果从错误状态恢复', (tester) async {
      await _pumpLab(tester);

      await tester.tap(find.text('示例·无产物（引物不匹配）'));
      await tester.pumpAndSettle();
      expect(find.textContaining('正向引物在模板上没有匹配'), findsOneWidget);

      await tester.tap(find.text('示例·标准扩增'));
      await tester.pumpAndSettle();

      expect(find.textContaining('正向引物在模板上没有匹配'), findsNothing);
      expect(find.textContaining('产物长度核对：67 − 4 + 1 = 64 bp'), findsOneWidget);
    });
  });

  group('输入错误必须看得见', () {
    testWidgets('非法碱基：lethal 横幅 + 旧结果清空', (tester) async {
      await _pumpLab(tester);

      // 第 2 个输入框 = 正向引物
      await tester.enterText(find.byType(TextField).at(1), 'ATGGCATCXATCGTTAGCAT');
      await tester.tap(find.text('开始扩增'));
      await tester.pumpAndSettle();

      expect(find.textContaining('正向引物只能含 A、T、C、G'), findsOneWidget);
      expect(find.textContaining('「X」'), findsOneWidget);
      expect(find.textContaining('产物长度核对'), findsNothing);
    });

    testWidgets('引物过短：点名长度与允许范围', (tester) async {
      await _pumpLab(tester);

      await tester.enterText(find.byType(TextField).at(1), 'ATGGCATCG');
      await tester.tap(find.text('开始扩增'));
      await tester.pumpAndSettle();

      expect(find.textContaining('正向引物长度 9 nt'), findsOneWidget);
      expect(find.textContaining('超出教学范围'), findsOneWidget,
          reason: '文案必须写出允许范围（左栏提示里也印了同一段数字，故不按 10–30 nt 计数）');
    });

    testWidgets('改好输入后错误消失、结果回来', (tester) async {
      await _pumpLab(tester);

      await tester.enterText(find.byType(TextField).at(1), 'ATGGCATCXATCGTTAGCAT');
      await tester.tap(find.text('开始扩增'));
      await tester.pumpAndSettle();
      expect(find.textContaining('四种碱基'), findsOneWidget);

      await tester.enterText(find.byType(TextField).at(1), 'ATGGCATCGATCGTTAGCAT');
      await tester.tap(find.text('开始扩增'));
      await tester.pumpAndSettle();

      expect(find.textContaining('四种碱基'), findsNothing);
      expect(find.textContaining('产物长度核对：67 − 4 + 1 = 64 bp'), findsOneWidget);
    });
  });

  group('isPristine（父页脏页守卫的判据）', () {
    testWidgets('出厂为 true；点示例 / 换循环数后为 false', (tester) async {
      final key = GlobalKey<PcrLabState>();
      await _pumpLab(tester, hostKey: key);

      expect(key.currentState!.isPristine, isTrue, reason: '出厂 = 没被学生动过');

      await tester.tap(find.text('示例·标准扩增'));
      await tester.pumpAndSettle();
      expect(key.currentState!.isPristine, isTrue,
          reason: '点「标准扩增」= 把默认题摆回来，仍是出厂状态');

      await tester.tap(find.text('5 次'));
      await tester.pumpAndSettle();
      expect(key.currentState!.isPristine, isFalse, reason: '换了循环数 = 自己出了题');
    });

    testWidgets('只在模板框里改字也算 dirty', (tester) async {
      final key = GlobalKey<PcrLabState>();
      await _pumpLab(tester, hostKey: key);

      await tester.enterText(find.byType(TextField).first, 'GGGATGGCATCG');
      await tester.pumpAndSettle();

      expect(key.currentState!.isPristine, isFalse);
    });
  });

  group('showInputs=false（页面里的用法）', () {
    testWidgets('只出结果，输入区不重复渲染', (tester) async {
      await _pumpLab(tester, showInputs: false);

      expect(find.text('开始扩增'), findsNothing);
      expect(find.text('模板顶链（5′→3′）'), findsNothing);
      expect(find.textContaining('产物长度核对：67 − 4 + 1 = 64 bp'), findsOneWidget);
      expect(find.text('样品 64 bp'), findsOneWidget);
    });
  });

  group('窄屏（390）', () {
    testWidgets('自包含形态 390 宽零溢出（长序列不横溢）', (tester) async {
      await _pumpLab(tester, size: const Size(390, 3200));

      expect(tester.takeException(), isNull);
      expect(find.textContaining('产物长度核对：67 − 4 + 1 = 64 bp'), findsOneWidget);
      expect(find.text('样品 64 bp'), findsOneWidget);
    });
  });

  group('分子页接线（第 5 页签：限制酶切 / PCR 与电泳）', () {
    testWidgets('5 个页签仍在；第 5 页签默认仍是限制酶切（不回归）', (tester) async {
      await _pumpPage(tester);

      for (final label in ['碱基组成', '复制与标记', '基因表达', '配子种类', '基因工程']) {
        expect(find.text(label), findsWidgets, reason: '页签「$label」必须还在');
      }
      expect(_tabIndex(tester), 0);

      await _openEngineering(tester);

      expect(_tabIndex(tester), 4);
      expect(find.text('限制酶'), findsOneWidget, reason: '默认仍是限制酶切的输入面板');
      expect(find.text('计算切点与片段'), findsOneWidget);
      expect(find.text('PCR 与电泳'), findsOneWidget, reason: '实验选择器必须可触达');
      expect(find.textContaining('长度核算：3 + 9 + 7 = 19 bp'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('选「PCR 与电泳」：左栏换成 PCR 输入，右栏出 PCR 结果', (tester) async {
      await _pumpPage(tester);
      await _openEngineering(tester);

      await _selectLab(tester, 'PCR 与电泳');

      expect(find.text('模板顶链（5′→3′）'), findsOneWidget,
          reason: '宽屏左栏注入 PCR 的输入面板');
      expect(find.text('开始扩增'), findsOneWidget);
      expect(find.text('计算切点与片段'), findsNothing,
          reason: '同一时刻左栏只挂当前实验的输入');
      expect(find.text('样品 64 bp'), findsOneWidget, reason: '右栏出 PCR 结果');
      expect(find.text('2^25 = 33554432 份'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('两个实验往返：各自的输入与结果都保住（互不重置）', (tester) async {
      await _pumpPage(tester);
      await _openEngineering(tester);

      // ① 限制酶切改成 BamHI（3 + 7），与出厂 3 + 9 + 7 可区分
      await tester.ensureVisible(find.text('示例·BamHI 单位点'));
      await tester.tap(find.text('示例·BamHI 单位点'));
      await tester.pumpAndSettle();
      expect(find.textContaining('长度核算：3 + 7 = 10 bp'), findsOneWidget);

      // ② 切到 PCR，改成 5 次循环（与出厂 2^25 可区分）
      await _selectLab(tester, 'PCR 与电泳');
      await tester.ensureVisible(find.text('5 次'));
      await tester.tap(find.text('5 次'));
      await tester.pumpAndSettle();
      expect(find.text('2^5 = 32 份'), findsOneWidget);

      // ③ 切回限制酶切：BamHI 的结果还在（没被重置成出厂题）
      await _selectLab(tester, '限制酶切');
      expect(
        find.descendant(
          of: find.byType(RestrictionLab),
          matching: find.textContaining('长度核算：3 + 7 = 10 bp'),
        ),
        findsOneWidget,
        reason: '限制酶切的状态不得因切换实验被重置',
      );

      // ④ 再切回 PCR：5 次循环的结果还在
      await _selectLab(tester, 'PCR 与电泳');
      expect(
        find.descendant(
          of: find.byType(PcrLab),
          matching: find.text('2^5 = 32 份'), // 精确匹配结果行（解释句里也有这串）
        ),
        findsOneWidget,
        reason: 'PCR 的状态不得因切换实验被重置',
      );
    });

    testWidgets('「全部计算」在 PCR 上也生效，且不丢当前输入', (tester) async {
      await _pumpPage(tester);
      await _openEngineering(tester);

      await _selectLab(tester, 'PCR 与电泳');
      await tester.enterText(find.byType(TextField).at(1), 'ATGGCATCGATCGTTAGCAT');
      await tester.pumpAndSettle();

      await tester.tap(find.text('全部计算'));
      await tester.pumpAndSettle();

      expect(find.textContaining('产物长度核对：67 − 4 + 1 = 64 bp'), findsOneWidget);
      expect(find.text('2^25 = 33554432 份'), findsOneWidget);
      // 输入框里的学生输入必须还在（重算 ≠ 重置）
      expect(
        tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
        'ATGGCATCGATCGTTAGCAT',
      );
    });

    testWidgets('离开分子页再回来：第 5 页签仍是学生选的 PCR', (tester) async {
      await _pumpPage(tester);
      await _openEngineering(tester);
      await _selectLab(tester, 'PCR 与电泳');

      await tester.tap(find.text('碱基组成'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('基因工程'));
      await tester.pumpAndSettle();

      expect(find.text('模板顶链（5′→3′）'), findsOneWidget,
          reason: '页签往返不得把实验选择重置回限制酶切');
      expect(find.text('样品 64 bp'), findsOneWidget);
    });

    testWidgets('390 窄屏：实验选择器可达，PCR 结果零溢出', (tester) async {
      await _pumpPage(tester, size: const Size(390, 844));
      await _openEngineering(tester);

      expect(_tabIndex(tester), 4);
      expect(find.text('PCR 与电泳'), findsOneWidget,
          reason: '窄屏选择器回落在结果区上方，必须可触达');

      await _selectLab(tester, 'PCR 与电泳');

      expect(find.text('开始扩增'), findsOneWidget);
      expect(find.textContaining('产物长度核对：67 − 4 + 1 = 64 bp'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
