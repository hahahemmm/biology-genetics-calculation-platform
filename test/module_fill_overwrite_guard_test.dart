// ════════════════════════════════════════════════════════════════════════
//  test/module_fill_overwrite_guard_test.dart
//  v2.19.32：给 4 个**无守卫**的非 push 填参目标接上防覆盖闸。
// ════════════════════════════════════════════════════════════════════════
//
//  ## 病灶
//
//  `ModuleFillTarget.canOverwrite`（`lib/ui/module_fill.dart`）：
//  目标页回答「我那儿现在是不是空着」。返回 false ⇒ `fill` 仍切页
//  （学生的导航意图要满足）但**跳过 `apply`**，并用 `kModuleFillSkippedDirty`
//  调 `onApplyFailed`。⚠️ `canOverwrite` 为 **null** 时**完全不设防** ——
//  直接往下 `apply(params)`，学生已敲的内容被无声顶掉。
//
//  v2.19.117 只给 9331 页 7 个页签挂了闸。这 4 个 target 既没有
//  `pushFactory`（新实例天然免疫）、也没有 `canOverwrite`：
//    · `molecular`  lib/pages/molecular_page.dart
//    · `evolution`  lib/pages/evolution_page.dart
//    · `ploidy`     lib/pages/ploidy_page.dart
//    · `pedigree`   lib/pages/genetic_pedigree_page.dart
//  学生从「考纲覆盖」页或「大题套路卡」点进去，自己敲的题被顶掉，
//  且**零提示**。
//
//  ## ⛔ 断言为什么落在 controller 实际值 / 渲染产物上
//
//  1. `fill()` **恒返回 true**（被拒绝时也返回 true）⇒ 断言「返回 true」
//     **不能**证明参数写进去了。所以正向一律断言 `TextField.controller!.text`
//     —— 那是 State 真正持有的同一个 controller 实例（`apply` 直接写 `.text`）。
//  2. 「树上有 widget」≠「屏上画出了东西」。所以反向一律**两条**：
//     controller 的 `.text` 没变 **且** 屏上出现了那句提示。
//
//  ## ⛔ 反向用例里「数据断言」故意排在接线检查前面
//
//  `_canOverwrite(...)` 是**接线**检查（守卫挂没挂）。若把它排在最前，
//  一旦守卫缺失，红输出只会说「canOverwrite 是 null」——那是**症状的
//  症状**，看不见学生真正遭遇的那件事：自己敲的题被无声顶掉。
//  所以顺序固定为 ① 数据断言 → ② 屏上提示 → ③ 接线检查。
//
//  ## 判据锚点（按 label 前缀，不按 controller 身份）
//
//  按 `labelText` 的**前缀**认输入框。产品改文案 ⇒ 前提断言 `findsOneWidget`
//  先红，**不会静默 0 命中**。前缀查找不是「改名免疫」，是「改名时必须有人
//  被叫醒」——真做到改名免疫得产品给稳定 `Key`，那是 `lib/` 的事。
//
//  ## 复现三要素
//
//  · 复现路径：主导航对应页（分子 5 / 进化 6 / 倍性 7 / 图谱 1）→ 视口
//    1400×3000 @1.0 →（反向用例）先 `enterText` 手敲，再 `ModuleFillBus.fill`。
//  · 判据锚点：按输入框 label 前缀 + SnackBar 文案**整句**。
// ════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/pages/evolution_page.dart';
import 'package:biology/pages/genetic_pedigree_page.dart';
import 'package:biology/pages/molecular_page.dart';
import 'package:biology/pages/ploidy_page.dart';
import 'package:biology/ui/module_fill.dart';

/// 按 `InputDecoration.labelText` 的**前缀**认输入框。
///
/// [prefix] 是 label 的稳定词头，**不是**整句照抄。保持 `startsWith`：
/// 放宽成 `contains` 会把无关字段一起拖进来 ⇒ `findsOneWidget` 变红、
/// `enterText` 抛「Too many elements」。
Finder fieldLike(String prefix) => find.byWidgetPredicate(
      (w) => w is TextField && (w.decoration?.labelText ?? '').startsWith(prefix),
      description: 'TextField(label 以「$prefix」开头)',
    );

/// 开一页（宽屏 + 高视口：工作台骨架 ≥1200 才把输入面板常驻左栏；
/// 三个工作台页的输入框都随当前页签重建，窄视口够不到）。
Future<void> _pump(WidgetTester t, Widget page) async {
  t.view.physicalSize = const Size(1400, 3000);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: page));
  await t.pump();
  await t.pump(const Duration(milliseconds: 600));
}

/// 目标页的 `canOverwrite()`（缺守卫 ⇒ 前提就红，不静默放行）。
bool _canOverwrite(String moduleId) {
  final t = ModuleFillBus.targetOf(moduleId);
  expect(t, isNotNull, reason: 'moduleId「$moduleId」必须已注册');
  final can = t!.canOverwrite;
  expect(can, isNotNull,
      reason: 'moduleId「$moduleId」必须挂 canOverwrite（深链不覆盖学生敲的题）');
  return can!();
}

/// controller 的**实际值**（不是「输入框在不在」；`findsOneWidget` 是前提硬断言）。
String _ctrlText(WidgetTester t, String labelPrefix) {
  final f = fieldLike(labelPrefix);
  expect(f, findsOneWidget, reason: '前提：「$labelPrefix」输入框在场上（唯一）');
  return t.widget<TextField>(f).controller!.text;
}

/// 点页签名把目标页签切到前台（TabBarView 懒构建，不切过去输入框不在树上）。
Future<void> _gotoTab(WidgetTester t, String tabName) async {
  final tab = find.text(tabName);
  expect(tab, findsWidgets, reason: '页签页名「$tabName」必须在屏上');
  await t.tap(tab.first);
  await t.pumpAndSettle();
}

void main() {
  setUp(() {
    // 必须在 pumpWidget **之前**清：各页在 initState 里注册 target。
    ModuleFillBus.resetForTest();
    // 假导航器：只求「切页这一步发生过」（守卫在 navigator 之后才问）。
    // 页面是被直接 pump 的，State 不重建。
    ModuleFillBus.navigator = (_) {};
  });
  tearDown(ModuleFillBus.resetForTest);

  group('molecular（分子页·中心法则）', () {
    testWidgets('出厂状态下 fill 真把模板链写进输入框', (t) async {
      await _pump(t, const MolecularPage());
      expect(_canOverwrite('molecular'), isTrue,
          reason: '出厂（没人动过）⇒ 放行写入');

      ModuleFillBus.fill('molecular', const {'template': 'ATGCATGC'});
      await t.pump();
      await t.pump(const Duration(milliseconds: 600)); // post-frame apply + tab 动画

      // 正向判据：controller 实际值（出厂 'TACGGATTA' ⇒ 应变成 'ATGCATGC'）。
      expect(_ctrlText(t, '模板链序列'), 'ATGCATGC',
          reason: '正向必须落在 controller 实际值上：出厂状态下参数要真写进去');
    });

    testWidgets('学生敲了题后 fill 不覆盖 + 屏上出提示', (t) async {
      await _pump(t, const MolecularPage());
      await _gotoTab(t, '基因表达');
      final f = fieldLike('模板链序列');
      expect(f, findsOneWidget, reason: '前提：「模板链序列」输入框在场上');
      await t.enterText(f, 'GGGGCCTT');
      await t.pump();

      ModuleFillBus.fill('molecular', const {'template': 'ATGCATGC'});
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));

      expect(_ctrlText(t, '模板链序列'), 'GGGGCCTT',
          reason: '反向：内容没变（手敲的 GGGGCCTT 还在）');
      expect(find.text(kModuleFillSkippedDirty), findsOneWidget,
          reason: '只加守卫不提示 = 学生看到「点了没反应」，比被顶掉更难排查');
      expect(_canOverwrite('molecular'), isFalse,
          reason: '接线检查：学生 enterText 敲了题 ⇒ 整页 dirty');
    });
  });

  group('evolution（进化页·基因频率）', () {
    testWidgets('出厂状态下 fill 真把 p/q 写进输入框', (t) async {
      await _pump(t, const EvolutionPage());
      expect(_canOverwrite('evolution'), isTrue, reason: '出厂 ⇒ 放行写入');

      ModuleFillBus.fill('evolution', const {'p': '0.9', 'q': '0.1'});
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));

      // 出厂 p=0.7 / q=0.3。
      expect(_ctrlText(t, 'A 基因频率 p'), '0.9',
          reason: '正向：p 由出厂 0.7 变成 0.9');
      expect(_ctrlText(t, 'a 基因频率 q'), '0.1',
          reason: '正向：q 由出厂 0.3 变成 0.1');
    });

    testWidgets('学生敲了题后 fill 不覆盖 + 屏上出提示', (t) async {
      await _pump(t, const EvolutionPage());
      await _gotoTab(t, '遗传平衡');
      final f = fieldLike('A 基因频率 p');
      expect(f, findsOneWidget, reason: '前提：「A 基因频率 p」输入框在场上');
      await t.enterText(f, '0.33');
      await t.pump();

      ModuleFillBus.fill('evolution', const {'p': '0.9', 'q': '0.1'});
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));

      expect(_ctrlText(t, 'A 基因频率 p'), '0.33',
          reason: '反向：内容没变（手敲的 0.33 还在）');
      expect(find.text(kModuleFillSkippedDirty), findsOneWidget,
          reason: '拒绝时必须明说「本次参数未写入」');
      expect(_canOverwrite('evolution'), isFalse, reason: '接线检查：敲了题 ⇒ 整页 dirty');
    });
  });

  group('ploidy（染色体倍性）', () {
    testWidgets('出厂状态下 fill 真把目标页签切到前台', (t) async {
      await _pump(t, const PloidyPage());
      expect(_canOverwrite('ploidy'), isTrue, reason: '出厂 ⇒ 放行');
      expect(fieldLike('亲本基因型'), findsNothing,
          reason: '前提：开局停在「组数判断」，育种应用的输入框不在屏上');

      ModuleFillBus.fill('ploidy', const {'tab': '2'});
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));

      // 正向判据落在**渲染产物**上：只有真的切到「育种应用」页签，
      // 这个输入框才会被构建出来（出厂值 AaBb）。
      expect(_ctrlText(t, '亲本基因型'), 'AaBb',
          reason: '正向：目标页签真的被切到前台（该输入框只存在于那个页签）');
    });

    testWidgets('学生敲了题后 fill 拒切 + 屏上出提示', (t) async {
      await _pump(t, const PloidyPage());
      final f = fieldLike('染色体总条数');
      expect(f, findsOneWidget, reason: '前提：「染色体总条数」输入框在场上');
      await t.enterText(f, '99');
      await t.pump();

      ModuleFillBus.fill('ploidy', const {'tab': '2'});
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));

      expect(fieldLike('亲本基因型'), findsNothing,
          reason: '反向：apply 整段没跑 ⇒ 连页签都没切过去');
      expect(_ctrlText(t, '染色体总条数'), '99',
          reason: '反向：学生敲的 99 没被改（出厂是 8）');
      expect(find.text(kModuleFillSkippedDirty), findsOneWidget,
          reason: '拒绝时必须明说「本次参数未写入」');
      expect(_canOverwrite('ploidy'), isFalse, reason: '接线检查：敲了题 ⇒ 整页 dirty');
    });
  });

  group('pedigree（遗传图谱）', () {
    testWidgets('出厂状态下 fill 真把双亲写进输入框', (t) async {
      await _pump(t, const GeneticPedigreePage());
      expect(_canOverwrite('pedigree'), isTrue, reason: '出厂 ⇒ 放行写入');

      ModuleFillBus.fill('pedigree', const {'father': 'AABB', 'mother': 'aabb'});
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));

      // 出厂 AABBCC / aabbcc。
      expect(_ctrlText(t, '亲本 ♂'), 'AABB', reason: '正向：父本由出厂 AABBCC 变成 AABB');
      expect(_ctrlText(t, '亲本 ♀'), 'aabb', reason: '正向：母本由出厂 aabbcc 变成 aabb');
    });

    testWidgets('学生敲了题后 fill 不覆盖 + 屏上出提示', (t) async {
      await _pump(t, const GeneticPedigreePage());
      final f = fieldLike('亲本 ♂');
      expect(f, findsOneWidget, reason: '前提：「亲本 ♂」输入框在场上');
      await t.enterText(f, 'TTTT');
      await t.pump();

      ModuleFillBus.fill('pedigree', const {'father': 'AABB', 'mother': 'aabb'});
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));

      expect(_ctrlText(t, '亲本 ♂'), 'TTTT',
          reason: '反向：内容没变（手敲的 TTTT 还在）');
      expect(find.text(kModuleFillSkippedDirty), findsOneWidget,
          reason: '拒绝时必须明说「本次参数未写入」');
      expect(_canOverwrite('pedigree'), isFalse, reason: '接线检查：敲了题 ⇒ dirty');
    });

    testWidgets('学生已算出的系谱图也算 dirty（输入框没动也要拦）', (t) async {
      await _pump(t, const GeneticPedigreePage());
      // 只点「计算」，**不动输入框** —— 双亲仍是出厂 AABBCC / aabbcc，
      // 但学生已经在画布上建了自己的系谱。
      final calc = find.text('计算');
      expect(calc, findsWidgets, reason: '前提：「计算」按钮在屏上');
      await t.tap(calc.first);
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));

      expect(_ctrlText(t, '亲本 ♂'), 'AABBCC',
          reason: '前提：输入框确实还是出厂值（这条要拦的不是输入框）');

      ModuleFillBus.fill('pedigree', const {'father': 'AABB', 'mother': 'aabb'});
      await t.pump();
      await t.pump(const Duration(milliseconds: 600));

      expect(_ctrlText(t, '亲本 ♂'), 'AABBCC',
          reason: '反向：双亲没被改（仍是出厂 AABBCC），学生画布上的系谱没被重建');
      expect(find.text(kModuleFillSkippedDirty), findsOneWidget,
          reason: '反向：屏上出现提示，而不是静默重建引擎');
      expect(_canOverwrite('pedigree'), isFalse,
          reason: '接线检查：已算出的系谱是学生自己的数据（重建引擎会丢外来样本与连线）');
    });
  });
}
