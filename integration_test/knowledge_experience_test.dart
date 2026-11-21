// 知识库实时检索的 Windows 实窗口体验夹具。
// 全程使用内存假数据，不访问网络、AI 配置或用户持久化文件。

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:biology/data/bio_knowledge_data.dart';
import 'package:biology/models/bio_knowledge.dart';
import 'package:biology/pages/widgets/knowledge_lab.dart';
import 'package:biology/services/bio_database_service.dart';
import 'package:biology/state/theme_controller.dart';
import 'package:biology/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

final _captureKey = GlobalKey();

class _FakeKnowledgeService implements BioDatabaseClient {
  _FakeKnowledgeService(this.onSearch);

  final Future<BioSearchResponse> Function(String query, BioSource? source)
  onSearch;

  @override
  Future<BioSearchResponse> search(String query, {BioSource? source}) =>
      onSearch(query, source);

  @override
  void dispose() {}
}

Future<void> _capture(WidgetTester tester, String name) async {
  await tester.pump();
  await tester.pumpAndSettle(const Duration(milliseconds: 100));
  final boundary =
      _captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final dir = Directory('.experience')..createSync(recursive: true);
  final file = File('${dir.path}${Platform.pathSeparator}$name.png');
  await file.writeAsBytes(bytes!.buffer.asUint8List(), flush: true);
  debugPrint('EXPERIENCE_CAPTURE=${file.absolute.path}');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('知识库加载骨架与上次结果归属', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ThemeController.instance.debugSetMode(ThemeMode.light);
    addTearDown(() => ThemeController.instance.debugSetMode(ThemeMode.system));

    final pending = Completer<BioSearchResponse>();
    var calls = 0;
    final service = _FakeKnowledgeService((query, source) {
      if (calls++ == 0) {
        expect(query, 'Taq');
        return Future.value(
          BioSearchResponse(
            records: <BioKnowledgeRecord>[
              kBioKnowledgeRecords.singleWhere(
                (record) => record.id == 'P19821',
              ),
            ],
            failures: const <String>[],
            queriedAt: DateTime(2026, 10, 30, 8, 30),
          ),
        );
      }
      expect(query, 'GFP');
      return pending.future;
    });

    await tester.pumpWidget(
      RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(child: KnowledgeLab(service: service)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('knowledge-search-input')),
      'Taq',
    );
    await tester.tap(find.widgetWithText(FilledButton, '实时查询'));
    await tester.pumpAndSettle();
    expect(find.text('实时结果'), findsOneWidget);

    final queryField = find.byKey(const Key('knowledge-search-input'));
    await tester.ensureVisible(queryField);
    await tester.tap(queryField);
    await tester.enterText(queryField, 'GFP');
    expect(tester.widget<TextField>(queryField).controller!.text, 'GFP');
    final searchButton = find.widgetWithText(FilledButton, '实时查询');
    await tester.ensureVisible(searchButton);
    await tester.tap(searchButton);
    await tester.pump();
    expect(calls, 2);
    expect(find.text('正在查询“GFP” · 来源：全部来源'), findsOneWidget);
    expect(find.text('P19821'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.ensureVisible(
      find.byKey(const ValueKey('knowledge-search-skeleton')),
    );
    await _capture(tester, 'knowledge_01_loading_desktop');

    pending.completeError(const BioDatabaseException('模拟数据库暂不可用：保留上次结果。'));
    await tester.pumpAndSettle();
    expect(find.text('上次实时结果'), findsOneWidget);
    expect(find.text('P19821'), findsOneWidget);
    expect(find.textContaining('关键词“Taq” · 来源：全部来源'), findsOneWidget);
    final errorText = find.textContaining('模拟数据库暂不可用');
    expect(errorText, findsOneWidget);

    await Scrollable.ensureVisible(tester.element(errorText), alignment: 0.1);
    final desktopError = tester.getRect(errorText);
    expect(
      desktopError.top >= 0 && desktopError.bottom <= 1000,
      isTrue,
      reason: '桌面错误横幅必须完整进入实窗口截图：$desktopError',
    );
    await _capture(tester, 'knowledge_02_error_desktop');

    await tester.ensureVisible(find.text('上次实时结果'));
    await _capture(tester, 'knowledge_03_previous_desktop');

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(errorText), alignment: 0.1);
    final mobileError = tester.getRect(errorText);
    expect(
      mobileError.left >= 0 && mobileError.right <= 390,
      isTrue,
      reason: '窄屏错误横幅不得横向溢出：$mobileError',
    );
    expect(
      mobileError.top >= 0 && mobileError.bottom <= 844,
      isTrue,
      reason: '窄屏错误横幅必须完整进入实窗口截图：$mobileError',
    );
    await _capture(tester, 'knowledge_04_error_mobile');

    await tester.ensureVisible(find.text('上次实时结果'));
    await _capture(tester, 'knowledge_05_previous_mobile');
    expect(tester.takeException(), isNull);
  });

  testWidgets('知识库部分来源失败仍展示可用结果', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ThemeController.instance.debugSetMode(ThemeMode.light);
    addTearDown(() => ThemeController.instance.debugSetMode(ThemeMode.system));

    final service = _FakeKnowledgeService((query, source) async {
      expect(query, 'Taq');
      return BioSearchResponse(
        records: <BioKnowledgeRecord>[
          kBioKnowledgeRecords.singleWhere((record) => record.id == 'P19821'),
        ],
        failures: const <String>['RCSB PDB：请求超时，请稍后重试。'],
        queriedAt: DateTime(2026, 10, 30, 8, 30),
      );
    });

    await tester.pumpWidget(
      RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(child: KnowledgeLab(service: service)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('knowledge-search-input')),
      'Taq',
    );
    await tester.tap(find.widgetWithText(FilledButton, '实时查询'));
    await tester.pumpAndSettle();

    final warning = find.textContaining('部分来源未返回（1 个）；已保留 1 条可用结果。');
    expect(warning, findsOneWidget);
    expect(find.byIcon(Icons.info_outline), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsNothing);
    expect(find.text('P19821'), findsNWidgets(2));
    await Scrollable.ensureVisible(tester.element(warning), alignment: 0.15);
    await _capture(tester, 'knowledge_06_partial_desktop');

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(warning), alignment: 0.15);
    final mobileWarning = tester.getRect(warning);
    expect(
      mobileWarning.left >= 0 && mobileWarning.right <= 390,
      isTrue,
      reason: '部分失败警示在窄屏不得横向溢出：$mobileWarning',
    );
    await _capture(tester, 'knowledge_07_partial_mobile');
    expect(tester.takeException(), isNull);
  });

  testWidgets('深色模式区分部分失败与全部失败', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ThemeController.instance.debugSetMode(ThemeMode.dark);
    addTearDown(() => ThemeController.instance.debugSetMode(ThemeMode.system));

    Future<void> revealAndCheck(Finder target, String label) async {
      await Scrollable.ensureVisible(tester.element(target), alignment: 0.15);
      await tester.pumpAndSettle();
      final rect = tester.getRect(target);
      final size = tester.view.physicalSize;
      expect(
        rect.left >= 0 && rect.right <= size.width,
        isTrue,
        reason: '$label 不得横向溢出：$rect',
      );
      expect(
        rect.top >= 0 && rect.bottom <= size.height,
        isTrue,
        reason: '$label 必须完整进入截图：$rect',
      );
    }

    var calls = 0;
    final service = _FakeKnowledgeService((query, source) async {
      calls++;
      if (query == 'Taq') {
        return BioSearchResponse(
          records: <BioKnowledgeRecord>[
            kBioKnowledgeRecords.singleWhere((record) => record.id == 'P19821'),
          ],
          failures: const <String>['RCSB PDB：请求超时，请稍后重试。'],
          queriedAt: DateTime(2026, 10, 30, 8, 30),
        );
      }
      expect(query, '全部失败');
      return BioSearchResponse(
        records: const <BioKnowledgeRecord>[],
        failures: const <String>[
          'UniProt：请求超时，请稍后重试。',
          'RCSB PDB：请求超时，请稍后重试。',
          'PubMed：请求超时，请稍后重试。',
        ],
        queriedAt: DateTime(2026, 10, 30, 8, 31),
      );
    });

    await tester.pumpWidget(
      RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SingleChildScrollView(child: KnowledgeLab(service: service)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(AppColors.isDark, isTrue);

    await tester.enterText(
      find.byKey(const Key('knowledge-search-input')),
      'Taq',
    );
    await tester.tap(find.widgetWithText(FilledButton, '实时查询'));
    await tester.pumpAndSettle();

    final partialWarning = find.textContaining('部分来源未返回（1 个）');
    expect(partialWarning, findsOneWidget);
    expect(find.text('P19821'), findsNWidgets(2));
    final infoIcon = tester.widget<Icon>(find.byIcon(Icons.info_outline));
    expect(infoIcon.color, AppColors.sand);
    expect(find.byIcon(Icons.error_outline), findsNothing);

    await revealAndCheck(partialWarning, '深色桌面部分失败提示');
    await _capture(tester, 'knowledge_08_partial_dark_desktop');
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    await revealAndCheck(partialWarning, '深色窄屏部分失败提示');
    await _capture(tester, 'knowledge_09_partial_dark_mobile');

    tester.view.physicalSize = const Size(1440, 1000);
    await tester.pumpAndSettle();
    final queryField = find.byKey(const Key('knowledge-search-input'));
    await tester.ensureVisible(queryField);
    await tester.tap(queryField);
    await tester.enterText(queryField, '全部失败');
    expect(tester.widget<TextField>(queryField).controller!.text, '全部失败');
    final searchButton = find.widgetWithText(FilledButton, '实时查询');
    await tester.ensureVisible(searchButton);
    await tester.tap(searchButton);
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.textContaining('关键词“全部失败” · 来源：全部来源'), findsOneWidget);

    final allFailedWarning = find.textContaining('UniProt：请求超时');
    expect(allFailedWarning, findsOneWidget);
    expect(find.textContaining('部分来源未返回'), findsNothing);
    expect(find.text('P19821'), findsNothing);
    expect(find.text('本次未取回可用记录，请根据上方错误提示重试。'), findsOneWidget);
    final errorIcon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
    expect(errorIcon.color, AppColors.lethal);
    expect(find.byIcon(Icons.info_outline), findsNothing);

    await revealAndCheck(allFailedWarning, '深色桌面全部失败提示');
    await _capture(tester, 'knowledge_10_all_failed_dark_desktop');
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    await revealAndCheck(allFailedWarning, '深色窄屏全部失败提示');
    await _capture(tester, 'knowledge_11_all_failed_dark_mobile');
    expect(tester.takeException(), isNull);
  });

  testWidgets('正常无匹配与全部失败使用不同空态', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ThemeController.instance.debugSetMode(ThemeMode.light);
    addTearDown(() => ThemeController.instance.debugSetMode(ThemeMode.system));

    Future<void> revealAndCheck(Finder target, String label) async {
      await Scrollable.ensureVisible(tester.element(target), alignment: 0.15);
      await tester.pumpAndSettle();
      final rect = tester.getRect(target);
      final size = tester.view.physicalSize;
      expect(
        rect.left >= 0 && rect.right <= size.width,
        isTrue,
        reason: '$label 不得横向溢出：$rect',
      );
      expect(
        rect.top >= 0 && rect.bottom <= size.height,
        isTrue,
        reason: '$label 必须完整进入截图：$rect',
      );
    }

    var calls = 0;
    final service = _FakeKnowledgeService((query, source) async {
      calls++;
      if (query == '无匹配') {
        return BioSearchResponse(
          records: const <BioKnowledgeRecord>[],
          failures: const <String>[],
          queriedAt: DateTime(2026, 10, 30, 8, 32),
        );
      }
      expect(query, '全部失败');
      return BioSearchResponse(
        records: const <BioKnowledgeRecord>[],
        failures: const <String>[
          'UniProt：请求超时，请稍后重试。',
          'RCSB PDB：请求超时，请稍后重试。',
          'PubMed：请求超时，请稍后重试。',
        ],
        queriedAt: DateTime(2026, 10, 30, 8, 33),
      );
    });

    await tester.pumpWidget(
      RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(child: KnowledgeLab(service: service)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('knowledge-search-input')),
      '无匹配',
    );
    await tester.tap(find.widgetWithText(FilledButton, '实时查询'));
    await tester.pumpAndSettle();
    expect(calls, 1);

    final noMatch = find.byKey(const ValueKey('knowledge-live-no-match'));
    expect(noMatch, findsOneWidget);
    expect(find.text('本次查询没有匹配记录。'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '填入 GFP 示例'), findsOneWidget);
    expect(find.byIcon(Icons.search_off), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsNothing);
    expect(find.textContaining('未取回可用记录'), findsNothing);

    final builtInEmpty = find.byKey(const ValueKey('knowledge-built-in-empty'));
    expect(builtInEmpty, findsOneWidget);
    expect(find.text('内置精选中没有匹配项。'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '清空筛选'), findsOneWidget);

    await revealAndCheck(builtInEmpty, '浅色桌面内置精选空态');
    await revealAndCheck(noMatch, '浅色桌面无匹配空态');
    await _capture(tester, 'knowledge_12_no_match_desktop');
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    await revealAndCheck(builtInEmpty, '浅色窄屏内置精选空态');
    await revealAndCheck(noMatch, '浅色窄屏无匹配空态');
    await _capture(tester, 'knowledge_13_no_match_mobile');

    tester.view.physicalSize = const Size(1440, 1000);
    await tester.pumpAndSettle();
    final queryField = find.byKey(const Key('knowledge-search-input'));
    await tester.ensureVisible(queryField);
    await tester.tap(queryField);
    await tester.enterText(queryField, '全部失败');
    expect(tester.widget<TextField>(queryField).controller!.text, '全部失败');
    final searchButton = find.widgetWithText(FilledButton, '实时查询');
    await tester.ensureVisible(searchButton);
    await tester.tap(searchButton);
    await tester.pumpAndSettle();
    expect(calls, 2);

    final allFailedWarning = find.textContaining('UniProt：请求超时');
    expect(allFailedWarning, findsOneWidget);
    expect(noMatch, findsNothing);
    expect(find.byIcon(Icons.search_off), findsNothing);
    expect(find.text('本次查询没有匹配记录。'), findsNothing);
    expect(find.text('本次未取回可用记录，请根据上方错误提示重试。'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);

    await revealAndCheck(allFailedWarning, '浅色桌面全部失败提示');
    await _capture(tester, 'knowledge_14_all_failed_light_desktop');
    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    await revealAndCheck(allFailedWarning, '浅色窄屏全部失败提示');
    await _capture(tester, 'knowledge_15_all_failed_light_mobile');
    expect(tester.takeException(), isNull);
  });

  testWidgets('CRISPR 与 PAM 精选卡在桌面和窄屏完整展示', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ThemeController.instance.debugSetMode(ThemeMode.light);
    addTearDown(() => ThemeController.instance.debugSetMode(ThemeMode.system));

    Future<void> revealAndCheck(Finder target, String label) async {
      await Scrollable.ensureVisible(tester.element(target), alignment: 0.1);
      await tester.pumpAndSettle();
      final rect = tester.getRect(target);
      final size = tester.view.physicalSize;
      expect(
        rect.left >= 0 && rect.right <= size.width,
        isTrue,
        reason: '$label 不得横向溢出：$rect',
      );
      expect(
        rect.top >= 0 && rect.bottom <= size.height,
        isTrue,
        reason: '$label 必须完整进入截图：$rect',
      );
    }

    var calls = 0;
    final service = _FakeKnowledgeService((query, source) async {
      calls++;
      throw StateError('内置 CRISPR 与 PAM 示例不应发起实时查询：$query');
    });
    final cas9 = kBioKnowledgeRecords.singleWhere((r) => r.id == '4OO8');
    final pam = kBioKnowledgeRecords.singleWhere((r) => r.id == '4UN3');

    await tester.pumpWidget(
      RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(child: KnowledgeLab(service: service)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ActionChip, 'CRISPR'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.byType(Card), findsNWidgets(4));
    expect(find.text('4OO8'), findsOneWidget);
    expect(find.text('4UN3'), findsOneWidget);
    expect(find.text('23287722'), findsOneWidget);
    expect(find.text('25079318'), findsOneWidget);
    expect(find.text(cas9.title), findsOneWidget);
    expect(find.text(cas9.subtitle), findsOneWidget);
    expect(find.text(cas9.url), findsOneWidget);
    expect(find.text(cas9.caution!), findsOneWidget);

    final cas9Card = find.ancestor(
      of: find.text('4OO8'),
      matching: find.byType(Card),
    );
    expect(cas9Card, findsOneWidget);
    await revealAndCheck(cas9Card, 'Cas9 桌面结构卡');
    await _capture(tester, 'knowledge_16_cas9_desktop');

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    await revealAndCheck(cas9Card, 'Cas9 窄屏结构卡');
    await _capture(tester, 'knowledge_17_cas9_mobile');

    tester.view.physicalSize = const Size(1440, 1000);
    await tester.pumpAndSettle();
    await revealAndCheck(find.widgetWithText(ActionChip, 'PAM'), 'PAM 示例按钮');
    await tester.tap(find.widgetWithText(ActionChip, 'PAM'));
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsNWidgets(2));
    expect(find.text('4OO8'), findsNothing);
    expect(find.text('4UN3'), findsOneWidget);
    expect(find.text('25079318'), findsOneWidget);
    expect(find.text(pam.title), findsOneWidget);
    expect(find.text(pam.url), findsOneWidget);
    expect(find.text(pam.caution!), findsOneWidget);

    final pamCard = find.ancestor(
      of: find.text('4UN3'),
      matching: find.byType(Card),
    );
    expect(pamCard, findsOneWidget);
    await revealAndCheck(pamCard, 'PAM 桌面结构卡');
    await _capture(tester, 'knowledge_18_pam_desktop');

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    await revealAndCheck(pamCard, 'PAM 窄屏结构卡');
    await _capture(tester, 'knowledge_19_pam_mobile');
    expect(calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('SpCas9 正反向切割练习在桌面和窄屏完整展示', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ThemeController.instance.debugSetMode(ThemeMode.light);
    addTearDown(() => ThemeController.instance.debugSetMode(ThemeMode.system));

    Future<void> revealAndCheck(Finder target, String label) async {
      await Scrollable.ensureVisible(tester.element(target), alignment: 0.08);
      await tester.pumpAndSettle();
      final rect = tester.getRect(target);
      final size = tester.view.physicalSize;
      expect(
        rect.left >= 0 && rect.right <= size.width,
        isTrue,
        reason: '$label 不得横向溢出：$rect',
      );
      expect(
        rect.top >= 0 && rect.bottom <= size.height,
        isTrue,
        reason: '$label 必须完整进入截图：$rect',
      );
    }

    var calls = 0;
    final service = _FakeKnowledgeService((query, source) async {
      calls++;
      throw StateError('离线切割练习不应发起实时查询：$query');
    });
    await tester.pumpWidget(
      RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(child: KnowledgeLab(service: service)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(2));

    final topExample = find.widgetWithText(ActionChip, '上链 NGG 示例');
    await tester.ensureVisible(topExample);
    await tester.tap(topExample);
    await tester.pumpAndSettle();
    final topCut = find.text('顶链第 22 位与第 23 位之间（两条链同一边界）');
    expect(find.text('位点 1 · 上链 NGG'), findsOneWidget);
    expect(find.text('TGG'), findsOneWidget);
    expect(topCut, findsOneWidget);
    expect(find.byKey(const Key('cas9-strand-scroll-0')), findsOneWidget);
    final sitePanel = find.byKey(const Key('cas9-site-panel-0'));
    await revealAndCheck(sitePanel, '上链切割桌面完整位点面板');
    await _capture(tester, 'knowledge_20_cas9_top_desktop');

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    await revealAndCheck(sitePanel, '上链切割窄屏完整位点面板');
    await _capture(tester, 'knowledge_21_cas9_top_mobile');

    final bottomExample = find.widgetWithText(ActionChip, '互补链 NGG 示例');
    await tester.ensureVisible(bottomExample);
    await tester.tap(bottomExample);
    await tester.pumpAndSettle();
    final bottomCut = find.text('顶链第 10 位与第 11 位之间（两条链同一边界）');
    expect(find.text('位点 1 · 互补链 NGG（顶链 CCN）'), findsOneWidget);
    expect(find.text('CGG'), findsOneWidget);
    expect(find.text('TGG'), findsNothing);
    expect(bottomCut, findsOneWidget);
    await revealAndCheck(sitePanel, '互补链切割窄屏完整位点面板');
    await _capture(tester, 'knowledge_22_cas9_bottom_mobile');

    tester.view.physicalSize = const Size(1440, 1000);
    await tester.pumpAndSettle();
    await revealAndCheck(sitePanel, '互补链切割桌面完整位点面板');
    await _capture(tester, 'knowledge_23_cas9_bottom_desktop');
    expect(calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('同一 DNA 的正反向双位点在桌面和窄屏完整展示', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ThemeController.instance.debugSetMode(ThemeMode.light);
    addTearDown(() => ThemeController.instance.debugSetMode(ThemeMode.system));

    Future<void> revealAndCheck(Finder target, String label) async {
      await Scrollable.ensureVisible(tester.element(target), alignment: 0.08);
      await tester.pumpAndSettle();
      final rect = tester.getRect(target);
      final size = tester.view.physicalSize;
      expect(
        rect.left >= 0 && rect.right <= size.width,
        isTrue,
        reason: '$label 不得横向溢出：$rect',
      );
      expect(
        rect.top >= 0 && rect.bottom <= size.height,
        isTrue,
        reason: '$label 必须完整进入截图：$rect',
      );
    }

    var calls = 0;
    final service = _FakeKnowledgeService((query, source) async {
      calls++;
      throw StateError('双位点离线切割练习不应发起实时查询：$query');
    });
    await tester.pumpWidget(
      RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(child: KnowledgeLab(service: service)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const proto = 'ACGTACGTACGTACGTACGT';
    final sequence = '${'A' * 20}AGGCCT$proto';
    const bottom = 'TTTTTTTTTTTTTTTTTTTTTCCGGATGCATGCATGCATGCATGCA';
    final input = find.byKey(const Key('cas9-sequence-input'));
    await tester.ensureVisible(input);
    await tester.tap(input);
    await tester.enterText(input, sequence);
    final compute = find.widgetWithText(FilledButton, '判断切割位置');
    await tester.ensureVisible(compute);
    await tester.tap(compute);
    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(find.text('找到 2 个可分析位点 · 双链共 2 个 NGG motif'), findsOneWidget);
    final first = find.byKey(const Key('cas9-site-panel-0'));
    final second = find.byKey(const Key('cas9-site-panel-1'));
    expect(first, findsOneWidget);
    expect(second, findsOneWidget);
    expect(find.byKey(const Key('cas9-strand-scroll-0')), findsOneWidget);
    expect(find.byKey(const Key('cas9-strand-scroll-1')), findsOneWidget);

    expect(
      find.descendant(of: first, matching: find.text('位点 1 · 上链 NGG')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: first, matching: find.text('AGG')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: first, matching: find.text('顶链 motif 位次：第 21–23 位')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: first, matching: find.text('A' * 20)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: first,
        matching: find.text('顶链第 17 位与第 18 位之间（两条链同一边界）'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: first, matching: find.text('5′-$sequence-3′')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: first, matching: find.text('3′-$bottom-5′')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: first, matching: find.text('${' ' * 20}↓')),
      findsOneWidget,
    );

    expect(
      find.descendant(
        of: second,
        matching: find.text('位点 2 · 互补链 NGG（顶链 CCN）'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: second, matching: find.text('AGG')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: second, matching: find.text('顶链 motif 位次：第 24–26 位')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: second, matching: find.text(proto)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: second,
        matching: find.text('顶链第 29 位与第 30 位之间（两条链同一边界）'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: second, matching: find.text('5′-$sequence-3′')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: second, matching: find.text('3′-$bottom-5′')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: second, matching: find.text('${' ' * 32}↓')),
      findsOneWidget,
    );

    await revealAndCheck(first, '双位点桌面上链面板');
    await revealAndCheck(second, '双位点桌面互补链面板');
    await revealAndCheck(first, '双位点桌面截图面板');
    await _capture(tester, 'knowledge_24_cas9_multi_desktop');

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    await revealAndCheck(first, '双位点窄屏上链面板');
    await revealAndCheck(second, '双位点窄屏互补链面板');
    await _capture(tester, 'knowledge_25_cas9_multi_mobile');
    expect(calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('双位点长序列在 390 窄屏分别局部横滚', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ThemeController.instance.debugSetMode(ThemeMode.light);
    addTearDown(() => ThemeController.instance.debugSetMode(ThemeMode.system));

    Future<void> revealAndCheck(Finder target, String label) async {
      await Scrollable.ensureVisible(tester.element(target), alignment: 0.08);
      await tester.pumpAndSettle();
      final rect = tester.getRect(target);
      expect(
        rect.left >= 0 && rect.right <= 390,
        isTrue,
        reason: '$label 不得横向溢出：$rect',
      );
      expect(
        rect.top >= 0 && rect.bottom <= 844,
        isTrue,
        reason: '$label 必须完整进入截图：$rect',
      );
    }

    ScrollPosition positionOf(Finder scrollView) {
      final scrollable = find.descendant(
        of: scrollView,
        matching: find.byType(Scrollable),
      );
      expect(scrollable, findsOneWidget);
      return tester.state<ScrollableState>(scrollable).position;
    }

    var calls = 0;
    final service = _FakeKnowledgeService((query, source) async {
      calls++;
      throw StateError('长序列双位点练习不应发起实时查询：$query');
    });
    await tester.pumpWidget(
      RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(child: KnowledgeLab(service: service)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const proto = 'ACGTACGTACGTACGTACGT';
    final sequence = '${'A' * 80}AGGCCT$proto';
    expect(sequence.length, 106);
    final input = find.byKey(const Key('cas9-sequence-input'));
    await tester.ensureVisible(input);
    await tester.tap(input);
    await tester.enterText(input, sequence);
    final compute = find.widgetWithText(FilledButton, '判断切割位置');
    await tester.ensureVisible(compute);
    await tester.tap(compute);
    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(find.text('找到 2 个可分析位点 · 双链共 2 个 NGG motif'), findsOneWidget);
    expect(find.text('顶链第 77 位与第 78 位之间（两条链同一边界）'), findsOneWidget);
    expect(find.text('顶链第 89 位与第 90 位之间（两条链同一边界）'), findsOneWidget);
    final firstPanel = find.byKey(const Key('cas9-site-panel-0'));
    final secondPanel = find.byKey(const Key('cas9-site-panel-1'));
    final firstScroll = find.byKey(const Key('cas9-strand-scroll-0'));
    final secondScroll = find.byKey(const Key('cas9-strand-scroll-1'));
    await revealAndCheck(firstPanel, '长序列双位点窄屏上链面板');
    await revealAndCheck(secondPanel, '长序列双位点窄屏互补链面板');

    final firstPosition = positionOf(firstScroll);
    final secondPosition = positionOf(secondScroll);
    expect(firstPosition.maxScrollExtent, greaterThan(0));
    expect(secondPosition.maxScrollExtent, greaterThan(0));
    expect(firstPosition.pixels, 0);
    expect(secondPosition.pixels, 0);

    await tester.ensureVisible(firstScroll);
    await tester.drag(firstScroll, const Offset(-240, 0));
    await tester.pumpAndSettle();
    expect(firstPosition.pixels, greaterThan(0));
    expect(secondPosition.pixels, 0, reason: '两个位点的横向滚动必须互不影响');
    await revealAndCheck(firstPanel, '长序列上链面板滚动后截图');
    expect(firstPosition.pixels, greaterThan(0), reason: '截图取景不应重置上链横滚');
    await _capture(tester, 'knowledge_26_cas9_multi_long_mobile');

    await tester.ensureVisible(secondScroll);
    await tester.drag(secondScroll, const Offset(-240, 0));
    await tester.pumpAndSettle();
    expect(secondPosition.pixels, greaterThan(0));
    expect(firstPosition.pixels, greaterThan(0), reason: '滚动第二个位点不应重置第一个位点');
    await revealAndCheck(secondPanel, '长序列互补链面板滚动后截图');
    expect(secondPosition.pixels, greaterThan(0), reason: '截图取景不应重置互补链横滚');
    await _capture(tester, 'knowledge_27_cas9_multi_long_scrolled_mobile');
    expect(calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('连接酶成键辨析支持重选并离线追溯证据', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ThemeController.instance.debugSetMode(ThemeMode.light);
    addTearDown(() => ThemeController.instance.debugSetMode(ThemeMode.system));

    Future<void> revealAndCheck(Finder target, String label) async {
      await Scrollable.ensureVisible(tester.element(target), alignment: 0.08);
      await tester.pumpAndSettle();
      final rect = tester.getRect(target);
      final size = tester.view.physicalSize;
      expect(
        rect.left >= 0 && rect.right <= size.width,
        isTrue,
        reason: '$label 不得横向溢出：$rect',
      );
      expect(
        rect.top >= 0 && rect.bottom <= size.height,
        isTrue,
        reason: '$label 必须完整进入截图：$rect',
      );
    }

    var calls = 0;
    final service = _FakeKnowledgeService((query, source) async {
      calls++;
      throw StateError('连接酶离线练习不应发起实时查询：$query');
    });
    Widget app(ThemeData theme) => RepaintBoundary(
      key: _captureKey,
      child: MaterialApp(
        theme: theme,
        home: Scaffold(
          body: SingleChildScrollView(child: KnowledgeLab(service: service)),
        ),
      ),
    );

    await tester.pumpWidget(app(AppTheme.light()));
    await tester.pumpAndSettle();

    final panel = find.byKey(const Key('dna-ligase-bond-exercise'));
    final hydrogen = find.byKey(const Key('dna-ligase-hydrogen-bond'));
    final phosphodiester = find.byKey(
      const Key('dna-ligase-phosphodiester-bond'),
    );
    expect(panel, findsOneWidget);
    expect(hydrogen, findsOneWidget);
    expect(phosphodiester, findsOneWidget);

    await tester.ensureVisible(hydrogen);
    await tester.tap(hydrogen);
    await tester.pumpAndSettle();
    expect(find.text('再想一想：氢键负责碱基互补配对，不是连接酶催化的骨架共价连接。请重新选择。'), findsOneWidget);
    expect(find.textContaining('正确。DNA 连接酶'), findsNothing);
    await revealAndCheck(panel, '连接酶桌面答错面板');
    await _capture(tester, 'knowledge_28_ligase_wrong_desktop');

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    await tester.ensureVisible(phosphodiester);
    await tester.tap(phosphodiester);
    await tester.pumpAndSettle();
    expect(
      find.text(
        '正确。DNA 连接酶催化 DNA 骨架缺口处的 3′-OH 与 5′-磷酸形成磷酸二酯键，封闭缺口；不是连接碱基对之间的氢键。',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('请重新选择'), findsNothing);
    expect(
      find.bySemanticsLabel('三撇羟基与五撇磷酸在 DNA 连接酶作用下形成磷酸二酯键'),
      findsOneWidget,
    );
    await revealAndCheck(panel, '连接酶窄屏答对面板');
    await _capture(tester, 'knowledge_29_ligase_correct_mobile');

    tester.view.physicalSize = const Size(1440, 1000);
    ThemeController.instance.debugSetMode(ThemeMode.dark);
    await tester.pumpWidget(app(AppTheme.dark()));
    await tester.pumpAndSettle();
    expect(AppColors.isDark, isTrue);
    expect(find.textContaining('正确。DNA 连接酶'), findsOneWidget);
    expect(find.byKey(const Key('dna-ligase-feedback')), findsOneWidget);
    final formula = find.descendant(of: panel, matching: find.byType(Math));
    expect(formula, findsOneWidget);
    final formulaRichTexts = tester
        .widgetList<RichText>(
          find.descendant(of: formula, matching: find.byType(RichText)),
        )
        .toList();
    expect(formulaRichTexts, isNotEmpty);
    for (final richText in formulaRichTexts) {
      expect(
        richText.text.style?.color,
        AppColors.inkD,
        reason: '深色公式的实际字形必须使用浅色画笔，而非只更新外层 Widget',
      );
    }
    await revealAndCheck(panel, '连接酶深色桌面答对面板');
    await _capture(tester, 'knowledge_30_ligase_correct_dark_desktop');

    final evidence = find.widgetWithText(ActionChip, '查看连接酶证据');
    await tester.ensureVisible(evidence);
    await tester.tap(evidence);
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsOneWidget);
    expect(find.text('4377758'), findsOneWidget);
    expect(find.text('P19821'), findsNothing);
    expect(calls, 0, reason: '证据入口只能筛选内置精选，不得联网');
    expect(tester.takeException(), isNull);
  });

  testWidgets('Taq 耐热辨析在窄屏和深色下可重选并离线追溯证据', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ThemeController.instance.debugSetMode(ThemeMode.light);
    addTearDown(() => ThemeController.instance.debugSetMode(ThemeMode.system));

    Future<void> revealAndCheck(Finder target, String label) async {
      await Scrollable.ensureVisible(tester.element(target), alignment: 0.08);
      await tester.pumpAndSettle();
      final rect = tester.getRect(target);
      final size = tester.view.physicalSize;
      expect(
        rect.left >= 0 && rect.right <= size.width,
        isTrue,
        reason: '$label 不得横向溢出：$rect',
      );
      expect(
        rect.top >= 0 && rect.bottom <= size.height,
        isTrue,
        reason: '$label 必须完整进入截图：$rect',
      );
    }

    var calls = 0;
    final service = _FakeKnowledgeService((query, source) async {
      calls++;
      throw StateError('Taq 离线练习不应发起实时查询：$query');
    });
    Widget app(ThemeData theme) => RepaintBoundary(
      key: _captureKey,
      child: MaterialApp(
        theme: theme,
        home: Scaffold(
          body: SingleChildScrollView(child: KnowledgeLab(service: service)),
        ),
      ),
    );

    await tester.pumpWidget(app(AppTheme.light()));
    await tester.pumpAndSettle();

    final panel = find.byKey(const Key('taq-heat-stable-exercise'));
    final correct = find.byKey(const Key('taq-heat-stable-choice'));
    final hotter = find.byKey(const Key('taq-hotter-choice'));
    final denaturation = find.byKey(const Key('taq-denaturation-choice'));
    expect(panel, findsOneWidget);
    expect(correct, findsOneWidget);
    expect(hotter, findsOneWidget);
    expect(denaturation, findsOneWidget);

    await tester.ensureVisible(hotter);
    await tester.tap(hotter);
    await tester.pumpAndSettle();
    expect(find.textContaining('耐热不等于温度越高越好'), findsOneWidget);
    expect(find.textContaining('正确。Taq DNA 聚合酶'), findsNothing);
    await revealAndCheck(panel, 'Taq 桌面温度误区面板');
    await _capture(tester, 'knowledge_31_taq_hotter_desktop');

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    await tester.ensureVisible(denaturation);
    await tester.tap(denaturation);
    await tester.pumpAndSettle();
    expect(find.textContaining('不能说 Taq 通过切割 DNA 骨架使双链变性'), findsOneWidget);
    expect(find.textContaining('正确。Taq DNA 聚合酶'), findsNothing);

    await tester.ensureVisible(correct);
    await tester.tap(correct);
    await tester.pumpAndSettle();
    expect(find.textContaining('正确。Taq DNA 聚合酶'), findsOneWidget);
    expect(find.textContaining('再想一想'), findsNothing);
    expect(
      find.bySemanticsLabel('Taq DNA 聚合酶在延伸阶段沿五撇到三撇方向合成 DNA'),
      findsOneWidget,
    );
    await revealAndCheck(panel, 'Taq 窄屏答对面板');
    await _capture(tester, 'knowledge_32_taq_correct_mobile');

    tester.view.physicalSize = const Size(1440, 1000);
    ThemeController.instance.debugSetMode(ThemeMode.dark);
    await tester.pumpWidget(app(AppTheme.dark()));
    await tester.pumpAndSettle();
    expect(AppColors.isDark, isTrue);
    expect(find.byKey(const Key('taq-heat-feedback')), findsOneWidget);
    final formula = find.descendant(of: panel, matching: find.byType(Math));
    expect(formula, findsOneWidget);
    final formulaRichTexts = tester
        .widgetList<RichText>(
          find.descendant(of: formula, matching: find.byType(RichText)),
        )
        .toList();
    expect(formulaRichTexts, isNotEmpty);
    for (final richText in formulaRichTexts) {
      expect(richText.text.style?.color, AppColors.inkD);
    }
    await revealAndCheck(panel, 'Taq 深色桌面答对面板');
    await _capture(tester, 'knowledge_33_taq_correct_dark_desktop');

    final evidence = find.widgetWithText(ActionChip, '查看 Taq 证据');
    await tester.ensureVisible(evidence);
    await tester.tap(evidence);
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsNWidgets(3));
    expect(find.text('P19821'), findsOneWidget);
    expect(find.text('3LWM'), findsOneWidget);
    expect(find.text('2448875'), findsOneWidget);
    expect(find.text('P00642'), findsNothing);
    expect(calls, 0, reason: 'Taq 证据入口只能筛选内置精选，不得联网');
    expect(tester.takeException(), isNull);
  });

  testWidgets('PCR 引物延伸辨析在窄屏和深色下可重选并离线追溯证据', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ThemeController.instance.debugSetMode(ThemeMode.light);
    addTearDown(() => ThemeController.instance.debugSetMode(ThemeMode.system));

    Future<void> revealAndCheck(Finder target, String label) async {
      await Scrollable.ensureVisible(tester.element(target), alignment: 0.08);
      await tester.pumpAndSettle();
      final rect = tester.getRect(target);
      final size = tester.view.physicalSize;
      expect(
        rect.left >= 0 && rect.right <= size.width,
        isTrue,
        reason: '$label 不得横向溢出：$rect',
      );
      expect(
        rect.top >= 0 && rect.bottom <= size.height,
        isTrue,
        reason: '$label 必须完整进入截图：$rect',
      );
    }

    var calls = 0;
    final service = _FakeKnowledgeService((query, source) async {
      calls++;
      throw StateError('引物延伸离线练习不应发起实时查询：$query');
    });
    Widget app(ThemeData theme) => RepaintBoundary(
      key: _captureKey,
      child: MaterialApp(
        theme: theme,
        home: Scaffold(
          body: SingleChildScrollView(child: KnowledgeLab(service: service)),
        ),
      ),
    );

    await tester.pumpWidget(app(AppTheme.light()));
    await tester.pumpAndSettle();

    final panel = find.byKey(const Key('primer-extension-exercise'));
    final correct = find.byKey(const Key('primer-three-oh-choice'));
    final fiveEnd = find.byKey(const Key('primer-five-end-choice'));
    expect(panel, findsOneWidget);
    expect(correct, findsOneWidget);
    expect(fiveEnd, findsOneWidget);

    await tester.ensureVisible(fiveEnd);
    await tester.tap(fiveEnd);
    await tester.pumpAndSettle();
    expect(find.textContaining('延伸发生在引物的 3′ 端，不是 5′-磷酸端'), findsOneWidget);
    expect(find.textContaining('正确。引物为延伸提供起点'), findsNothing);
    await revealAndCheck(panel, '引物延伸桌面答错面板');
    await _capture(tester, 'knowledge_34_primer_wrong_desktop');

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    await tester.ensureVisible(correct);
    await tester.tap(correct);
    await tester.pumpAndSettle();
    expect(find.textContaining('正确。引物为延伸提供起点'), findsOneWidget);
    expect(find.textContaining('模板链按 3′→5′ 方向被读取'), findsOneWidget);
    expect(find.textContaining('再想一想'), findsNothing);
    expect(
      find.bySemanticsLabel('新脱氧核苷酸接到引物三撇羟基端，新链沿五撇到三撇方向延伸'),
      findsOneWidget,
    );
    await revealAndCheck(panel, '引物延伸窄屏答对面板');
    await _capture(tester, 'knowledge_35_primer_correct_mobile');

    tester.view.physicalSize = const Size(1440, 1000);
    ThemeController.instance.debugSetMode(ThemeMode.dark);
    await tester.pumpWidget(app(AppTheme.dark()));
    await tester.pumpAndSettle();
    expect(AppColors.isDark, isTrue);
    expect(find.byKey(const Key('primer-extension-feedback')), findsOneWidget);
    final formula = find.descendant(of: panel, matching: find.byType(Math));
    expect(formula, findsOneWidget);
    final formulaRichTexts = tester
        .widgetList<RichText>(
          find.descendant(of: formula, matching: find.byType(RichText)),
        )
        .toList();
    expect(formulaRichTexts, isNotEmpty);
    for (final richText in formulaRichTexts) {
      expect(richText.text.style?.color, AppColors.inkD);
    }
    await revealAndCheck(panel, '引物延伸深色桌面答对面板');
    await _capture(tester, 'knowledge_36_primer_correct_dark_desktop');

    final evidence = find.widgetWithText(ActionChip, '查看引物证据');
    await tester.ensureVisible(evidence);
    await tester.tap(evidence);
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsNWidgets(2));
    expect(find.text('15823023'), findsOneWidget);
    expect(find.text('2448875'), findsOneWidget);
    expect(find.text('P19821'), findsNothing);
    expect(find.textContaining('不是 Taq'), findsOneWidget);
    expect(calls, 0, reason: '引物证据入口只能筛选内置精选，不得联网');
    expect(tester.takeException(), isNull);
  });

  testWidgets('PCR 温度循环辨析在窄屏和深色下可重选并离线追溯证据', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ThemeController.instance.debugSetMode(ThemeMode.light);
    addTearDown(() => ThemeController.instance.debugSetMode(ThemeMode.system));

    Future<void> revealAndCheck(Finder target, String label) async {
      await Scrollable.ensureVisible(tester.element(target), alignment: 0.08);
      await tester.pumpAndSettle();
      final rect = tester.getRect(target);
      final size = tester.view.physicalSize;
      expect(
        rect.left >= 0 && rect.right <= size.width,
        isTrue,
        reason: '$label 不得横向溢出：$rect',
      );
      expect(
        rect.top >= 0 && rect.bottom <= size.height,
        isTrue,
        reason: '$label 必须完整进入截图：$rect',
      );
    }

    var calls = 0;
    final service = _FakeKnowledgeService((query, source) async {
      calls++;
      throw StateError('PCR 温度循环离线练习不应发起实时查询：$query');
    });
    Widget app(ThemeData theme) => RepaintBoundary(
      key: _captureKey,
      child: MaterialApp(
        theme: theme,
        home: Scaffold(
          body: SingleChildScrollView(child: KnowledgeLab(service: service)),
        ),
      ),
    );

    await tester.pumpWidget(app(AppTheme.light()));
    await tester.pumpAndSettle();

    final panel = find.byKey(const Key('pcr-cycle-exercise'));
    final correct = find.byKey(const Key('pcr-cycle-correct-choice'));
    final annealFirst = find.byKey(const Key('pcr-cycle-anneal-first-choice'));
    expect(panel, findsOneWidget);
    expect(correct, findsOneWidget);
    expect(annealFirst, findsOneWidget);

    await tester.ensureVisible(annealFirst);
    await tester.tap(annealFirst);
    await tester.pumpAndSettle();
    expect(find.textContaining('不能跳过双链分离直接开始退火'), findsOneWidget);
    expect(find.textContaining('正确。经典 PCR 按'), findsNothing);
    await revealAndCheck(panel, 'PCR 温度循环桌面答错面板');
    await _capture(tester, 'knowledge_37_pcr_cycle_wrong_desktop');

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    await tester.ensureVisible(correct);
    await tester.tap(correct);
    await tester.pumpAndSettle();
    expect(find.textContaining('正确。经典 PCR 按'), findsOneWidget);
    expect(find.textContaining('耐热 DNA 聚合酶再延伸引物'), findsOneWidget);
    expect(find.textContaining('再想一想'), findsNothing);
    expect(find.bySemanticsLabel('经典 PCR 三步依次为变性、退火、延伸，并反复循环'), findsOneWidget);
    await revealAndCheck(panel, 'PCR 温度循环窄屏答对面板');
    await _capture(tester, 'knowledge_38_pcr_cycle_correct_mobile');

    tester.view.physicalSize = const Size(1440, 1000);
    ThemeController.instance.debugSetMode(ThemeMode.dark);
    await tester.pumpWidget(app(AppTheme.dark()));
    await tester.pumpAndSettle();
    expect(AppColors.isDark, isTrue);
    expect(find.byKey(const Key('pcr-cycle-feedback')), findsOneWidget);
    final formula = find.descendant(of: panel, matching: find.byType(Math));
    expect(formula, findsOneWidget);
    final formulaRichTexts = tester
        .widgetList<RichText>(
          find.descendant(of: formula, matching: find.byType(RichText)),
        )
        .toList();
    expect(formulaRichTexts, isNotEmpty);
    for (final richText in formulaRichTexts) {
      expect(richText.text.style?.color, AppColors.inkD);
    }
    await revealAndCheck(panel, 'PCR 温度循环深色桌面答对面板');
    await _capture(tester, 'knowledge_39_pcr_cycle_correct_dark_desktop');

    final evidence = find.widgetWithText(ActionChip, '查看 PCR 循环证据');
    await tester.ensureVisible(evidence);
    await tester.tap(evidence);
    await tester.pumpAndSettle();
    expect(find.byType(Card), findsOneWidget);
    expect(find.text('23399825'), findsOneWidget);
    expect(find.textContaining('PMC4102308'), findsOneWidget);
    expect(find.text('2448875'), findsNothing);
    expect(find.text('P19821'), findsNothing);
    expect(calls, 0, reason: 'PCR 循环证据入口只能筛选内置精选，不得联网');
    expect(tester.takeException(), isNull);
  });

  testWidgets('PCR 理论扩增卡在桌面与窄屏精确计算并离线追溯证据', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ThemeController.instance.debugSetMode(ThemeMode.light);
    addTearDown(() => ThemeController.instance.debugSetMode(ThemeMode.system));
    final semantics = tester.ensureSemantics();

    Future<void> revealAndCheck(Finder target, String label) async {
      await Scrollable.ensureVisible(tester.element(target), alignment: 0.06);
      await tester.pumpAndSettle();
      final rect = tester.getRect(target);
      final size = tester.view.physicalSize;
      expect(
        rect.left >= 0 && rect.right <= size.width,
        isTrue,
        reason: '$label 不得横向溢出：$rect',
      );
      expect(
        rect.top >= 0 && rect.bottom <= size.height,
        isTrue,
        reason: '$label 必须完整进入截图：$rect',
      );
    }

    Future<void> choose(Finder target) async {
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    var calls = 0;
    final service = _FakeKnowledgeService((query, source) async {
      calls++;
      throw StateError('PCR 理论扩增离线练习不应发起实时查询：$query');
    });
    await tester.pumpWidget(
      RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(child: KnowledgeLab(service: service)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final panel = find.byKey(const Key('pcr-amplification-exercise'));
    final result = find.byKey(const Key('pcr-amplification-result'));
    final initial3 = find.byKey(const Key('pcr-amplification-initial-3'));
    final cycle0 = find.byKey(const Key('pcr-amplification-cycle-0'));
    final cycle4 = find.byKey(const Key('pcr-amplification-cycle-4'));
    final cycle30 = find.byKey(const Key('pcr-amplification-cycle-30'));
    final evidence = find.widgetWithText(ActionChip, '查看理论扩增证据');
    expect(panel, findsOneWidget);
    expect(result, findsOneWidget);
    expect(
      find.descendant(of: result, matching: find.byType(Math)),
      findsOneWidget,
    );

    Future<void> expectProduct(String product, int cycles, String fold) async {
      expect(find.text('理想产物：$product 份目标 DNA 分子'), findsOneWidget);
      expect(
        tester.getSemantics(result).label,
        contains('3 份初始模板经过 $cycles 次理想 PCR 循环得到 $product 份目标 DNA 分子'),
      );
      expect(find.text('相对初始模板放大 $fold 倍。'), findsOneWidget);
    }

    Future<void> expectOfflineEvidence() async {
      await choose(evidence);
      expect(find.byType(Card), findsNWidgets(2));
      expect(find.text('23399825'), findsOneWidget);
      expect(find.text('17417022'), findsOneWidget);
      expect(find.textContaining('PMC4102308'), findsOneWidget);
      expect(
        find.textContaining('10.1007/978-1-59745-257-1_25'),
        findsOneWidget,
      );
      expect(find.text('2448875'), findsNothing);
      expect(calls, 0, reason: '理论扩增证据只能筛选内置精选，不得联网');
    }

    await choose(initial3);
    await choose(cycle4);
    await expectProduct('48', 4, '16');
    expect(find.textContaining('不是 3 × 4 = 12'), findsOneWidget);
    await revealAndCheck(panel, 'PCR 理论扩增桌面面板');
    await _capture(tester, 'knowledge_40_pcr_amplification_desktop');

    await choose(cycle0);
    await expectProduct('3', 0, '1');
    await choose(cycle30);
    await expectProduct('3221225472', 30, '1073741824');
    await revealAndCheck(panel, 'PCR 理论扩增桌面大整数面板');
    await expectOfflineEvidence();

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    await choose(cycle4);
    await expectProduct('48', 4, '16');
    await revealAndCheck(panel, 'PCR 理论扩增窄屏面板');
    await _capture(tester, 'knowledge_41_pcr_amplification_mobile');

    await choose(cycle0);
    await expectProduct('3', 0, '1');
    await choose(cycle30);
    await expectProduct('3221225472', 30, '1073741824');
    await revealAndCheck(panel, 'PCR 理论扩增窄屏大整数面板');
    await expectOfflineEvidence();
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });

  testWidgets('PCR 恒定效率对照卡在桌面与窄屏比较模型并离线追溯证据', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    ThemeController.instance.debugSetMode(ThemeMode.light);
    addTearDown(() => ThemeController.instance.debugSetMode(ThemeMode.system));
    final semantics = tester.ensureSemantics();

    Future<void> revealAndCheck(String label) async {
      final panel = find.byKey(const Key('pcr-efficiency-exercise'));
      await Scrollable.ensureVisible(tester.element(panel), alignment: 0.06);
      await tester.pumpAndSettle();
      final rect = tester.getRect(panel);
      final size = tester.view.physicalSize;
      expect(
        rect.left >= 0 && rect.right <= size.width,
        isTrue,
        reason: '$label 不得横向溢出：$rect',
      );
      expect(
        rect.top >= 0 && rect.bottom <= size.height,
        isTrue,
        reason: '$label 必须完整进入截图：$rect',
      );
    }

    Future<void> choose(Finder target) async {
      await tester.ensureVisible(target);
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    var calls = 0;
    final service = _FakeKnowledgeService((query, source) async {
      calls++;
      throw StateError('PCR 效率对照不应发起实时查询：$query');
    });
    await tester.pumpWidget(
      RepaintBoundary(
        key: _captureKey,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(child: KnowledgeLab(service: service)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final result = find.byKey(const Key('pcr-efficiency-result'));
    expect(find.byKey(const Key('pcr-efficiency-exercise')), findsOneWidget);
    expect(result, findsOneWidget);
    expect(
      find.descendant(of: result, matching: find.byType(Math)),
      findsNWidgets(2),
    );
    expect(find.text('理想模型：16 份'), findsOneWidget);
    expect(find.text('恒定效率模型：13.0321 份（约为理想的 81.45%）'), findsOneWidget);

    await choose(find.byKey(const Key('pcr-efficiency-percent-80')));
    await choose(find.byKey(const Key('pcr-efficiency-cycle-10')));
    expect(find.text('理想模型：1024 份'), findsOneWidget);
    expect(find.text('恒定效率模型：357.0467 份（约为理想的 34.87%）'), findsOneWidget);
    expect(tester.getSemantics(result).label, contains('每轮效率 80%'));
    await revealAndCheck('PCR 效率对照桌面面板');
    await _capture(tester, 'knowledge_42_pcr_efficiency_desktop');

    await choose(find.widgetWithText(ActionChip, '查看效率与平台期证据'));
    expect(find.byType(Card), findsNWidgets(2));
    expect(find.text('23399825'), findsOneWidget);
    expect(find.text('8013946'), findsOneWidget);
    expect(find.text('17417022'), findsNothing);
    expect(find.text('2448875'), findsNothing);
    expect(calls, 0, reason: '效率与平台期证据只能筛选内置精选，不得联网');

    tester.view.physicalSize = const Size(390, 844);
    await tester.pumpAndSettle();
    await choose(find.byKey(const Key('pcr-efficiency-percent-100')));
    expect(find.text('理想模型：1024 份'), findsOneWidget);
    expect(find.text('恒定效率模型：1024.0000 份（约为理想的 100.00%）'), findsOneWidget);
    expect(find.textContaining('本卡没有模拟平台期'), findsOneWidget);
    await revealAndCheck('PCR 效率对照窄屏面板');
    await _capture(tester, 'knowledge_43_pcr_efficiency_mobile');
    semantics.dispose();
    expect(tester.takeException(), isNull);
  });
}
