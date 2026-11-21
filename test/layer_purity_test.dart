// layer_purity_test.dart —— 引擎层纯度守卫（v2.24）
//
// 2026-11 架构盘点实测：lib/engine/ 有 4 条出边破了「纯 Dart 引擎」承诺——
//   · ai_client.dart        → package:flutter/foundation.dart（kReleaseMode / visibleForTesting）
//   · scan_bank_store.dart  → package:flutter/foundation.dart + ../storage/
//   · mono_variant.dart     → ../state/mistake_book.dart（领域层反依赖状态层）
// 处置：前两者本就不是引擎（网络客户端 / 持久化），后者是错题本的变式内核，
// 分别迁到 lib/services/、lib/state/。本文件把那次的结论钉死：
// 引擎层一旦重新长出 Flutter 依赖或向上依赖，立刻红。
//
// 判据只扫 import 行，不扫注释——注释里提到 flutter 不算违约。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 引擎层不允许向上依赖的目录前缀。
const List<String> _upwardDirs = <String>[
  '../state/',
  '../storage/',
  '../pages/',
  '../ui/',
  '../services/',
  '../charts/',
  '../guide/',
];

/// 提取一个 dart 文件中所有 import 的目标串。
List<String> importTargets(String text) {
  final out = <String>[];
  for (final line in text.split('\n')) {
    final t = line.trimLeft();
    if (!t.startsWith('import ')) continue;
    final rest = t.substring(7).trimLeft();
    if (rest.isEmpty) continue;
    final quote = rest[0];
    if (quote != "'" && quote != '"') continue;
    final end = rest.indexOf(quote, 1);
    if (end > 1) out.add(rest.substring(1, end));
  }
  return out;
}

/// 提取一个 dart 文件中所有 export 的目标串（barrel 向上 re-export 同样破纯度）。
List<String> exportTargets(String text) {
  final out = <String>[];
  for (final line in text.split('\n')) {
    final t = line.trimLeft();
    if (!t.startsWith('export ')) continue;
    final rest = t.substring(7).trimLeft();
    if (rest.isEmpty) continue;
    final quote = rest[0];
    if (quote != "'" && quote != '"') continue;
    final end = rest.indexOf(quote, 1);
    if (end > 1) out.add(rest.substring(1, end));
  }
  return out;
}

void main() {
  group('解析器自检（守卫本身必须是活的）', () {
    test('importTargets 能取出普通 import / 多行 / 条件导入', () {
      const sample = '''
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../state/x.dart'
    if (dart.library.html) '../storage/y.dart';

export 'z.dart';
class A {}
''';
      final got = importTargets(sample);
      expect(got, contains('dart:io'));
      expect(got, contains('package:flutter/foundation.dart'));
      expect(got, contains('../state/x.dart'));
      expect(got, isNot(contains('z.dart')), reason: 'export 不是 import，不该被计入');
      expect(got, hasLength(3));
    });

    test('引擎目录里确实扫得到 import（防止路径写错导致空扫）', () {
      final files = Directory('lib/engine')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      final total = files.fold<int>(
        0,
        (sum, f) => sum + importTargets(f.readAsStringSync()).length,
      );
      expect(total, greaterThan(30), reason: '引擎层 import 数量异常，守卫可能没读到文件');
    });

    test('引擎内部相对导入指向自身目录时不被误判为越界', () {
      for (final bad in _upwardDirs) {
        expect(bad.startsWith('../'), isTrue);
      }
      // engine 内部同层引用（如 'fraction.dart'）不以 ../ 开头，天然放行。
      expect(importTargets("import 'fraction.dart';"), equals(['fraction.dart']));
    });

    test('exportTargets 只认 export，不把 import 算进来', () {
      const sample = "import 'a.dart'\nexport 'b.dart'\nexport '../state/c.dart'\n";
      expect(exportTargets(sample), equals(['b.dart', '../state/c.dart']));
      expect(importTargets(sample), equals(['a.dart']), reason: 'import 与 export 必须分开统计');
    });
  });

  group('引擎层纯度（lib/engine/ 必须纯 Dart）', () {
    final engineDir = Directory('lib/engine');

    test('lib/engine/ 存在且文件数正常', () {
      expect(engineDir.existsSync(), isTrue, reason: '扫描根 lib/engine/ 必须存在');
      final count = engineDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .length;
      expect(count, greaterThan(20), reason: '引擎文件数异常偏少，守卫可能扫错了目录');
    });

    test('没有任何文件 import package:flutter/', () {
      final offenders = <String>[];
      for (final e in engineDir.listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        for (final target in importTargets(e.readAsStringSync())) {
          if (target.startsWith('package:flutter/')) {
            offenders.add('${e.path} -> $target');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: '引擎层不得依赖 Flutter：需要 Flutter 能力的东西属于 services/ 或 ui/',
      );
    });

    test('barrel 不得向上 re-export（export 也是依赖）', () {
      final offenders = <String>[];
      for (final e in engineDir.listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        for (final target in exportTargets(e.readAsStringSync())) {
          if (target.startsWith('package:flutter/')) {
            offenders.add('${e.path} -> $target');
          }
          for (final bad in _upwardDirs) {
            if (target.startsWith(bad)) offenders.add('${e.path} -> $target');
          }
        }
      }
      expect(offenders, isEmpty, reason: '引擎 barrel 导出上层文件等于把依赖反转藏起来了');
    });

    test('没有任何文件向上依赖 state/storage/pages/ui/services/charts/guide', () {
      final offenders = <String>[];
      for (final e in engineDir.listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        for (final target in importTargets(e.readAsStringSync())) {
          for (final bad in _upwardDirs) {
            if (target.startsWith(bad)) offenders.add('${e.path} -> $target');
          }
        }
      }
      expect(
        offenders,
        isEmpty,
        reason: '依赖方向只能是 lib -> engine；engine 反向依赖说明有文件放错了层',
      );
    });
  });
}
