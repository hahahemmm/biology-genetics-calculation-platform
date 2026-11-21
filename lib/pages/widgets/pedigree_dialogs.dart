// pedigree_dialogs.dart —— 系谱页对话框群（2.3 重构阶段 4 抽取）
//
// 从 genetic_pedigree_page.dart 抽出，全部改为顶层函数：对话框 UI 与
// 输入校验在此；页面状态变更（setState / 引擎重算 / 日志 / 历史 / toast）
// 通过返回值回到页面侧的小包装方法完成。行为与抽取前逐行一致
// （「确定」「取消」「添加」「保存并重算」等文案是测试依赖）。

import 'package:flutter/material.dart';

import '../../data/preset_genotypes.dart';
import '../../engine/pedigree_graph.dart';
import '../../state/history_store.dart';
import '../../theme.dart';

// ── 伴性遗传：下拉填 X=/x=/Y=/y= 表型标签 ─────────────
/// 伴性遗传标注对话框。返回确认后的配置（可能为空配置 = 清除标注）；
/// 返回 null = 用户点「关闭」未确认。
Future<SexLinkedConfig?> showPedigreeSexLinkedDialog({
  required BuildContext context,
  required SexLinkedConfig? current,
}) async {
  final xCtrl = TextEditingController(text: current?.xLabel ?? '');
  final xlCtrl = TextEditingController(text: current?.xLowerLabel ?? '');
  final yCtrl = TextEditingController(text: current?.yLabel ?? '');
  final ylCtrl = TextEditingController(text: current?.yLowerLabel ?? '');
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('伴性遗传标注'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('填写后，结果中含该等位基因的样本会标注表型并着色（X=蓝，x=黄）。',
                style: AppText.caption),
            const SizedBox(height: 14),
            _sexField('X =', xCtrl, '如：病'),
            _sexField('x =', xlCtrl, '如：正常'),
            _sexField('Y =', yCtrl, '如：病'),
            _sexField('y =', ylCtrl, '如：正常'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('关闭'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('应用'),
        ),
      ],
    ),
  );
  SexLinkedConfig? result;
  if (confirmed == true) {
    result = SexLinkedConfig(
      xLabel: xCtrl.text.trim().isEmpty ? null : xCtrl.text.trim(),
      xLowerLabel: xlCtrl.text.trim().isEmpty ? null : xlCtrl.text.trim(),
      yLabel: yCtrl.text.trim().isEmpty ? null : yCtrl.text.trim(),
      yLowerLabel: ylCtrl.text.trim().isEmpty ? null : ylCtrl.text.trim(),
    );
  }
  for (final c in [xCtrl, xlCtrl, yCtrl, ylCtrl]) {
    Future<void>.delayed(const Duration(milliseconds: 400), c.dispose);
  }
  return result;
}

Widget _sexField(String label, TextEditingController ctrl, String hint) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: ctrl,
      style: AppText.genotype,
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        helperText: hint,
      ),
    ),
  );
}

// ── v2.1 亲本预置 / 基因频率 / 位点致死筛选 ──────────────
/// 简单判断基因型是否含 >2 份等位（预置弹窗提示先开多倍体用）。
bool isPolyploidGenotype(String g) {
  var run = 0, maxRun = 0;
  String? last;
  for (final c in g.split('')) {
    if (c == '-') continue;
    final u = c.toUpperCase();
    if (u == last) {
      run++;
    } else {
      last = u;
      run = 1;
    }
    if (run > maxRun) maxRun = run;
  }
  return maxRun > 2;
}

/// v2.1 亲本「预置」对话框：列全部预置组合，点选同时填 ♂+♀。
/// 返回选中的组合；null = 取消。
Future<PresetCross?> showPedigreePresetDialog(BuildContext context) async {
  return showDialog<PresetCross>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('预置亲本'),
      content: SizedBox(
        width: 420,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final p in presetCrosses)
              ListTile(
                dense: true,
                leading: const Icon(Icons.library_books_outlined, size: 18),
                title: Text(p.name),
                subtitle: Text('${p.male} × ${p.female} — ${p.note}',
                    style: AppText.caption),
                onTap: () => Navigator.pop(ctx, p),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
      ],
    ),
  );
}

/// v2.1 「计算基因频率」对话框：位点 | p | q | AA | Aa | aa 频率表。
Future<void> showPedigreeFreqDialog({
  required BuildContext context,
  required PedigreeGraphEngine engine,
}) async {
  final freqs = engine.locusFrequencies();
  // 任一（位点）基因型频率偏离哈迪-温伯格预期 → 尾部加教学提示
  final deviated = freqs.any((f) => (f.fAA - f.p * f.p).abs() > 0.001);
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('基因频率'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Table(
              border: TableBorder.all(color: AppColors.border, width: 0.5),
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                TableRow(
                  decoration: BoxDecoration(color: AppColors.surfaceLow),
                  children: [
                    for (final h in ['位点', '显性等位 p', '隐性等位 q', 'AA', 'Aa', 'aa'])
                      _freqCell(h, header: true),
                  ],
                ),
                for (final f in freqs)
                  TableRow(children: [
                    _freqCell(f.locus),
                    _freqCell(_freqPct(f.p)),
                    _freqCell(_freqPct(f.q)),
                    _freqCell(_freqPct(f.fAA)),
                    _freqCell(_freqPct(f.fAa)),
                    _freqCell(_freqPct(f.faa)),
                  ]),
              ],
            ),
            const SizedBox(height: 12),
            Text('按当前全部节点统计；开启哈迪-温伯格：随机交配下一代 '
                'AA=p²、Aa=2pq、aa=q²。', style: AppText.caption),
            if (deviated) ...[
              const SizedBox(height: 6),
              Text('当前群体偏离遗传平衡（教学要点：基因频率不变≠基因型频率不变）',
                  style: AppText.caption.copyWith(color: AppColors.sand)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

Widget _freqCell(String text, {bool header = false}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    child: Text(
      text,
      textAlign: TextAlign.center,
      style: header
          ? AppText.caption.copyWith(
              fontWeight: FontWeight.w700, color: AppColors.ink)
          : AppText.caption,
    ),
  );
}

String _freqPct(double v) => '${(v * 100).toStringAsFixed(1)}%';

/// v2.1c「位点致死筛选」对话框：用户自行输入致死基因型（不限于 A，
/// 可指定任意位点：AA / aa / BB…）；开启多倍体后可输入 AAA / AAAA /
/// AAAAA（3~5 份字母）；已设条件列表可逐条删除。返回确认后的工作
/// 副本列表；null = 取消（页面侧据此应用并重算）。
Future<List<String>?> showPedigreeLethalDialog({
  required BuildContext context,
  required PedigreeGraphEngine engine,
  required bool allowPolyploid,
}) async {
  final input = TextEditingController();
  var list = List<String>.of(engine.lethalGens); // 工作副本
  String? localError;
  final applied = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('位点致死筛选'),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '输入要致死的纯合基因型（如 AA=显性纯合致死、aa=隐性'
                    '纯合致死），可指定任意位点（B 位点填 BB）。'
                    '${allowPolyploid ? '已开启多倍体：允许 AAA / AAAA / AAAAA（三/四/五倍体纯合）。' : '未开多倍体：仅允许 2 字母（二倍体纯合）；开启后可输入 AAA 等多倍体纯合。'}',
                    style: AppText.caption),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: input,
                        autofocus: true,
                        style: AppText.genotype,
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: '致死基因型（如 AA / aa / BB…）',
                          errorText: localError,
                        ),
                        onSubmitted: (_) => _addLethalInput(input, list,
                            allowPolyploid,
                            () => setLocal(() {},),
                            (err) => setLocal(() => localError = err)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => _addLethalInput(input, list,
                          allowPolyploid,
                          () => setLocal(() {}),
                          (err) => setLocal(() => localError = err)),
                      child: const Text('添加'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (list.isEmpty)
                  Text('尚未设置致死条件——子代全部正常存活。',
                      style: AppText.caption)
                else
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final g in List.of(list))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${_locusNameOf(g)}：$g 纯合致死',
                                  style: AppText.body.copyWith(
                                      fontWeight: FontWeight.w600),
                                ),
                              ),
                              IconButton(
                                tooltip: '删除该致死条件',
                                icon: Icon(Icons.delete_outline,
                                    size: 18, color: AppColors.lethal),
                                onPressed: () => setLocal(() {
                                  list.remove(g);
                                  localError = null;
                                }),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    ),
  );
  // 同 showPedigreeAddSampleDialog 模式：无论用户取消或确认，都延迟 400ms
  // 释放 controller，避开对话框退出动画期 TextField 重建复用同一 controller
  // 触发 "used after disposed" 异常。
  Future<void>.delayed(const Duration(milliseconds: 400), input.dispose);
  if (applied != true) return null;
  return list;
}

/// 校验并追加一个致死条件：仅同字母（大小写组合）1~5 份；多倍体
/// 未开时仅 2 份。成功时清空输入框；失败把信息写入 [onError]。
void _addLethalInput(
  TextEditingController input,
  List<String> list,
  bool allowPolyploid,
  VoidCallback onChanged,
  ValueChanged<String?> onError,
) {
  final raw = input.text.trim().toUpperCase();
  if (raw.isEmpty) {
    onError('请输入致死基因型');
    return;
  }
  if (raw.split('').any((c) => RegExp(r'^[A-Za-z]$').hasMatch(c) == false)) {
    onError('只能输入同一字母（如 AA / BB / AAA）');
    return;
  }
  if (raw.length > 5) {
    onError('最多 5 份（五倍体纯合）');
    return;
  }
  if (!allowPolyploid && raw.length != 2) {
    onError('未开启多倍体：仅支持二倍体（如 AA）；开启「多倍体」后可输入 AAA / AAAA');
    return;
  }
  if (raw.length >= 2 && raw.split('').toSet().length != 1) {
    onError('同一字母如 AA / BBB，大小写可混写');
    return;
  }
  if (!list.contains(raw)) list.add(raw);
  input.clear();
  onError(null);
  onChanged();
}

/// 位点名（'AAA' → 'A 位点'）。
String _locusNameOf(String g) => '${g[0].toUpperCase()} 位点';

// ── R3 添加样本 / R14 添加家族 / 编辑外来样本 ─────────────
/// 「添加样本」对话框。返回确认后的表单值；null = 取消
/// （页面侧据此校验/入引擎/记日志/提示）。
Future<({String genotype, PedigreeNodeKind kind, int generation, int familyId})?>
    showPedigreeAddSampleDialog({
  required BuildContext context,
  required PedigreeGraphEngine engine,
  required int tappedGen,
  required String p1,
  required String p2,
}) async {
  final genoCtrl = TextEditingController();
  // R17：默认「混合」（雌雄混合群体桶，渲染同子代组合桶）
  PedigreeNodeKind kind = PedigreeNodeKind.group;
  // 目标世代可选范围：0 .. max(已展开最大世代, 点中世代)
  final maxChoice =
      tappedGen > engine.maxGeneration ? tappedGen : engine.maxGeneration;
  int generation = tappedGen;
  // R14：多家族时选择样本加入哪个家族的交配池
  int familyId = engine.familyIds.first;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('添加样本'),
        content: SizedBox(
          width: 340,
          // 多家族时多一个「所属家族」下拉，小窗口下需可滚动防溢出
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              TextField(
                controller: genoCtrl,
                style: AppText.genotype,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: '基因型',
                  helperText: '如 AaBb',
                ),
              ),
              _genotypePresets(genoCtrl, setLocal, p1, p2),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text('性别', style: AppText.label),
                  const SizedBox(width: 12),
                  ChoiceChip(
                    label: const Text('混合 ♂♀'),
                    selected: kind == PedigreeNodeKind.group,
                    onSelected: (_) => setLocal(
                        () => kind = PedigreeNodeKind.group),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('♂ 雄'),
                    selected: kind == PedigreeNodeKind.male,
                    onSelected: (_) => setLocal(
                        () => kind = PedigreeNodeKind.male),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('♀ 雌'),
                    selected: kind == PedigreeNodeKind.female,
                    onSelected: (_) => setLocal(
                        () => kind = PedigreeNodeKind.female),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<int>(
                initialValue: generation,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: '目标世代',
                ),
                items: [
                  for (var g = 0; g <= maxChoice; g++)
                    DropdownMenuItem(
                        value: g, child: Text(g == 0 ? 'P 代' : 'F$g')),
                ],
                onChanged: (g) {
                  if (g != null) setLocal(() => generation = g);
                },
              ),
              if (engine.familyIds.length > 1) ...[
                const SizedBox(height: 14),
                DropdownButtonFormField<int>(
                  initialValue: familyId,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: '所属家族',
                  ),
                  items: [
                    for (final f in engine.familyIds)
                      DropdownMenuItem(
                          value: f, child: Text('家族 ${engine.familyLabel(f)}')),
                  ],
                  onChanged: (f) {
                    if (f != null) setLocal(() => familyId = f);
                  },
                ),
              ],
            ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('添加'),
          ),
        ],
      ),
    ),
  );

  final result = confirmed == true
      ? (
          genotype: genoCtrl.text.trim(),
          kind: kind,
          generation: generation,
          familyId: familyId,
        )
      : null;
  // 注意：不要立刻 dispose genoCtrl——对话框退出动画期间 TextField 仍会
  // 用同一 controller 重建，提前 dispose 会触发 "used after disposed"。
  // 延迟一个动画周期再释放。
  Future<void>.delayed(const Duration(milliseconds: 400), genoCtrl.dispose);
  return result;
}

/// R14 多家族：添加独立家族。新家族双亲落在 P 代、独立繁衍（自己的
/// 交配池）；与既有家族成员连线（点选-点选，跨栏也可以连）即发生
/// 跨家族交配，子代进入合并家族（如 A×B）。
/// 返回确认后的 (父本, 母本) 基因型；null = 取消。
Future<({String father, String mother})?> showPedigreeAddFamilyDialog({
  required BuildContext context,
  required String p1,
  required String p2,
}) async {
  final fCtrl = TextEditingController();
  final mCtrl = TextEditingController();

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('添加家族'),
        content: SizedBox(
          width: 360,
          // 双基因型输入 + 双预设 chips 较高，小窗口下需可滚动防溢出
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('新家族独立繁衍（拥有自己的交配池）。之后点选两个不同家族的节点连线，即可发生跨家族交配，子代进入合并家族（如 A×B）。',
                  style: AppText.caption),
              const SizedBox(height: 14),
              TextField(
                controller: fCtrl,
                style: AppText.genotype,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: '父本基因型 ♂',
                  helperText: '如 Aa',
                ),
              ),
              _genotypePresets(fCtrl, setLocal, p1, p2),
              const SizedBox(height: 10),
              TextField(
                controller: mCtrl,
                style: AppText.genotype,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: '母本基因型 ♀',
                  helperText: '如 Aa',
                ),
              ),
              _genotypePresets(mCtrl, setLocal, p1, p2),
            ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('添加'),
          ),
        ],
      ),
    ),
  );

  final result = confirmed == true
      ? (father: fCtrl.text.trim(), mother: mCtrl.text.trim())
      : null;
  // 同上：延迟释放，避开对话框退出动画期的重建。
  Future<void>.delayed(const Duration(milliseconds: 400), () {
    fCtrl.dispose();
    mCtrl.dispose();
  });
  return result;
}

/// 「编辑样本」对话框：改基因型/性别（混合桶性别不可改）。
/// 返回确认后的表单值；null = 取消（页面侧据此入引擎/重算/记日志）。
Future<({String genotype, PedigreeNodeKind kind})?>
    showPedigreeEditSampleDialog({
  required BuildContext context,
  required PedigreeNode node,
  required String p1,
  required String p2,
}) async {
  final genoCtrl = TextEditingController(text: node.genotype);
  var kind = node.kind;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text('编辑样本 ${node.genotype}'),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: genoCtrl,
                style: AppText.genotype,
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: '基因型',
                  helperText: '如 AaBb（成对字母）',
                ),
              ),
              _genotypePresets(genoCtrl, setLocal, p1, p2),
              const SizedBox(height: 14),
              if (node.kind == PedigreeNodeKind.group)
                // 混合桶性别不可改（会架空已分裂的半边），仅作说明
                Row(
                  children: [
                    Text('性别', style: AppText.label),
                    const SizedBox(width: 12),
                    Text('混合 ♂♀（不可修改，如需变更请删除后重新添加）',
                        style: AppText.caption),
                  ],
                )
              else
                Row(
                  children: [
                    Text('性别', style: AppText.label),
                    const SizedBox(width: 12),
                    ChoiceChip(
                      label: const Text('♂ 雄'),
                      selected: kind == PedigreeNodeKind.male,
                      onSelected: (_) =>
                          setLocal(() => kind = PedigreeNodeKind.male),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('♀ 雌'),
                      selected: kind == PedigreeNodeKind.female,
                      onSelected: (_) =>
                          setLocal(() => kind = PedigreeNodeKind.female),
                    ),
                  ],
                ),
              const SizedBox(height: 10),
              Text('保存后将立即重算该样本下游世代',
                  style: AppText.caption),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存并重算'),
          ),
        ],
      ),
    ),
  );

  final result =
      confirmed == true ? (genotype: genoCtrl.text.trim(), kind: kind) : null;
  // 延迟释放：对话框退出动画期间 TextField 仍会复用 controller
  Future<void>.delayed(const Duration(milliseconds: 400), genoCtrl.dispose);
  return result;
}

// ── v2.1 基因型编辑 ──────────────────────────────────────
/// 「编辑基因型」对话框（外来样本 / P 代初始双亲）；确认按钮内直接调
/// engine.editGenotype 校验（错误就地在框内展示）。返回 true = 已确认
/// 且引擎已接受新基因型（页面侧据此重算/记日志/归档）。
Future<bool> showPedigreeEditGenotypeDialog({
  required BuildContext context,
  required PedigreeGraphEngine engine,
  required PedigreeNode n,
}) async {
  final ctrl = TextEditingController(text: n.genotype);
  String? localError;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('编辑基因型'),
        content: SizedBox(
          width: 320,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  style: AppText.genotype,
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: '新基因型（如 AaBbCc）',
                    errorText: localError,
                  ),
                  onSubmitted: (_) =>
                      Navigator.of(ctx).pop(true),
                ),
                const SizedBox(height: 8),
                Text(
                  n.isExternal
                      ? '外来样本可修改；保存后立即重算后代。'
                      : '初始双亲可修改；保存后立即重算后代。'
                          '计算产出的子代不可直接修改。',
                  style: AppText.caption,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final err = engine.editGenotype(n.id, ctrl.text);
              if (err != null) {
                setLocal(() => localError = err);
                return;
              }
              Navigator.of(ctx).pop(true);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
  return confirmed == true;
}

// ── R16 操作日志面板 + v2.1 计算历史面板 ─────────────────────
/// 日志面板：最新在上；每条可「回退到此处」（第 0 步=最开始）；
/// v3.4「撤销上一步回退」撤销最近一次回退（Ctrl+Shift+Z 语义）。
/// [labels] 为各步操作描述（下标即步号，末位 = 当前状态）。
void showPedigreeLogDialog({
  required BuildContext context,
  required List<String> labels,
  required bool canRedoRevert,
  required void Function(int index) onRevertTo,
  required VoidCallback onRedoRevert,
}) {
  showDialog(
    context: context,
    builder: (dCtx) => AlertDialog(
      title: const Text('操作日志'),
      content: SizedBox(
        width: 480,
        height: 400,
        child: labels.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history_toggle_off,
                          size: 48, color: AppColors.steel),
                      const SizedBox(height: 12),
                      Text('暂无操作记录', style: AppText.sectionTitle),
                      const SizedBox(height: 8),
                      Text(
                        '对谱系的每一步操作都会记录在这里，\n可随时回退到任意一步。',
                        textAlign: TextAlign.center,
                        style: AppText.body.copyWith(color: AppColors.steel),
                      ),
                    ],
                  ),
                ),
              )
            : ListView(
                children: [
                  for (var i = labels.length - 1; i >= 0; i--)
                    ListTile(
                      dense: true,
                      leading: Text('#$i', style: AppText.monoSmall),
                      title: Text(labels[i], style: AppText.body),
                      subtitle: i == labels.length - 1
                          ? Text('当前状态',
                              style: TextStyle(
                                  fontSize: 11, color: AppColors.teal))
                          : i == 0
                              ? Text('最开始（回退到此即到头）',
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: AppColors.steel))
                              : null,
                      trailing: i < labels.length - 1
                          ? TextButton(
                              onPressed: () {
                                Navigator.of(dCtx).pop();
                                onRevertTo(i);
                              },
                              child: const Text('回退到此处'),
                            )
                          : null,
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: canRedoRevert
              ? () {
                  Navigator.of(dCtx).pop();
                  onRedoRevert();
                }
              : null,
          child: const Text('撤销上一步回退'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dCtx).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

/// v2.1 历史面板：自动记录的每次计算（基因型/家族/产出）；顶部
/// 「保存当前并开新对话」= 归档当下白板（含家族）后清空开始新对话，
/// 与历史完全隔离（历史只读回看）。
void showPedigreeHistoryDialog({
  required BuildContext context,
  required List<HistoryEntry> history,
  required bool Function() isMounted,
  required Future<void> Function() onSaveAndNew,
}) {
  showDialog(
    context: context,
    builder: (dCtx) => AlertDialog(
      title: const Text('计算历史'),
      content: SizedBox(
        width: 520,
        height: 420,
        child: history.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inbox_outlined,
                          size: 48, color: AppColors.steel),
                      const SizedBox(height: 12),
                      Text('暂无历史记录', style: AppText.sectionTitle),
                      const SizedBox(height: 8),
                      Text(
                        '每次「计算」会自动记录在这里。',
                        textAlign: TextAlign.center,
                        style: AppText.body.copyWith(color: AppColors.steel),
                      ),
                    ],
                  ),
                ),
              )
            : ListView.builder(
                itemCount: history.length,
                itemBuilder: (ctx, i) {
                  final h = history[history.length - 1 - i];
                  final t = DateTime.fromMillisecondsSinceEpoch(h.epochMs);
                  final ts = '${t.month}月${t.day}日 '
                      '${t.hour.toString().padLeft(2, '0')}:'
                      '${t.minute.toString().padLeft(2, '0')}';
                  return ListTile(
                    dense: true,
                    leading: Icon(Icons.auto_stories_outlined,
                        size: 18, color: AppColors.teal),
                    title: Text(h.label, style: AppText.body),
                    subtitle: Text(
                        '$ts\n${h.detail}',
                        style: AppText.caption,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis),
                  );
                },
              ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            // P0 修复：先关对话框（退场动画进行中不触碰页面状态），
            // 延迟一帧后再执行重置——避免 deactivate element 重建
            // 在 release 下直接崩溃（用户报告「按此按钮死机」）。
            Navigator.of(dCtx).pop();
            await Future<void>.delayed(
                const Duration(milliseconds: 80));
            if (!isMounted()) return;
            await onSaveAndNew();
          },
          icon: const Icon(Icons.add_comment_outlined, size: 18),
          label: const Text('保存当前并开新对话'),
        ),
        TextButton(
          onPressed: () => Navigator.of(dCtx).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

/// 常用基因型预制 chips：点选即填入（含当前双亲基因型），仍可手动输入。
Widget _genotypePresets(TextEditingController ctrl, StateSetter setLocal,
    String p1, String p2) {
  final presets = <String>{
    p1,
    p2,
    'AABBCC', 'AaBbCc', 'aabbcc', 'AaBb', 'aabb', 'Aa', 'aa',
  }.where((s) => s.isNotEmpty && s.length % 2 == 0).toList();
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SizedBox(height: 10),
      Text('常用基因型（点选填入）', style: AppText.caption),
      const SizedBox(height: 6),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final p in presets)
            ActionChip(
              label: Text(p),
              labelStyle: AppText.monoSmall,
              onPressed: () => setLocal(() {
                ctrl.text = p;
                ctrl.selection = TextSelection.collapsed(offset: p.length);
              }),
            ),
        ],
      ),
    ],
  );
}

// ── R19 按家族删代：删除栏（家族 × 世代，支持全部家族/全部代数） ──
/// 「删除整代」对话框。返回确认后的选择（famChoice/genChoice，
/// -1 = 全部家族/全部代数）；null = 取消（页面侧据此删除/重算/记日志）。
Future<({int famChoice, int genChoice})?> showPedigreeDeleteGenerationDialog({
  required BuildContext context,
  required PedigreeGraphEngine engine,
}) async {
  var famChoice = -1; // -1 = 全部家族
  var genChoice = -1; // -1 = 全部代数
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('删除整代'),
        content: SizedBox(
          width: 340,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '删除指定家族/世代的全部计算后代（外来样本保留在原位，'
                  '等重新推进到该代时再入池）。删除后立即重算。',
                  style: AppText.caption,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: famChoice,
                  decoration: const InputDecoration(
                      isDense: true, labelText: '家族'),
                  items: [
                    const DropdownMenuItem(
                        value: -1, child: Text('全部家族')),
                    for (final f in engine.familyIds)
                      DropdownMenuItem(
                          value: f,
                          child:
                              Text('家族 ${engine.familyLabel(f)}')),
                  ],
                  onChanged: (v) {
                    if (v != null) setLocal(() => famChoice = v);
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  initialValue: genChoice,
                  decoration: const InputDecoration(
                      isDense: true, labelText: '世代'),
                  items: [
                    const DropdownMenuItem(
                        value: -1, child: Text('全部代数')),
                    for (var g = 1; g <= engine.maxGeneration; g++)
                      // R8 学生走查 #15：removeFamilyGeneration 删的是
                      //「该代及以后」——裸标 F2 被误读为只删一代。
                      DropdownMenuItem(
                          value: g, child: Text('F$g 及以后')),
                  ],
                  onChanged: (v) {
                    if (v != null) setLocal(() => genChoice = v);
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    ),
  );
  if (confirmed != true) return null;
  return (famChoice: famChoice, genChoice: genChoice);
}
