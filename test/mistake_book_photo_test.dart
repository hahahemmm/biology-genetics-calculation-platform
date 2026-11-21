// mistake_book_photo_test.dart —— 错题本「拍照上传」识别回填测试
//
// 覆盖：
//   1. 新增模式：对话框含「拍照上传」按钮 +「识别结果请核对后再保存」提示
//   2. 识别成功：四字段回填表单，**不自动提交**（走用户点保存的原有路径）
//   3. 识别不出的字段（空字符串）保留用户已有输入，不覆盖
//   4. 取消选图：静默返回，不报错、不改字段
//   5. AI 未配置 / 请求失败：可读中文提示，不清空已填内容
//   6. AI 返回非法 JSON：可读中文提示，不清空已填内容
//   7. 识别期间按钮 loading 且禁用（防重复点击）
//   8. 编辑模式：拍照回填后点「保存」走原有更新路径（不被破坏）
//   9. 390 窄屏：按钮不溢出
//
// 全程不联网：选图走 MistakeBookPage.debugPicker 注入，AI 走
// MistakeBookAi.debugSender 注入；错题数据写 temp 目录（debugFilePath），
// 不碰真实用户目录 ~/.biology_app。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:biology/services/ai_client.dart';
import 'package:biology/pages/mistake_book_page.dart';
import 'package:biology/state/mistake_book.dart';
import 'package:biology/ui/image_pick.dart';
import 'package:biology/ui/mistake_book_ai.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap() => const MaterialApp(home: MistakeBookPage());

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(800, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_wrap());
  await tester.pumpAndSettle(const Duration(milliseconds: 50));
}

/// 读对话框里某 label 的 TextField 当前文本。
String _fieldText(WidgetTester tester, String label) => tester
    .widget<TextField>(find.widgetWithText(TextField, label))
    .controller!
    .text;

/// 一张假题目图（3 字节，内容无关——debugSender 不看图）。
PickedImage _fakeImage({String ext = 'png'}) =>
    PickedImage(Uint8List.fromList([1, 2, 3]), 'q.$ext', ext);

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mistake_book_photo_test');
    MistakeBook.debugFilePath = '${tmp.path}/mistake_book.json';
    MistakeBook.instance.debugReset();
  });

  tearDown(() {
    MistakeBookPage.debugPicker = null;
    MistakeBookAi.debugSender = null;
    MistakeBook.instance.debugResetAiOrganize();
    MistakeBook.debugFilePath = null;
    MistakeBook.instance.debugReset();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  testWidgets('新增模式：表单含「拍照上传」按钮 + 核对提示', (tester) async {
    await _pump(tester);
    await tester.tap(find.byTooltip('添加错题'));
    await tester.pumpAndSettle();
    expect(find.text('拍照上传'), findsOneWidget,
        reason: '新增/编辑共用表单的拍照入口');
    expect(find.text('识别结果请核对后再保存'), findsOneWidget,
        reason: '不承诺识别一定准确，提示用户核对');
  });

  testWidgets('拍照识别成功：四字段回填表单，不自动提交', (tester) async {
    List<AiMessage>? sent;
    MistakeBookPage.debugPicker = () async => _fakeImage();
    MistakeBookAi.debugSender = (msgs) async {
      sent = msgs;
      return AiResult.ok('{"stem":"AaBb 自交 F2 比例题","userAnswer":"9:3:4",'
          '"correctAnswer":"9:3:3:1","subjectArea":"自由组合定律"}');
    };
    await _pump(tester);
    await tester.tap(find.byTooltip('添加错题'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('拍照上传'));
    await tester.pumpAndSettle();

    // 请求侧：图片转 base64 随 prompt 发出，prompt 要求只输出 JSON
    final userMsg = sent!.last;
    expect(userMsg.imagePngBase64, base64Encode([1, 2, 3]),
        reason: '图片字节转 base64 挂在 user 消息上');
    expect(userMsg.imageMimeType, 'image/png');
    expect(userMsg.content, contains('"stem"'));
    expect(userMsg.content, contains('绝对不要编造'),
        reason: '识别不出留空、不编造');

    // 回填侧：四个控制器
    expect(_fieldText(tester, '题目摘要 *'), 'AaBb 自交 F2 比例题');
    expect(_fieldText(tester, '错误答案'), '9:3:4');
    expect(_fieldText(tester, '正确答案'), '9:3:3:1');
    expect(_fieldText(tester, '关联考点'), '自由组合定律');

    // 不自动提交：对话框未关、错题本没有新条目
    expect(find.text('添加错题'), findsWidgets, reason: '对话框还开着');
    expect(MistakeBook.instance.entries, isEmpty,
        reason: '必须用户点「添加」才落库');
    // 清 SnackBar（5s）避免 pending timer
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });

  testWidgets('识别不出的字段留空 ⇒ 保留用户已有输入', (tester) async {
    MistakeBookPage.debugPicker = () async => _fakeImage(ext: 'jpg');
    MistakeBookAi.debugSender = (msgs) async => AiResult.ok(
        '{"stem":"新的题目摘要","userAnswer":"","correctAnswer":"","subjectArea":""}');
    await _pump(tester);
    await tester.tap(find.byTooltip('添加错题'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '错误答案'), '手填错答');
    await tester.enterText(find.widgetWithText(TextField, '正确答案'), '手填正答');
    await tester.tap(find.text('拍照上传'));
    await tester.pumpAndSettle();

    expect(_fieldText(tester, '题目摘要 *'), '新的题目摘要',
        reason: '识别出的字段正常回填');
    expect(_fieldText(tester, '错误答案'), '手填错答',
        reason: 'AI 留空 ⇒ 不覆盖用户已填');
    expect(_fieldText(tester, '正确答案'), '手填正答');
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });

  testWidgets('取消选图：静默返回，不报错、不改字段', (tester) async {
    MistakeBookPage.debugPicker = () async => null;
    await _pump(tester);
    await tester.tap(find.byTooltip('添加错题'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '题目摘要 *'), '手打的题');
    await tester.tap(find.text('拍照上传'));
    await tester.pumpAndSettle();

    expect(_fieldText(tester, '题目摘要 *'), '手打的题');
    expect(find.byType(SnackBar), findsNothing, reason: '取消是正常操作，静默');
    expect(find.text('拍照上传'), findsOneWidget, reason: '按钮恢复可用');
  });

  testWidgets('AI 未配置 / 请求失败：中文提示 + 保留已填内容', (tester) async {
    MistakeBookPage.debugPicker = () async => _fakeImage();
    MistakeBookAi.debugSender = (msgs) async =>
        const AiResult.fail('未配置 AI：请先在「设置」页填入 BaseURL 和 API Key。');
    await _pump(tester);
    await tester.tap(find.byTooltip('添加错题'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '题目摘要 *'), '保留我');
    await tester.tap(find.text('拍照上传'));
    await tester.pumpAndSettle();

    expect(find.textContaining('未配置 AI'), findsOneWidget,
        reason: '失败原因直接可读，不是英文技术报错');
    expect(_fieldText(tester, '题目摘要 *'), '保留我',
        reason: '失败不得清空用户已填内容');
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });

  testWidgets('AI 返回非法 JSON：中文提示 + 保留已填内容', (tester) async {
    MistakeBookPage.debugPicker = () async => _fakeImage();
    MistakeBookAi.debugSender =
        (msgs) async => AiResult.ok('这是一段自然语言，不是 JSON');
    await _pump(tester);
    await tester.tap(find.byTooltip('添加错题'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '题目摘要 *'), '保留我');
    await tester.tap(find.text('拍照上传'));
    await tester.pumpAndSettle();

    expect(find.textContaining('不是有效 JSON'), findsOneWidget,
        reason: '解析失败给可读中文提示');
    expect(_fieldText(tester, '题目摘要 *'), '保留我');
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });

  testWidgets('识别期间按钮 loading 且禁用（防重复点击）', (tester) async {
    final gate = Completer<PickedImage?>();
    MistakeBookPage.debugPicker = () => gate.future;
    await _pump(tester);
    await tester.tap(find.byTooltip('添加错题'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('拍照上传'));
    await tester.pump();

    expect(find.text('识别中…'), findsOneWidget, reason: '按钮进入 loading 文案');
    final btn = tester
        .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '识别中…'));
    expect(btn.onPressed, isNull, reason: '识别中禁用，防重复点击');

    gate.complete(null); // 取消路径收尾（静默）
    await tester.pumpAndSettle();
    expect(find.text('拍照上传'), findsOneWidget, reason: '结束后按钮恢复可用');
  });

  testWidgets('编辑模式：拍照回填后点「保存」走原有更新路径', (tester) async {
    MistakeBookPage.debugPicker = () async => _fakeImage();
    MistakeBookAi.debugSender = (msgs) async => AiResult.ok(
        '{"stem":"识别的新摘要","userAnswer":"","correctAnswer":"新正答","subjectArea":"伴性遗传"}');
    await _pump(tester);
    final entry = MistakeBook.instance.add(
      stem: '原摘要',
      userAnswer: '原错答',
      correctAnswer: '原正答',
      errorType: MistakeErrorType.concept,
      subjectArea: '分离定律',
    );
    await tester.pumpAndSettle();
    // 更多 → 编辑（与既有表单入口一致）
    await tester.tap(find.widgetWithText(TextButton, '更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    expect(find.text('编辑错题'), findsOneWidget);
    expect(_fieldText(tester, '题目摘要 *'), '原摘要', reason: '编辑模式初始值正常');

    await tester.tap(find.text('拍照上传'));
    await tester.pumpAndSettle();
    expect(_fieldText(tester, '题目摘要 *'), '识别的新摘要');
    expect(_fieldText(tester, '错误答案'), '原错答',
        reason: 'userAnswer 识别为空 ⇒ 保留原值');
    expect(_fieldText(tester, '正确答案'), '新正答');
    expect(_fieldText(tester, '关联考点'), '伴性遗传');

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    final cur = MistakeBook.instance.findById(entry.id)!;
    expect(cur.stem, '识别的新摘要', reason: '保存走原有 update 路径');
    expect(cur.userAnswer, '原错答');
    expect(cur.correctAnswer, '新正答');
    expect(cur.subjectArea, '伴性遗传');
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('390 窄屏：「拍照上传」按钮不溢出', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_wrap());
    await tester.pumpAndSettle(const Duration(milliseconds: 50));
    await tester.tap(find.byTooltip('添加错题'));
    await tester.pumpAndSettle();

    expect(find.text('拍照上传'), findsOneWidget);
    expect(find.text('识别结果请核对后再保存'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '窄屏无 RenderFlex 溢出');
  });
}
