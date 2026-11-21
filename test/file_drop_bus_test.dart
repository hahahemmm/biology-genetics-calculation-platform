// file_drop_bus_test.dart —— Wave2 拖图入窗总线单测（纯 Dart）。
//
// 覆盖（工单规格）：
//   - takeImage：png 命中 / txt 跳过；全非图片 → null；大写 .PNG 命中
//     且 extension 归一小写；多图取第一个；读不了的图片跳到下一候选。
//   - claim/release/hasConsumer 计数语义（重复 claim、多 release 钳 0）。
//   - broadcast stream：多订阅者都收到 publish。

import 'dart:io';
import 'dart:typed_data';

import 'package:biology/ui/file_drop_bus.dart';
import 'package:biology/ui/image_pick.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('file_drop_bus_test');
    FileDropBus.instance.resetForTest();
  });

  tearDown(() {
    FileDropBus.instance.resetForTest();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  File fake(String name, List<int> bytes) =>
      File('${tmp.path}${Platform.pathSeparator}$name')
        ..writeAsBytesSync(bytes);

  group('takeImage（路径 → PickedImage 静态工具，v2.19.67 P2 #5 改异步）', () {
    test('png 命中、txt 跳过：txt 在前也只取那张 png', () async {
      final txt = fake('note.txt', [4, 5]);
      final png = fake('题.png', [1, 2, 3]); // 中文文件名走 UTF-8 路径链路
      final img = await FileDropBus.takeImage([txt.path, png.path]);
      expect(img, isNotNull);
      expect(img!.name, '题.png');
      expect(img.extension, 'png');
      expect(img.bytes, Uint8List.fromList([1, 2, 3]));
    });

    test('全非图片（txt/pdf/无扩展名）→ null', () async {
      final txt = fake('a.txt', [1]);
      final pdf = fake('b.pdf', [2]);
      final noext = File('${tmp.path}${Platform.pathSeparator}c')..writeAsStringSync('x');
      expect(
          await FileDropBus.takeImage([txt.path, pdf.path, noext.path]), isNull);
    });

    test('大写扩展名 .PNG/.JPG 命中，extension 归一小写', () async {
      final up = fake('SHOT.PNG', [9]);
      expect(await FileDropBus.takeImage([up.path]), isNotNull);
      final img = (await FileDropBus.takeImage([up.path]))!;
      expect(img.extension, 'png');
      expect(img.name, 'SHOT.PNG');
    });

    test('多图连拖只取第一个命中项', () async {
      final a = fake('a.png', [1]);
      final b = fake('b.jpg', [2]);
      final img = await FileDropBus.takeImage([b.path, a.path]);
      expect(img!.name, 'b.jpg'); // 列表顺序优先，不挑扩展名
    });

    test('命中扩展名但文件已被删 → 跳过取下一候选；全读不到 → null', () async {
      final gone = '${tmp.path}${Platform.pathSeparator}gone.png';
      final live = fake('live.png', [7]);
      final img = await FileDropBus.takeImage([gone, live.path]);
      expect(img, isNotNull);
      expect(img!.name, 'live.png');
      expect(await FileDropBus.takeImage([gone]), isNull);
    });
  });

  group('claim/release/hasConsumer（消费者计数）', () {
    test('默认无消费者；claim 累加、release 递减、多 release 钳 0', () {
      final bus = FileDropBus.instance;
      expect(bus.hasConsumer, isFalse);
      bus.claim();
      expect(bus.hasConsumer, isTrue);
      bus.claim(); // 两个对话框叠开（理论上）仍算有消费者
      expect(bus.hasConsumer, isTrue);
      bus.release();
      expect(bus.hasConsumer, isTrue);
      bus.release();
      expect(bus.hasConsumer, isFalse);
      bus.release(); // 防御：不许打穿成负
      expect(bus.hasConsumer, isFalse);
    });
  });

  group('publish → broadcast stream（多订阅者都收到）', () {
    test('HomeShell 与拍题对话框两个订阅者同轮各收一份', () async {
      final bus = FileDropBus.instance;
      final a = <String>[];
      final b = <String>[];
      final s1 = bus.stream.listen((i) => a.add(i.name));
      final s2 = bus.stream.listen((i) => b.add(i.name));
      bus.publish(PickedImage(
          Uint8List.fromList([1]), 'drop1.png', 'png'));
      await pumpEventQueue();
      expect(a, ['drop1.png']);
      expect(b, ['drop1.png']);
      // broadcast 不回放：晚订阅者收不到历史事件——initialImage 参数
      // 存在的原因（见 file_drop_bus.dart 消费协议第 3 条）。
      final late = <String>[];
      final s3 = bus.stream.listen((i) => late.add(i.name));
      await pumpEventQueue();
      expect(late, isEmpty);
      s1.cancel();
      s2.cancel();
      s3.cancel();
    });
  });
}
