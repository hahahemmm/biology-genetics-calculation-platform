// ai_tools.dart —— AI 可调用的工具层（v2.24，OpenAI function calling）
//
// 为什么存在：模型心算遗传比例会错。punnett_cross 把具体基因型 / 比例题交给
// lib/engine/cross_engine.dart 的确定性引擎；web_search / fetch_url 用来查
// 学科通行的术语表述与真题出处；run_python / run_shell 用于数值验证与本软件相关诊断
// （默认关闭，开关见 AiToolSettings）。
//
// 纪律：
//   - schemas() 只列出**当前真的可用**的工具（设置开关 + 解释器探测 + 通道）。
//   - call() 永不抛异常：任何失败都转成中文短句返回，让模型自己改参数。
//   - 返回值里不得出现 apiKey；错误文本统一过 redactSensitive。
//   - 本文件直接用 dart:io（Process / File）：桌面与安卓走真实进程，
//     Web 端由 kIsWeb 短路（探测恒 null，相关工具不出现）。仓库里
//     history_store / mistake_book 等同样直接 import dart:io 并靠 kIsWeb
//     分支，沿用同一约定，不另拆条件导入。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:http/http.dart' as http;

import '../engine/cross_engine.dart';
import '../state/ai_tool_settings.dart';
import 'ai_client.dart';

/// 执行工具时的宿主环境。
///
/// 一个 host 对应一轮对话：config 决定联网工具走哪个通道，settings 决定
/// 哪些工具被允许，[confirm] 是危险操作前的人工确认钩子。
class AiToolHost {
  AiToolHost({
    required this.config,
    required this.settings,
    this.confirm,
    this.pythonExe,
    this.shellExe,
  });

  final AiConfig config;
  final AiToolSettings settings;

  /// 危险操作（run_python / run_shell）前的人工确认：返回 true 才继续。
  /// 未注入时以 [settings] 的开关本身作为用户授权（UI 接入时必须传）。
  final Future<bool> Function(String title, String detail)? confirm;

  /// 测试注入：非空时跳过自动探测。
  final String? pythonExe;
  final String? shellExe;

  /// 探测结果静态缓存：同一进程只探一次，之后直接复用 Future。
  static Future<String?>? _pythonProbe;
  static Future<String?>? _shellProbe;

  /// 探测本机 Python 解释器（命中返回可执行名，未命中返回 null）。
  ///
  /// Windows 顺序：`python` → `py -3`；其它平台：`python3` → `python`。
  /// 判据：exitCode 0 且输出含 "Python"（排除微软商店的占位 stub）。
  static Future<String?> detectPython() => _pythonProbe ??= _probePython();

  /// 探测本机命令行（Windows：pwsh → powershell；其它平台：/bin/sh）。
  static Future<String?> detectShell() => _shellProbe ??= _probeShell();

  static Future<String?> _probePython() async {
    // Web 端没有进程：直接判定不可用（也避免 dart:io 在浏览器里抛错）。
    if (kIsWeb) return null;
    // flutter test 环境不探子进程：既避免每次跑测试都拉两个 shell，
    // 也避免真实异步在 FakeAsync 里悬空导致 pumpAndSettle 不收敛。
    if (Platform.environment['FLUTTER_TEST'] == 'true') return null;
    final candidates = <(String, List<String>)>[
      if (Platform.isWindows) ...[
        ('python', const <String>[]),
        ('py', const <String>['-3']),
      ] else ...[
        ('python3', const <String>[]),
        ('python', const <String>[]),
      ],
    ];
    for (final (exe, pre) in candidates) {
      try {
        final r = await Process.run(
          exe,
          [...pre, '-V'],
        ).timeout(const Duration(seconds: 8));
        // ProcessResult 没有可读的 toString，版本号只能从 stdout/stderr 取。
        final text = '${r.stdout}${r.stderr}';
        if (r.exitCode == 0 && text.toLowerCase().contains('python')) {
          return exe;
        }
      } catch (_) {
        // 该候选不存在 / 超时：试下一个。
      }
    }
    return null;
  }

  static Future<String?> _probeShell() async {
    if (kIsWeb) return null;
    if (Platform.environment['FLUTTER_TEST'] == 'true') return null;
    if (!Platform.isWindows) {
      return File('/bin/sh').existsSync() ? '/bin/sh' : null;
    }
    for (final exe in const ['pwsh', 'powershell']) {
      try {
        final r = await Process.run(
          exe,
          const ['-NoProfile', '-NonInteractive', '-Command', 'exit 0'],
        ).timeout(const Duration(seconds: 10));
        if (r.exitCode == 0) return exe;
      } catch (_) {
        // 未安装 / 超时：试下一个。
      }
    }
    return null;
  }

  /// 给 chat/completions 的 tools 数组（只包含当前真正可用的工具）。
  Future<List<Map<String, dynamic>>> schemas() async {
    final out = <Map<String, dynamic>>[_punnettSchema];
    if (_webReady) {
      out.add(_webSearchSchema);
      out.add(_fetchSchema);
    }
    if (settings.python && await _python() != null) out.add(_pythonSchema);
    if (settings.shell && await _shell() != null) out.add(_shellSchema);
    return out;
  }

  /// 执行一次工具调用，返回给模型的文本结果（永不抛异常）。
  Future<String> call(String name, Map<String, dynamic> args) async {
    try {
      switch (name) {
        case 'punnett_cross':
          return _punnett(args);
        case 'web_search':
          return await _webSearch(args);
        case 'fetch_url':
          return await _fetchUrl(args);
        case 'run_python':
          return await _runPython(args);
        case 'run_shell':
          return await _runShell(args);
        default:
          return '参数错误：未知工具 $name';
      }
    } catch (e) {
      return '工具执行失败：${redactSensitive(_shortReason(e), maxLength: 200)}';
    }
  }

  // ---------- punnett_cross ----------

  String _punnett(Map<String, dynamic> args) {
    final p1 = _str(args['p1']);
    final p2 = _str(args['p2']);
    if (p1 == null || p2 == null) {
      return '参数错误：p1 与 p2 必须是非空基因型字符串（如 "Aa"、"AaBb"）';
    }
    final kind = _str(args['kind']) ?? 'single';
    if (kind != 'single' && kind != 'dihybrid') {
      return '参数错误：kind 只能是 single 或 dihybrid';
    }
    final modName = _str(args['modification']) ?? 'complete';
    final mod = _modificationOf(modName);
    if (mod == null) {
      return '参数错误：modification 只能是 complete / incomplete / codominant / '
          'lethalDominant / lethalRecessive';
    }


    // 引擎把基因型逐字符当等位基因：长度不对会算出一堆无意义结果，
    // 双基因少一位还会 RangeError（被 call() 兜成「工具执行失败」，
    // 模型拿不到可纠正的提示）。这里先挡住并说清格式。
    final wantLen = kind == 'single' ? 2 : 4;
    for (final g in <String>[p1, p2]) {
      final letters = g.replaceAll(RegExp(r'[^A-Za-z]'), '');
      if (letters.length != wantLen) {
        return '参数错误：${kind == 'single' ? '单基因' : '双基因'}的基因型必须正好 '
            '$wantLen 个字母（例：${kind == 'single' ? 'Aa' : 'AaBb'}），收到 "$g"';
      }
      // 同一对位点必须是同一字母的大小写两态（Aa、Bb）；写成 AB 会被
      // 引擎当成两个不同的等位基因，比例看着像对的，其实没有意义。
      for (var i = 0; i < wantLen; i += 2) {
        if (letters[i].toUpperCase() != letters[i + 1].toUpperCase()) {
          return '参数错误："$g" 的第 ${i ~/ 2 + 1} 对位点必须是同一字母的'
              '大小写形态（如 Aa），不能是 ${letters[i]}${letters[i + 1]}';
        }
      }
    }
    // 两个亲本必须描述同一组位点：Aa x Bb 的每一对都合法，但合起来是
    // 两个不同的基因，引擎照样算出 3:1——输出看着像答案，其实无意义。
    // 复用 _dominantLettersOf 做「大写 + 去重 + 忽略顺序」的集合比较。
    final loci1 = _dominantLettersOf(p1, 26).toSet();
    final loci2 = _dominantLettersOf(p2, 26).toSet();
    if (loci1.length != loci2.length || !loci1.containsAll(loci2)) {
      return '参数错误：两个亲本必须描述同一对（或两对）位点，'
          'p1="$p1" 与 p2="$p2" 不是同一个基因';
    }
    final engine = CrossEngine();
    final CrossResult r;
    final String head;
    if (kind == 'single') {
      // 字母必须从输入里推：引擎判表型靠「基因型里是否含显性/隐性字母」
      // （见 cross_engine 的 _phenotypeFor），写死 A/a 会让 Bb × Bb、
      // DdEe × DdEe 全落进显性分支，输出「显性 4/4」这种错答案。
      final letters = _dominantLettersOf('$p1$p2', 1);
      final dominant = letters.isEmpty ? 'A' : letters.first;
      r = engine.singleGeneCross(
        p1,
        p2,
        dominant: dominant,
        recessive: dominant.toLowerCase(),
        modification: mod,
      );
      head = '单基因（$modName）';
    } else {
      // 双基因引擎没有修饰模型参数，只按完全显性统计。
      // 两个位点的显性字母同样取自 p1 的字母顺序，缺失时补齐 A / B。
      final letters = _dominantLettersOf(p1, 2);
      final locus1 = letters.isNotEmpty ? letters[0] : 'A';
      final locus2 = letters.length > 1 ? letters[1] : 'B';
      r = engine.dihybridCross(
        p1,
        p2,
        locus1Dominant: locus1,
        locus1Recessive: locus1.toLowerCase(),
        locus2Dominant: locus2,
        locus2Recessive: locus2.toLowerCase(),
      );
      head = '双基因（完全显性）';
    }

    final b = StringBuffer()
      ..writeln('杂交类型：$head')
      ..writeln('亲本：$p1 × $p2')
      ..writeln('配子：${r.gametesP1.join('/')} × ${r.gametesP2.join('/')}');
    b.write('基因型比例（合计 ${r.totalGenotype}）：');
    b.writeln(r.genotypeRatios
        .map((g) => '${g.genotype} ${_frac(g.count, r.totalGenotype)}')
        .join('，'));
    b.write('表型比例（合计 ${r.totalPhenotype}）：');
    b.write(r.phenotypeRatios
        .map((p) => '${p.phenotype} ${_frac(p.count, r.totalPhenotype)}')
        .join('，'));
    if (kind == 'dihybrid' && modName != 'complete') {
      b.write('\n注：双基因模式不支持修饰模型，本结果按完全显性计算。');
    }
    return b.toString();
  }

  /// 从基因型字符串里按出现顺序取前 [max] 个不重复的字母，统一转大写，
  /// 作为显性字母。为什么按顺序而不是写死：学生的题用 D/E、R/r 等字母的
  /// 情况很常见，只有跟着输入走，引擎的表型判定才对得上基因型。
  /// 只要 ASCII 字母（跳过空格、× 等杂字符），取不到时返回空列表由调用处补齐。
  static List<String> _dominantLettersOf(String text, int max) {
    final out = <String>[];
    for (final ch in text.split('')) {
      final up = ch.toUpperCase();
      final code = up.length == 1 ? up.codeUnitAt(0) : 0;
      if (code < 0x41 || code > 0x5A) continue;
      if (out.contains(up)) continue;
      out.add(up);
      if (out.length == max) break;
    }
    return out;
  }

  static Modification? _modificationOf(String n) {
    switch (n) {
      case 'complete':
        return Modification.completeDominance;
      case 'incomplete':
        return Modification.incompleteDominance;
      case 'codominant':
        return Modification.codominance;
      case 'lethalDominant':
        return Modification.lethalDominant;
      case 'lethalRecessive':
        return Modification.lethalRecessive;
      default:
        return null;
    }
  }

  // ---------- web_search / fetch_url ----------

  /// 联网工具是否可用：开关打开 + DeepSeek 通道 + 有 key（tools 接口
  /// 只走这条通道，其它通道没有 /tools 端点）。
  bool get _webReady =>
      settings.web &&
      config.provider == AiConfig.providerDeepSeek &&
      config.apiKey.isNotEmpty;

  /// 工具基址：baseUrl 已带 /v1 就只补 /tools，否则补 /v1/tools。
  /// 例：https://api.deepseek.com → https://api.deepseek.com/v1/tools
  String get _toolsBase {
    var base = config.baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return base.endsWith('/v1') ? '$base/tools' : '$base/v1/tools';
  }

  Future<String> _webSearch(Map<String, dynamic> args) async {
    if (!_webReady) {
      return '参数错误：web_search 当前不可用（联网工具已关闭或当前通道不支持）';
    }
    final query = _str(args['query']);
    if (query == null) return '参数错误：query 必须是非空字符串';
    final rawCount = args['count'];
    var count = 5;
    if (rawCount != null) {
      if (rawCount is! num) return '参数错误：count 必须是整数';
      count = rawCount.toInt().clamp(1, 20);
    }

    final (status, raw) = await _post('$_toolsBase/tools/search', {
      'query': query,
      'count': count,
      'need_content': true,
    });
    if (status != 200) {
      return '搜索失败（HTTP $status）：${redactSensitive(raw, maxLength: 200)}';
    }
    final results = _decode(raw)?['results'];
    if (results is! List || results.isEmpty) return '没有搜到结果（query=$query）';

    final b = StringBuffer();
    var n = 0;
    for (final e in results) {
      if (n >= 5) break; // 只喂前 5 条，避免上下文被搜索结果灌满
      if (e is! Map) continue;
      n++;
      final title = _str(e['title']) ?? '（无标题）';
      final url = _str(e['url']) ?? '';
      final summary = _str(e['summary']) ?? _str(e['snippet']) ?? '';
      b.writeln('[$n] $title');
      if (url.isNotEmpty) b.writeln(url);
      if (summary.isNotEmpty) b.writeln(_clip(summary, 600));
      b.writeln();
    }
    return _clip(b.toString().trim(), 6000);
  }

  Future<String> _fetchUrl(Map<String, dynamic> args) async {
    if (!_webReady) {
      return '参数错误：fetch_url 当前不可用（联网工具已关闭或当前通道不支持）';
    }
    final url = _str(args['url']);
    if (url == null) return '参数错误：url 必须是非空字符串';
    final uri = Uri.tryParse(url);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return '参数错误：url 必须是 http(s) 地址';
    }

    final (status, raw) = await _post('$_toolsBase/tools/fetch', {'url': url});
    if (status != 200) {
      return '抓取失败（HTTP $status）：${redactSensitive(raw, maxLength: 200)}';
    }
    final j = _decode(raw);
    if (j == null) return '抓取失败：响应不是有效 JSON';
    final title = _str(j['title']) ?? '';
    final content = _str(j['content']) ?? '';
    if (title.isEmpty && content.isEmpty) return '抓取失败：正文为空';
    return _clip(title.isEmpty ? content : '$title\n$content', 6000);
  }

  /// POST 一次 tools 接口，返回 (状态码, 响应体)。超时 20s。
  Future<(int, String)> _post(String url, Map<String, dynamic> body) async {
    final res = await http
        .post(
          Uri.parse(url),
          headers: {
            'Content-Type': 'application/json; charset=utf-8',
            'Authorization': 'Bearer ${config.apiKey}',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 20));
    return (res.statusCode, res.body);
  }

  static Map<String, dynamic>? _decode(String raw) {
    try {
      final j = jsonDecode(raw);
      return j is Map ? Map<String, dynamic>.from(j) : null;
    } catch (_) {
      return null;
    }
  }

  // ---------- run_python / run_shell ----------

  Future<String> _runPython(Map<String, dynamic> args) async {
    // 开关是硬闸：schema 没列出来不代表模型不会硬调。
    if (!settings.python) {
      return '参数错误：run_python 未启用（需用户先在设置里打开「允许 AI 执行本机 Python」）';
    }
    final script = _str(args['code']);
    if (script == null) return '参数错误：code 必须是非空字符串';
    final exe = await _python();
    if (exe == null) return '工具执行失败：本机未探测到 Python 解释器';

    final approved =
        confirm == null ? true : await confirm!('运行 Python 代码', script);
    if (!approved) return '用户拒绝执行该代码';

    final tmpDir = Directory.systemTemp;
    final sep = Platform.pathSeparator;
    final name = 'biology_ai_'
        '${DateTime.now().microsecondsSinceEpoch}_'
        '${Random().nextInt(0xFFFFFF).toRadixString(16)}.py';
    final file = File('${tmpDir.path}$sep$name');
    try {
      await file.writeAsString(script, encoding: utf8);
      final r = await _runProcess(
        exe,
        [..._pythonPreArgs(exe), file.path],
        tmpDir.path,
        const Duration(seconds: 10),
      );
      if (r == null) return '执行超时（10 秒），已终止';
      final (code, out, err) = r;
      return _clip('exit=$code\nstdout:\n$out\nstderr:\n$err', 4000);
    } finally {
      // 临时脚本必删（含异常路径），避免把模型生成的代码留在盘上。
      try {
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
    }
  }

  Future<String> _runShell(Map<String, dynamic> args) async {
    if (!settings.shell) {
      return '参数错误：run_shell 未启用（需用户先在设置里打开「允许 AI 执行本机命令行」）';
    }
    final command = _str(args['command']);
    if (command == null) return '参数错误：command 必须是非空字符串';
    final exe = await _shell();
    if (exe == null) return '工具执行失败：本机未探测到可用命令行';

    final approved =
        confirm == null ? true : await confirm!('执行命令行', command);
    if (!approved) return '用户拒绝执行该命令';

    // 工作目录固定系统临时目录：绝不能是应用数据目录，否则模型一条
    // 递归删除就可能抹掉用户的错题本 / 配置。
    final r = await _runProcess(
      exe,
      _shellArgs(exe, command),
      Directory.systemTemp.path,
      const Duration(seconds: 15),
    );
    if (r == null) return '执行超时（15 秒），已终止';
    final (code, out, err) = r;
    return _clip('exit=$code\n$out\n$err', 4000);
  }

  /// 起进程收 stdout / stderr；超时则 sigkill 并返回 null。
  Future<(int, String, String)?> _runProcess(
    String exe,
    List<String> args,
    String workDir,
    Duration limit,
  ) async {
    final p = await Process.start(
      exe,
      args,
      workingDirectory: workDir,
      runInShell: false,
    );
    // 两个流必须同时开读：只读一个时，另一个管道写满缓冲区会让子进程
    // 卡在 write 上一直等到超时（原 join 版也是并行，这里保持并行）。
    final outF = _collectBounded(p.stdout, _streamLimit);
    final errF = _collectBounded(p.stderr, _streamLimit);
    final int code;
    try {
      code = await p.exitCode.timeout(limit);
    } on TimeoutException {
      p.kill(ProcessSignal.sigkill);
      // 被 kill 后管道可能还挂着尾巴：限时收干净，不让 future 悬空。
      try {
        await Future.wait([outF, errF]).timeout(const Duration(seconds: 2));
      } catch (_) {}
      return null;
    }
    final (out, outCut) = await outF;
    final (err, errCut) = await errF;
    // 截断标记只进诊断日志：最终文本仍按 4000 字裁剪，模型看到的
    // 「已截断」由 _clip 给出，这里再贴一行只会挤掉正文。
    if (outCut || errCut) {
      debugPrint('ai_tools._runProcess: 输出超过 $_streamLimit 字已截断'
          '（stdout=$outCut, stderr=$errCut）');
    }
    return (code, out, err);
  }

  /// 单个输出流的内存上限（字符）。喂给模型的文本另按 4000 字裁剪。
  static const int _streamLimit = 20000;

  /// 边读边截：超过 [limit] 字符后继续 drain（不阻塞子进程写），但不再累积。
  /// 返回 (已保留文本, 是否截断)。
  ///
  /// 为什么不能 transform(...).join()：那会先把子进程的全部输出收进内存
  /// 再截 4000 字，一段 while True: print(...) 十秒就能吃光内存。
  /// 超过上限后仍要读到流结束——管道不读空，子进程写满缓冲区就卡在
  /// write 上等不到 exitCode，只会变成一次假的「执行超时」。
  static Future<(String, bool)> _collectBounded(
    Stream<List<int>> s,
    int limit,
  ) async {
    final kept = StringBuffer();
    var chars = 0;
    var cut = false;
    // allowMalformed：超时被 kill 时管道尾部可能是半个多字节字符，
    // 默认解码器会抛 FormatException，把一次正常超时变成「工具执行失败」。
    final text = s.transform(const Utf8Decoder(allowMalformed: true));
    await for (final chunk in text) {
      if (chars >= limit) {
        cut = true;
        continue; // 继续读、不再存：既限内存，又不让子进程卡在管道上
      }
      final room = limit - chars;
      if (chunk.length <= room) {
        kept.write(chunk);
        chars += chunk.length;
      } else {
        kept.write(chunk.substring(0, room));
        chars = limit;
        cut = true;
      }
    }
    return (kept.toString(), cut);
  }

  /// Windows 的 `py` 启动器要 `-3` 指定 Python 3（探测时用的同一组参数）。
  static List<String> _pythonPreArgs(String exe) {
    final lower = exe.toLowerCase();
    if (Platform.isWindows &&
        (lower == 'py' || lower.endsWith('py.exe') || lower.endsWith('\\py'))) {
      return const ['-3'];
    }
    return const [];
  }

  /// PowerShell 走 -Command，其它 shell 走 -c。
  static List<String> _shellArgs(String exe, String command) {
    final lower = exe.toLowerCase();
    if (lower.endsWith('pwsh') ||
        lower.endsWith('pwsh.exe') ||
        lower.endsWith('powershell') ||
        lower.endsWith('powershell.exe')) {
      return ['-NoProfile', '-NonInteractive', '-Command', command];
    }
    return ['-c', command];
  }

  Future<String?> _python() async => pythonExe ?? await detectPython();

  Future<String?> _shell() async => shellExe ?? await detectShell();

  // ---------- 小工具 ----------

  static String? _str(Object? v) {
    if (v is! String) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  /// 约分后的分数（如 2/4 → 1/2）。
  static String _frac(int count, int total) {
    if (total <= 0) return '$count';
    final g = _gcd(count.abs(), total);
    return '${count ~/ g}/${total ~/ g}';
  }

  static int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);

  static String _clip(String s, int max) => s.length <= max
      ? s
      : '${s.substring(0, max)}…(已截断，原文 ${s.length} 字)';

  static String _shortReason(Object e) =>
      e.toString().replaceAll(RegExp(r'\s+'), ' ').trim();

  // ---------- schema（OpenAI function calling） ----------

  static const Map<String, dynamic> _punnettSchema = {
    'type': 'function',
    'function': {
      'name': 'punnett_cross',
      'description':
          '用本软件的确定性遗传引擎计算杂交配子与基因型/表型比例。凡是涉及具体'
              '亲本基因型、比例、概率的题，必须先用这个工具算，不要自己心算。',
      'parameters': {
        'type': 'object',
        'properties': {
          'p1': {
            'type': 'string',
            'description': '亲本 1 基因型，如 Aa、aa、AaBb',
          },
          'p2': {
            'type': 'string',
            'description': '亲本 2 基因型',
          },
          'kind': {
            'type': 'string',
            'enum': ['single', 'dihybrid'],
            'description': 'single=单基因（默认），dihybrid=双基因独立分配',
          },
          'modification': {
            'type': 'string',
            'enum': [
              'complete',
              'incomplete',
              'codominant',
              'lethalDominant',
              'lethalRecessive',
            ],
            'description': '修饰模型，默认 complete（仅单基因模式生效）',
          },
        },
        'required': ['p1', 'p2'],
      },
    },
  };

  static const Map<String, dynamic> _webSearchSchema = {
    'type': 'function',
    'function': {
      'name': 'web_search',
      'description': '联网搜索。用于查学科通行的术语表述与题目出处、最新资料。搜到的内容要用引用链接标注。',
      'parameters': {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': '搜索词'},
          'count': {
            'type': 'integer',
            'description': '返回条数，默认 5，范围 1-20',
          },
        },
        'required': ['query'],
      },
    },
  };

  static const Map<String, dynamic> _fetchSchema = {
    'type': 'function',
    'function': {
      'name': 'fetch_url',
      'description': '抓取指定网页并转成 Markdown 正文。配合 web_search 用：先搜再抓最相关的一两条。',
      'parameters': {
        'type': 'object',
        'properties': {
          'url': {'type': 'string', 'description': '要抓取的 http(s) 地址'},
        },
        'required': ['url'],
      },
    },
  };

  static const Map<String, dynamic> _pythonSchema = {
    'type': 'function',
    'function': {
      'name': 'run_python',
      'description':
          '在本机 Python 解释器里执行一段代码并返回 stdout/stderr。用于数值计算、'
              '数据处理、验证推导。执行前会请用户确认。',
      'parameters': {
        'type': 'object',
        'properties': {
          'code': {'type': 'string', 'description': '完整可执行的 Python 代码'},
        },
        'required': ['code'],
      },
    },
  };

  static const Map<String, dynamic> _shellSchema = {
    'type': 'function',
    'function': {
      'name': 'run_shell',
      'description':
          '在本机命令行执行一条命令并返回输出。执行前会请用户确认。仅用于本软件'
              '相关的目录操作与诊断。',
      'parameters': {
        'type': 'object',
        'properties': {
          'command': {'type': 'string', 'description': '要执行的单条命令'},
        },
        'required': ['command'],
      },
    },
  };
}
