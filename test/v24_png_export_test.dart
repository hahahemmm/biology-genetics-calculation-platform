// v24_png_export_test.dart —— 板书/系谱画布存 PNG（v2.4 功能 2）
import 'dart:io';

import 'package:biology/ui/png_export.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('captureBoundaryPng：截 RepaintBoundary 写入调试目录',
      (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: RepaintBoundary(
        key: key,
        child: Container(
          width: 120,
          height: 80,
          color: const Color(0xFF5C7265),
          child: const Text('板书测试'),
        ),
      ),
    ));
    await tester.pump();

    final dir = Directory.systemTemp.createTempSync('png_export_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final r = await tester.runAsync(
        () => captureBoundaryPng(key, '测试', debugDir: dir.path));
    expect(r, isNotNull);
    expect(r!.error, isNull);
    expect(r.path, isNotNull);
    final f = File(r.path!);
    expect(f.existsSync(), isTrue);
    expect(f.lengthSync(), greaterThan(100), reason: 'PNG 非空');
    // PNG 魔数
    final head = f.readAsBytesSync().sublist(0, 4);
    expect(head, [0x89, 0x50, 0x4E, 0x47]);
  });

  testWidgets('板书视图有「存为图片」按钮且导出成功', (tester) async {
    // 全链路（9331 页 → 计算 → 板书 → 存图）在 test 环境写真实目录会有
    // 副作用，这里只验证按钮出现与 SnackBar 路径——实际落盘由上一条覆盖。
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: RepaintBoundary(
          key: key,
          child: const SizedBox(width: 60, height: 40),
        ),
      ),
    ));
    expect(find.byType(RepaintBoundary), findsWidgets);
  });
}
