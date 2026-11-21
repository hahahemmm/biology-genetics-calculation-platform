// image_pick_web_test.dart —— v2.12 跨端完备测试
//
// 覆盖 lib/ui/image_pick_stub.dart 的 runWithCancelTimeout 行为。
//
// 为什么测试 stub 而非 web：image_pick_web.dart 顶部依赖 package:web
// （HTMLInputElement / FileReader 等 DOM API），VM 平台直接 import 会
// 编译失败。timeout 兜底逻辑抽到 stub 后，VM 测试可纯 dart 覆盖
// 全部 3 路径（正常完成 / 立即取消 / 永久悬挂）。
//
// 设计语义：兜底 = 视为取消（fallback 默认为 null），不抛 TimeoutException。
// UI 上层把 null 视作用户在系统对话框点了「取消」——面板无任何状态污染。
import 'dart:async';
import 'dart:typed_data';

import 'package:biology/ui/image_pick_stub.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('image_pick_stub.runWithCancelTimeout', () {
    test('正常完成：future 在 timeout 内完成 → 返回真实值（不触发 timeout）', () async {
      // 10ms 后 future 正常完成 → 远小于 200ms timeout → 走 fast path
      final c = Completer<int>();
      Future<void>.delayed(const Duration(milliseconds: 10), () {
        if (!c.isCompleted) c.complete(42);
      });
      final result = await runWithCancelTimeout<int>(
        c.future,
        timeout: const Duration(milliseconds: 200),
        fallback: -1,
      );
      expect(result, 42, reason: 'fast path 必须原样透传 future 的值');
    });

    test('用户取消：future 立即 complete(null) → 返回 null', () async {
      // 模拟"用户在浏览器文件对话框点取消"语义：change 事件不触发，
      // 但我们这里验证另一种"change 触发了但 files 为空"的等价路径
      // ——image_pick_web.dart 内部 done.complete(null)。
      final c = Completer<String?>();
      c.complete(null);
      final result = await runWithCancelTimeout<String?>(
        c.future,
        timeout: const Duration(seconds: 1),
        fallback: 'UNREACHABLE',
      );
      expect(result, isNull, reason: '已完成 future 的 null 应当透传');
    });

    test('永久悬挂：future 永不完成 → timeout 触发返回 fallback，不抛异常', () async {
      // 关键路径：模拟 v2.11 阶段的 bug 场景——done.future 永不完成。
      // 修复后：60s 后必须 fallback=null 返回，UI 才能继续「视为取消」分支。
      final hanging = Completer<PickedImage?>().future; // 永不 complete
      final result = await runWithCancelTimeout<PickedImage?>(
        hanging,
        timeout: const Duration(milliseconds: 80),
        fallback: null,
      );
      expect(result, isNull, reason: '超时后必须返回 fallback');
    });

    test('timeout 触发后不抛 TimeoutException（关键不变量）', () async {
      // 退路必须 absorb TimeoutException：UI 上层 try/catch 已经会捕获
      // 异常并显示 SnackBar，但 timeout 是"正常取消"语义，不应走异常
      // 分支——否则 snackbar 会误报「选图失败」。
      final hanging = Completer<int>().future;
      Object? caught;
      try {
        await runWithCancelTimeout<int>(
          hanging,
          timeout: const Duration(milliseconds: 50),
          fallback: 0,
        );
      } catch (e) {
        caught = e;
      }
      expect(caught, isNull, reason: 'timeout 必须不抛异常，fallback 直接返回');
    });

    test('fallback 默认值：不传 fallback → 返回 null', () async {
      // 默认 fallback = null 等价于"用户取消"，调用方按 null 处理。
      final hanging = Completer<String>().future;
      final result = await runWithCancelTimeout<String>(
        hanging,
        timeout: const Duration(milliseconds: 30),
      );
      expect(result, isNull, reason: '默认 fallback 必须为 null');
    });

    test('正常 PickedImage 完成：验证类型透传', () async {
      // 端到端：模拟 web 端 FileReader 完成后 done.complete(PickedImage(...))。
      final c = Completer<PickedImage?>();
      final img = PickedImage(Uint8List.fromList([1, 2, 3, 4]), 'photo.png', 'png');
      c.complete(img);
      final result = await runWithCancelTimeout<PickedImage?>(
        c.future,
        timeout: const Duration(milliseconds: 200),
        fallback: null,
      );
      expect(result, isNotNull);
      expect(result!.name, 'photo.png');
      expect(result.extension, 'png');
      expect(result.bytes, [1, 2, 3, 4]);
    });
  });

  group('image_pick_stub 平台契约', () {
    test('导出 PickedImage 类（与 web/io/stub 共享）', () {
      // image_pick.dart 用 conditional import 分发到 web/io/stub；
      // VM 平台测试只 import stub 直接验证 PickedImage 数据契约。
      // 编译期保证：能 import 即说明 PickedImage 暴露。
      final img = PickedImage(Uint8List(0), 'x.png', 'png');
      expect(img.name, 'x.png');
      expect(img.extension, 'png');
      expect(img.bytes.length, 0);
    });

    test('stub 的 pickImageFile() 立即返回 null（兜底语义）', () async {
      // 非 web/io 平台直接返回 null，与"用户取消"等价（UI 上层都按
      // null = 无选择处理）。注意 VM 测试不要 import image_pick.dart
      // （会条件转发到 image_pick_io.dart，Windows VM 会弹 PowerShell）。
      final r = await pickImageFile();
      expect(r, isNull);
    });
  });
}
