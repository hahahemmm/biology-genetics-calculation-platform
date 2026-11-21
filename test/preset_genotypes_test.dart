// preset_genotypes_test.dart —— lib/data/preset_genotypes.dart 纯数据不变量
// 防数据录错/截断/学科口径回归：条数与必填非空、亲本位点结构一致、
// 多倍体判定、比例文案与亲本组合口径、无空串与前后空格。

import 'package:biology/data/preset_genotypes.dart';
import 'package:biology/pages/widgets/pedigree_dialogs.dart';
import 'package:flutter_test/flutter_test.dart';

/// 逐位点统计等位基因份数（忽略大小写与连字符），如 'AaaBbbCcc' → {A:3, B:3, C:3}。
Map<String, int> _locusCounts(String g) {
  final m = <String, int>{};
  for (final c in g.replaceAll('-', '').split('')) {
    final k = c.toUpperCase();
    m[k] = (m[k] ?? 0) + 1;
  }
  return m;
}

void main() {
  test('预设共 9 条，且 name/male/female/note 四字段均非空', () {
    expect(presetCrosses, hasLength(9));
    for (final p in presetCrosses) {
      expect(p.name.isNotEmpty, isTrue, reason: 'name 为空：$p');
      expect(p.male.isNotEmpty, isTrue, reason: 'male 为空：$p');
      expect(p.female.isNotEmpty, isTrue, reason: 'female 为空：$p');
      expect(p.note.isNotEmpty, isTrue, reason: 'note 为空：$p');
    }
  });

  test('第 1 条两对基因自交 AaBb × AaBb，说明用直白口径', () {
    final p = presetCrosses[0];
    expect(p.name, '双杂合自交（两对基因）');
    expect(p.male, 'AaBb');
    expect(p.female, 'AaBb');
    expect(p.note, contains('9:3:3:1'));
    expect(p.note, contains('基因型 9 种'));
    expect(p.note, isNot(contains('F1')));
  });

  test('名称/说明/基因型均无前后空格、无空串', () {
    for (final p in presetCrosses) {
      for (final f in [p.name, p.male, p.female, p.note]) {
        expect(f.trim(), f, reason: '存在前后空格："$f"');
      }
    }
  });

  test('每条亲本两侧位点结构一致（逐位点等位基因份数相同）', () {
    for (final p in presetCrosses) {
      expect(_locusCounts(p.male), _locusCounts(p.female),
          reason: '位点结构错位：${p.name}（${p.male} × ${p.female}）');
    }
  });

  test('仅第 9 条为多倍体（isPolyploidGenotype 判定）', () {
    final poly = presetCrosses[8];
    expect(poly.male, 'AaaBbbCcc');
    expect(isPolyploidGenotype(poly.male), isTrue);
    expect(isPolyploidGenotype(poly.female), isTrue);
    expect(poly.note, contains('多倍体'));
    for (final p in presetCrosses.take(8)) {
      expect(isPolyploidGenotype(p.male), isFalse,
          reason: '前 8 条不应被判定为多倍体：${p.name}（${p.male}）');
      expect(isPolyploidGenotype(p.female), isFalse,
          reason: '前 8 条不应被判定为多倍体：${p.name}（${p.female}）');
    }
  });

  test('第 2 条 AABBCC × aabbcc 口径为 27:9:9:9:3:3:3:1，不得回退 9:3:3:1', () {
    final p = presetCrosses[1];
    expect(p.male, 'AABBCC');
    expect(p.female, 'aabbcc');
    expect(p.note, contains('27:9:9:9:3:3:3:1'));
    expect(p.note, isNot(contains('9:3:3:1')));
  });

  test('第 6 条 AaBbCc × AaBbcc 说明含 9:3:3:1 与 1:1 口径', () {
    final p = presetCrosses[5];
    expect(p.male, 'AaBbCc');
    expect(p.female, 'AaBbcc');
    expect(p.note, contains('9:3:3:1'));
    expect(p.note, contains('1:1'));
  });

  test('第 4 条测交、第 8 条全隐性对照的基因型登记正确', () {
    expect(presetCrosses[3].male, 'AaBbCc');
    expect(presetCrosses[3].female, 'aabbcc');
    expect(presetCrosses[7].male, 'aabbcc');
    expect(presetCrosses[7].female, 'aabbcc');
    expect(presetCrosses[7].note, contains('全隐性'));
  });
}
