// pedigree_mini_calcs.dart —— 杂交计算面板内的迷你计算器块（v2.19.19）
//
// 用户记忆复原：杂交计算面板曾是「竖向滚动 + 多个 9331 式紧凑计算器」
// 的一整层面板（含 9331/单基因/连锁互换/自由交配等）。本文件提供
// 9331 之外的迷你块——每个块都是「输入 → 计算 → 紧凑结果」的简洁形态，
// 在 300px 面板内竖排，复用主引擎（KaojiCalc.crossAuto / LinkageEngine.cross）
// 与 9331 页严格同算法，零新增计算逻辑。
//
// 面板宿主：pedigree_cross_panel.dart（SingleChildScrollView 竖滚串联）。

import 'package:flutter/material.dart';

import '../../engine/kaoji_calc.dart';
import '../../engine/linkage_engine.dart';
import '../../theme.dart';

/// 单基因速算：Aa × Aa → 3:1 / 1:2:1（分离定律教学最高频）。
class MonoMiniCalc extends StatefulWidget {
  const MonoMiniCalc({super.key});

  @override
  State<MonoMiniCalc> createState() => _MonoMiniCalcState();
}

class _MonoMiniCalcState extends State<MonoMiniCalc> {
  final _p1 = TextEditingController(text: 'Aa');
  final _p2 = TextEditingController(text: 'Aa');
  final _calc = KaojiCalc();
  String? _error;
  ({String pheno, String geno})? _result;

  void _go() {
    final a = _p1.text.trim(), b = _p2.text.trim();
    if (!RegExp(r'^[A-Za-z]{2}$').hasMatch(a) ||
        !RegExp(r'^[A-Za-z]{2}$').hasMatch(b)) {
      setState(() {
        _error = '各 2 个字符（如 Aa / aa）';
        _result = null;
      });
      return;
    }
    final r = _calc.crossAuto(p1: a, p2: b);
    final res = r.result;
    if (res == null) {
      setState(() {
        _error = r.error ?? '计算失败';
        _result = null;
      });
      return;
    }
    setState(() {
      _error = null;
      _result = (pheno: res.phenotypeRatio.toString(), geno: '');
    });
  }

  @override
  void dispose() {
    _p1.dispose();
    _p2.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('单基因速算', style: AppText.label),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _p1,
                style: AppText.genotype,
                decoration: const InputDecoration(
                  labelText: '亲本 1',
                  hintText: 'Aa',
                  isDense: true,
                ),
                onSubmitted: (_) => _go(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child:
                  Icon(Icons.close, size: 16, color: AppColors.steel),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _p2,
                style: AppText.genotype,
                decoration: const InputDecoration(
                  labelText: '亲本 2',
                  hintText: 'Aa',
                  isDense: true,
                ),
                onSubmitted: (_) => _go(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            onPressed: _go,
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('计算'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(_error!,
              style: AppText.caption.copyWith(color: AppColors.lethal)),
        ],
        if (r != null) ...[
          const SizedBox(height: 8),
          Text('表型比 ${r.pheno}',
              style: AppText.monoSmall.copyWith(color: AppColors.teal)),
        ],
      ],
    );
  }
}

/// 连锁互换速算：AB/ab × ab/ab，r=20% → 表型比。
class LinkageMiniCalc extends StatefulWidget {
  const LinkageMiniCalc({super.key});

  @override
  State<LinkageMiniCalc> createState() => _LinkageMiniCalcState();
}

class _LinkageMiniCalcState extends State<LinkageMiniCalc> {
  final _p1 = TextEditingController(text: 'AB/ab');
  final _p2 = TextEditingController(text: 'ab/ab');
  final _r = TextEditingController(text: '20%');
  final _engine = LinkageEngine();
  String? _error;
  String? _ratio;

  void _go() {
    try {
      final res = _engine.cross(_p1.text, _p2.text, _r.text);
      setState(() {
        _error = null;
        _ratio = res.phenotypeRatio.join(':');
      });
    } on ArgumentError catch (e) {
      setState(() {
        _error = e.message?.toString() ?? '输入格式错误';
        _ratio = null;
      });
    }
  }

  @override
  void dispose() {
    _p1.dispose();
    _p2.dispose();
    _r.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('连锁互换速算', style: AppText.label),
        const SizedBox(height: 8),
        TextField(
          controller: _p1,
          style: AppText.genotype,
          decoration: const InputDecoration(
            labelText: '亲本 1',
            hintText: 'AB/ab',
            isDense: true,
          ),
          onSubmitted: (_) => _go(),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _p2,
          style: AppText.genotype,
          decoration: const InputDecoration(
            labelText: '亲本 2',
            hintText: 'ab/ab（测交）',
            isDense: true,
          ),
          onSubmitted: (_) => _go(),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _r,
          style: AppText.genotype,
          decoration: const InputDecoration(
            labelText: '交换值 r',
            hintText: '20% / 0.2 / 1/5',
            isDense: true,
          ),
          onSubmitted: (_) => _go(),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonalIcon(
            onPressed: _go,
            icon: const Icon(Icons.play_arrow_rounded, size: 18),
            label: const Text('计算'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 6),
          Text(_error!,
              style: AppText.caption.copyWith(color: AppColors.lethal)),
        ],
        if (_ratio != null) ...[
          const SizedBox(height: 8),
          Text('表型比 $_ratio',
              style: AppText.monoSmall.copyWith(color: AppColors.teal)),
        ],
      ],
    );
  }
}
