// scroll_reveal_test.dart —— revealInViewport「先量后滚、只滚一次」守卫网
//
// 被测：lib/ui/scroll_reveal.dart 的纯函数 revealInViewport。
// 断言纪律：能断具体 offset 就断具体值（布局全固定：视口高 200，
// 目标占 content [300,400)，两侧各 300 填充 ⇒ 滚动去向可精确预期）。

import 'package:biology/ui/scroll_reveal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 固定布局：视口高 200，目标 [300,400)，内容总高 700。
Future<void> _pumpList(WidgetTester t, GlobalKey key) async {
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(
        height: 200,
        child: ListView(
          children: [
            const SizedBox(height: 300),
            Container(key: key, height: 100, color: Colors.teal),
            const SizedBox(height: 300),
          ],
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

ScrollPosition _pos(WidgetTester t) =>
    t.state<ScrollableState>(find.byType(Scrollable)).position;

void main() {
  testWidgets('目标在视口下方：滚到目标终点贴视口底（pixels 0 → 200）', (t) async {
    final key = GlobalKey();
    await _pumpList(t, key);
    expect(_pos(t).pixels, 0, reason: '初始未滚动（非键盘/函数通道基线）');

    final ok = await revealInViewport(key.currentContext!);

    expect(ok, isTrue, reason: '目标在下方外 ⇒ 确实发起滚动');
    expect(_pos(t).pixels, closeTo(200, 0.5),
        reason: 'alignment 1.0：让目标终点 400 贴视口底 ⇒ pixels = 200');
  });

  testWidgets('目标在视口上方：滚到目标起点贴视口顶（pixels 350 → 300）', (t) async {
    final key = GlobalKey();
    await _pumpList(t, key);
    _pos(t).jumpTo(350); // 视口 [350,550)，目标顶部被卷出 50px

    final ok = await revealInViewport(key.currentContext!);

    expect(ok, isTrue, reason: '目标在上方外 ⇒ 确实发起滚动');
    expect(_pos(t).pixels, closeTo(300, 0.5),
        reason: 'alignment 0.0：让目标起点 300 贴视口顶 ⇒ pixels = 300');
  });

  testWidgets('目标已完整可见：no-op 返回 false，pixels 一字不动', (t) async {
    final key = GlobalKey();
    await _pumpList(t, key);
    _pos(t).jumpTo(250); // 视口 [250,450)，目标 [300,400) 完整在内

    final ok = await revealInViewport(key.currentContext!);

    expect(ok, isFalse, reason: '已完整可见 ⇒ 不发起滚动（区别于 ensureVisible 原样调）');
    expect(_pos(t).pixels, 250, reason: '一个像素都不许动');
  });

  testWidgets('幂等：成功 reveal 后立刻再调，第二次 no-op 且位置不变', (t) async {
    final key = GlobalKey();
    await _pumpList(t, key);

    expect(await revealInViewport(key.currentContext!), isTrue);
    expect(_pos(t).pixels, closeTo(200, 0.5));

    expect(await revealInViewport(key.currentContext!), isFalse,
        reason: '第二次调用时目标已完整可见 ⇒ 幂等 no-op');
    expect(_pos(t).pixels, closeTo(200, 0.5), reason: '第二次不许再滚');
  });

  testWidgets('容差边界：超容差 0.4px 不滚、超 0.6px 滚', (t) async {
    final key = GlobalKey();
    await _pumpList(t, key);

    _pos(t).jumpTo(300.4); // 目标顶部仅比视口顶高 0.4px（< tolerance 0.5）
    expect(await revealInViewport(key.currentContext!), isFalse,
        reason: '0.4px 超出在 0.5 容差内 ⇒ 视为已可见');
    expect(_pos(t).pixels, 300.4);

    _pos(t).jumpTo(300.6); // 超出 0.6px（> tolerance）
    expect(await revealInViewport(key.currentContext!), isTrue,
        reason: '超出容差 ⇒ 必须滚');
    expect(_pos(t).pixels, closeTo(300, 0.5), reason: '滚到目标起点贴视口顶');
  });

  testWidgets('降级：目标不在 Scrollable 内 ⇒ false 不抛错', (t) async {
    final key = GlobalKey();
    await t.pumpWidget(MaterialApp(
      home: Center(child: Container(key: key, width: 50, height: 50)),
    ));
    await t.pumpAndSettle();

    expect(await revealInViewport(key.currentContext!), isFalse,
        reason: 'Scrollable.maybeOf 为 null ⇒ no-op 降级');
  });

  testWidgets('降级：目标已卸载（context 未挂载）⇒ false 不抛错', (t) async {
    final key = GlobalKey();
    await t.pumpWidget(MaterialApp(
      home: Center(child: Container(key: key, width: 50, height: 50)),
    ));
    final ctx = key.currentContext!;
    await t.pumpWidget(const MaterialApp(home: SizedBox()));
    expect(ctx.mounted, isFalse, reason: '前提：目标已随树卸载');

    expect(await revealInViewport(ctx), isFalse,
        reason: 'postFrame/异步回调进来时元素已销毁 ⇒ 安全降级');
  });
}
