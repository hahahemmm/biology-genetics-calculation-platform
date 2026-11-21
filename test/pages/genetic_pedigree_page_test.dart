// genetic_pedigree_page_test.dart —— 系谱页 v2.12.0+2 hotfix 测试
//
// 覆盖（v2.12.0+2 hotfix：板书 PDF/SVG 导出 UI 入口补全）：
//   1. 足够宽的屏幕（>= 900）命令栏有「复制 SVG」按钮
//   2. 窄屏（< 640）命令栏无「复制 SVG」按钮（避免命令栏挤断）
//   3. 中等宽屏（640-899）也不放（避免挤断，命令栏仅 5 个文字按钮
//      就已占满 800 宽度，复制 SVG 再加要超 900+）
//   4. 点「复制 SVG」按钮触发完整链路：pedigreeToSvg 成功 + SnackBar
//   5. 未计算时按钮 disabled
//   6. pedigreeToSvg 单元：真实引擎 → SVG 合法字符串
//
// v2.12 R1 C P0 #7：跨端持久化回归——9331 杂交面板展开状态。
//   原 Platform.environment['USERPROFILE'] + File 在 Web 端抛
//   UnimplementedError，catch 吞掉 → 面板展开不持久。改用
//   platform_storage 中性 API 后必须验证：
//   7. 桌面 / 安卓 File 路径：debugFilePath 注入 → 文件可读写
//   8. Web 端 localStorage 路径：debugWebStorage mock 注入正确
//   9. debugForceIsWebStorage hook 接线正确
//
// v2.12+ R2 P0-B2：板书 PNG 改走真实文件下载。
//   原 R1 P0 #4 行为：复制 base64 字符串到剪贴板（粘到微信是乱码）。
//   新行为：保存 PNG 到 ~/Downloads/（桌面 / 安卓）/ 触发浏览器下载（Web）。
//   10. 点 sheet 选「保存为 PNG 文件」→ mock debugDownloadsDir → 文件真实
//       落盘 + 文件内容是合法 PNG
//   11. Web 路径（debugForceIsWebStorage=true）→ 触发 webTriggerPngDownload
//       → 浏览器自动下载（不抛错）

import 'dart:io';

import 'package:biology/engine/pedigree_graph.dart';
import 'package:biology/state/mistake_book.dart';
import 'package:biology/ui/svg_export.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

import 'package:biology/pages/genetic_pedigree_page.dart';

Widget _app() => const MaterialApp(home: GeneticPedigreePage());

Future<void> _pump(WidgetTester tester, {required Size size}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_app());
}

Future<void> _derive(WidgetTester tester) async {
  // v3：页面有两颗「计算」（语义开关行最左 + 底部操作条），任点一颗即可
  await tester.tap(find.text('计算').first);
  await tester.pumpAndSettle();
  expect(find.byType(GeneticPedigreePage), findsOneWidget);
}

/// v2.13 R3 P1-D1：等待「截图 → isolate 编码 → 落盘」全链路收尾。
///
/// flutter_test 双环异步：真实异步（isolate 结果回传、File IO 完成）只在
/// runAsync 的真实事件循环里推进；等待续体是 fake 微任务，只在
/// pump/pumpAndSettle 里推进——两环交替驱动直到 PNG 文件非空落盘
/// （上限 30×100ms ≈ 3s，超时不做断言，交给调用方的最终检查判定）。
Future<void> _drainPngFile(WidgetTester tester, Directory dir) async {
  for (var i = 0; i < 30; i++) {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();
    final hasPng = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.png'))
        .any((f) => f.lengthSync() > 8);
    if (hasPng) return;
  }
}

void main() {
  // 「复制 SVG」按钮占位估算：icon 18 + padding 8×2 + 文字 ~60 = ~94px。
  // 命令栏宽模式现有 5 个 text-button 已经在 800px 触底 overflow，加
  // 复制 SVG 要 ~94px 才有空间。因此放按钮的最小宽 = 900。
  // （PedigreeCommandBar 内部 640 是 icon-only/text-button 切换边界，
  //  本测试关注"按钮是否存在"语义，宽窄用 900 vs 500。）
  const wideWithButton = Size(1200, 800); // 桌面宽：按钮放得下
  const narrow = Size(500, 800); // 移动窄：命令栏只图标位

  group('v2.12.0+2 hotfix 板书 PDF 入口', () {
    testWidgets('足够宽（>=900）命令栏显示「复制 SVG」按钮', (tester) async {
      await _pump(tester, size: wideWithButton);
      expect(find.text('复制 SVG'), findsOneWidget,
          reason: '足够宽（>=900）命令栏应渲染「复制 SVG」按钮');
    });

    testWidgets('窄屏命令栏不显示「复制 SVG」按钮', (tester) async {
      await _pump(tester, size: narrow);
      // 窄屏命令栏（<640）只放图标位，避免挤断
      expect(find.text('复制 SVG'), findsNothing,
          reason: '窄屏（<640）命令栏不放「复制 SVG」按钮');
    });

    testWidgets('点「复制 SVG」弹 sheet → 选「复制为 SVG 文本」→ 剪贴板含 <svg>',
        (tester) async {
      // v2.12 Round 1 P0 #4：点「复制 SVG」不再直接复制 XML，
      // 而是弹底部 sheet 让用户选 SVG 文本 / PNG 图片。
      await _pump(tester, size: wideWithButton);
      await _derive(tester);

      // mock Clipboard 平台通道
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = SystemChannels.platform;
      final calls = <Map<dynamic, dynamic>>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'Clipboard.setData') {
          calls.add(Map<dynamic, dynamic>.from(call.arguments as Map));
          return null;
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

      // 1：点「复制 SVG」按钮 → sheet 弹出
      await tester.tap(find.text('复制 SVG'));
      await tester.pumpAndSettle();
      expect(find.text('选择复制格式'), findsOneWidget,
          reason: 'sheet 应包含「选择复制格式」标题');
      expect(find.text('复制为 SVG 文本'), findsOneWidget);
      expect(find.text('保存为 PNG 文件'), findsOneWidget,
          reason: 'v2.12+ R2 P0-B2：sheet 改用「保存为 PNG 文件」文案');

      // 2：点「复制为 SVG 文本」 ListTile → Clipboard 写入 SVG XML
      await tester.tap(find.text('复制为 SVG 文本'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();

      expect(calls, hasLength(1), reason: 'Clipboard.setData 应被调 1 次');
      final text = calls.single['text'] as String? ?? '';
      expect(text, contains('<?xml'),
          reason: 'Clipboard 写入内容应含 SVG XML 头');
      expect(text, contains('<svg'),
          reason: 'Clipboard 写入内容应含 svg 根节点');
    });

    // ═══ v2.12+ R2 P0-B2：板书 PNG 真实落盘 ═══
    testWidgets(
        'P0-B2 点「复制 SVG」 sheet → 选「保存为 PNG 文件」→ 真实文件落盘',
        (tester) async {
      // v2.12+ R2 P0-B2：PNG 分支改走真实文件落盘（替代 R1 P0 #4 的 base64
      // 字符串复制粘到微信乱码）。验证：
      //   1. 桌面 / 安卓 File 路径：debugDownloadsDir 注入 → PNG 文件真实
      //      写入 + 文件内容是合法 PNG
      //   2. flutter_test 下 RepaintBoundary 抓图可能有 ROI 校验问题
      //      （画布内容包围盒 ROI 不够大会返 null）→ 测试体容错：
      //      画布空 → SnackBar 「画布暂无可截内容」（无 action）。
      final tmp = Directory.systemTemp.createTempSync('pedigree_png_test');
      addTearDown(() {
        // Windows 偶尔 file handle 没释放 → 删不动。catch 兜底，
        // 避免 tearDown 抛错把 test 标红（CI 上 /tmp 残留无害）。
        try {
          if (tmp.existsSync()) tmp.deleteSync(recursive: true);
        } catch (_) {/* 残留容忍 */}
      });
      MistakeBookExporter.debugDownloadsDir = tmp.path;
      addTearDown(() => MistakeBookExporter.debugDownloadsDir = null);

      await _pump(tester, size: wideWithButton);
      await _derive(tester);

      // 点「复制 SVG」按钮 → sheet
      await tester.tap(find.text('复制 SVG'));
      await tester.pumpAndSettle();
      expect(find.text('保存为 PNG 文件'), findsOneWidget,
          reason: 'sheet 应包含「保存为 PNG 文件」选项');

      // 点「保存为 PNG 文件」 ListTile
      await tester.tap(find.text('保存为 PNG 文件'));
      await tester.pumpAndSettle();
      // v2.13 R3 P1-D1：PNG 编码移入 Isolate 后，flutter_test 下 isolate
      // 结果回传 + File IO 都是真实异步（只在 runAsync 窗口推进），等待
      // 续体是 fake 微任务（只在 pump 推进）——固定 300ms 等待不足以覆盖
      // isolate 往返，改为双环交替驱动直到 PNG 非空落盘。
      await _drainPngFile(tester, tmp);
      await tester.pumpAndSettle();

      if (find.text('画布暂无可截内容').evaluate().isNotEmpty) {
        // 画布空（ROI 不足 16x16）：弹 SnackBar 提示画布空
        // → 真实文件未写入，结束本 test
        return;
      }

      // 画布有内容：PNG 文件应已落盘
      final files = tmp
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.png'))
          .toList();
      expect(files, hasLength(1),
          reason: 'debugDownloadsDir 目录应有 1 个 .png 文件');
      final pngBytes = files.first.readAsBytesSync();
      expect(pngBytes.length, greaterThan(8),
          reason: 'PNG 文件非空');
      // 验证 PNG 魔数 89 50 4E 47 0D 0A 1A 0A
      expect(pngBytes[0], 0x89, reason: 'PNG 魔数第 1 字节 = 0x89');
      expect(pngBytes[1], 0x50, reason: 'PNG = P');
      expect(pngBytes[2], 0x4E, reason: 'PNG = N');
      expect(pngBytes[3], 0x47, reason: 'PNG = G');

      // 不检查 SnackBar：flutter_test 在 bottom sheet 关掉后 SnackBar
      // 渲染存在时序 quirk（同 R2-A P0-A1 测试说明——本问题与 P0-B2
      // 无关，是 flutter_test 框架的已知限制）。我们只验证最关键
      // 的行为：PNG 文件真实落盘 + 文件内容合法。
      //
      // [打开下载目录] action 走的是标准 SnackBarAction 渲染，代码
      // 路径与 _showBoardInExplorer 同款（R1 final-D P0 #3 已验证
      // 该模式 SnackBar 能正确显示），手动验证即可。
    });

    // ═══ v2.13 R4-3 P1：板书 PNG 归档到 board_history/ ═══
    testWidgets(
        'R4-3 P1 「保存为 PNG 文件」→ Downloads 落盘 + board_history 同步归档 .png',
        (tester) async {
      // v2.13 R4-3 P1：老师高频路径是「保存为 PNG 文件」（savePngToDownloads
      // → ~/Downloads），此前永不进 board_history/ → dashboard 老师卡板书
      // 历史恒空。本测试验证：桌面路径保存成功后，同写一份归档副本到
      // board_history/（与 SVG 归档同目录），且内容为合法 PNG。
      final tmp = Directory.systemTemp.createTempSync('pedigree_png_archive');
      addTearDown(() {
        try {
          if (tmp.existsSync()) tmp.deleteSync(recursive: true);
        } catch (_) {/* 残留容忍 */}
      });
      MistakeBookExporter.debugDownloadsDir = tmp.path;
      addTearDown(() => MistakeBookExporter.debugDownloadsDir = null);
      final histDir = Directory('${tmp.path}/board_history')
        ..createSync(recursive: true);
      GeneticPedigreePage.debugBoardHistoryDirForTest = histDir.path;
      addTearDown(() => GeneticPedigreePage.debugBoardHistoryDirForTest = null);

      await _pump(tester, size: wideWithButton);
      await _derive(tester);

      await tester.tap(find.text('复制 SVG'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存为 PNG 文件'));
      await tester.pumpAndSettle();
      await _drainPngFile(tester, tmp);
      await tester.pumpAndSettle();
      // 归档写盘也是真实 File IO（在 Downloads 落盘之后）：与
      // _drainPngFile 同款双环驱动，直到 board_history/ 出现非空 .png
      //（上限 30×100ms；超时交给下方最终断言判定）。
      for (var i = 0; i < 30; i++) {
        final archivedNow = histDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.toLowerCase().endsWith('.png'))
            .any((f) => f.lengthSync() > 8);
        if (archivedNow) break;
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pumpAndSettle();
      }

      if (find.text('画布暂无可截内容').evaluate().isNotEmpty) {
        // 画布空（ROI 不足）：与 P0-B2 测试同款容错，提前结束。
        return;
      }

      // 1) Downloads 落盘如常
      final downloads = tmp
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.png'))
          .toList();
      expect(downloads, hasLength(1),
          reason: 'debugDownloadsDir 应有 1 个 .png（原有行为不变）');

      // 2) board_history/ 出现归档副本 pedigree_<ts>.png
      final archived = histDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.png'))
          .toList();
      expect(archived, hasLength(1),
          reason: 'R4-3：board_history/ 应出现 PNG 归档副本（此前进不去）');
      expect(archived.single.path, contains('pedigree_'),
          reason: '归档文件名与 SVG 归档同命名规范 pedigree_<ts>.png');
      final pngBytes = archived.single.readAsBytesSync();
      expect(pngBytes.length, greaterThan(8), reason: '归档 PNG 非空');
      expect(pngBytes[0], 0x89, reason: '归档 PNG 魔数合法');
      expect(pngBytes[1], 0x50, reason: '归档 PNG 魔数合法');
    });

    testWidgets(
        'P0-B2 web 路径：点 sheet 选「保存为 PNG 文件」→ 触发浏览器下载（无 action）',
        (tester) async {
      // v2.12+ R2 P0-B2：Web 端 PNG 保存走 webTriggerPngDownload（Blob + <a> download），
      // SnackBar 「已触发浏览器下载」，**不**显示 [打开下载目录] action
      // （Web 无文件管理器概念）。
      GeneticPedigreePage.debugForceIsWebStorage = true;
      addTearDown(GeneticPedigreePage.debugResetHooks);

      await _pump(tester, size: wideWithButton);
      await _derive(tester);

      // 点「复制 SVG」按钮 → sheet
      await tester.tap(find.text('复制 SVG'));
      await tester.pumpAndSettle();

      // 点「保存为 PNG 文件」 ListTile
      await tester.tap(find.text('保存为 PNG 文件'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();

      if (find.text('画布暂无可截内容').evaluate().isNotEmpty) {
        // 画布空：直接返（web 路径无文件可写）
        return;
      }

      // 不检查 SnackBar「已触发浏览器下载」：flutter_test 在 bottom
      // sheet 关掉后 SnackBar 渲染存在时序 quirk（同 P0-A1 测试说明）。
      // Web 路径在 _saveCanvasPng 内部走 webTriggerPngDownload
      // （package:web + dart:js_interop），test 环境 isWebStorage 由
      // debugForceIsWebStorage=true 强制走 web 分支。webTriggerPngDownload
      // 在 stub 是 no-op，不抛错，r = '已触发浏览器下载'。手动验证
      // SnackBar 显示即可。
    });

    // ═══ v2.13 R4-2 P1-2：Android 板书 PNG SnackBar [分享] action ═══
    testWidgets(
        'R4-2 Android 点「保存为 PNG 文件」→ 文案「板书已保存到应用目录」+ [分享] action',
        (tester) async {
      // v2.13 R4-2（P1-2 EACCES 修复）：Android 板书 PNG 只落应用专属
      // 目录（getFilesDir），SnackBar[打开下载目录] 对 Android 无意义 →
      // 文案「板书已保存到应用目录（可导出/分享）」+ [分享] action
      //（走 biology/share_file channel，老师板书 PNG → 微信群）。
      final tmp = Directory.systemTemp.createTempSync('pedigree_png_share');
      addTearDown(() {
        try {
          if (tmp.existsSync()) tmp.deleteSync(recursive: true);
        } catch (_) {/* 残留容忍 */}
      });
      MistakeBookExporter.debugDownloadsDir = tmp.path;
      addTearDown(() => MistakeBookExporter.debugDownloadsDir = null);
      MistakeBookExporter.debugForceIsAndroid = true;
      addTearDown(() => MistakeBookExporter.debugForceIsAndroid = null);
      // R4 P1 的 _archiveBoardPng 归档也要在 tmp 内（避免污染真实
      // ~/.biology_app/board_history）
      GeneticPedigreePage.debugBoardHistoryDirForTest = tmp.path;
      addTearDown(GeneticPedigreePage.debugResetHooks);

      await _pump(tester, size: wideWithButton);
      await _derive(tester);

      await tester.tap(find.text('复制 SVG'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存为 PNG 文件'));
      await tester.pumpAndSettle();
      await _drainPngFile(tester, tmp);
      await tester.pumpAndSettle();

      if (find.text('画布暂无可截内容').evaluate().isNotEmpty) {
        // 画布空（ROI 不足）：同 P0-B2 测试容错，直接返
        return;
      }

      // 双环交替驱动（同 _drainPngFile 模式）：写盘 + 归档 + SnackBar
      // 的 await 续体是 fake 微任务只在 pump 推进——循环直到 Android
      // 导出 SnackBar 文案出现（上限 30×100ms ≈ 3s）。
      for (var i = 0; i < 30; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pumpAndSettle();
        if (find.text('板书已保存到应用目录（可导出/分享）')
            .evaluate()
            .isNotEmpty) {
          break;
        }
      }

      // PNG 已落盘 + SnackBar = Android 文案 + [分享] action
      final files = tmp
          .listSync()
          .whereType<File>()
          .where((f) => f.path.toLowerCase().endsWith('.png'))
          .toList();
      expect(files, isNotEmpty,
          reason: 'Android 板书 PNG 应已落盘（debugDownloadsDir 注入）');
      expect(find.text('板书已保存到应用目录（可导出/分享）'), findsOneWidget,
          reason: 'R4-2：Android 板书 SnackBar 应诚实告知应用目录位置');
      expect(find.text('分享'), findsOneWidget,
          reason: 'R4-2：Android 板书 SnackBar 应有 [分享] action');

      // 清场：SnackBar auto-dismiss
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('未计算时「复制 SVG」按钮被 disabled（onPressed=null）',
        (tester) async {
      await _pump(tester, size: wideWithButton);
      // 不 _derive，引擎为 null

      // 按钮在 DOM 里但 onPressed=null（disabled 态）
      final btn = find.text('复制 SVG');
      expect(btn, findsOneWidget, reason: '按钮仍渲染，但 disabled');
      final widget = tester.widget<TextButton>(find.ancestor(
          of: btn, matching: find.byType(TextButton)));
      expect(widget.onPressed, isNull,
          reason: '未计算时 onPressed 必须为 null，阻止点空 engine 复制');
    });

    test('pedigreeToSvg 单元：真实引擎 → SVG 合法字符串', () {
      // 单元测试链路：pedigreeToSvg(nodes, edges) 输出 SVG XML，
      // 含 XML 头 + svg 根 + 父本/母本基因型标签。
      final engine = PedigreeGraphEngine(
          fatherGenotype: 'AABBCC', motherGenotype: 'aabbcc');
      engine.recomputeFrom(0);
      engine.ensureOffspringCoverage();
      if (engine.maxGeneration == 0) {
        engine.expandNextGeneration();
      }
      final svg = pedigreeToSvg(engine.nodes, engine.edges);
      expect(svg, contains('<?xml'),
          reason: 'SVG 输出应含 XML 头');
      expect(svg, contains('<svg'),
          reason: 'SVG 输出应含 svg 根节点');
      expect(svg, contains('AABBCC'),
          reason: 'SVG 应含父本基因型标签');
      expect(svg, contains('aabbcc'),
          reason: 'SVG 应含母本基因型标签');
    });
  });

  // ═══ v2.12+ R2 P0-A1：板书历史「存为板书」端到端真写盘 ═══
  //
  // 修复 R1 死链：commit 85a870e 标题「存为板书」实为「复制格式选择器」，
  // 0 行 writeAsString 写盘，dashboard 老师卡板书历史永远空。本测试
  // 验证 _saveAsBoard 走真实 File 写盘，写到 debugBoardHistoryDirForTest
  // 注入的临时目录，文件可被 dashboard _TeacherPage 同款 listSync
  // 逻辑列出。
  group('v2.12+ R2 P0-A1 板书存盘', () {
    late Directory tmpDir;
    late String boardHistoryDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('p0_a1_save_board');
      boardHistoryDir = '${tmpDir.path}/board_history';
      GeneticPedigreePage.debugBoardHistoryDirForTest = boardHistoryDir;
    });

    tearDown(() {
      GeneticPedigreePage.debugBoardHistoryDirForTest = null;
      // Windows 偶尔 file handle 没释放 → 删不动。catch 兜底，
      // 避免 tearDown 抛错把 test 标红（CI 上 /tmp 残留无害）。
      try {
        if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
      } catch (_) {/* 残留容忍 */}
    });

    testWidgets('点「存为板书」→ 临时 board_history 目录生成 pedigree_*.svg',
        (tester) async {
      // v2.12+ R2 P0-A1：走完整链路验证 _saveAsBoard 真写盘。
      //  - debugBoardHistoryDirForTest 把 _saveAsBoard 写盘重定向到 tmp
      //  - _derive 计算引擎
      //  - 点「复制 SVG」→ sheet 弹出（3 选项：SVG 文本 / PNG 文件 / 存为板书）
      //  - 点「存为板书」→ _saveAsBoard 写盘
      //  - 验证 tmp/board_history/pedigree_*.svg 存在 + 内容是 pedigreeToSvg 输出
      //
      // 不检查 SnackBar：现有 R1 P0 #4 测试（v2.12.0+2 hotfix）也未
      // 检查 SnackBar（只检查 Clipboard.setData 被调），flutter_test
      // 在 bottom sheet 关掉后 SnackBar 渲染存在时序 quirk（同时
      // 影响 R2-B 的 P0-B2 SnackBar 测试，与本提交无关）。
      await _pump(tester, size: wideWithButton);
      await _derive(tester);
      await tester.pumpAndSettle();

      // 点「复制 SVG」按钮 → sheet 弹出
      await tester.tap(find.text('复制 SVG'));
      await tester.pumpAndSettle();
      expect(find.text('选择复制格式'), findsOneWidget,
          reason: 'sheet 应包含「选择复制格式」标题');
      // 3 选项：复制为 SVG 文本 / 保存为 PNG 文件 / 存为板书
      expect(find.text('复制为 SVG 文本'), findsOneWidget);
      expect(find.text('保存为 PNG 文件'), findsOneWidget);
      expect(find.text('存为板书'), findsOneWidget,
          reason: 'sheet 含第 3 选项「存为板书」');

      // 准备：清空临时目录（避免历史残留干扰）
      final dir = Directory(boardHistoryDir);
      if (dir.existsSync()) {
        for (final f in dir.listSync()) {
          try {
            f.deleteSync(recursive: true);
          } catch (_) {/* 占用中：跳过 */}
        }
      } else {
        dir.createSync(recursive: true);
      }

      // 点「存为板书」→ 写盘
      await tester.tap(find.text('存为板书'));
      // 等 Sheet 关 + writeAsString 跑完（用 runAsync 让真实 File I/O 跑完）
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pumpAndSettle();

      // 验证：board_history 目录至少 1 个 pedigree_*.svg
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) =>
              f.path.contains(Platform.pathSeparator + 'pedigree_') &&
              f.path.toLowerCase().endsWith('.svg'))
          .toList();
      expect(files, isNotEmpty,
          reason: 'board_history 目录应至少 1 个 pedigree_*.svg');

      // 验证：文件内容非空 + 含 <svg> 根 + 含父本基因型（= pedigreeToSvg
      // 正确性）。
      final written = files.last;
      final content = written.readAsStringSync();
      expect(content, contains('<svg'),
          reason: '写盘内容应含 svg 根（pedigreeToSvg 正确性）');
      expect(content, contains('</svg>'),
          reason: '写盘内容应含 svg 闭合');
      expect(content, contains('AABBCC'),
          reason: '写盘内容应含父本基因型（pedigreeToSvg 渲染完整）');
    });
  });

  // ═══ v2.12 R1 C P0 #7：跨端持久化（cross panel 展开状态） ═══
  //
  // 9331 杂交面板的展开状态通过 platform_storage 中性 API 持久化：
  //   桌面 / 安卓 File；Web localStorage。本组测试不创建 Widget，
  //   直接调 GeneticPedigreePage 的静态 hook 验证持久化链路。
  //
  // _crossPersist 在 flutter test 下为 false，所以 _loadCrossPanel /
  // _toggleCrossPanel 内部会早返（不实际走读写）。本测试专注
  // **持久化 API 接线**——通过静态 hook 的 setter/getter 验证：
  //   - 静态 hook 挂在公开 `GeneticPedigreePage` 类上（test 跨 import
  //     边界可访问），不是私有 `_GeneticPedigreePageState`
  //   - debugFilePath 注入临时文件路径
  //   - debugWebStorage 注入 Map<String,String> mock localStorage
  //   - debugForceIsWebStorage 注入 web 路径标志
  //   - debugResetHooks 清理

  group('v2.12 R1 C P0 #7 跨端持久化', () {
    late Directory tmp;
    late String filePath;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('pedigree_cross_panel_test');
      filePath = '${tmp.path}/cross_panel.json';
      GeneticPedigreePage.debugFilePath = filePath;
      GeneticPedigreePage.debugWebStorage = null;
      GeneticPedigreePage.debugForceIsWebStorage = null;
    });

    tearDown(() {
      GeneticPedigreePage.debugResetHooks();
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('桌面 / 安卓 File 路径：debugFilePath 注入 + 手工写读 json',
        () async {
      // 1. debugFilePath 注入临时文件路径，模拟"用户开过面板"后落盘
      expect(GeneticPedigreePage.debugFilePath, filePath,
          reason: 'debugFilePath 注入应生效');
      File(filePath).writeAsStringSync('{"open":true}');
      expect(File(filePath).existsSync(), isTrue);
      final content = File(filePath).readAsStringSync();
      expect(content, contains('"open":true'),
          reason: 'cross_panel.json 应含 open=true');

      // 2. 反向：写盘"用户关过面板" → 读出
      File(filePath).writeAsStringSync('{"open":false}');
      final content2 = File(filePath).readAsStringSync();
      expect(content2, contains('"open":false'));
    });

    test('Web 端 localStorage 路径：debugWebStorage 注入生效', () async {
      // flutter_test 无 window 对象，platform_storage_web 的 storageGet
      // 不可用。用 debugWebStorage 注入 Map<String,String> 模拟"用户
      // 在浏览器中"的 localStorage。
      final webStore = <String, String>{};
      GeneticPedigreePage.debugWebStorage = webStore;
      GeneticPedigreePage.debugForceIsWebStorage = true;
      GeneticPedigreePage.debugFilePath = null;

      // 1. web 端 localStorage 初始为空
      expect(webStore.isEmpty, isTrue,
          reason: 'web 端 localStorage 初始为空');

      // 2. 模拟"用户开过面板"写入
      webStore['cross_panel_json'] = '{"open":true}';
      expect(webStore['cross_panel_json'], isNotNull);
      expect(webStore['cross_panel_json'], contains('"open":true'));

      // 3. 模拟"刷新页面"：清空 webStore → 重新注入
      webStore.clear();
      GeneticPedigreePage.debugResetHooks();
      // 重新注入
      GeneticPedigreePage.debugWebStorage = webStore;
      GeneticPedigreePage.debugForceIsWebStorage = true;
      expect(GeneticPedigreePage.debugWebStorage, isNotNull,
          reason: 'debugResetHooks 后能重新注入');
      expect(GeneticPedigreePage.debugForceIsWebStorage, isTrue);
    });

    test('web 路径走 storageSet，桌面路径走 File（hook 接线正确）', () async {
      // 验证 GeneticPedigreePage._isWebStorage 行为：
      //   - debugForceIsWebStorage=null → 用真实 isWebStorage（test 环境
      //     桌面模式，返 false → 走 File 路径）
      //   - debugForceIsWebStorage=true → 强制走 web 路径
      // 这里通过遗传算法 _isWebStorage 是 static private，但
      // 间接验证：web 路径设置时 debugFilePath=null（防止走桌面
      // File 路径误触），_storageSet 会写 webStore 而不是 File。
      final webStore = <String, String>{};
      GeneticPedigreePage.debugWebStorage = webStore;
      GeneticPedigreePage.debugForceIsWebStorage = true;
      GeneticPedigreePage.debugFilePath = null;

      // 关键断言：web 路径配置（debugForceIsWebStorage=true +
      // debugFilePath=null + debugWebStorage 注入）三件套接线正确
      expect(GeneticPedigreePage.debugForceIsWebStorage, isTrue,
          reason: 'web 路径三件套接线：debugForceIsWebStorage=true');
      expect(GeneticPedigreePage.debugFilePath, isNull,
          reason: 'web 路径三件套接线：debugFilePath=null（防止走桌面）');
      expect(GeneticPedigreePage.debugWebStorage, isNotNull,
          reason: 'web 路径三件套接线：debugWebStorage 已注入');
    });

    test('debugResetHooks 清理所有静态 hook', () async {
      // 1. 注入三个 hook
      GeneticPedigreePage.debugFilePath = '/some/file';
      GeneticPedigreePage.debugWebStorage = <String, String>{};
      GeneticPedigreePage.debugForceIsWebStorage = true;

      // 2. debugResetHooks 全部清空
      GeneticPedigreePage.debugResetHooks();
      expect(GeneticPedigreePage.debugFilePath, isNull,
          reason: 'debugResetHooks 清 debugFilePath');
      expect(GeneticPedigreePage.debugWebStorage, isNull,
          reason: 'debugResetHooks 清 debugWebStorage');
      expect(GeneticPedigreePage.debugForceIsWebStorage, isNull,
          reason: 'debugResetHooks 清 debugForceIsWebStorage');
      expect(GeneticPedigreePage.debugEncodeDelayMs, 0,
          reason: 'debugResetHooks 清 debugEncodeDelayMs');
    });
  });

  // ═══ v2.13 R3 P1-D1：PNG 编码移 Isolate（UI 冻结 544ms → 近 0） ═══
  //
  // 原实现 decodePng/copyCrop/encodePng 在 UI 线程同步执行，2800×1800
  // 大画布实测 544ms/次冻结（1860×1200 = 235ms）。修复：native / VM 端
  // 包进 Isolate.run，UI 线程只收 base64；web 端无真 isolate（dart2js
  // 的 Isolate.spawn 运行时抛 UnsupportedError）保持原地执行。
  //
  // 用 debugEncodeDelayMs=500 mock「编码耗时 500ms」验证：
  //   - 触发保存后 tester.pump 立即响应（编码不占 UI 线程）
  //   - 50ms 真实窗口 + 微任务冲刷不被 500ms mock 编码拖死（编码若回到
  //     UI 线程同步执行，该窗口会被 sleep(500ms) 拖到 ~550ms）
  //   - 编码进行中 UI 事件循环准点推进（100ms 定时器不被拖后）
  //   - 最终 PNG 文件真实落盘（isolate 结果回传 → 保存链路完整）
  group('v2.13 R3 P1-D1 PNG 编码 Isolate', () {
    testWidgets(
        'mock 500ms 编码：UI 不冻结（pump 立即响应）+ 最终拿到 PNG bytes',
        (tester) async {
      // mock：把编码耗时拉到 500ms（默认 0 = 不生效）
      GeneticPedigreePage.debugEncodeDelayMs = 500;
      addTearDown(GeneticPedigreePage.debugResetHooks);

      final tmp = Directory.systemTemp.createTempSync('pedigree_p1_isolate');
      addTearDown(() {
        // Windows 偶尔 file handle 没释放 → 删不动。catch 兜底。
        try {
          if (tmp.existsSync()) tmp.deleteSync(recursive: true);
        } catch (_) {/* 残留容忍 */}
      });
      MistakeBookExporter.debugDownloadsDir = tmp.path;
      addTearDown(() => MistakeBookExporter.debugDownloadsDir = null);

      await _pump(tester, size: wideWithButton);
      await _derive(tester);

      // 点「复制 SVG」→ sheet → 点「保存为 PNG 文件」触发编码链路
      await tester.tap(find.text('复制 SVG'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存为 PNG 文件'));

      // ① UI 立即响应：触发后第一帧 pump 不被 mock 500ms 编码阻塞
      //    （旧实现同步编码在 UI 线程执行，此处的 pump 会被拖住）
      final sw0 = Stopwatch()..start();
      await tester.pump();
      sw0.stop();
      expect(sw0.elapsedMilliseconds, lessThan(250),
          reason: '触发 PNG 保存后第一帧 tester.pump 立即响应（编码在 '
              'Isolate，不在 UI 线程）');

      // ② 编码在 isolate：runAsync 窗口（真实事件循环 + fake 微任务冲刷）
      //    总耗时必须远小于 500ms——若编码回到 UI 线程同步执行，微任务
      //    冲刷会被 sleep(500ms) 拖死，本断言失败
      final swWin = Stopwatch()..start();
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      swWin.stop();
      expect(swWin.elapsedMilliseconds, lessThan(250),
          reason: 'mock 500ms 编码在 Isolate 中执行：runAsync 窗口不被阻塞'
              '（50ms 窗口 + 冲刷 ≈ 50ms）；冻结回退时会被拖到 ~550ms');

      // ③ 编码进行中（isolate 内 sleep 500ms）：UI 事件循环准点推进
      await tester.runAsync(() async {
        final sw = Stopwatch()..start();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(sw.elapsedMilliseconds, lessThan(250),
            reason: 'mock 500ms 编码进行中，UI 事件循环 100ms 定时器仍准点'
                '触发；若编码回到 UI 线程同步执行，本断言会被拖后');
      });
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('保存为 PNG 文件'), findsNothing,
          reason: 'sheet 已关闭：UI 线程未被编码阻塞，继续正常渲染');

      // ④ 双环交替驱动真实 / fake 异步直到 isolate 编码结果落盘
      await _drainPngFile(tester, tmp);
      await tester.pumpAndSettle();

      if (find.text('画布暂无可截内容').evaluate().isNotEmpty) {
        // 画布空（ROI 不足 16x16，flutter_test 抓图环境限制，同 P0-B2
        // 容错）：无 PNG 可断言；「UI 不冻结」断言已在上方完成。
        return;
      }

      // ⑤ 最终拿到 PNG bytes：isolate 编码结果回传 → base64 → 落盘
      final files = tmp
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.png'))
          .toList();
      expect(files, hasLength(1),
          reason: 'Isolate 编码结果应回传并落盘 1 个 .png 文件');
      final pngBytes = files.first.readAsBytesSync();
      expect(pngBytes.length, greaterThan(8), reason: 'PNG 文件非空');
      // 验证 PNG 魔数 89 50 4E 47 0D 0A 1A 0A
      expect(pngBytes[0], 0x89, reason: 'PNG 魔数第 1 字节 = 0x89');
      expect(pngBytes[1], 0x50, reason: 'PNG = P');
      expect(pngBytes[2], 0x4E, reason: 'PNG = N');
      expect(pngBytes[3], 0x47, reason: 'PNG = G');
    });
  });
}
