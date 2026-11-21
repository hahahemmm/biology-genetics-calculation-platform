// canvas_input_test.dart —— lib/ui/canvas_input.dart 公开契约测试
//
// 未防御记录（按要求不断言）：canvasPanByScreenDelta / canvasPanAfterScroll
// 对 NaN / Infinity 输入均无防御，Matrix4.translationValues 不抛异常、
// 会静默产出 NaN/Infinity 平移矩阵，调用方需自行保证输入有限。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/ui/canvas_input.dart';

/// 逐元素近似比较两个矩阵（浮点乘法有微小误差）。
void expectMatrixClose(Matrix4 actual, Matrix4 expected) {
  for (var i = 0; i < 16; i++) {
    expect(actual.storage[i], moreOrLessEquals(expected.storage[i], epsilon: 1e-9),
        reason: 'storage[\$i] 不一致');
  }
}

/// 按下按键并在测试结束时自动松开，避免污染后续用例。
Future<void> pressKey(LogicalKeyboardKey key) async {
  await simulateKeyDownEvent(key);
  addTearDown(() => simulateKeyUpEvent(key));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final scale80 = Matrix4.diagonal3Values(0.8, 0.8, 1);

  group('canvasPanByScreenDelta', () {
    test('单位矩阵 + (35,0) 平移 35', () {
      final r = canvasPanByScreenDelta(Matrix4.identity(), const Offset(35, 0));
      expect(r.storage[12], moreOrLessEquals(35, epsilon: 1e-9));
      expect(r.storage[13], moreOrLessEquals(0, epsilon: 1e-9));
    });

    test('80% 缩放下拖 35px 仍走 35px（回归「右乘不跟手」bug）', () {
      final r = canvasPanByScreenDelta(scale80, const Offset(35, 0));
      expect(r.storage[12], moreOrLessEquals(35, epsilon: 1e-9));
    });

    test('左乘顺序：等于 T*M 且不等于 M*T', () {
      const delta = Offset(35, 0);
      final r = canvasPanByScreenDelta(scale80, delta);
      final leftMul = Matrix4.translationValues(35, 0, 0)..multiply(scale80);
      final rightMul = scale80.clone()..multiply(Matrix4.translationValues(35, 0, 0));
      expectMatrixClose(r, leftMul);
      expect(r.storage[12], isNot(moreOrLessEquals(rightMul.storage[12], epsilon: 1e-9)),
          reason: '不应等于右乘（右乘后平移是 28 而非 35）');
    });

    test('Offset.zero 不改变矩阵', () {
      final r = canvasPanByScreenDelta(scale80, Offset.zero);
      expectMatrixClose(r, scale80);
    });

    test('负值 delta 正常平移', () {
      final r = canvasPanByScreenDelta(Matrix4.identity(), const Offset(-10, -20));
      expect(r.storage[12], moreOrLessEquals(-10, epsilon: 1e-9));
      expect(r.storage[13], moreOrLessEquals(-20, epsilon: 1e-9));
    });

    test('极大值 1e9 不抛异常且平移正确', () {
      final r = canvasPanByScreenDelta(Matrix4.identity(), const Offset(1e9, -1e9));
      expect(r.storage[12], moreOrLessEquals(1e9, epsilon: 1e-3));
      expect(r.storage[13], moreOrLessEquals(-1e9, epsilon: 1e-3));
    });

    test('缩放为 0 / 极大缩放时平移仍按屏幕像素', () {
      final zeroScale = Matrix4.diagonal3Values(0, 0, 1);
      final r0 = canvasPanByScreenDelta(zeroScale, const Offset(35, 0));
      expect(r0.storage[12], moreOrLessEquals(35, epsilon: 1e-9));

      final hugeScale = Matrix4.diagonal3Values(1000, 1000, 1);
      final r1 = canvasPanByScreenDelta(hugeScale, const Offset(35, 0));
      expect(r1.storage[12], moreOrLessEquals(35, epsilon: 1e-9));
    });

    test('已在平移中的矩阵继续按屏幕像素叠加平移', () {
      final moved = Matrix4.translationValues(100, 50, 0)..multiply(scale80);
      final r = canvasPanByScreenDelta(moved, const Offset(35, 10));
      expect(r.storage[12], moreOrLessEquals(135, epsilon: 1e-9));
      expect(r.storage[13], moreOrLessEquals(60, epsilon: 1e-9));
    });
  });

  group('canvasPanAfterScroll', () {
    test('向下滚动 (0,100) 内容上移（y 取反）', () {
      final r = canvasPanAfterScroll(scale80, const Offset(0, 100));
      expect(r.storage[13], moreOrLessEquals(-100, epsilon: 1e-9));
    });

    test('向右滚动 (100,0) 内容左移（x 取反）', () {
      final r = canvasPanAfterScroll(Matrix4.identity(), const Offset(100, 0));
      expect(r.storage[12], moreOrLessEquals(-100, epsilon: 1e-9));
    });

    test('零滚动不改变矩阵', () {
      final r = canvasPanAfterScroll(scale80, Offset.zero);
      expectMatrixClose(r, scale80);
    });

    test('带缩放时取反平移仍不受缩放影响', () {
      final r = canvasPanAfterScroll(scale80, const Offset(0, 100));
      expect(r.storage[12], moreOrLessEquals(0, epsilon: 1e-9));
      expect(r.storage[13], moreOrLessEquals(-100, epsilon: 1e-9));
      // 与 canvasPanByScreenDelta(-scrollDelta) 一致
      expectMatrixClose(r, canvasPanByScreenDelta(scale80, const Offset(0, -100)));
    });
  });

  group('canvasZoomModifierPressed', () {
    test('无按键时为 false', () {
      expect(canvasZoomModifierPressed, isFalse);
    });

    test('按住 Ctrl 为 true，松开恢复 false', () async {
      await pressKey(LogicalKeyboardKey.controlLeft);
      expect(canvasZoomModifierPressed, isTrue);
      await simulateKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(canvasZoomModifierPressed, isFalse);
    });

    test('按住 Meta 为 true，松开恢复 false', () async {
      await pressKey(LogicalKeyboardKey.metaLeft);
      expect(canvasZoomModifierPressed, isTrue);
      await simulateKeyUpEvent(LogicalKeyboardKey.metaLeft);
      expect(canvasZoomModifierPressed, isFalse);
    });

    test('Ctrl 与 Meta 同按同样为 true', () async {
      await pressKey(LogicalKeyboardKey.controlLeft);
      await pressKey(LogicalKeyboardKey.metaLeft);
      expect(canvasZoomModifierPressed, isTrue);
    });
  });
}
