import 'dart:async';

import 'package:biology/data/bio_knowledge_data.dart';
import 'package:biology/models/bio_knowledge.dart';
import 'package:biology/pages/molecular_page.dart';
import 'package:biology/pages/widgets/cas9_cut_exercise.dart';
import 'package:biology/pages/widgets/knowledge_lab.dart';
import 'package:biology/services/bio_database_service.dart';
import 'package:biology/ui/tex_formula.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeBioService implements BioDatabaseClient {
  _FakeBioService(this.onSearch);

  final Future<BioSearchResponse> Function(String query, BioSource? source)
  onSearch;
  int calls = 0;

  @override
  Future<BioSearchResponse> search(String query, {BioSource? source}) {
    calls++;
    return onSearch(query, source);
  }

  @override
  void dispose() {}
}

BioSearchResponse _response(List<BioKnowledgeRecord> records) =>
    BioSearchResponse(
      records: records,
      failures: const <String>[],
      queriedAt: DateTime(2026, 10, 29, 8, 30),
    );

Future<void> _pumpLab(
  WidgetTester tester, {
  required BioDatabaseClient service,
  GlobalKey<KnowledgeLabState>? key,
  Future<bool> Function(Uri uri)? linkLauncher,
  bool showInputs = true,
  Size size = const Size(1100, 4200),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: KnowledgeLab(
            key: key,
            service: service,
            linkLauncher: linkLauncher,
            showInputs: showInputs,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openKnowledgeOnPage(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: MolecularPage()));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('基因工程'));
  await tester.tap(find.text('基因工程'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('知识库'));
  await tester.tap(find.text('知识库'));
  await tester.pumpAndSettle();
}

void main() {
  group('知识库自包含形态', () {
    testWidgets('默认离线展示 18 条精选、六条 TeX 公式，不发起网络请求', (tester) async {
      final service = _FakeBioService((_, _) async => _response(const []));
      await _pumpLab(tester, service: service);

      expect(service.calls, 0);
      expect(find.byType(Card), findsNWidgets(18));
      expect(find.byType(TextField), findsNWidgets(2));
      expect(find.byType(TexFormula), findsNWidgets(6));
      expect(find.text('内置精选'), findsOneWidget);
      expect(find.text('P00642'), findsOneWidget);
      expect(find.text('4OO8'), findsOneWidget);
      expect(find.text('4UN3'), findsOneWidget);
      expect(find.text('23287722'), findsOneWidget);
      expect(find.text('25079318'), findsOneWidget);
      expect(find.text('4377758'), findsOneWidget);
      expect(find.textContaining('A138T 突变体'), findsOneWidget);
      expect(find.textContaining('不是完整的 832 aa 蛋白'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('连接酶辨析答错后可重选，证据只筛选离线精选', (tester) async {
      final service = _FakeBioService((_, _) async => _response(const []));
      await _pumpLab(tester, service: service, size: const Size(390, 4200));

      expect(find.text('DNA 连接酶连接哪种化学键？'), findsOneWidget);
      final hydrogen = find.byKey(const Key('dna-ligase-hydrogen-bond'));
      final phosphodiester = find.byKey(
        const Key('dna-ligase-phosphodiester-bond'),
      );
      expect(hydrogen, findsOneWidget);
      expect(phosphodiester, findsOneWidget);
      expect(find.textContaining('请重新选择'), findsNothing);

      await tester.tap(hydrogen);
      await tester.pumpAndSettle();
      expect(
        find.text('再想一想：氢键负责碱基互补配对，不是连接酶催化的骨架共价连接。请重新选择。'),
        findsOneWidget,
      );
      expect(find.textContaining('正确。DNA 连接酶'), findsNothing);

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

      await tester.tap(find.widgetWithText(ActionChip, '查看连接酶证据'));
      await tester.pumpAndSettle();
      expect(find.byType(Card), findsOneWidget);
      expect(find.text('4377758'), findsOneWidget);
      expect(service.calls, 0, reason: '证据入口只筛选内置精选，不应联网');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Taq 耐热练习答对后可离线追溯蛋白、结构与论文证据', (tester) async {
      final service = _FakeBioService((_, _) async => _response(const []));
      await _pumpLab(tester, service: service, size: const Size(390, 4600));

      expect(find.byKey(const Key('taq-heat-stable-exercise')), findsOneWidget);
      await tester.tap(find.byKey(const Key('taq-heat-stable-choice')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          '正确。Taq DNA 聚合酶的耐热性质使 PCR 能在较高温度进行，并适应反复温度循环；这不等于温度越高越好或永远不会失活。',
        ),
        findsOneWidget,
      );
      expect(
        find.bySemanticsLabel('Taq DNA 聚合酶在延伸阶段沿五撇到三撇方向合成 DNA'),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(ActionChip, '查看 Taq 证据'));
      await tester.pumpAndSettle();
      expect(find.byType(Card), findsNWidgets(3));
      expect(find.text('P19821'), findsOneWidget);
      expect(find.text('3LWM'), findsOneWidget);
      expect(find.text('2448875'), findsOneWidget);
      expect(find.text('P00642'), findsNothing);
      expect(service.calls, 0, reason: 'Taq 证据入口只筛选内置精选，不应联网');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Taq 练习纠正温度越高越好和催化变性的误解并可重选', (tester) async {
      final service = _FakeBioService((_, _) async => _response(const []));
      await _pumpLab(tester, service: service, size: const Size(390, 4600));

      await tester.tap(find.byKey(const Key('taq-hotter-choice')));
      await tester.pumpAndSettle();
      expect(
        find.text('再想一想：耐热不等于温度越高越好，也不等于永远不会失活。PCR 需要按规程控制各阶段温度。'),
        findsOneWidget,
      );
      expect(find.textContaining('正确。Taq DNA 聚合酶'), findsNothing);

      await tester.tap(find.byKey(const Key('taq-denaturation-choice')));
      await tester.pumpAndSettle();
      expect(
        find.text('再想一想：高温变性与 Taq 的延伸合成是不同事件，不能说 Taq 通过切割 DNA 骨架使双链变性。'),
        findsOneWidget,
      );
      expect(find.textContaining('正确。Taq DNA 聚合酶'), findsNothing);

      await tester.tap(find.byKey(const Key('taq-heat-stable-choice')));
      await tester.pumpAndSettle();
      expect(find.textContaining('正确。Taq DNA 聚合酶'), findsOneWidget);
      expect(find.textContaining('再想一想'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('PCR 引物延伸练习区分末端与方向并可离线追溯证据', (tester) async {
      final service = _FakeBioService((_, _) async => _response(const []));
      await _pumpLab(tester, service: service, size: const Size(390, 5000));

      expect(
        find.byKey(const Key('primer-extension-exercise')),
        findsOneWidget,
      );
      expect(find.text('PCR 引物为什么需要游离 3′-OH？'), findsOneWidget);
      await tester.tap(find.byKey(const Key('primer-five-end-choice')));
      await tester.pumpAndSettle();
      expect(
        find.text('再想一想：延伸发生在引物的 3′ 端，不是 5′-磷酸端；新链的合成方向应按新链自身书写。'),
        findsOneWidget,
      );
      expect(find.textContaining('正确。引物为延伸提供起点'), findsNothing);

      await tester.tap(find.byKey(const Key('primer-middle-choice')));
      await tester.pumpAndSettle();
      expect(find.textContaining('不是从引物中部随机接入'), findsOneWidget);
      expect(find.textContaining('正确。引物为延伸提供起点'), findsNothing);

      await tester.tap(find.byKey(const Key('primer-three-oh-choice')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          '正确。引物为延伸提供起点，新的脱氧核苷酸接到游离 3′-OH 端，所以新链按 5′→3′ 方向延伸；与之配对的模板链按 3′→5′ 方向被读取。',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('再想一想'), findsNothing);
      expect(
        find.bySemanticsLabel('新脱氧核苷酸接到引物三撇羟基端，新链沿五撇到三撇方向延伸'),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(ActionChip, '查看引物证据'));
      await tester.pumpAndSettle();
      expect(find.byType(Card), findsNWidgets(2));
      expect(find.text('15823023'), findsOneWidget);
      expect(find.text('2448875'), findsOneWidget);
      expect(find.text('P19821'), findsNothing);
      expect(find.textContaining('不是 Taq'), findsOneWidget);
      expect(service.calls, 0, reason: '引物证据入口只筛选内置精选，不应联网');
      expect(tester.takeException(), isNull);
    });

    testWidgets('PCR 温度循环练习纠正顺序误区并呈现 TeX 与规程边界', (tester) async {
      final service = _FakeBioService((_, _) async => _response(const []));
      await _pumpLab(tester, service: service, size: const Size(390, 5200));

      expect(find.byKey(const Key('pcr-cycle-exercise')), findsOneWidget);
      await tester.tap(find.byKey(const Key('pcr-cycle-anneal-first-choice')));
      await tester.pumpAndSettle();
      expect(
        find.text('再想一想：经典 PCR 先使双链 DNA 变性分开，再降温让引物退火，不能跳过双链分离直接开始退火。'),
        findsOneWidget,
      );
      expect(find.textContaining('正确。经典 PCR 按'), findsNothing);

      await tester.tap(
        find.byKey(const Key('pcr-cycle-extension-first-choice')),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('再想一想：延伸发生在引物完成退火之后，不能在一个新循环开始时跳过变性和退火。'),
        findsOneWidget,
      );
      expect(find.textContaining('正确。经典 PCR 按'), findsNothing);

      await tester.tap(find.byKey(const Key('pcr-cycle-correct-choice')));
      await tester.pumpAndSettle();
      expect(
        find.text(
          '正确。经典 PCR 按变性→退火→延伸反复循环：双链分开后，引物与互补序列配对，耐热 DNA 聚合酶再延伸引物、合成新链。',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('再想一想'), findsNothing);
      expect(
        find.bySemanticsLabel('经典 PCR 三步依次为变性、退火、延伸，并反复循环'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('pcr-cycle-exercise')),
          matching: find.textContaining('具体温度和时间'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('PCR 温度循环证据只筛选开放综述且不联网', (tester) async {
      final service = _FakeBioService((_, _) async => _response(const []));
      await _pumpLab(tester, service: service, size: const Size(390, 5200));

      await tester.tap(find.widgetWithText(ActionChip, '查看 PCR 循环证据'));
      await tester.pumpAndSettle();
      expect(find.byType(Card), findsOneWidget);
      expect(find.text('23399825'), findsOneWidget);
      expect(find.textContaining('PMC4102308'), findsOneWidget);
      expect(find.text('2448875'), findsNothing);
      expect(find.text('P19821'), findsNothing);
      expect(find.textContaining('具体温度和时间'), findsOneWidget);
      expect(service.calls, 0, reason: 'PCR 循环证据入口只筛选内置精选，不应联网');
      expect(tester.takeException(), isNull);
    });

    testWidgets('PCR 理论扩增卡支持初始模板、0 次循环与 BigInt 精确结果', (tester) async {
      final service = _FakeBioService((_, _) async => _response(const []));
      await _pumpLab(tester, service: service, size: const Size(390, 5600));

      expect(
        find.byKey(const Key('pcr-amplification-exercise')),
        findsOneWidget,
      );
      expect(find.text('PCR 循环数如何影响理论产物？'), findsOneWidget);
      expect(find.bySemanticsLabel('理论产物份数等于初始模板份数乘 2 的循环数次方'), findsOneWidget);
      expect(find.text('理想产物：1 份目标 DNA 分子'), findsOneWidget);

      await tester.tap(find.byKey(const Key('pcr-amplification-initial-3')));
      await tester.tap(find.byKey(const Key('pcr-amplification-cycle-4')));
      await tester.pumpAndSettle();
      expect(find.text('理想产物：48 份目标 DNA 分子'), findsOneWidget);
      final dynamicFormula = find.descendant(
        of: find.byKey(const Key('pcr-amplification-result')),
        matching: find.byType(TexFormula),
      );
      expect(dynamicFormula, findsOneWidget);
      expect(
        tester.getSemantics(dynamicFormula).label,
        contains('3 份初始模板经过 4 次理想 PCR 循环得到 48 份目标 DNA 分子'),
        reason: '结果区会合并朗读产物、动态公式与放大倍数',
      );
      expect(find.textContaining('不是 3 × 4 = 12'), findsOneWidget);

      await tester.tap(find.byKey(const Key('pcr-amplification-cycle-0')));
      await tester.pumpAndSettle();
      expect(find.text('理想产物：3 份目标 DNA 分子'), findsOneWidget);

      await tester.tap(find.byKey(const Key('pcr-amplification-cycle-30')));
      await tester.pumpAndSettle();
      expect(find.text('理想产物：3221225472 份目标 DNA 分子'), findsOneWidget);
      expect(find.text('相对初始模板放大 1073741824 倍。'), findsOneWidget);
      expect(find.textContaining('平台期'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('PCR 理论扩增证据同时支持每轮加倍与平台期边界且不联网', (tester) async {
      final service = _FakeBioService((_, _) async => _response(const []));
      await _pumpLab(tester, service: service, size: const Size(390, 5600));

      await tester.tap(find.widgetWithText(ActionChip, '查看理论扩增证据'));
      await tester.pumpAndSettle();
      expect(find.byType(Card), findsNWidgets(2));
      expect(find.text('23399825'), findsOneWidget);
      expect(find.text('17417022'), findsOneWidget);
      expect(find.textContaining('PMC4102308'), findsOneWidget);
      expect(
        find.textContaining('10.1007/978-1-59745-257-1_25'),
        findsOneWidget,
      );
      expect(find.text('2448875'), findsNothing);
      expect(service.calls, 0, reason: '理论扩增证据入口只筛选内置精选，不应联网');
      expect(tester.takeException(), isNull);
    });

    testWidgets('CRISPR 示例同时展示 Cas9 结构与原始研究文献', (tester) async {
      final service = _FakeBioService((_, _) async => _response(const []));
      await _pumpLab(tester, service: service);

      await tester.tap(find.text('CRISPR'));
      await tester.pumpAndSettle();

      expect(find.byType(Card), findsNWidgets(4));
      expect(find.text('4OO8'), findsOneWidget);
      expect(find.text('4UN3'), findsOneWidget);
      expect(find.text('23287722'), findsOneWidget);
      expect(find.text('25079318'), findsOneWidget);
      expect(find.textContaining('不能单凭结构推断'), findsOneWidget);
      expect(service.calls, 0, reason: '示例只筛选离线精选，不应联网');
      expect(tester.takeException(), isNull);
    });

    testWidgets('PAM 教学卡区分靶 DNA 与引导 RNA，证据筛选不混入 4OO8', (tester) async {
      final service = _FakeBioService((_, _) async => _response(const []));
      await _pumpLab(tester, service: service, size: const Size(390, 4200));

      expect(find.text('PAM ≠ 引导 RNA 配对区'), findsOneWidget);
      expect(find.textContaining('并非所有 Cas 蛋白通用'), findsWidgets);
      expect(
        find.bySemanticsLabel(
          '化脓性链球菌 Cas9 的经典 PAM 为 5 撇 NGG 3 撇，N 可为 A、T、C 或 G',
        ),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(ActionChip, 'PAM'));
      await tester.pumpAndSettle();

      expect(find.byType(Card), findsNWidgets(2));
      expect(find.text('4UN3'), findsOneWidget);
      expect(find.text('25079318'), findsOneWidget);
      expect(find.text('4OO8'), findsNothing);
      expect(service.calls, 0, reason: 'PAM 证据筛选必须保持离线');
      expect(tester.takeException(), isNull);
    });

    testWidgets('记录卡复制链接写入原始 URL 并显示来源反馈', (tester) async {
      final service = _FakeBioService((_, _) async => _response(const []));
      final record = kBioKnowledgeRecords.singleWhere((r) => r.id == 'P00642');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = SystemChannels.platform;
      final calls = <MethodCall>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'Clipboard.setData') calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await _pumpLab(tester, service: service);
      await tester.tap(find.text('EcoRI'));
      await tester.tap(find.text('UniProt').first);
      await tester.pumpAndSettle();
      expect(find.text(record.url), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, '复制链接'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      expect(calls, hasLength(1));
      expect(calls.single.arguments, <String, Object?>{'text': record.url});
      expect(find.text('已复制 UniProt P00642 的链接'), findsOneWidget);
      expect(service.calls, 0, reason: '复制原始链接不应触发数据库查询');
      expect(tester.takeException(), isNull);
    });

    testWidgets('剪贴板复制失败时显示手动复制恢复指引', (tester) async {
      final service = _FakeBioService((_, _) async => _response(const []));
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const channel = SystemChannels.platform;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'Clipboard.setData') {
          throw PlatformException(code: 'clipboard_unavailable');
        }
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      await _pumpLab(tester, service: service);
      await tester.tap(find.text('EcoRI'));
      await tester.tap(find.text('UniProt').first);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, '复制链接'));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      expect(find.text('无法复制 UniProt P00642 的链接，请选中上方链接手动复制。'), findsOneWidget);
      expect(find.text('已复制 UniProt P00642 的链接'), findsNothing);
      expect(service.calls, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('记录卡通过系统浏览器打开原始 URL', (tester) async {
      final service = _FakeBioService((_, _) async => _response(const []));
      final record = kBioKnowledgeRecords.singleWhere((r) => r.id == 'P00642');
      final opened = <Uri>[];
      await _pumpLab(
        tester,
        service: service,
        linkLauncher: (uri) async {
          opened.add(uri);
          return true;
        },
      );
      await tester.tap(find.text('EcoRI'));
      await tester.tap(find.text('UniProt').first);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, '打开原始页面'));
      await tester.pumpAndSettle();

      expect(opened, <Uri>[Uri.parse(record.url)]);
      expect(service.calls, 0, reason: '打开原始页面不应触发数据库查询');
      expect(find.textContaining('无法打开'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('系统浏览器拒绝打开时显示复制链接恢复指引', (tester) async {
      final service = _FakeBioService((_, _) async => _response(const []));
      await _pumpLab(
        tester,
        service: service,
        linkLauncher: (_) async => false,
      );
      await tester.tap(find.text('EcoRI'));
      await tester.tap(find.text('UniProt').first);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, '打开原始页面'));
      await tester.pumpAndSettle();

      expect(
        find.text('无法打开 UniProt P00642 的原始页面，请复制链接后在浏览器中打开。'),
        findsOneWidget,
      );
      expect(service.calls, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('系统浏览器打开异常被捕获并显示恢复指引', (tester) async {
      final service = _FakeBioService((_, _) async => _response(const []));
      await _pumpLab(
        tester,
        service: service,
        linkLauncher: (_) async => throw StateError('模拟平台打开异常'),
      );
      await tester.tap(find.text('EcoRI'));
      await tester.tap(find.text('UniProt').first);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, '打开原始页面'));
      await tester.pumpAndSettle();

      expect(
        find.text('无法打开 UniProt P00642 的原始页面，请复制链接后在浏览器中打开。'),
        findsOneWidget,
      );
      expect(service.calls, 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('非法原始 URL 不调用系统打开器并显示恢复指引', (tester) async {
      const record = BioKnowledgeRecord(
        source: BioSource.uniprot,
        id: 'INVALID-URL',
        title: '非法链接边界记录',
        subtitle: '仅用于测试',
        summary: '模拟上游返回非 HTTP 地址，不应交给系统浏览器。',
        url: 'not a valid url',
      );
      final service = _FakeBioService(
        (_, _) async => _response(const [record]),
      );
      var launchCalls = 0;
      await _pumpLab(
        tester,
        service: service,
        linkLauncher: (_) async {
          launchCalls++;
          return true;
        },
      );
      await tester.enterText(
        find.byKey(const Key('knowledge-search-input')),
        'INVALID-URL',
      );
      await tester.tap(find.widgetWithText(FilledButton, '实时查询'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(Card),
          matching: find.text('INVALID-URL'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(TextButton, '打开原始页面'));
      await tester.pumpAndSettle();

      expect(launchCalls, 0, reason: '非法 URL 必须在调用系统打开器前拦截');
      expect(
        find.text('无法打开 UniProt INVALID-URL 的原始页面，请复制链接后在浏览器中打开。'),
        findsOneWidget,
      );
      expect(service.calls, 1, reason: '只有实时查询可以访问服务，打开链接不得再次查询');
      expect(tester.takeException(), isNull);
    });

    testWidgets('点示例只筛选内置结果；来源筛选可组合', (tester) async {
      final service = _FakeBioService((_, _) async => _response(const []));
      await _pumpLab(tester, service: service);

      await tester.tap(find.text('EcoRI'));
      await tester.pumpAndSettle();
      expect(find.byType(Card), findsNWidgets(2));
      expect(find.text('P00642'), findsOneWidget);
      expect(find.text('2OXV'), findsOneWidget);
      expect(find.text('P19821'), findsNothing);
      expect(service.calls, 0, reason: '点示例不应偷偷联网');

      await tester.tap(find.text('UniProt').first);
      await tester.pumpAndSettle();
      expect(find.byType(Card), findsOneWidget);
      expect(find.text('P00642'), findsOneWidget);
      expect(find.text('2OXV'), findsNothing);
    });

    testWidgets('内置精选无匹配可一键清空筛选且不联网', (tester) async {
      final service = _FakeBioService((_, _) async => _response(const []));
      await _pumpLab(tester, service: service);
      await tester.tap(find.text('UniProt').first);
      await tester.enterText(
        find.byKey(const Key('knowledge-search-input')),
        '不存在的条目',
      );
      await tester.pumpAndSettle();

      expect(find.byType(Card), findsNothing);
      expect(
        find.byKey(const ValueKey('knowledge-built-in-empty')),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextButton, '清空筛选'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, '清空筛选'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('knowledge-search-input')))
            .controller!
            .text,
        isEmpty,
      );
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '全部来源'))
            .selected,
        isTrue,
      );
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'UniProt'))
            .selected,
        isFalse,
      );
      expect(find.byType(Card), findsNWidgets(18));
      expect(
        find.byKey(const ValueKey('knowledge-built-in-empty')),
        findsNothing,
      );
      expect(service.calls, 0, reason: '清空本地筛选不应发起实时查询');
      expect(tester.takeException(), isNull);
    });

    testWidgets('清空筛选保留上次实时结果并丢弃途中响应', (tester) async {
      final pending = Completer<BioSearchResponse>();
      var call = 0;
      final service = _FakeBioService((query, source) {
        expect(source, BioSource.uniprot);
        if (call++ == 0) {
          expect(query, 'Taq');
          return Future.value(
            _response(<BioKnowledgeRecord>[
              kBioKnowledgeRecords.singleWhere((r) => r.id == 'P19821'),
            ]),
          );
        }
        expect(query, '不存在的条目');
        return pending.future;
      });
      await _pumpLab(tester, service: service);
      await tester.tap(find.text('UniProt').first);
      await tester.enterText(
        find.byKey(const Key('knowledge-search-input')),
        'Taq',
      );
      await tester.tap(find.widgetWithText(FilledButton, '实时查询'));
      await tester.pumpAndSettle();
      expect(find.text('实时查询'), findsNWidgets(2));

      await tester.enterText(
        find.byKey(const Key('knowledge-search-input')),
        '不存在的条目',
      );
      await tester.tap(find.widgetWithText(FilledButton, '实时查询'));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('knowledge-search-skeleton')),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(TextButton, '清空筛选'));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('knowledge-search-skeleton')),
        findsNothing,
      );
      expect(find.text('上次实时结果'), findsOneWidget);
      expect(find.textContaining('关键词“Taq” · 来源：UniProt'), findsOneWidget);
      expect(find.text('P19821'), findsNWidgets(2), reason: '一条内置、一条上次实时结果');

      pending.complete(_response(const []));
      await tester.pumpAndSettle();
      expect(service.calls, 2);
      expect(find.text('上次实时结果'), findsOneWidget);
      expect(find.text('P19821'), findsNWidgets(2));
      expect(
        find.byKey(const ValueKey('knowledge-live-no-match')),
        findsNothing,
      );
      expect(
        find.byType(Card),
        findsNWidgets(19),
        reason: '18 条内置精选加 1 条保留的上次实时结果',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('实时成功结果与内置精选明确分区，并显示查询时间', (tester) async {
      final service = _FakeBioService((query, source) async {
        expect(query, 'Taq');
        expect(source, isNull);
        return _response(<BioKnowledgeRecord>[
          kBioKnowledgeRecords.singleWhere((r) => r.id == 'P19821'),
        ]);
      });
      await _pumpLab(tester, service: service);
      await tester.enterText(
        find.byKey(const Key('knowledge-search-input')),
        'Taq',
      );
      await tester.tap(find.text('实时查询'));
      await tester.pumpAndSettle();

      expect(service.calls, 1);
      expect(find.text('实时查询'), findsNWidgets(2), reason: '按钮与结果分区标题');
      expect(find.text('实时结果'), findsOneWidget);
      expect(find.textContaining('2026-10-29 08:30:00'), findsOneWidget);
      expect(find.text('内置精选'), findsOneWidget);
    });

    testWidgets('实时结果标明查询条件，编辑条件后明确归为上次结果', (tester) async {
      final service = _FakeBioService((query, source) async {
        expect(query, 'Taq');
        expect(source, BioSource.uniprot);
        return _response(<BioKnowledgeRecord>[
          kBioKnowledgeRecords.singleWhere((r) => r.id == 'P19821'),
        ]);
      });
      await _pumpLab(tester, service: service, size: const Size(390, 3600));
      await tester.tap(find.text('UniProt').first);
      await tester.enterText(
        find.byKey(const Key('knowledge-search-input')),
        'Taq',
      );
      await tester.tap(find.text('实时查询'));
      await tester.pumpAndSettle();

      expect(find.text('实时查询'), findsNWidgets(2));
      expect(
        find.text(
          '关键词“Taq” · 来源：UniProt · 查询时间：2026-10-29 08:30:00 · '
          '数据库当次响应，未逐条教学审核',
        ),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const Key('knowledge-search-input')),
        'GFP',
      );
      await tester.pump();
      expect(find.text('上次实时结果'), findsOneWidget);
      expect(find.text('实时查询'), findsOneWidget);
      expect(find.text('P19821'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('请求途中更改来源后，旧来源响应不会进入新筛选', (tester) async {
      final pending = Completer<BioSearchResponse>();
      BioSource? requestedSource;
      final service = _FakeBioService((query, source) {
        expect(query, 'Taq');
        requestedSource = source;
        return pending.future;
      });
      await _pumpLab(tester, service: service);
      await tester.tap(find.text('UniProt').first);
      await tester.enterText(
        find.byKey(const Key('knowledge-search-input')),
        'Taq',
      );
      await tester.tap(find.text('实时查询'));
      await tester.pump();
      expect(requestedSource, BioSource.uniprot);

      await tester.tap(find.text('RCSB PDB').first);
      await tester.pump();
      pending.complete(
        _response(<BioKnowledgeRecord>[
          kBioKnowledgeRecords.singleWhere((r) => r.id == 'P19821'),
        ]),
      );
      await tester.pumpAndSettle();

      expect(find.text('实时结果'), findsNothing);
      expect(find.text('上次实时结果'), findsNothing);
      expect(find.text('实时查询'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('加载保留旧结果并显示骨架，失败后旧结果仍可读取', (tester) async {
      final pending = Completer<BioSearchResponse>();
      var call = 0;
      final service = _FakeBioService((query, source) {
        if (call++ == 0) {
          return Future.value(
            _response(<BioKnowledgeRecord>[
              kBioKnowledgeRecords.singleWhere((r) => r.id == 'P19821'),
            ]),
          );
        }
        return pending.future;
      });
      await _pumpLab(tester, service: service);
      await tester.enterText(
        find.byKey(const Key('knowledge-search-input')),
        'Taq',
      );
      await tester.tap(find.text('实时查询'));
      await tester.pumpAndSettle();
      expect(find.text('实时结果'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('knowledge-search-input')),
        'GFP',
      );
      await tester.tap(find.widgetWithText(FilledButton, '实时查询'));
      await tester.pump();

      expect(find.text('上次实时结果'), findsOneWidget);
      expect(find.text('P19821'), findsOneWidget);
      expect(find.text('正在查询“GFP” · 来源：全部来源'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('knowledge-search-skeleton')),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);

      pending.completeError(const BioDatabaseException('服务暂时不可用，请稍后重试。'));
      await tester.pumpAndSettle();

      expect(find.textContaining('服务暂时不可用'), findsOneWidget);
      expect(find.text('上次实时结果'), findsOneWidget);
      expect(find.text('P19821'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('knowledge-search-skeleton')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('实时失败有中文错误，内置精选不消失', (tester) async {
      final service = _FakeBioService(
        (_, _) async => throw const BioDatabaseException('服务暂时不可用，请稍后重试。'),
      );
      await _pumpLab(tester, service: service);
      await tester.enterText(
        find.byKey(const Key('knowledge-search-input')),
        'EcoRI',
      );
      await tester.tap(find.text('实时查询'));
      await tester.pumpAndSettle();

      expect(find.textContaining('服务暂时不可用'), findsOneWidget);
      expect(find.text('内置精选'), findsOneWidget);
      expect(find.text('P00642'), findsOneWidget);
      expect(find.byType(Card), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets('部分来源失败保留结果并显示非错误警示', (tester) async {
      final service = _FakeBioService(
        (_, _) async => BioSearchResponse(
          records: <BioKnowledgeRecord>[
            kBioKnowledgeRecords.singleWhere((r) => r.id == 'P19821'),
          ],
          failures: const <String>['RCSB PDB：请求超时，请稍后重试。'],
          queriedAt: DateTime(2026, 10, 29, 8, 30),
        ),
      );
      await _pumpLab(tester, service: service);
      await tester.enterText(
        find.byKey(const Key('knowledge-search-input')),
        'Taq',
      );
      await tester.tap(find.widgetWithText(FilledButton, '实时查询'));
      await tester.pumpAndSettle();

      final warning = find.textContaining('部分来源未返回（1 个）；已保留 1 条可用结果。');
      final metadata = find.textContaining('关键词“Taq” · 来源：全部来源');
      expect(warning, findsOneWidget);
      expect(find.textContaining('RCSB PDB：请求超时'), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(find.text('P19821'), findsNWidgets(2)); // 内置精选与实时结果各一条。
      expect(
        tester.getTopLeft(warning).dy,
        greaterThan(tester.getTopLeft(metadata).dy),
        reason: '部分失败提示应贴近实时结果，而不是置顶成整次错误',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('全部来源失败且无结果时显示错误与恢复指引', (tester) async {
      final service = _FakeBioService(
        (_, _) async => BioSearchResponse(
          records: const <BioKnowledgeRecord>[],
          failures: const <String>[
            'UniProt：请求超时，请稍后重试。',
            'RCSB PDB：请求超时，请稍后重试。',
            'PubMed：请求超时，请稍后重试。',
          ],
          queriedAt: DateTime(2026, 10, 29, 8, 30),
        ),
      );
      await _pumpLab(tester, service: service);
      await tester.enterText(
        find.byKey(const Key('knowledge-search-input')),
        'Taq',
      );
      await tester.tap(find.widgetWithText(FilledButton, '实时查询'));
      await tester.pumpAndSettle();

      expect(find.textContaining('UniProt：请求超时'), findsOneWidget);
      expect(find.textContaining('RCSB PDB：请求超时'), findsOneWidget);
      expect(find.textContaining('PubMed：请求超时'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      expect(find.byIcon(Icons.info_outline), findsNothing);
      expect(find.textContaining('部分来源未返回'), findsNothing);
      expect(find.textContaining('已保留'), findsNothing);
      expect(find.text('本次未取回可用记录，请根据上方错误提示重试。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('实时无匹配提供示例恢复动作，不伪装成来源失败', (tester) async {
      final service = _FakeBioService((_, _) async => _response(const []));
      await _pumpLab(tester, service: service);
      await tester.enterText(
        find.byKey(const Key('knowledge-search-input')),
        '不存在的条目',
      );
      await tester.tap(find.widgetWithText(FilledButton, '实时查询'));
      await tester.pumpAndSettle();

      expect(find.text('本次查询没有匹配记录。'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('knowledge-live-no-match')),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.search_off), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(find.textContaining('未取回可用记录'), findsNothing);

      await tester.tap(find.widgetWithText(TextButton, '填入 GFP 示例'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('knowledge-search-input')))
            .controller!
            .text,
        'GFP',
      );
      expect(service.calls, 1, reason: '填入示例只恢复输入，不应自动发起新请求');
      expect(tester.takeException(), isNull);
    });

    testWidgets('空关键词不请求服务，提示仍然可见', (tester) async {
      final service = _FakeBioService((_, _) async => _response(const []));
      await _pumpLab(tester, service: service);
      await tester.tap(find.text('实时查询'));
      await tester.pumpAndSettle();

      expect(service.calls, 0);
      expect(find.text('请输入关键词，或先点一个示例。'), findsOneWidget);
      expect(find.byType(Card), findsNWidgets(18));
    });

    testWidgets('旧响应不会覆盖新查询', (tester) async {
      final first = Completer<BioSearchResponse>();
      final second = Completer<BioSearchResponse>();
      var call = 0;
      final service = _FakeBioService(
        (_, _) => call++ == 0 ? first.future : second.future,
      );
      await _pumpLab(tester, service: service);

      await tester.enterText(
        find.byKey(const Key('knowledge-search-input')),
        'EcoRI',
      );
      await tester.tap(find.text('实时查询'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('knowledge-search-input')),
        'Taq',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      second.complete(
        _response(<BioKnowledgeRecord>[
          kBioKnowledgeRecords.singleWhere((r) => r.id == 'P19821'),
        ]),
      );
      await tester.pumpAndSettle();
      first.complete(
        _response(<BioKnowledgeRecord>[
          kBioKnowledgeRecords.singleWhere((r) => r.id == 'P00642'),
        ]),
      );
      await tester.pumpAndSettle();

      final liveSection = find.text('实时结果');
      expect(liveSection, findsOneWidget);
      expect(
        find.descendant(of: find.byType(Card), matching: find.text('实时结果')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(Card), matching: find.text('P19821')),
        findsNWidgets(2),
        reason: '一条内置 Taq、一条实时 Taq',
      );
      expect(
        find.descendant(of: find.byType(Card), matching: find.text('P00642')),
        findsNothing,
        reason: '当前内置关键词是 Taq，迟到的 EcoRI 实时响应也必须被丢弃',
      );
    });

    testWidgets('isPristine 与 showInputs=false 遵循既有实验契约', (tester) async {
      final key = GlobalKey<KnowledgeLabState>();
      final service = _FakeBioService((_, _) async => _response(const []));
      await _pumpLab(tester, service: service, key: key, showInputs: false);
      expect(key.currentState!.isPristine, isTrue);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(Card), findsNWidgets(18));
    });

    testWidgets('390 窄屏长标题、URL、公式均零溢出', (tester) async {
      final service = _FakeBioService((_, _) async => _response(const []));
      await _pumpLab(tester, service: service, size: const Size(390, 3600));
      expect(tester.takeException(), isNull);
      expect(find.text('2OXV'), findsOneWidget);
      expect(find.byType(TexFormula), findsNWidgets(6));
    });
  });

  group('分子页接线', () {
    testWidgets('知识库可触达，原默认限制酶切不变', (tester) async {
      tester.view.physicalSize = const Size(1600, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: MolecularPage()));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('基因工程'));
      await tester.tap(find.text('基因工程'));
      await tester.pumpAndSettle();
      expect(find.text('计算切点与片段'), findsOneWidget);

      await tester.ensureVisible(find.text('知识库'));
      await tester.tap(find.text('知识库'));
      await tester.pumpAndSettle();
      expect(find.text('知识检索'), findsOneWidget);
      expect(find.text('实时查询'), findsOneWidget);
      expect(find.text('内置精选'), findsOneWidget);
      expect(find.text('计算切点与片段'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('PAM 练习在分子页可计算，单双位点切换后都保留结果', (tester) async {
      tester.view.physicalSize = const Size(1600, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _openKnowledgeOnPage(tester);

      expect(find.text('SpCas9 切割位置练习'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
      await tester.ensureVisible(find.text('上链 NGG 示例'));
      await tester.tap(find.text('上链 NGG 示例'));
      await tester.pumpAndSettle();
      expect(find.text('顶链第 22 位与第 23 位之间（两条链同一边界）'), findsOneWidget);

      await tester.ensureVisible(find.text('PCR 与电泳'));
      await tester.tap(find.text('PCR 与电泳'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('知识库'));
      await tester.tap(find.text('知识库'));
      await tester.pumpAndSettle();

      expect(find.text('顶链第 22 位与第 23 位之间（两条链同一边界）'), findsOneWidget);
      final input = find.byKey(const Key('cas9-sequence-input'));
      expect(
        tester.widget<TextField>(input).controller!.text,
        Cas9CutExerciseState.topExample,
      );

      const proto = 'ACGTACGTACGTACGTACGT';
      final sequence = '${'A' * 80}AGGCCT$proto';
      await tester.ensureVisible(input);
      await tester.tap(input);
      await tester.enterText(input, sequence);
      final compute = find.widgetWithText(FilledButton, '判断切割位置');
      await tester.ensureVisible(compute);
      await tester.tap(compute);
      await tester.pumpAndSettle();
      expect(find.text('找到 2 个可分析位点 · 双链共 2 个 NGG motif'), findsOneWidget);
      expect(find.byKey(const Key('cas9-site-panel-0')), findsOneWidget);
      expect(find.byKey(const Key('cas9-site-panel-1')), findsOneWidget);
      expect(find.text('顶链第 77 位与第 78 位之间（两条链同一边界）'), findsOneWidget);
      expect(find.text('顶链第 89 位与第 90 位之间（两条链同一边界）'), findsOneWidget);

      await tester.ensureVisible(find.text('PCR 与电泳'));
      await tester.tap(find.text('PCR 与电泳'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('知识库'));
      await tester.tap(find.text('知识库'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('cas9-site-panel-0')), findsOneWidget);
      expect(find.byKey(const Key('cas9-site-panel-1')), findsOneWidget);
      expect(find.text('顶链第 77 位与第 78 位之间（两条链同一边界）'), findsOneWidget);
      expect(find.text('顶链第 89 位与第 90 位之间（两条链同一边界）'), findsOneWidget);
      expect(tester.widget<TextField>(input).controller!.text, sequence);
      expect(tester.takeException(), isNull);
    });

    testWidgets('三个实验往返：知识检索词、BamHI 与 PCR 循环数都保住', (tester) async {
      tester.view.physicalSize = const Size(1600, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const MaterialApp(home: MolecularPage()));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('基因工程'));
      await tester.tap(find.text('基因工程'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('示例·BamHI 单位点'));
      await tester.tap(find.text('示例·BamHI 单位点'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('PCR 与电泳'));
      await tester.tap(find.text('PCR 与电泳'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('5 次'));
      await tester.tap(find.text('5 次'));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('知识库'));
      await tester.tap(find.text('知识库'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('knowledge-search-input')),
        'GFP',
      );
      await tester.pumpAndSettle();
      expect(find.byType(Card), findsNWidgets(3));

      await tester.ensureVisible(find.text('限制酶切'));
      await tester.tap(find.text('限制酶切'));
      await tester.pumpAndSettle();
      expect(find.textContaining('长度核算：3 + 7 = 10 bp'), findsOneWidget);

      await tester.ensureVisible(find.text('PCR 与电泳'));
      await tester.tap(find.text('PCR 与电泳'));
      await tester.pumpAndSettle();
      expect(find.text('2^5 = 32 份'), findsOneWidget);

      await tester.ensureVisible(find.text('知识库'));
      await tester.tap(find.text('知识库'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('knowledge-search-input')))
            .controller!
            .text,
        'GFP',
      );
      expect(find.byType(Card), findsNWidgets(3));
      expect(tester.takeException(), isNull);
    });

    testWidgets('390 页面内知识库选择器与内容零溢出', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _openKnowledgeOnPage(tester);
      expect(find.text('知识检索'), findsOneWidget);
      expect(find.text('内置精选'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
