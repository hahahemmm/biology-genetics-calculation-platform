// ai_chat_persist_queue_test.dart —— v2.19.57 落盘串行队列守卫
//
// 背景：local_secure_store.dart 头部记账的遗留弱化——聊天历史写盘曾
// 是 fire-and-forget，进程被杀可能丢本次写入；且 clearHistory 走
// AiChatStore.clear()、send 走 save()，两条独立异步链交错时旧快照可能
// 后落盘（历史复活）。v2.19.57 改为 [_persistQueue] 串行队列：
// 入队时刻快照定死内容，执行序 = 入队序 ⇒ 后写必然覆盖前写。
//
// 本文件钉住五条契约：
//   ① notify 早于落盘（调用同步返回时已发生）——气泡不被 KDF 卡住；
//   ② await 的 Future 仍代表落盘完成（真 IO 验证）；
//   ③ 串行：挂起的第一写未放行期间来的写必须排队，放行后磁盘 = 最后
//      一次写的快照（注入 sink 排成确定时序，不靠 PBKDF2 碰运气）；
//   ④ 清空与在飞 send 的写串行：清空排队的空快照先于后续写完成，
//      在飞请求完成后磁盘 = 当时的最新状态（历史不复活、也不丢回答）；
//   ⑤ 写失败可观测：不 await 的链（send）不外抛但记 lastPersistError；
//      await 的 clearHistory 拿到异常本身。
//   另附对照用例：不排队的两条独立链确实会让旧快照后落盘覆盖新状态，
//   证明 ③④ 的串行断言不是空跑。
//
// 注：send 的「未配置」分支（不注入 sender 时）是确定性写入源——
// 入口落盘后直接 return，没有网络悬停。
// ⚠️ 本文件无 widget 用例（面板有常驻 repeat() 呼吸动画，永不 settle）。

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:biology/services/ai_client.dart';
import 'package:biology/state/scan_bank_store.dart';
import 'package:biology/pages/settings_page.dart'
    show AiChatStore, AiSettingsStore;
import 'package:biology/services/local_secure_store.dart';
import 'package:biology/ui/ai_chat_controller.dart';

/// 一条落盘事件的记录辅助。
List<String> _flat(List<Map<String, String>> msgs) =>
    [for (final m in msgs) '${m['role']}:${m['text']}'];

/// 可控「磁盘」：记录每次写的开始/结束顺序与当前内容。
///
/// 前 [holdFirst] 次写会挂起，等测试 `releaseAll()`——把「KDF 快慢 /
/// resolve 先后」这一本来只能碰运气的时序排成确定时序。
class _ScriptedDisk {
  _ScriptedDisk({this.holdFirst = 1});

  int holdFirst;

  /// 事件流：`start#N` / `end#N`（N = 第几次写）。
  final List<String> events = [];

  /// 每次写的快照，按**开始**顺序。
  final List<List<Map<String, String>>> starts = [];

  /// 当前「磁盘」内容（= 最后一次**完成**的写）。
  List<Map<String, String>> content = const [];

  final List<Completer<void>> _gates = [];

  int get writesStarted => starts.length;

  Future<void> write(List<Map<String, String>> snapshot) async {
    final n = starts.length + 1;
    starts.add(snapshot);
    events.add('start#$n');
    if (n <= holdFirst) {
      final g = Completer<void>();
      _gates.add(g);
      await g.future;
      _gates.remove(g);
    }
    content = snapshot; // 只有跑完才算落盘
    events.add('end#$n');
  }

  void releaseAll() {
    for (final g in _gates.toList()) {
      g.complete();
    }
  }
}

Future<void> _drainMicrotasks([int rounds = 8]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// 等到条件满足或轮数耗尽（轮询式，FakeAsync 安全）。
Future<void> _until(bool Function() cond, [int maxRounds = 100]) async {
  for (var i = 0; i < maxRounds && !cond(); i++) {
    await _drainMicrotasks(2);
  }
  expect(cond(), isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late AiChatController ctrl;
  late _ScriptedDisk disk;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('v21957_persist_queue');
    AiChatStore.debugFilePath = '${tmp.path}/ai_chat_history.json';
    AiChatStore.debugForceIsWebStorage = false;
    // sendScan 成功后会自动入库——不收进临时目录就会脏写真实用户目录。
    ScanBankStore.debugFilePath = '${tmp.path}/scan_bank.json';
    // 未配置前提：内置 MiniMax key 让 AiConfig.fromEnv() 恒返回已配置，
    // 而本文件的确定性写入源是 send 的「尚未配置」分支——显式钉死。
    AiSettingsStore.debugConfig = const AiConfig(apiKey: '');
    LocalSecureStore.debugResetHooks();
    LocalSecureStore.debugMachineKeyPath = '${tmp.path}/.machine.key';
    ctrl = AiChatController.instance..reset();
    // 单例的落盘队列跨用例存活：上一例若没收口，先丢弃残留再开跑，
    // 否则本例的第一次写会排在死 job 后面（表现为「sink 从未被调用」）。
    ctrl.debugResetPersistQueue();
    AiChatController.debugResetHooks();
    ctrl.lastPersistError = null;
    disk = _ScriptedDisk();
    AiChatController.debugPersistSink = disk.write;
  });

  tearDown(() async {
    disk.releaseAll();
    // 收敛判据用**同步**的 debugPersistIdle，而不是 await debugWaitPersistIdle()：
    // tearDown 跑在真实区域，等 FakeAsync 区域创建的 Completer 可能永不动。
    for (var i = 0; i < 100 && !ctrl.debugPersistIdle; i++) {
      await _drainMicrotasks(4);
    }
    AiChatController.debugPersistSink = null;
    ctrl.debugSender = null;
    ctrl.debugScanSender = null;
    AiSettingsStore.debugConfig = null;
    AiChatStore.debugFilePath = null;
    AiChatStore.debugForceIsWebStorage = null;
    ScanBankStore.debugFilePath = null;
    ctrl.reset();
    ctrl.debugResetPersistQueue();
    await tmp.delete(recursive: true).catchError((_) => Directory(''));
  });

  group('① notify 早于落盘（UI 不被写盘卡住）', () {
    test('send 调用后 notify 先于落盘完成发生', () async {
      disk.holdFirst = 1; // 挂住第一写，把「notify 已发生 / 写未完成」切成可断言态。
      var notifies = 0;
      ctrl.addListener(() => notifies++);
      // 未配置分支：不注入 sender，走「尚未配置」路径（也落盘）。
      final future = ctrl.send('你好');
      // send 体内首个 await 是 AiSettingsStore.load()——notify 在微任务
      // 批次里发生，轮询等到它。
      await _until(() => notifies > 0);
      // 关键判据：notify 已发生，而本次写被挂起未完成（气泡不被写盘卡住）。
      expect(disk.content, isEmpty, reason: 'notify 时磁盘必须还没写');
      expect(disk.events, ['start#1'], reason: '写可以 start，但不能 end');
      disk.releaseAll();
      await future;
      await ctrl.debugWaitPersistIdle();
      expect(_flat(disk.content).first, 'user:你好');
      expect(ctrl.lastPersistError, isNull);
    });
  });

  group('② await Future = 落盘完成（真 IO）', () {
    test('clearHistory 返回前文件已为空（真 sink，无注入）', () async {
      AiChatController.debugPersistSink = null; // 走真 AiChatStore.save
      ctrl.messages.add(const AiChatMessage('user', '旧问题'));
      await ctrl.clearHistory();
      expect(ctrl.debugPersistIdle, isTrue);
      final onDisk = await AiChatStore.load();
      expect(onDisk, isEmpty, reason: 'await 返回时清空必须已落盘');
    });
  });

  group('③ 串行队列：后写必然覆盖前写', () {
    test('挂起写未放行期间来的写必须排队，放行后磁盘 = 最后写', () async {
      final writesBase = ctrl.debugPersistWrites;
      // send 未配置分支：messages=[user, assistant 提示] → notify →
      // await 落盘（写①）→ return。写①内容非空（两条消息）。
      final sendFuture = ctrl.send('第一条问题');
      await _until(() => disk.events.isNotEmpty);
      expect(disk.events, ['start#1']);
      // 写①挂起期间清空历史：空快照排为写②，但必须等写①完成才 start。
      final clearFuture = ctrl.clearHistory();
      expect(disk.writesStarted, 1,
          reason: '串行：写①未放行时写②不能 start');
      disk.releaseAll();
      await Future.wait([sendFuture, clearFuture]);
      await ctrl.debugWaitPersistIdle();
      expect(disk.events, ['start#1', 'end#1', 'start#2', 'end#2'],
          reason: '写必须按入队序 start→end 完成，无交错');
      expect(_flat(disk.content), isEmpty,
          reason: '最后完成的是清空写，磁盘必须为空');
      // debugPersistWrites 是单例累计值（跨用例不清零），用差值断言本用例。
      expect(ctrl.debugPersistWrites - writesBase, 2);
    });

    test('快照在入队时刻定死：写执行时读不到后来的内存状态', () async {
      final sendFuture = ctrl.send('入队时的消息');
      await _until(() => disk.events.isNotEmpty);
      // 写①已 start 并挂起。此刻清空历史（排写②，快照 = []），
      // 再**直接改内存**不入队——写②开始执行时内存里已有一条新消息，
      // 若实现是「写时才回读」，写②会带上它；入队冻结则必须仍写 []。
      expect(disk.starts.single.length, 2,
          reason: '未配置分支入队时已有 user+assistant 两条');
      expect(disk.starts.single.first['text'], '入队时的消息');
      final clearFuture = ctrl.clearHistory();
      ctrl.messages.add(const AiChatMessage('user', '入队后的新消息'));
      disk.releaseAll();
      await Future.wait([sendFuture, clearFuture]);
      await ctrl.debugWaitPersistIdle();
      expect(disk.content, isEmpty,
          reason: '写②快照在入队时刻冻结为 []，执行时不得回读内存');
    });

    test('对照：不排队的两条独立链确实会复活（守卫非空跑）', () {
      // 手写「v2.19.57 之前」的形态：两个写互不等待，靠闸门让旧快照
      // 后落盘。证明上面两条用例的断言真的能区分两种实现。
      final oldSnapshot = [
        {'role': 'user', 'text': '旧消息'}
      ];
      final oldGate = Completer<void>();
      List<Map<String, String>>? diskContent = <Map<String, String>>[];
      // 旧链：先发后至（先 start、后 end）。
      final oldChain = () async {
        await oldGate.future;
        diskContent = oldSnapshot; // 旧快照后落盘
      }();
      // 新链（清空）：立刻完成。
      diskContent = <Map<String, String>>[];
      oldGate.complete();
      // 同步驱动旧链到结束再断言。
      return oldChain.then((_) {
        expect(diskContent, oldSnapshot,
            reason: '不排队时旧快照确实后落盘覆盖新状态——对照成立');
      });
    });
  });

  group('④ 清空与在飞 send 串行：历史不复活', () {
    test('send 网络悬停期间清空，完成后回答入列、磁盘 = 最新状态', () async {
      // debugSender 非空时 send 跳过配置检查（源码契约）。
      final gate = Completer<AiResult>();
      ctrl.debugSender = (_) => gate.future;
      final sendFuture = ctrl.send('悬停的问题');
      await _until(() => ctrl.busy);
      // 此刻 send 已完成入口落盘（写①）并停在 sender 门前。
      await _until(() => disk.writesStarted >= 1);
      // 请求在飞：用户清空历史（可达时序——面板清空不锁 busy）。
      // 注意不能 await clearHistory：写②排在写①后，而写①此刻被 disk
      // 闸门挂起——await 会死锁。先拿 Future，统一放行后再等。
      final clearFuture = ctrl.clearHistory();
      expect(ctrl.messages, isEmpty, reason: '清内存必须立刻生效');
      expect(disk.writesStarted, 1,
          reason: '写①被挂起期间写②不能 start');
      // 先放行磁盘闸门（写①→写②），再放行 sender 闸门（send 追加回答）。
      disk.releaseAll();
      gate.complete(const AiResult.ok('回答内容'));
      await Future.wait([sendFuture, clearFuture]);
      await ctrl.debugWaitPersistIdle();
      expect(disk.events, [
        'start#1', 'end#1', // 写①：send 入口（[user]）
        'start#2', 'end#2', // 写②：清空（[]）
        'start#3', 'end#3', // 写③：send 收尾（[assistant]）
      ], reason: '三写按入队序完成，无交错');
      // 清空后完成的回答仍应入列（它发生在清空之后 = 最新状态），
      // 且 send 途中清空不抛 RangeError（history 构造 max(0,…) 夹取）。
      expect(ctrl.messages.length, 1);
      expect(ctrl.messages.single.text, '回答内容');
      expect(_flat(disk.content), ['assistant:回答内容'],
          reason: '磁盘 = 最后一次写的快照（清空后到达的回答）');
    });
  });

  group('⑤ 写失败可观测', () {
    test('不 await 的链（send）不外抛，但记 lastPersistError', () async {
      disk.holdFirst = 0;
      AiChatController.debugPersistSink =
          (_) async => throw StateError('磁盘满');
      // send 走「未配置」分支也会落盘——调用点不 await。
      final future = ctrl.send('会写失败的问题');
      await future; // send 本身完成（异常被 _persistLogged 吞掉）
      await ctrl.debugWaitPersistIdle();
      expect(ctrl.lastPersistError, contains('历史未能持久化'),
          reason: '失败必须记账，不能静默');
      expect(ctrl.lastPersistError, contains('磁盘满'));
    });

    test('await 的 clearHistory 拿到异常本身', () async {
      AiChatController.debugPersistSink =
          (_) async => throw StateError('权限拒绝');
      Object? caught;
      try {
        await ctrl.clearHistory();
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<StateError>(),
          reason: 'clearHistory 的 Future 必须以异常结束（写失败可观测）');
      expect(ctrl.lastPersistError, contains('权限拒绝'));
    });
  });

  // ⑥ 守卫的是**真实 store 的抛错契约**（生产路径）：⑤ 注入 sink 只证
  // 明了队列层会把 sink 的异常往后传；若 AiChatStore.save 自己把写盘
  // 异常吞掉（v2.19.57 之前的形态），生产里 sink 永不抛 ⇒ 队列把失败
  // 当成功 ⇒ lastPersistError 永远 null、clearHistory 永远「成功」。
  // 这里不注入 sink，把 debugFilePath 指到「父路径被同名文件占住」的
  // 非法位置——LocalSecureStore._atomicReplace 的 createSync 必抛
  // FileSystemException——断言异常真的穿过真实 save() 到达调用方。
  group('⑥ 真实 AiChatStore.save 失败传播（不注入 sink）', () {
    test('clearHistory 经真实 save 失败时 Future 以异常结束 + 记账', () async {
      AiChatController.debugPersistSink = null; // 走真 AiChatStore.save
      final blocker = File('${tmp.path}/blocker')..createSync();
      AiChatStore.debugFilePath = '${blocker.path}/ai_chat_history.json';
      Object? caught;
      try {
        await ctrl.clearHistory();
      } catch (e) {
        caught = e;
      }
      expect(caught, isNotNull,
          reason: '真实写失败必须穿过 AiChatStore.save 到达 await 调用方'
              '（save 若吞错，此处 caught 恒 null，守卫变红）');
      expect(ctrl.lastPersistError, contains('历史未能持久化'),
          reason: '失败必须记账，不能静默');
    });

    test('send 经真实 save 失败：调用本身不抛，但记账且无成功写', () async {
      AiChatController.debugPersistSink = null;
      final writesBase = ctrl.debugPersistWrites;
      final blocker = File('${tmp.path}/blocker')..createSync();
      AiChatStore.debugFilePath = '${blocker.path}/ai_chat_history.json';
      // send 的落盘是 fire-and-forget（_persistLogged 吞 + 记账）。
      final future = ctrl.send('写不进磁盘的问题');
      await future;
      await ctrl.debugWaitPersistIdle();
      expect(ctrl.lastPersistError, contains('历史未能持久化'),
          reason: '真实失败同样要记账');
      expect(ctrl.debugPersistWrites - writesBase, 0,
          reason: '失败写不得计入成功次数');
    });
  });
}
