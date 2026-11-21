// cross_pedigree_link_test.dart —— 9331 ↔ 遗传图谱 应用层链接守卫网
//
// 被测：lib/ui/cross_pedigree_link.dart 的 openCrossInPedigree / returnToCrossCalculator。
// 依赖：ModuleFillBus（register/resetForTest 由测试注入）；非 push 路径的
// apply 在 postFrame 回调里执行 ⇒ 断言 apply 前必须 pump 一帧（既有惯例同
// test/module_fill_test.dart「主导航 target 走 pageIndex」用例）。

import 'package:biology/ui/cross_pedigree_link.dart';
import 'package:biology/ui/module_fill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(ModuleFillBus.resetForTest);
  tearDown(ModuleFillBus.resetForTest);

  testWidgets('新契约：pedigree_from_cross 已注册时参数拼接逐项正确', (t) async {
    await t.pumpWidget(const SizedBox());
    final got = <Map<String, String>>[];
    ModuleFillBus.register(ModuleFillTarget(
      moduleId: 'pedigree_from_cross',
      pageIndex: 1,
      label: '遗传图谱·追加计算',
      apply: (p) {
        got.add(p);
        return true;
      },
    ));

    final ok = openCrossInPedigree(
      p1: 'AaBb',
      p2: 'AAbb',
      ratio: '9:3:3:1',
      sourceLabel: '自定义来源',
    );
    await t.pump();

    expect(ok, isTrue);
    expect(got, [
      {
        'p1': 'AaBb',
        'p2': 'AAbb',
        'ratio': '9:3:3:1',
        'sourceLabel': '自定义来源',
      }
    ], reason: 'p1/p2/ratio/sourceLabel 四项拼接逐项钉住');
  });

  testWidgets('默认参数：ratio 缺省空串、sourceLabel 缺省「9331 杂交计算」', (t) async {
    await t.pumpWidget(const SizedBox());
    final got = <Map<String, String>>[];
    ModuleFillBus.register(ModuleFillTarget(
      moduleId: 'pedigree_from_cross',
      pageIndex: 1,
      label: '遗传图谱·追加计算',
      apply: (p) {
        got.add(p);
        return true;
      },
    ));

    openCrossInPedigree(p1: 'Aa', p2: 'aa');
    await t.pump();

    expect(got.single['ratio'], '', reason: 'ratio 缺省必须是空串而不是 null/缺键');
    expect(got.single['sourceLabel'], '9331 杂交计算');
  });

  testWidgets('回退契约：新目标未注册时落旧 pedigree 键（father/mother）', (t) async {
    await t.pumpWidget(const SizedBox());
    final got = <Map<String, String>>[];
    ModuleFillBus.register(ModuleFillTarget(
      moduleId: 'pedigree',
      pageIndex: 3,
      label: '遗传图谱',
      apply: (p) {
        got.add(p);
        return true;
      },
    ));

    final ok = openCrossInPedigree(p1: 'XAY', p2: 'XAXa');
    await t.pump();

    expect(ok, isTrue, reason: '回退路径命中仍返回 true');
    expect(got, [
      {'father': 'XAY', 'mother': 'XAXa'}
    ], reason: '旧契约只有 father/mother 两键，不带 p1/p2');
  });

  testWidgets('双缺：两个目标都未注册 ⇒ 返回 false（缺目标即缺参降级）', (t) async {
    await t.pumpWidget(const SizedBox());

    expect(openCrossInPedigree(p1: 'Aa', p2: 'aa'), isFalse,
        reason: 'pedigree_from_cross 与 pedigree 均未注册 ⇒ 无处可填');
  });

  testWidgets('重复调用：连调两次，每次各填一次参数、各返回 true', (t) async {
    await t.pumpWidget(const SizedBox());
    final got = <Map<String, String>>[];
    ModuleFillBus.register(ModuleFillTarget(
      moduleId: 'pedigree_from_cross',
      pageIndex: 1,
      label: '遗传图谱·追加计算',
      apply: (p) {
        got.add(p);
        return true;
      },
    ));

    expect(openCrossInPedigree(p1: 'AA', p2: 'aa', ratio: '3:1'), isTrue);
    expect(openCrossInPedigree(p1: 'Aa', p2: 'Aa', ratio: '1:2:1'), isTrue);
    await t.pump();

    expect(got.length, 2, reason: '两次调用两次填参，不多不少');
    expect(got[0]['ratio'], '3:1');
    expect(got[1]['ratio'], '1:2:1', reason: '第二次的参数不许被第一次覆盖');
  });

  testWidgets('returnToCrossCalculator：cross_dihybrid 已注册 ⇒ 导航到其页码', (t) async {
    await t.pumpWidget(const SizedBox());
    final nav = <int>[];
    ModuleFillBus.navigator = nav.add;
    ModuleFillBus.register(const ModuleFillTarget(
      moduleId: 'cross_dihybrid',
      pageIndex: 2,
      label: '遗传计算器·双基因',
      apply: _alwaysTrue,
    ));

    expect(returnToCrossCalculator(), isTrue);
    expect(nav, [2], reason: '导航器恰好收到目标页码一次');
  });

  testWidgets('returnToCrossCalculator 降级：缺目标 / 缺导航器 / 页码为负 ⇒ false', (t) async {
    await t.pumpWidget(const SizedBox());

    // ① 目标未注册
    ModuleFillBus.navigator = (_) {};
    expect(returnToCrossCalculator(), isFalse, reason: 'cross_dihybrid 未注册');

    // ② 导航器未注册
    ModuleFillBus.register(const ModuleFillTarget(
      moduleId: 'cross_dihybrid',
      pageIndex: 2,
      label: '遗传计算器·双基因',
      apply: _alwaysTrue,
    ));
    ModuleFillBus.navigator = null;
    expect(returnToCrossCalculator(), isFalse, reason: 'navigator 为 null ⇒ 不跳');

    // ③ 页码为负（不在主导航）
    ModuleFillBus.navigator = (_) {};
    ModuleFillBus.register(const ModuleFillTarget(
      moduleId: 'cross_dihybrid',
      pageIndex: -1,
      label: '遗传计算器·双基因',
      apply: _alwaysTrue,
    ));
    expect(returnToCrossCalculator(), isFalse, reason: 'pageIndex < 0 ⇒ 不跳');
  });
}

bool _alwaysTrue(Map<String, String> _) => true;
