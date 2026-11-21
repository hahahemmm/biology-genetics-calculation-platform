// module_fill.dart —— 拍题识别「填入对应模块」总线（v2.5 功能 1）
//
// 场景：老师在「问 AI」里上传题目图片，AI 识别出题型与参数后，
// 一键跳转到对应模块页面并把参数填进去（如遗传计算器的 p1/p2）。
//
// 架构：各页面在 initState 注册「填参目标」（moduleId → 页码 + 填参回调），
// HomeShell 注册导航器（切导航索引，不 push——项目既有裁定）。
// AI 面板只认 moduleId，不认识具体页面，解耦。
//
// v2.12 扩展（不在主导航的页面）：
//   目标可声明 pushFactory（不传 pageIndex 同样合法）。fill 时把 params
//   入队 _pendingFills，再由 pusher 推到路由栈；页面 initState 调
//   consumePending() 取出并 apply——与主导航切页后再 apply 的语义对齐。

import 'package:flutter/material.dart' show MaterialPageRoute, Navigator;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'ai_chat_controller.dart' show appCanvasKey;

/// 闸被拦下时交给 [ModuleFillTarget.onApplyFailed] 的 `reason`：**目标页已被
/// 使用者改过，本次参数未写入**。屏上提示直接用它（文案纪律：无 markdown
/// 星号、无方向词）。
const String kModuleFillSkippedDirty = '目标页签已有你自己的题，本次参数未写入';

/// 一个可填参的模块目标。
class ModuleFillTarget {
  /// 模块标识（AI 识别 JSON 里的 module 字段值），如 'cross_dihybrid'。
  final String moduleId;

  /// 主导航页码（HomeShell IndexedStack index）。
  /// v2.12：不传或传 -1 表示不在主导航（见 pushFactory）。
  final int pageIndex;

  /// 展示名（结果卡按钮文案用），如「遗传计算器·双基因」。
  final String label;

  /// 填参回调：页面已切到前台后调用；返回是否成功消费参数。
  final bool Function(Map<String, String> params) apply;

  /// v2.9 动作路由：AI 标准动作序列（[{"type":...}, ...]）的执行回调；可选——
  /// 无动作执行器的模块留 null（动作路由时回退填参/仅总结）。
  final bool Function(List<Map<String, String>> actions)? applyActions;

  /// v2.12：可选——当目标页面不在主导航（如变异页/遗传病页）时，
  /// fill 走 push 路由而非切导航索引。null = 走 pageIndex 切主导航。
  final WidgetBuilder? pushFactory;

  /// v2.19.32（移植备份仓）：可选——apply 拒收时的口信回调（页面自己给
  /// 提示，总闸不猜原因）。同 [applyActions] 的「加法」形状：null = 静默
  /// （旧行为），已有注册点一行不用改。
  final void Function(String moduleId, String reason)? onApplyFailed;

  /// v2.19.32（移植备份仓 v2.19.117 闸）：可选——**本次是否允许覆盖目标页
  /// 里已有的内容**。默认 null ＝ 一律允许（拍题识别/讲题回放/错题本的语义
  /// 是「我刚捕获了一道新题，拿去算」，覆盖是应该的）；课标 chip 的语义是
  /// 「带我去看看那一栏」，覆盖掉学生正在做的题是不该的——由目标页自己回答
  /// 「我那儿现在是不是空着」。判据 = isPristine 比**具名出厂常量**（⛔ 不用
  /// initState 快照）。返回 false 时：[fill]/[fillScan] **仍然切页**（导航
  /// 意图要满足），但**跳过写入**，并用 [kModuleFillSkippedDirty] 调
  /// [onApplyFailed]。只挡非 push 分支——push 目标是新实例，天然免疫。
  final bool Function()? canOverwrite;

  const ModuleFillTarget({
    required this.moduleId,
    required this.pageIndex,
    required this.label,
    required this.apply,
    this.applyActions,
    this.pushFactory,
    this.onApplyFailed,
    this.canOverwrite,
  });
}

/// 全局填参总线（静态注册表）。
class ModuleFillBus {
  static final Map<String, ModuleFillTarget> _targets = {};

  /// HomeShell 注册的主导航切换器（切 IndexedStack 索引）。
  static void Function(int pageIndex)? navigator;

  /// v2.12：push 路由回调（不在主导航的页面专用）。默认走 appCanvasKey
  /// 找 root Navigator 直接 push；测试或自定义路由可覆盖。
  static void Function(WidgetBuilder pushFactory)? pusher;

  /// v2.12：fill 入队的待处理 params（push 模式下页面 initState 调
  /// consumePending 取走）。key = moduleId。
  static final Map<String, Map<String, String>> _pendingFills = {};

  /// v2.12：fill 入队的待处理 actions（push 模式下页面 initState 调
  /// consumePendingActions 取走）。key = moduleId。
  static final Map<String, List<Map<String, String>>> _pendingActions = {};

  /// v2.19.35：push 型 target 的「本次 fill 来源标签」随 fill 入队，
  /// pushFactory 构建目标页时 [consumePushSourceLabel] 取走（取后即焚——
  /// 拍题等不传标签的 fill 取到 null ⇒ 回落注册点默认「拍题识别」）。
  /// 解决：课标深链 push 的遗传病/变异页，回程横幅原先写死
  /// 「来自拍题识别」= 一句假话（worker 发现并上报的阻塞项）。
  static final Map<String, String> _pendingPushSourceLabels = {};

  /// 取走并清除 moduleId 的待用来源标签（pushFactory 构建目标页时调用）。
  static String? consumePushSourceLabel(String moduleId) =>
      _pendingPushSourceLabels.remove(moduleId);

  /// v2.14 R5 补：拍题原图（base64）随 fill 传给目标页——学生走查：
  /// 系谱识别必须对照原图核对，原图只在拍题瞬间存在（sendScan 消费后
  /// pendingScanImage 即清空），拍题对话框在 _fill 前挂入，目标页
  /// takePendingScanImage() 取走展示。
  static String? _pendingScanImageBase64;

  /// 拍题对话框挂入原图（fill 前调用）。
  static void stageScanImage(String? base64) {
    _pendingScanImageBase64 = base64;
  }

  /// 目标页取走随 fill 传递的拍题原图（取走后清空；无则 null）。
  static String? takePendingScanImage() {
    final b64 = _pendingScanImageBase64;
    _pendingScanImageBase64 = null;
    return b64;
  }

  /// 页面注册填参目标（initState 调）；重复注册覆盖旧的。
  static void register(ModuleFillTarget target) {
    _targets[target.moduleId] = target;
  }

  /// 页面销毁时注销（dispose 调）。
  static void unregister(String moduleId) {
    _targets.remove(moduleId);
  }

  /// 查询某模块是否支持自动填参（结果卡据此决定按钮可用态）。
  static ModuleFillTarget? targetOf(String moduleId) => _targets[moduleId];

  /// 测试用：清空全部注册、导航器、pusher、待处理队列。
  static void resetForTest() {
    _targets.clear();
    _pendingPushSourceLabels.clear();
    navigator = null;
    pusher = null;
    _pendingFills.clear();
    _pendingActions.clear();
    _pendingScanImageBase64 = null;
  }

  /// v2.12：push 模式下，页面 initState 调用此方法取走 push 前入队的 params。
  /// 取走后清空条目；未入队则返回 null。
  static Map<String, String>? consumePending(String moduleId) {
    return _pendingFills.remove(moduleId);
  }

  /// v2.12：push 模式下，页面 initState 调用此方法取走 push 前入队的 actions。
  static List<Map<String, String>> consumePendingActions(String moduleId) {
    return _pendingActions.remove(moduleId) ?? const [];
  }

  /// 跳转并填参：先切页，待新页帧渲染完成后再回调填参。
  /// 返回 false = 该模块未注册（面板应提示「暂不支持自动填参」）。
  static bool fill(String moduleId, Map<String, String> params,
      {String? sourceLabel}) {
    final t = _targets[moduleId];
    if (t == null) return false;
    if (t.pushFactory != null) {
      // v2.12：不在主导航的页面——入队 + push 路由。
      _pendingFills[moduleId] = params;
      // v2.19.35：来源标签随 fill 入队，pushFactory 构建时取走。
      if (sourceLabel != null) _pendingPushSourceLabels[moduleId] = sourceLabel;
      _dispatchPush(t.pushFactory!, moduleId);
      return true;
    }
    navigator?.call(t.pageIndex);
    // v2.19.32（移植备份仓 v2.19.117 闸）：切页之后、写参之前，问一次
    // 目标页「你那儿还是空的吗」。⛔ 必须放在 navigator?.call **之后**
    // （切页才把目标页签挂上，State/controller 才拿得到当前值）；
    // 只挡非 push 分支——push 模式目标是新实例，本来就没人往里填过。
    // 拒绝时仍 return true：导航意图已满足，只是没写入。
    final can = t.canOverwrite;
    if (can != null && !can()) {
      t.onApplyFailed?.call(moduleId, kModuleFillSkippedDirty);
      return true; // 已跳转，只是没写入
    }
    // 切页后目标页 State 重建，当帧直接填会打在旧实例上——
    // 等下一帧再 apply（与 GuideController 切页后重建 overlay 同理）。
    SchedulerBinding.instance.addPostFrameCallback((_) {
      // v2.19.32：apply 的返回值不再被丢弃——拒收时交回给页面自己说，
      // 学生至少知道「带不走」而不是对着默认值照抄（同备份仓 v2.19.31）。
      final ok = t.apply(params);
      if (!ok) {
        t.onApplyFailed?.call(moduleId, '目标页未消费本次参数');
      }
    });
    // addPostFrameCallback 自己不排帧：导航器是假实现（测试）时
    // 没有 setState 排帧，回调会永远等不到——兜底排一帧。
    SchedulerBinding.instance.scheduleFrame();
    return true;
  }

  /// v2.9 动作路由：带标准动作序列的填参入口。
  /// 动作非空且目标注册了 applyActions → 走动作路由；否则回退填参。
  /// 返回 false = 模块未注册。
  static bool fillScan(String moduleId, Map<String, String> params,
      List<Map<String, String>> actions,
      {String? sourceLabel}) {
    final t = _targets[moduleId];
    if (t == null) return false;
    if (t.pushFactory != null) {
      // v2.12：不在主导航的页面——入队 + push 路由。
      _pendingFills[moduleId] = params;
      _pendingActions[moduleId] = List.of(actions);
      // v2.19.35：同 fill，来源标签随本次入队。
      if (sourceLabel != null) _pendingPushSourceLabels[moduleId] = sourceLabel;
      _dispatchPush(t.pushFactory!, moduleId);
      return true;
    }
    navigator?.call(t.pageIndex);
    // v2.19.32（移植备份仓 v2.19.143 修复）：⛔ 这条路径原先完全绕过
    // canOverwrite——而拍题识别链路走的正是 fillScan（scan_upload_dialog /
    // assistant_panel），学生会看着手敲的值被静默顶掉、连一句「没有覆盖」
    // 都没有。闸必须在这里：navigator?.call 之后（同 fill）、useActions
    // **之前**——applyActions（如系谱 create_family/add_external）同样会
    // 重建状态，更具破坏性，不能只拦填参那半边。
    final can = t.canOverwrite;
    if (can != null && !can()) {
      t.onApplyFailed?.call(moduleId, kModuleFillSkippedDirty);
      return true; // 已跳转，只是没写入
    }
    final useActions = actions.isNotEmpty && t.applyActions != null;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (useActions) {
        if (t.applyActions!(actions)) return; // 动作全部消费
      }
      // v2.19.32：同 fill——回退填参的拒收也要让页面能说出口。
      final ok = t.apply(params); // 回退：仅填参（或动作路由失败时兜底）
      if (!ok) {
        t.onApplyFailed?.call(moduleId, '目标页未消费本次参数');
      }
    });
    SchedulerBinding.instance.scheduleFrame();
    return true;
  }

  /// v2.12：内部——执行 push 路由。优先用外部注入的 pusher；未注入时
  /// 走 appCanvasKey 兜底（root Navigator，恒可达）。
  ///
  /// v2.12 修复 (VerB1 Bug 1)：兜底失败时（pusher 未注入 + appCanvasKey
  /// 上下文亦不可达，如冷启动极早期）静默放弃会让 `_pendingFills` /
  /// `_pendingActions` 永久残留 → 下次用户从 curriculum_page 正常打开
  /// VariationPage 时 initState 调 consumePending 取到幽灵数据自动高亮+滚动。
  /// 修复：兜底失败时清掉本 moduleId 的两条入队数据。
  static void _dispatchPush(WidgetBuilder pushFactory, String moduleId) {
    final p = pusher;
    if (p != null) {
      p(pushFactory);
      return;
    }
    final ctx = appCanvasKey.currentContext;
    if (ctx == null) {
      // 兜底失败（无 pusher + 无 Navigator 上下文）→ 清掉入队避免幽灵消费。
      _pendingFills.remove(moduleId);
      _pendingActions.remove(moduleId);
      _pendingPushSourceLabels.remove(moduleId);
      return;
    }
    Navigator.of(ctx).push(MaterialPageRoute<void>(builder: pushFactory));
  }
}
