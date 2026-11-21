// scan_upload_dialog.dart —— 拍题识别独立入口（v2.10 入口分离）
//
// 分离原因（用户反馈 2026-09-02）：拍题识别（上传题目图片）原来挤在
// 「问 AI」聊天面板里——问 AI 时会自动携带画布截图，AI 可能把软件内置
// 截图误当题目上传，形成识别死循环。两个入口分开：
//   - 问 AI（psychology FAB / 各页按钮）：截图问答，无上传题目按钮；
//   - 拍题（add_photo_alternate FAB / 本对话框）：专门上传题目图片 →
//     AI 识别 → 总结 + 标准动作 → 填入对应模块/执行动作 → 自动入库。
//
// 本对话框复用 AiChatController.sendScan（识别+入库全流程），UI 独立成框。
// 学生模式与课堂模式都呈现（拍题是学生刷题也能用的功能）。
//
// v2.12+ R1 P0 #1：识别结果卡加「存入错题本」按钮——OCR 错的题正好
// 是学生最常需要整理的，让"想加错题本"从 4 步手动录入变成 1 步点按。
// SnackBar 5 秒可 Undo（点错了立刻撤回）——OCR 错的题如果已经入库，
// 学生不会知道撤回到哪一条（v2.12 错题本 ID 透明），所以 Undo 用
// entry 引用拿新 id（沿用 mistake_book_page 的 Undo 设计）。
// v2.12+ R1 final-B P0 #2：原 commit 把 Undo 推迟到"未来再加"，但这是
// 学生每日用的高频操作（30 秒/题，5 道 = 2.5 分钟），必须 inline。
// 现在 SnackBar action 是「撤销」——点走 `MistakeBook.delete(added.id)`
// 把 entry 移到 trash，5 秒过期后用户可从错题本回收站恢复。
//
// Wave2 拖图入窗（2026-10）：对话框成为拖拽图片的活跃消费者——
// mounted 期间 claim FileDropBus，新拖的图直接 _send 进识别；
// initialImage 让 HomeShell 兜底开框时把触发开框的那张图直接带入
//（broadcast 流不回放，见 file_drop_bus.dart 消费协议）。

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../state/first_run_store.dart';
import '../state/mistake_book.dart';
import '../theme.dart';
import 'ai_chat_controller.dart';
import 'file_drop_bus.dart';
import 'image_pick.dart';
import 'module_fill.dart';

/// 打开拍题识别对话框。[picker] 测试注入用：替换平台选图。
/// [initialImage] Wave2 拖图入窗：拖拽兜底开框时带入的首图，打开后
/// 自动开始识别（不弹空框等用户再点按钮）。
Future<void> showScanUploadDialog(
  BuildContext context, {
  Future<PickedImage?> Function()? picker,
  PickedImage? initialImage,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _ScanUploadDialog(
        picker: picker, initialImage: initialImage),
  );
}

class _ScanUploadDialog extends StatefulWidget {
  final Future<PickedImage?> Function()? picker;
  final PickedImage? initialImage;
  const _ScanUploadDialog({this.picker, this.initialImage});

  @override
  State<_ScanUploadDialog> createState() => _ScanUploadDialogState();
}

class _ScanUploadDialogState extends State<_ScanUploadDialog> {
  AiChatController get _ctrl => AiChatController.instance;

  /// v2.14 R5：本次选图的 base64 备份——sendScan 成功后控制器内的
  /// pendingScanImage 即被消费清空，「填入对应模块」时系谱页要展示
  /// 原图给学生核对识别结果，只有这里还留着。
  String? _pickedB64;

  /// Wave2 拖图入窗：对话框打开期间订阅拖入图（claim 让 HomeShell
  /// 兜底知道「有消费者，别重复开框」）。
  StreamSubscription<PickedImage>? _dropSub;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onChanged);
    // Wave2 拖图入窗：登记为活跃消费者 + 订阅新拖图。识别中
    // （busy/refreshing）到达的拖图不排队（连拍由用户点「再拍一题」
    // 串行，协议见 file_drop_bus.dart 文件头）——但零反馈 = 用户
    // 以为拖丢了（v2.19.67 P2 #4），丢帧时补 SnackBar 人话提示。
    FileDropBus.instance.claim();
    _dropSub = FileDropBus.instance.stream.listen((img) {
      if (!mounted) return;
      if (_ctrl.busy || _ctrl.refreshing) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('识别中，请稍后再拖')));
        return;
      }
      _send(img);
    });
    // 拖拽兜底开框：首图直接进识别流程（不弹空框等用户点按钮）。
    final init = widget.initialImage;
    if (init != null) _send(init);
  }

  @override
  void dispose() {
    _dropSub?.cancel();
    _dropSub = null;
    FileDropBus.instance.release();
    _ctrl.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// 挂图 → 立即识别（_pick 系统选图与 Wave2 拖图入窗共用出口）。
  ///
  /// v2.11 M6：路径加 try/catch——平台插件不可用 / 拖入文件读半路
  /// 被删等异常冒泡到框架会让整个 dialog 闪退，改本地 SnackBar 提示。
  /// v2.13 R3 P1-A1：sendScan 返回成功与否。失败（断网/额度用尽/
  /// 解析失败/未配置）弹 SnackBar——本对话框不渲染聊天，spinner
  /// 消失后零反馈；成功不弹（结果卡正常渲染）。「已打断」不算失败
  /// （lastScanError 为空），也不弹条。
  Future<void> _send(PickedImage f) async {
    try {
      final b64 = base64Encode(f.bytes);
      _pickedB64 = b64;
      _ctrl.attachScanImage(b64, _mimeOf(f.extension), f.name);
      final ok = await _ctrl.sendScan();
      if (!mounted || ok) return;
      final err = _ctrl.lastScanError;
      if (err == null) return;
      // v2.13 UI 走查 P0：错误信息人话化——学生/老师不可懂
      // 「403: 网关防护拦截（Cloudflare）」类技术串，按类别给可行动提示。
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_friendlyError(err))));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选图失败：$e')));
    }
  }

  /// 选图 → 挂入控制器 → 立即识别。
  ///
  /// v2.11 M6：选图路径加 try/catch——平台插件不可用 / FileUploadInputElement
  /// 抛异常时，错误冒泡到 Flutter 框架会让整个 dialog 闪退。
  /// 改为本地 try/catch + SnackBar 提示，UI 状态保持稳定。
  Future<void> _pick() async {
    if (_ctrl.busy || _ctrl.refreshing) return;
    final pick = widget.picker ?? pickImageFile;
    try {
      final f = await pick();
      if (!mounted || f == null) return;
      await _send(f);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('选图失败：$e')));
    }
  }

  /// 把引擎错误串映射为学生可行动的提示（保留已经人话化的信息）。
  static String _friendlyError(String err) {
    if (err.contains('网络')) {
      return '识别失败：网络连接异常，请检查网络后重试';
    }
    if (err.contains('未配置') || err.contains('401') || err.contains('API Key')) {
      return '识别失败：AI 未配置或密钥失效，请到「设置」页检查 AI 配置';
    }
    if (err.contains('403') || err.contains('网关')) {
      return '识别失败：识别服务暂时忙碌，请稍后重试';
    }
    if (err.contains('解析') || err.contains('格式') || err.contains('空')) {
      return '识别失败：题目可能不清晰——可改用「读题填参」手动输入条件';
    }
    return '识别失败，请重试';
  }

  static String _mimeOf(String? ext) {
    switch (ext?.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      default:
        return 'image/png';
    }
  }

  /// 填入对应模块/执行动作 → 关对话框 → 跳页。
  void _fill(ScanResult scan) {
    // v2.14 R5：原图随 fill 带给目标页（系谱识别要对照核对；控制器里
    // 的那份已被 sendScan 消费清空，只能用本对话框的备份）。
    ModuleFillBus.stageScanImage(_pickedB64);
    final ok = ModuleFillBus.fillScan(scan.module, scan.params, scan.actions);
    if (ok) {
      Navigator.of(context).pop();
    } else {
      ModuleFillBus.takePendingScanImage(); // 不跳页 = 没人消费，清掉防串图
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('该题型暂不支持自动填参，已为你总结题干')));
    }
  }

  /// v2.12+ R1 P0 #1：把识别结果加进错题本。
  ///
  /// 字段映射：
  ///   - stem            = scan.summary          (AI 总结的题干/考点)
  ///   - subjectArea     = scanModuleLabel(...) (识别为的模块名)
  ///   - userAnswer / correctAnswer = ''          (OCR 还没识别对错，留空给学生填)
  ///   - errorType       = concept               (OCR 误识 / 概念理解错最常见)
  ///
  /// v2.12+ R2 A2 P1-4：**保留 dialog 不 pop**——学生可以继续拍下一
  /// 张题（拍题入口是多张连拍的场景，弹走 dialog 会打断连续录入）。
  /// 只弹「已加入错题本 → [撤销]」SnackBar，5 秒可 Undo——避免 OCR
  /// 错的题被静默入库，学生回头看错题本发现"这题明明识别对了为什么
  /// 进错题本"的认知撕裂。
  ///
  /// Undo 流程：点 [撤销] → `MistakeBook.instance.delete(added.id)` →
  /// entry 进 trash（不是真删，与 v2.12 R1 P0 #5 软删除一致）。
  /// 5 秒过期后用户还可以从错题本页回收站恢复（之前 R1 #5 已做）。
  /// 不用 `restoreFromTrash` 是因为刚 add 的 entry 在 entries 不在 trash，
  /// delete 把 entry 移到 trash 后用户后续可走回收站链路恢复。
  void _addToMistakeBook(ScanResult scan) {
    // v2.13 R4-1 P0（一票否决修复）：老师角色守卫。拍题对话框在老师
    // 模式下也呈现（拍题是备课演示也能用的功能）——但错题本是学生
    // 私人空间：dashboard 老师视图按 studentOnly 过滤隐藏错题本入口
    //（见 dashboard_page.dart _visibleEntries），老师写入 = 数据进
    // 不可见错题本 + AI 整理照跑耗额度写不可见条目。守卫：老师点
    //「存入错题本」→ SnackBar 说明 + 不写入。方案 A（与 supervisor
    // 对齐）。学生照常写入。
    // v2.13 R5 P0：移除"家长"分支——产品决策 Biology 不面向家长。
    if (FirstRunStore.instance.currentRole() == UserRole.teacher) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(const SnackBar(
          content: Text('老师模式下错题本对学生可见；如需收藏请切学生模式')));
      return;
    }
    // R5 学生走查：与「存入错题本」共享组件同款去重——同一识别结果
    // 连点两次 / 与练习入口各存一次，会产生重复条目 + AI 整理重复耗额。
    final r = MistakeBook.instance.addOrFind(
      stem: scan.summary,
      userAnswer: '',
      correctAnswer: '',
      errorType: MistakeErrorType.concept,
      subjectArea: scanModuleLabel(scan.module),
    );
    if (!r.isNew) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(
          const SnackBar(content: Text('这道題已在错题本里（按识别摘要查重）')));
      return;
    }
    final added = r.entry;
    // v2.13 R3 P1-A2：与表单入口同款——加错题后立即入队 AI 自动整理。
    // 表单 _handleAdd 有这行（v2.12+ R1 P0 #3），拍题入口之前漏了 →
    // 学生最高频路径缺"AI 主动整理"承诺（5 秒归类 SnackBar 不弹）。
    // 入队不依赖 mounted：即使 dialog 已关，后台 500ms debounce 照跑。
    MistakeBook.instance.debugEnqueueAiOrganize(added.id);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('已加入错题本'),
        duration: const Duration(seconds: 5),
        // SnackBar + action 时 Flutter 默认 persist=true → 永不 dismiss，
        // 5 秒 Undo 窗口失效。显式 false 让 SnackBar 5 秒后真消失
        //（与 mistake_book_page 的 Undo 删除同一设计——见 v2.12 Wave 3-B P1）。
        persist: false,
        action: SnackBarAction(
          label: '撤销',
          onPressed: () {
            // 点 [撤销] = 软删除（移到 trash），后续可从错题本回收站恢复。
            // 这里不调 restoreFromTrash：刚 add 的 entry 在 entries 不在 trash，
            // 直接 delete(id) 是把"存入错题本"这个动作撤回的正确语义。
            MistakeBook.instance.delete(added.id);
          },
        ),
      ),
    );
    assert(added.id.isNotEmpty,
        'MistakeBook.add 应返回带 id 的 entry（看 mistake_book.dart:312）');
  }

  @override
  Widget build(BuildContext context) {
    final scan = _ctrl.lastScan;
    final busy = _ctrl.busy;
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.add_photo_alternate_outlined,
              size: 20, color: AppColors.teal),
          const SizedBox(width: 8),
          const Expanded(child: Text('拍题识别')),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // v2.13 学生走查 P0：零术语版介绍 + 空态价值主张——
            // 「参数」是开发词；首屏只一个图标学生以为坏了。
            // R6 学生走查 #4：桌面端是文件选择器、没有相机入口——
            // 文案不说「拍照」，说「选题目照片」，手机拍的传过来也行。
            // R7：「内置题库」措辞违背「工具不是内容库」观感——
            // 改「我的题库」并指路（问 AI 面板内查看）。
            Text('选一张题目照片（手机拍了传过来也行，截图/课件图都可以），'
                'AI 读题后自动把条件填进对应计算器；识别成功的题还会'
                '存入「我的题库」（在「问 AI」面板里查看）。',
                style: AppText.caption.copyWith(color: AppColors.graphite)),
            const SizedBox(height: 14),
            if (busy)
              Row(children: [
                const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 10),
                Text(_ctrl.busyLabel.isEmpty ? '正在识别…' : _ctrl.busyLabel,
                    style: AppText.caption.copyWith(color: AppColors.steel)),
              ])
            else if (scan != null)
              _buildResult(scan)
            else
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    children: [
                      Icon(Icons.document_scanner_outlined,
                          size: 40, color: AppColors.teal),
                      const SizedBox(height: 10),
                      // R6 学生走查 #4：桌面端无相机，文案与能力一致。
                      Text('选题目照片 → 自动填条件 → 出答案步骤',
                          style: AppText.caption
                              .copyWith(color: AppColors.graphite)),
                      const SizedBox(height: 4),
                      Text('手写的题也能试；识别不对可手动改参数',
                          style: AppText.caption
                              .copyWith(color: AppColors.steel)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
        FilledButton.icon(
          onPressed: busy ? null : _pick,
          icon: const Icon(Icons.photo_library_outlined, size: 18),
          label: Text(scan == null ? '选择题目图片' : '再拍一题'),
        ),
      ],
    );
  }

  /// 识别结果：总结 + 模块 + 动作清单 + 填入按钮。
  Widget _buildResult(ScanResult scan) {
    final target = ModuleFillBus.targetOf(scan.module);
    final fillable = target != null &&
        (scan.params.isNotEmpty ||
            (scan.actions.isNotEmpty && target.applyActions != null));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('识别为：${scanModuleLabel(scan.module)}',
            style: AppText.caption.copyWith(color: AppColors.teal)),
        const SizedBox(height: 8),
        Text(scan.summary, style: AppText.body.copyWith(fontSize: 13)),
        if (scan.actions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final a in scan.actions)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.sand.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(scanActionLabel(a),
                        style:
                            AppText.caption.copyWith(color: AppColors.graphite)),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        // v2.12+ R1 P0 #1：第二行加「存入错题本」按钮，与「填入对应模块」并列。
        // OCR 错的题正好是学生最常需要整理的（不靠 AI 整理，而是用户主动
        // 决策"这题我确实不会/答错了"）。两按钮同权——「填入」走计算器链路，
        // 「存入错题本」走错题本链路，互不干扰。
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (fillable)
              FilledButton.icon(
                onPressed: () => _fill(scan),
                icon: const Icon(Icons.input_outlined, size: 16),
                label: Text('填入${target.label}'),
                style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact),
              )
            else
              Text('该题型仅总结，暂不支持自动填参',
                  style: AppText.caption.copyWith(color: AppColors.steel)),
            // v2.12+ R1 P0 #1：「存入错题本」按钮——outlined 风格表次要操作
            // (主操作是「填入」)。icon 用 bookmark_add 暗示"加入收藏"。
            OutlinedButton.icon(
              onPressed: () => _addToMistakeBook(scan),
              icon: const Icon(Icons.bookmark_add_outlined, size: 16),
              label: const Text('存入错题本'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.teal,
                side: BorderSide(color: AppColors.teal),
              ),
            ),
            // R6 学生走查 #6：原裸 Text 长得像不可点的第三枚按钮——
            // 带图标 + 前置说明，明确它是状态而非操作。
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_outline,
                    size: 13, color: AppColors.steel),
                const SizedBox(width: 4),
                Text('已存入题库',
                    style: AppText.caption.copyWith(color: AppColors.steel)),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// v2.9 动作的中文标签（拍题对话框与 AI 面板结果卡共用）。
/// R5 学生走查补齐：pd_inference（add_member）/ disease_risk
///（set_parents）动作落到中文——识别成功后学生不再看到原始英文类型名。
String scanActionLabel(Map<String, String> a) {
  switch (a['type']) {
    case 'create_family':
      return '创建家族 ${a['father'] ?? ''}×${a['mother'] ?? ''}';
    case 'add_external':
      return '添加样本 ${a['genotype'] ?? ''}';
    case 'next_generation':
      return '计算下一代';
    case 'add_member':
      // pd_inference 系谱录入：id + 性别 + 表型。
      final sex = a['sex'] == 'female' ? '女' : '男';
      final st = a['status'] == 'affected' ? '患病' : '正常';
      return '录入成员 ${a['id'] ?? ''}·$sex·$st';
    case 'set_parents':
      // disease_risk 风险计算：设双亲基因型与显隐模式。
      final mode = (a['mode'] ?? '').toLowerCase() == 'dom' ? '显性' : '隐性';
      return '设双亲 ${a['father'] ?? ''}×${a['mother'] ?? ''}（$mode）';
    case 'pd_capture_chart':
      // 系谱底图（对照原图核对用；防御性映射——当前 prompt 未强制）。
      return '系谱底图（对照核对）';
    default:
      return a['type'] ?? '动作';
  }
}
