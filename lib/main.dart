
import 'dart:async';
import 'dart:ui' show FlutterView;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/ai_client.dart' show AiConfig;
import 'pages/big_question_cards_page.dart';
import 'pages/cross_calculator_page.dart';
import 'pages/curriculum_page.dart';
import 'pages/dashboard_page.dart';
import 'pages/evolution_page.dart';
import 'pages/genetic_disease_page.dart';
import 'pages/genetic_pedigree_page.dart';
import 'pages/knowledge_graph_page.dart';
import 'pages/molecular_page.dart';
import 'pages/ploidy_page.dart';
import 'pages/variation_page.dart';
import 'pages/settings_page.dart';
import 'pages/home_page.dart';
import 'services/window_channel.dart';
import 'state/accounts_store.dart';
import 'state/app_state.dart';
import 'state/first_run_store.dart';
import 'state/present_mode_controller.dart';
import 'state/theme_controller.dart';
import 'theme.dart';
import 'guide/guide_controller.dart';
import 'guide/guide_keys.dart';
import 'guide/guide_overlay.dart';
import 'ui/account_gate.dart';
import 'ui/ai_chat_controller.dart' show appCanvasKey;
import 'ui/app_navigator_key.dart';
import 'ui/app_navigation.dart';
import 'ui/assistant_panel.dart';
import 'ui/classroom_quick_bar.dart';
import 'ui/file_drop.dart';
import 'ui/file_drop_bus.dart';
import 'ui/image_pick.dart' show PickedImage;
import 'ui/module_fill.dart';
import 'ui/page_activation.dart';
import 'ui/scan_upload_dialog.dart';
import 'ui/scroll_reveal.dart';
import 'pages/widgets/shortcut_cheatsheet.dart';

/// 生物遗传题教学软件（Flutter，跨平台：Windows / 安卓 / iOS / Web）。
///
/// 核心模块：遗传图谱计算 + 9331 计算器 + AI 遗传助手（右侧滑出，
/// 自动读取当前页面与计算上下文）。
/// 领域逻辑全部在 lib/engine（纯 Dart，与平台无关）；
/// 设计约定见 docs/ARCHITECTURE.md 与 lib/theme.dart。
///
/// v2.19.8 护眼模式暖色矩阵（5×4 行主序）：微升红绿 + 压蓝 ~8% +
/// 暖白常数项——温和档，白天白底不刺眼，深色模式同样生效。
const List<double> _eyeCareMatrix = <double>[
  1.03, 0.02, -0.01, 0, 12,
  0.01, 1.01, -0.01, 0, 8,
  -0.04, -0.01, 0.92, 0, -2,
  0, 0, 0, 1, 0,
];

/// v2.12+ R1 final-B P0 #4：全局异常兜底——之前任何未捕获异常
/// （坏 JSON 导入、平台插件报错、async 未 await 等）会冒泡到
/// FlutterError.onError 让整个 app 闪退，学生做题到一半崩溃
/// 体验灾难。现在双层兜底：
///   1. FlutterError.onError：UI 同步路径异常（build/layout/paint）
///   2. runZonedGuarded：async 异步路径异常（Future unhandled、Timer
///      callback 抛错等）
/// 都走 FlutterError.presentError 打印到 console，但不再让 app 闪退。
Future<void> main() async {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    // v2.12+ R1 final-B P0 #4：UI 同步路径异常兜底（build / layout /
    // paint 阶段未捕获错误）。保留 FlutterError.presentError 打印
    // 到 console 便于排错，但不 throw → 整个 app 不闪退。
    FlutterError.onError = (details) {
      FlutterError.presentError(details);
      // 不 rethrow，app 继续运行。坏 JSON 导入 / 平台插件报错等
      // 都走这里，UI 层配合 try/catch 弹 SnackBar 即可。
    };
    // v2.12.0+2 hotfix 补漏：启动即加载 AppState 偏好（思维链默认展开等）
    // ——之前 v2.12.0+2 hotfix 加了 setter + 落盘，但启动钩子漏挂导致重启
    // 后偏好失效回到默认 true。await 加载完再 runApp，避免首帧闪默认。
    // v2.24：先定档案目录，再让各 store 读盘（顺序不能反）。
    await AccountsStore.instance.load();
    await AppState.instance.load();
    // v3.8：安卓启动即沉浸全屏——系统状态栏（时间/信号/电池）与底部
    // 导航栏默认隐藏，屏幕边缘滑动可临时唤出、数秒后自动缩回（官方
    // 推荐 SystemUiMode.immersiveSticky）。修复用户反馈：状态栏透明
    // 叠加在应用命令栏上，时间文字正好盖住左上角 ☰、右侧内容与系统
    // 图标混叠——沉浸后状态栏不再占据/拦截顶部区域，☰ 露出且可点。
    // Windows 桌面无状态栏概念，此调用被平台忽略，无副作用。
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    // v2.2 主题重写：AppColors token 已从 ThemeController.effectiveBrightness
    // 实时派生（用户锁定模式优先，仅「跟随系统」时读平台亮度），
    // 无需也不允许在生产路径手动 sync——静态残留已灭绝。
    runApp(BiologyApp());
  }, (error, stack) {
    // v2.12+ R1 final-B P0 #4：async 异步路径异常兜底（Future unhandled
    // / Timer callback / 平台插件回调等）。同样打印到 console 但
    // 不 throw，app 继续运行。
    FlutterError.presentError(FlutterErrorDetails(
      exception: error,
      stack: stack,
      library: 'app async zone',
    ));
  });
}

class BiologyApp extends StatefulWidget {
  const BiologyApp({super.key});

  @override
  State<BiologyApp> createState() => _BiologyAppState();
}

class _BiologyAppState extends State<BiologyApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    ThemeController.instance.load();
    PresentModeController.instance.load();
    // v2.1k：监听系统亮度切换（白天↔晚上）——ListenableBuilder 只订阅
    // ThemeController.mode 变化，不会响应 platformBrightness 变化；
    // 之前会导致：用户在浅色模式 + 系统切到深色 → _dark 残留浅色
    // → AppColors.ink 拿到错误的色 → 课标页 description 出现"白字白底"
    // 不可见（暖米白字 on 暖近白底）。监听 platform brightness 变化
    // 主动 notify，触发 ListenableBuilder rebuild → AppColors.sync 同步。
    WidgetsBinding.instance.addObserver(this);
    // v2.19.26：首帧后应用方向策略（手机锁竖屏 / 平板放开，
    // 见 _applyOrientationPolicy）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyOrientationPolicy();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() {
    // 系统亮度切换（白天↔晚上）→ 触发 ThemeController notify，
    // 顶层 ListenableBuilder rebuild → AppColors.sync 用最新
    // MediaQuery.platformBrightnessOf(context) 重新求值 → 全局 _dark
    // 同步。mode 仍是 ThemeMode.system 时尤其关键。
    // 用 ThemeController.onPlatformBrightnessChanged() 公开方法（避免
    // ChangeNotifier.notifyListeners 外部 protected 警告）。
    ThemeController.instance.onPlatformBrightnessChanged();
  }

  // ── v2.19.26 安卓端方向策略 ──
  //
  // 手机（短边 < 600dp，如 9:19.5 的 390×844）：锁竖屏——竖拿是
  // 设计基准（底导 + 单列流），横屏不保证体验，直接不给出；
  // 平板（短边 ≥ 600dp，覆盖 3:4 的 768×1024 / 834×1112 与
  // 16:10 常见 10" 屏）：放开横竖双方向，布局按宽自适应
  // （≥600 宽 rail / 窄屏堆叠），横屏默认、竖屏也可用。
  // 零插件（SystemChrome 纯 Dart）；Windows/Web 平台调用被忽略。
  // 类档差分：只有手机↔平板跨档才重复下发，窗口缩放不刷平台通道。
  //
  // 视图来源：MaterialApp.builder 里捕获的 FlutterView（本 State 的
  // context 在 View 之上，View.maybeOf 返 null，故借 builder context）。
  // 尺寸取 view.physicalSize（视图物理像素）——官方示例取 display.size
  // 是为防大屏 letterbox 误判；但 Android 16（targetSdk 36，本机 SDK
  // 默认已 36）会忽略 ≥600dp 设备的方向锁，letterbox 风险由系统兜底，
  // 且 flutter_test 的 TestDisplay 不跟随视口覆盖（widget test 走不通
  // display 路径）。类档差分照旧。
  bool? _tabletOriented;
  FlutterView? _policyView;

  void _applyOrientationPolicy() {
    final view = _policyView;
    if (view == null) return;
    final size = view.physicalSize / view.devicePixelRatio;
    final tablet = size.shortestSide >= 600;
    if (tablet == _tabletOriented) return;
    _tabletOriented = tablet;
    // unawaited：平台通道异步，失败由全局 zone 兜底打印，不阻塞 UI。
    // 手机档含 portraitDown（官方建议锁竖屏至少支持正反竖屏，
    // = Android userPortrait；倒扣手机内容不翻转）。
    unawaited(SystemChrome.setPreferredOrientations(tablet
        ? const [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
          ]
        : const [
            DeviceOrientation.portraitUp,
            DeviceOrientation.portraitDown,
          ]));
  }

  @override
  void didChangeMetrics() {
    // 折叠屏展开 / 多窗口跨档变化 → 重新评估方向策略（SystemChrome
    // 不触 setState，build 外调用安全）。类档未变时内部直接返回。
    _applyOrientationPolicy();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // 同时订阅主题与课堂模式：任一变化都重建 MaterialApp。
      listenable: Listenable.merge(
          [ThemeController.instance, PresentModeController.instance]),
      builder: (context, _) {
        // v2.2 主题重写：token 实时派生（ThemeController.effectiveBrightness），
        // 此处只需让 ListenableBuilder 订阅模式切换触发 rebuild；
        // 系统亮度变化由 didChangePlatformBrightness → notify 触发 rebuild，
        // Text/TextStyle 重建时重新求值 token getter——颜色永远正确。
        return MaterialApp(
          // v2.24：AI 工具执行前的确认对话框要在无 BuildContext 的调用链里弹，
          // 需要一个全局 Navigator 句柄（见 ui/tool_confirm.dart）。
          navigatorKey: appNavigatorKey,
          title: '生物遗传计算平台',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: ThemeController.instance.mode,
          // 课堂模式（2.3）：全场字号 ×1.3，面向大屏/白板讲课（按钮/
          // 芯片随文字等比变大，触控目标随之放大；画布另有激光笔层）。
          // builder 注入 MediaQuery.textScaler，覆盖所有页面与对话框
          //（builder 在 Navigator 之上）。
          // v2.3.4 白板触控增强：希沃/鸿合几平米白板，老师用胳膊/教鞭点，
          // 指针是「瞬移」而非连续滑动——除字号外再全局放大触控目标：
          // 图标按钮 52px、各类按钮最小 52px 高（WCAG/希沃课堂共识
          // 触控目标 ≥48px，大屏再上一档）。
          //
          // v2.12 设计系统闭环（VerC1 code review 修）：
          // 旧版外层 AnimatedTheme(data: base) + 内层 Theme(data: target)
          // 看似有 250ms ease-out 缓动——但 Theme.of(context) 找最近
          // 的 Theme，**内层 target 永远赢**，descendants 看到的是
          // 新色瞬间跳变；AnimatedTheme 这一层完全无效（死代码）。
          // 课堂模式仍走内层 Theme 立即覆盖 iconButtonTheme / 字号
          // （避免 AnimatedTheme tween 第 0 帧还是 begin 状态导致
          // whiteboard_touch_test 拿 null）。dark/light 切换瞬时
          // ——v2.12 范围内暂不实现真 lerp（TweenAnimationBuilder<Color>
          // 大改留待后续）。
          builder: (context, child) {
            // v2.19.26：捕获 FlutterView 供方向策略用（display 物理
            // 尺寸，见 _applyOrientationPolicy）。builder 的 context
            // 在 View 之下，View.maybeOf 可达；本 State 的 context
            // 在 MaterialApp 之上，不可达。
            _policyView = View.maybeOf(context);
            final base = Theme.of(context);
            final mq = MediaQuery.of(context);
            final presentOn = PresentModeController.instance.enabled;
            final scaledMq = presentOn
                ? mq.copyWith(
                    textScaler: mq.textScaler.clamp(
                        minScaleFactor: PresentModeController.textScale),
                  )
                : mq;
            final target = presentOn
                ? base.copyWith(
                    iconButtonTheme: IconButtonThemeData(
                      style: IconButton.styleFrom(
                        minimumSize: const Size(52, 52),
                        tapTargetSize: MaterialTapTargetSize.padded,
                      ),
                    ),
                    filledButtonTheme: FilledButtonThemeData(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(64, 52)),
                    ),
                    outlinedButtonTheme: OutlinedButtonThemeData(
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size(64, 52)),
                    ),
                    textButtonTheme: TextButtonThemeData(
                      style: TextButton.styleFrom(
                          minimumSize: const Size(56, 48)),
                    ),
                    // v2.18 R8 老师走查 #2/#9：课堂主题原先只抬四大按钮
                    // 类型，FilterChip 全军覆没（语义区 10 chip + 底栏
                    // 模式 segmented 保持最小体量，与 52px 大按钮危险
                    // 反差）。chipTheme 加肉：垂直 padding 12 → 课堂
                    // chip ≈ 48px+ 触控目标。
                    // v2.19.29 R13 移植：原 const ChipThemeData(labelStyle: 裸 TextStyle)
                    // 会把 chip 标签已解析样式整体抹掉（family/size/color
                    // 全 null，真机掉回引擎默认 14px）——与 theme.dart
                    // v2.1n「无色样式整体替换断链」同族。base.chipTheme
                    // 实测已带 w600，只覆盖 padding 即可。
                    chipTheme: base.chipTheme.copyWith(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                  )
                : base;
            // v2.19.8 R9 集成（v2.13 埋的 eyeCare 状态层至此接上）：
            // 护眼模式 = 全局暖色矩阵滤镜，叠加在浅/深/课堂主题之上——
            // 矩阵走「微升红绿 + 压蓝 + 暖白常数」温和档（用户反馈：
            // 白天白底刺眼，系统护眼模式关闭后尤甚）。放 builder 内层
            // → Navigator/对话框/画布全部吃滤镜，无需逐页改色。
            Widget inner = MediaQuery(
              data: scaledMq,
              child: Theme(data: target, child: child!),
            );
            if (ThemeController.instance.eyeCare) {
              inner = ColorFiltered(
                colorFilter: const ColorFilter.matrix(_eyeCareMatrix),
                child: inner,
              );
            }
            return inner;
          },
          // 不能 const：模式切换时若 widget 实例与上一帧 identical，
          // Element 会跳过 rebuild，AppColors token 不刷新 → 深浅混染。
          // v2.24：包门禁。仍不加 const——沿用上面「identical 实例会冻结
          // AppColors token」的约束（AccountGate 是 Stateful，State 不会丢）。
          home: AccountGate(child: HomeShell()),
        );
      },
    );
  }
}

/// v2.14 R5 学生走查 P0：pd_inference / disease_risk 的 ModuleFillTarget
/// **App 级常驻注册**。原实现注册在 GeneticDiseasePage.initState、
/// dispose 注销——而拍题 FAB 在 HomeShell 上：页面盖住 FAB 时扫不了，
/// pop 回来即注销，fillScan 在真实动线永远查不到 target（「拍系谱图→
/// 自动填入推断器」实际走不通；disease_risk 自 v2.12 起同款潜伏）。
/// 上移到 App 生命周期（HomeShell.initState 调用，永不注销）：
/// pushFactory 负责 push 新实例，被 push 页 initState 自愈消费
/// pending params/actions。apply 对 pushFactory target 不会被总线回调
/// （push 分支直接入队+push），false 是兜底语义。抽成顶层函数供
/// HomeShell 与测试共用。
void registerAppLevelModuleTargets() {
  ModuleFillBus.register(ModuleFillTarget(
    moduleId: 'pd_inference',
    pageIndex: -1,
    label: '系谱推断·判遗传方式',
    apply: (_) => false,
    pushFactory: (_) => GeneticDiseasePage(
        focusInference: true,
        sourceLabel:
            ModuleFillBus.consumePushSourceLabel('pd_inference') ?? '拍题识别'),
  ));
  ModuleFillBus.register(ModuleFillTarget(
    moduleId: 'disease_risk',
    pageIndex: -1,
    label: '遗传病页·风险计算',
    apply: (_) => false,
    pushFactory: (_) => GeneticDiseasePage(
        sourceLabel:
            ModuleFillBus.consumePushSourceLabel('disease_risk') ?? '拍题识别'),
  ));
  // v2.19.32 P1：cross_chromosomal_struct 上移应用级常驻注册。原注册跟
  // VariationPage 实例生命周期走（initState 注册 / dispose 注销），拍题
  // push 出的第二个实例 pop 时会注销全局 target，再次拍题深链返回 false。
  // 页面实例只消费入队数据，注册永不随页面销毁（同 pd_inference 先例）。
  ModuleFillBus.register(ModuleFillTarget(
    moduleId: 'cross_chromosomal_struct',
    pageIndex: -1,
    label: '变异页·染色体结构变异',
    apply: (_) => false,
    pushFactory: (_) => VariationPage(
        sourceLabel: ModuleFillBus.consumePushSourceLabel(
                'cross_chromosomal_struct') ??
            '拍题识别'),
  ));
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => HomeShellState();
}

/// v2.12 R1 C P0 #8：HomeShell 的 State 类**公开化**（原 `_HomeShellState`
/// 是 private，test 在同 package 也无法跨文件 import private 类）。改名
/// 为 `HomeShellState` 后 `test/main_test.dart` 能 `tester.state<HomeShellState>(...)`
/// 拿到 state 实例并调 debug 钩子（`debugForceOffstageCheck` /
/// `debugGetAccessTimes` / `debugSetAccessTimeForTest` / `debugGetOffstageTick`）。
/// 改名不破坏外部 API（HomeShell 仍是 widget，外部只 import 它的类型）。
class HomeShellState extends State<HomeShell> {
  int _index = 0;
  /// v3.7 ☰：仅折叠/展开「系谱左控制面板」——导航（桌面 Rail /
  /// 移动底部 NavigationBar）一律常驻，不可被 ☰ 隐藏（用户裁定：
  /// ☰ 收纳的是增加家族/连线/XY 等控制功能，导航保持可见）。
  /// 窄屏默认折叠（画布最大化，☰ 打开 = 控制抽屉）。
  bool _navCollapsed = false;

  // ── v2.12 R1 C P0 #8：IndexedStack 10 页 5min offstage 内存治理 ──
  //
  // 历史：v2.12 计划 a7bbd31 commit 写过此治理，在另一条 branch 被 reset
  // 时被一起丢弃，本次重做。
  //
  // 原 bug：IndexedStack 10 个 page State/Engine/Controller 全部常驻，
  // 启动后吃 30-80 MB（系谱/知识图谱引擎首当其冲）。修法：维护每页
  // 最近一次访问时间，超过阈值未访问 → `Visibility(visible: false,
  // maintainState: true)` 包住（保留 State 但不绘制）——这是 Flutter
  // 推荐的"挂起但不销毁"模式，比 `Offstage` 兼容性更好（Offstage
  // 会触发 MediaQuery 重算）。
  //
  // 5min 阈值经验值（2026-09-06 worker C 落地）：老师切 tab 频率高，
  // 5min 是"忘切"边界——再久用户大概率已离开当前任务，回访会重新
  // 触发 onTap 自动恢复 visible + state。15s 扫描周期足够轻量
  // （10 个 page × 1 次 DateTime.now 比较，< 1μs）。
  //
  // 设计：
  //   - `_lastAccess[i]` 记录第 i 页最近一次 onTap 时间
  //   - `Timer.periodic(15s)` 每 15s 检查一次
  //   - 检查命中 → `setState` 触发 ListenableBuilder rebuild
  //   - 当前页 (_index) 永不 offstage（用户能看到）
  //   - test 钩子：`debugForceOffstageCheck()` 立刻触发扫描
  //   - test 钩子：`debugGetAccessTimes()` 返 Map 副本（_lastAccess 镜像）
  static const Duration _offstageThreshold = Duration(minutes: 5);
  static const Duration _offstageScanPeriod = Duration(seconds: 15);

  /// 每页最近一次访问时间（onTap 时更新当前 index；初次启动时给所有
  /// 页一个"现在"基准，避免首帧就被 offstage）。
  final Map<int, DateTime> _lastAccess = <int, DateTime>{};

  /// 扫描周期 Timer；`dispose` 时 cancel。
  Timer? _offstageTimer;

  /// offstage 决策触发的 rebuild 计数器（test 用 `debugOffstageTick`
  /// 拿到最新 tick 值；逻辑路径不直接用——`shouldOffstage(i)` 决定
  /// 单页可见性，setState 触发整个 build 即可）。
  int _offstageTick = 0;

  /// Wave2 拖图入窗：FileDropBus 兜底订阅（拍题对话框未开时替它开框）。
  /// dispose 时 cancel。
  StreamSubscription<PickedImage>? _fileDropSub;

  /// v2.19.67 P2 #3：正在开拍题对话框的哨兵——从 _onDroppedImage 通过
  /// hasConsumer 检查到对话框 initState claim() 之间的窗口内，后续
  /// 拖图事件直接忽略（防双开）。对话框路由完成/失败后复位。
  bool _dropDialogOpening = false;

  /// v2.19.68 P2-6：课堂模式上一次开关态（null = 首帧基线）。
  /// 进入课堂大屏（false→true 跳变）时触发 AI Key 自检提醒。
  bool? _presentWasEnabled;

  /// 第 i 页当前是否应 offstage（不可见但保留 State）。
  bool _shouldOffstage(int i) {
    if (i == _index) return false; // 当前页永不 offstage
    final last = _lastAccess[i];
    if (last == null) return false; // 还没访问过 → 首次启动不 offstage
    return DateTime.now().difference(last) > _offstageThreshold;
  }

  // 2.2 批次2：移除刷题模块（练习/高考真题/系谱推断/变式辨识），
  // 转型通用生物计算器；导航保持剩余项原有相对顺序。
  // 2.2 批次4a：插入「首页」为第 0 项（图标化功能入口），默认启动页，
  // 原 9 项顺延；数字快捷键为位置映射（digit1→第0项…），自动适应。
  // v2.19.60：设置/关于移到导航末位（用户要求「设置页和详情页应该排在
  // 导航栏最后一个位置」）——变异/遗传病提前到 9/10，设置/关于落到 11/12。
  // v2.20.0：导航表从「五张并行常量表」收敛到 lib/ui/app_navigation.dart
  // 一个目录（名字/短名/描述/图标/首页卡片文案同源）。全部按位置读表的
  // 调用（Rail/底导/「全部」面板/数字键/引导 pageIndex/首页卡片）都读它。
  static const List<AppNavDestination> _nav = appNavDestinations;

  /// v2.19.60：供 test/nav_order_guard_test.dart 逐字比对顺序的只读快照。
  /// v2.20.0：改为派生 getter——顺序真相唯一在 app_navigation.dart，
  /// 守卫仍按位置逐字比对（签名不变，守卫文件零改动）。
  static List<String> get pageNamesForTest =>
      <String>[for (final d in _nav) d.name];

  /// v2.22.0：主导航**显示层**的可见条目（pageIndex 空间）。
  ///
  /// ⚠ 目录顺序 == pageIndex 永不变动；只是「套路卡」等页从 Rail / 底导 /
  /// 「全部」面板 / 首页撤下独立入口（visibleInNav = false）。显示层遍历
  /// 一律走这里，取到的下标仍是 pageIndex（_select 的入参语义不变）。
  static final List<int> _navVisibleIndexes = appNavVisiblePageIndexes;

  /// 当前页在主导航条上的**可见索引**；当前页不可见（隐藏页）⇒ -1
  /// （调用方据此不高亮任何项——绝不越界、不错位高亮）。
  int get _visibleNavIndex =>
      appNavVisibleIndexOf(_index.clamp(0, _nav.length - 1));

  // ── v2.20.0：导航选中项自动进视口 ────────────────────────────
  //
  // Rail 13 项在 800 高窗口下总高 ≈ 936（73×13）必须纵向滚；底导 14 项
  // 在 390 宽手机下必须横向滚。原实现两者都只是「可滚」，选到/落到
  // 屏幕外的项时选中态看不见（用户以为没选中）。这里给每个导航项挂
  // GlobalKey，select 后 postFrame 用 Scrollable.ensureVisible 拉进视口。
  //
  // 两套 Key 分开：Rail 与底导同一时刻只挂一套（build 里二选一），
  // 但分开可避免跨断点重建时同名 key 短暂并存。
  final List<GlobalKey> _railItemKeys = <GlobalKey>[
    for (var i = 0; i < _nav.length; i++) GlobalKey(debugLabel: 'rail-item-$i'),
  ];
  final List<GlobalKey> _bottomItemKeys = <GlobalKey>[
    for (var i = 0; i < _nav.length; i++)
      GlobalKey(debugLabel: 'bottom-item-$i'),
  ];

  /// 把当前选中项滚进它所在导航条的视口（postFrame 调用；已可见则 no-op）。
  ///
  /// v2.20.0（M3.1 评审返工）：原实现连调 keepVisibleAtEnd +
  /// keepVisibleAtStart，第二次会把**已经可见**的项对齐到视口起点
  ///（SDK 的 keepVisibleAtStart 对可见目标不会提前返回，只是把目标调成
  /// pixels——注释写反了）。现统一走 [revealInViewport]：先量 start/end
  /// 偏移判定是否已完整可见，只有真正越界才按方向滚一次。
  void _revealSelectedNavItem() {
    if (!mounted) return;
    final i = _index.clamp(0, _nav.length - 1);
    // v2.22.0：当前页若是隐藏页（不在主导航条上）⇒ 没有可滚入的元素，
    // 直接让路（既不越界取 key，也不滚动到别项）。
    if (appNavVisibleIndexOf(i) < 0) return;
    for (final keys in <List<GlobalKey>>[_railItemKeys, _bottomItemKeys]) {
      final ctx = keys[i].currentContext;
      if (ctx == null) continue;
      // duration zero ⇒ 立即跳到位（切页不该有滚动动画）；目标已可见时
      // helper 内部直接返回，连 jumpTo 都不会发。
      unawaited(revealInViewport(ctx));
      return; // 当前形态的那一套已处理（另一套不在树上）
    }
  }

  // 不能 static const：同上，页面实例必须每帧新建，主题切换时
  // Element.update 才会触发 rebuild 刷新静态 token（State 因
  // runtimeType+key 匹配而保留，画布数据不丢）。
  //
  // v2.20.0：页面列表直接按导航目录顺序生成，页面构建按稳定 id 分支
  // （不用 go_router、不动 IndexedStack 语义）。目录顺序 == 页面索引。
  List<Widget> _buildPages() => <Widget>[
        for (final d in _nav) _buildPageById(d.id),
      ];

  /// 一个导航目的地 → 页面实例（按稳定 id 分支；不引入路由库）。
  ///
  /// ★ 严禁给这些页面加 const：const 实例被 canonicalize，Element
  ///   identical 短路永不 rebuild → 启动首帧（system+平台dark）冻结的
  ///   inkD 米白标题文字在切浅色后永远残留 = 白底白字（2026-08-29
  ///   实锤：正是这四个被投诉的分子/进化/倍性页）。
  Widget _buildPageById(String id) {
    switch (id) {
      case 'home':
        // 2.2 批次4a：图标化首页；卡片点击经回调切导航索引
        //（单一导航事实源，首页不自开页面栈）。
        return DashboardPage(onOpenTool: _select);
      case 'pedigree':
        return GeneticPedigreePage(
            navCollapsed: _navCollapsed, onNavPressed: _onNavPressed);
      case 'cross':
        return CrossCalculatorPage(
            navCollapsed: _navCollapsed, onNavPressed: _onNavPressed);
      case 'graph':
        return KnowledgeGraphPage(
            navCollapsed: _navCollapsed,
            onNavPressed: _onNavPressed,
            onOpenTool: (i) => _selectWithReturn(i, 3));
      // v2.0 课标工具三页（桌面 Rail 直达；移动端经知识图谱页入口）
      case 'curriculum':
        return CurriculumPage(onOpenTool: (i) => _selectWithReturn(i, 4));
      case 'molecular':
        return MolecularPage();
      case 'evolution':
        return EvolutionPage();
      // v2.2 批次3：染色体倍性计算页（组数判断/倍性判定/育种/四倍体配子）
      case 'ploidy':
        return PloidyPage();
      // v2.19.24：大题套路卡（评论调研落地：识别信号→套路步骤→易错
      // 提醒→一句话背诵→关联计算器跳转）。
      case 'cards':
        return BigQuestionCardsPage(onOpenTool: (i) => _selectWithReturn(i, 8));
      // v2.19.31 导航扩项：变异/遗传病进主导航。两页没有本地工具抽屉，
      // 不再注入只翻系谱面板状态的死 ☰（全模块实窗口走查发现）。
      case 'variation':
        return VariationPage();
      case 'disease':
        return GeneticDiseasePage();
      // v2.19.60：设置/关于移到导航末位（用户要求）。
      // v2.6：☰ 已重定义为「本页工具抽屉」开关（系谱=控制面板、
      // 9331=计算工具、图谱=图谱工具）；设置/关于页无工具内容，
      // 不再注入 ☰（死按钮清除）。
      case 'settings':
        return SettingsPage();
      case 'about':
        return HomePage();
    }
    // 目录与 switch 不同步 = 开发期错误（不静默吞掉，测试里立刻炸）。
    throw StateError('app_navigation 目录里的 id「$id」没有对应页面');
  }

  void _select(int i) {
    // v2.19.26 手机 P1-2：切页释放输入框焦点——Android 默认点空白
    // 不收键盘（仅 web 收），不切页时旧页 TextField 长期占焦，
    // 键盘跟着跨页走、新页下半屏被占。底导/Rail/数字键/首页卡片
    // 全部走本入口，一处修复全链路生效。
    FocusManager.instance.primaryFocus?.unfocus();
    // 页面语义已经改变，旧页的即时反馈不得跨页压住新结果。
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    // v2.12 R1 C P0 #8：onTap 立即更新最近访问时间，避免下次扫描
    // 把当前刚点的页误判为 offstage；也确保"切走后再切回"路径上
    // 目标页 _lastAccess = now，5min 内不会被治理掉。
    _lastAccess[i] = DateTime.now();
    setState(() {
      _index = i;
      // 手动导航（Rail/快捷键/首页卡片/底导/全部面板）清除回程横幅。
      _returnToIndex = null;
    });
    AppState.instance.setPage(_nav[i].name);
    // v2.20.0：选中项滚进导航条视口（Rail 纵向 / 底导横向）——
    // 目标 Element 要等本帧 layout 完才有 RenderBox，故 postFrame。
    WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelectedNavItem());
  }

  // ── v2.12 R1 C P0 #8 测试钩子 ────────────────────────────────
  //
  // 设计原因：Timer.periodic(15s) 在 fake_async 下不真实触发（test
  // 时间靠 pumpAndSettle 推进），test 用 `debugForceOffstageCheck()`
  // 立刻扫一次，绕开 Timer 依赖。同 `debugEnsureLoaded` /
  // `debugSetMode` 模式：内部状态暴露给同 package test，外部不可见。

  /// 测试专用：立刻跑一次 offstage 扫描（绕过 15s Timer.periodic）。
  /// 命中任何 offstage 条件 → setState + rebuild。
  @visibleForTesting
  void debugForceOffstageCheck() {
    if (!mounted) return;
    var changed = false;
    for (var i = 0; i < _nav.length; i++) {
      if (_shouldOffstage(i)) {
        changed = true;
        break;
      }
    }
    if (changed) {
      setState(() {
        _offstageTick++;
      });
    }
  }

  /// 测试专用：把 `_lastAccess` 镜像 Map 返出来（不可变 Map 副本），
  /// test 验证"切 tab 时更新最近访问时间"语义。
  @visibleForTesting
  Map<int, DateTime> debugGetAccessTimes() {
    return Map<int, DateTime>.unmodifiable(_lastAccess);
  }

  /// 测试专用：返当前 offstage 决策触发的 rebuild 计数。
  /// test 验证"扫描后 setState 触发 rebuild"语义。
  @visibleForTesting
  int debugGetOffstageTick() => _offstageTick;

  /// 测试专用：返 offstage 阈值（5 分钟）。test 用
  /// `debugSetAccessTimeForTest(i, now.subtract(...))` 模拟"6 分钟前"
  /// 路径，避免直接改 const 阈值。
  @visibleForTesting
  Duration get debugOffstageThreshold => _offstageThreshold;

  /// 测试专用：把第 i 页的最近访问时间设为指定值。**不**触发 setState
  /// ——test 在调 `debugForceOffstageCheck()` 后才检查可见性。
  @visibleForTesting
  void debugSetAccessTimeForTest(int i, DateTime when) {
    _lastAccess[i] = when;
  }

  /// 测试专用：触发「第 i 页被 tap」语义（同生产路径 `_select(i)` 的
  /// `_lastAccess[i] = DateTime.now()` 副作用），但用公开命名让
  /// test 不必穿透 private。**不**触发 setState rebuild（让 test
  /// 完全控制 pump 时机）。
  @visibleForTesting
  void debugSelectPageAt(int i) {
    _lastAccess[i] = DateTime.now();
  }

  /// v2.2 双向跳转（泛化）：课标工具 chip / 知识图谱节点功能按钮
  /// 切导航索引（页面内跳转，不压路由栈）。记录来源页 → 目标页顶部
  /// 显示「返回来源页」横幅，点横幅或 Rail/底导均可跳回。
  void _selectWithReturn(int target, int from) {
    _select(target);
    if (target != from) setState(() => _returnToIndex = from);
  }

  int? _returnToIndex;

  /// v2.19.25：ModuleFillBus.navigator 闭包持有字段——dispose 必须与
  /// initState 赋的是同一实例才能判等清空（老用户 P3-1 恒 false 修复）。
  void Function(int)? _fillNavigator;

  /// v3.7 ☰：控制面板折叠/展开切换（导航不联动，始终常驻）。
  void _onNavPressed() {
    setState(() => _navCollapsed = !_navCollapsed);
  }

  /// 课堂快捷条的 bottom 锚点。
  ///
  /// 取值为「FAB 列高 + 底距 + 净空」，与 [build] 里 FAB 列的构成一一对应：
  ///   · 拍题 FAB（FloatingActionButton.small）= 40，永远在；
  ///   · 全局「问 AI」extended FAB = 56，与拍题间距 10，所有页面常驻；
  ///   · Scaffold 默认 endFloat 底距 16，条与列之间留 12 净空。
  ///
  /// 保留参数是为了让布局计算与 FAB 构成保持同一事实源。
  double _quickBarBottom({required bool withAiFab}) =>
      16 + 40 + (withAiFab ? 10 + 56 : 0) + 12;

  /// v2.2 移动端「全部功能导航」面板：BottomSheet 列出全部页面完整名称
  /// + 一句用途教学 + 当前页高亮；点项直达并关闭。解决窄屏底导
  /// 文字小/项多（需横向滑动）导致的功能发现困难。
  void _showAllNavSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.82),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            children: [
              Text('全部功能导航', style: AppText.sectionTitle),
              const SizedBox(height: 4),
              Text('点任意项直达对应页面；底部导航栏可左右滑动查看更多。',
                  style: AppText.caption),
              const SizedBox(height: 12),
              // v2.22.0：只列**可见**目的地（套路卡等隐藏页不在这里出现
              // ——它仍可经 9331 的 K 快捷键 / 错题本按需打开）。
              for (final navIndex in _navVisibleIndexes)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: ListTile(
                    dense: true,
                    leading: Icon(
                        navIndex == _index
                            ? _nav[navIndex].selectedIcon
                            : _nav[navIndex].icon,
                        color:
                            navIndex == _index ? AppColors.teal : AppColors.steel),
                    title: Text(_nav[navIndex].name, style: AppText.label),
                    subtitle: Text(_nav[navIndex].desc, style: AppText.caption),
                    selected: navIndex == _index,
                    selectedTileColor: AppColors.tealWash,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    onTap: () {
                      Navigator.of(sheetCtx).pop();
                      _select(navIndex);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 双向跳转回程横幅：tealWash 细条，点击任意处回来源页
  /// （课标 chip / 图谱节点共用）。
  Widget _buildReturnBanner(int from) {
    return Material(
      color: AppColors.tealWash,
      child: InkWell(
        onTap: () => _select(from),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Icon(Icons.arrow_back, size: 15, color: AppColors.teal),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    '来自${_nav[from].name} · 点击返回${_nav[from].shortName}页',
                    style: AppText.caption.copyWith(color: AppColors.ink)),
              ),
              Icon(_nav[from].selectedIcon, size: 15, color: AppColors.teal),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // v2.12 R1 C P0 #8：offstage 治理——给所有页一个"现在"基准时间，
    // 首帧不被治理。`_select(0)`（用户立刻切到第 0 页）会在 onTap 时
    // 覆盖第 0 页时间戳，但其他页的"现在"仍保持。
    final now = DateTime.now();
    for (var i = 0; i < _nav.length; i++) {
      _lastAccess[i] = now;
    }
    AppState.instance.setPage(_nav[0].name);
    GuideController.instance.addListener(_onGuideChanged);
    // v2.19.68 P2-6：监听课堂模式开关——进入课堂大屏时做一次 AI Key
    // 自检提醒（已配置静默；未配置弹一次性 SnackBar）。
    PresentModeController.instance.addListener(_onPresentModeChanged);
    // v2.5 拍题识别填参路由：AI 面板/题库经 ModuleFillBus 切页
    // （走主导航索引，不 push——与首页卡片同一事实源）。
    // v2.19.15 A+C 桥：navigator 改走 _selectWithReturn——所有经
    // ModuleFillBus 的跨页跳转（讲题回放 ▷ / 拍题识别 / 错题本 /
    // A 桥「在系谱展开」「在 9331 展开」）自动获得顶部「返回来源页」
    // 横幅，不再只图谱/课标两页有回程。from = 切页前的当前页。
    // v2.19.25 修复（老用户 P3-1）：dispose 用同一字段判等——
    // 原赋值是内联闭包、dispose 却比对 _select（方法 tear-off），
    // 永不相等 → dispose 永不清空，测试/多实例场景留悬空引用。
    _fillNavigator = (t) => _selectWithReturn(t, _index);
    ModuleFillBus.navigator = _fillNavigator;
    // v2.14 R5 学生走查 P0：pd_inference / disease_risk 上移 App 级
    // 常驻注册（原注册跟遗传病页生命周期走，拍题 FAB 永远够不着）。
    registerAppLevelModuleTargets();
    // Wave2 拖图入窗：注册原生拖放回调（file_drop_io 仅 Windows 生效，
    // 其它平台 no-op）+ 兜底订阅拍题对话框没开时的新拖图。
    initFileDrop(_onFilesDropped);
    _fileDropSub = FileDropBus.instance.stream.listen(_onDroppedImage);
    // v2.12 R1 C P0 #8：启动 offstage 治理扫描 Timer（15s 周期）。
    // 周期不是高频（10 page × DateTime.now 比较 = < 1μs），
    // 但仍建议在 debug / 单元测试环境用 `debugForceOffstageCheck`
    // 显式触发，避免 fake_async 跑不动 Timer.periodic。
    _offstageTimer = Timer.periodic(_offstageScanPeriod, (_) {
      if (!mounted) return;
      // 扫描：若有任何页应进入 offstage，触发 rebuild
      var changed = false;
      for (var i = 0; i < _nav.length; i++) {
        if (_shouldOffstage(i)) {
          changed = true;
          break;
        }
      }
      if (changed) {
        setState(() {
          _offstageTick++;
        });
      }
    });
    // v2.12 Wave 3-B：加载首启标记 + 角色。`first_run.json` 不存在或
    // 角色未选择时弹 dialog 引导用户选角色。load 走磁盘 IO 是 async，
    // 必须在首帧之后再弹 dialog（build 完成 → setState → dialog）；
    // 这里用 addPostFrameCallback 等首帧渲染。
    FirstRunStore.instance.load().then((_) {
      if (!mounted) return;
      if (FirstRunStore.instance.isFirstRun()) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          // 首启：角色 dialog 走完（await 这个 Future）再接力自动引导——
          // dialog 是模态的，先弹引导会被压在罩层底下，等于没弹。
          _showFirstRunRoleDialog().then((_) {
            if (mounted) _autoStartGuideIfNeeded();
          });
        });
      } else {
        // 角色已选：仅强制 rebuild 让 dashboard_page 读到最新 role
        //（stateful 已 subscribe，正常路径会自己 rebuild，但首启后
        // 立即进首屏可能落在 load 之前完成，加一次保险）。
        setState(() {});
        _autoStartGuideIfNeeded();
      }
    });
  }

  /// v2.13 R5 P0：首启角色选择 dialog。2 选 1，老师 / 学生。
  /// 老师工作流不展示「我的错题」（学生私人学习空间）；学生
  /// 看到完整 10 个入口。点选项直接写盘 + dismiss。
  /// barrierDismissible:false 强制二选一（无「稍后」——首启即定角色，
  /// 避免「先随便看看」的学生看到老师版界面困惑；R6 走查确认此设计）。
  ///
  /// v2.12 / v2.13 早期版本曾有第 3 选项「家长」——v2.13 R5 硬编码
  /// 移除：产品决策「Biology 不面向家长角色」（UX 走查 / persona
  /// 只考虑学生 + 老师），见 _ver_R5_1st_b.md §1。显式 2 张卡（不再
  /// `for (final r in UserRole.values)`）便于未来加角色时复审。
  Future<void> _showFirstRunRoleDialog() async {
    // 首启顺带定「这台电脑上叫什么」与启动 PIN：只问角色的话，默认档案是
    // 无 PIN 的「本机用户」，同一台电脑上任何人都能进学生的错题本。
    final nameCtrl = TextEditingController(text: '本机用户');
    final pinCtrl = TextEditingController();
    String? err;
    final picked = await showDialog<({UserRole role, String name, String pin})>(
      context: context,
      barrierDismissible: false,
      // PopScope：安卓返回键能关掉 showDialog（barrierDismissible 挡不住
      // 系统返回），关掉后 picked == null —— 角色照写、名字与 PIN 全跳过，
      // 用户直接落在无 PIN 的默认档案上。首启这一步不能被一键跳过。
      builder: (ctx) => PopScope(
        canPop: false,
        child: StatefulBuilder(
          builder: (ctx, setLocal) {
          // 角色 / 名字 / PIN 必须一起返回：分两次落盘会出现「选了老师但
          // 名字没写进去」这种半套状态。
          void submit(UserRole role) {
            final name = nameCtrl.text.trim();
            final pin = pinCtrl.text.trim();
            if (name.isEmpty) {
              setLocal(() => err = '请填写这台电脑上叫什么');
              return;
            }
            if (pin.isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(pin)) {
              setLocal(() => err = 'PIN 必须是 4 位数字');
              return;
            }
            Navigator.of(ctx).pop((role: role, name: name, pin: pin));
          }

          return AlertDialog(
            title: const Text('欢迎使用 Biology'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  maxLength: 20,
                  decoration: const InputDecoration(
                    labelText: '这台电脑上叫什么',
                    counterText: '',
                  ),
                ),
                TextField(
                  controller: pinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: '启动 PIN（4 位，可留空）',
                    counterText: '',
                    helperText: '留空则这台电脑上任何人都能进',
                  ),
                ),
                const SizedBox(height: 12),
                Text('选择最贴近你的使用场景，错题本等私人空间按角色显示。',
                    style: AppText.body.copyWith(color: AppColors.graphite)),
                if (err != null) ...[
                  const SizedBox(height: 8),
                  Text(err!,
                      style:
                          TextStyle(color: AppColors.lethal, fontSize: 12)),
                ],
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.school_outlined, color: AppColors.teal),
                  title: Text(UserRole.teacher.displayName, style: AppText.label),
                  subtitle: Text('备课 / 课堂演示（大屏模式 + 板书放映）\n'
                      '首页会出现「老师工具」；错题本是学生私域，不显示',
                      style: AppText.caption),
                  onTap: () => submit(UserRole.teacher),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.person_outline, color: AppColors.teal),
                  title: Text(UserRole.student.displayName, style: AppText.label),
                  subtitle: Text('刷题 / 错题整理 / 拍题识别\n'
                      '首页会出现「我的错题」卡——算完题可一键存入，AI 帮你归类错因',
                      style: AppText.caption),
                  onTap: () => submit(UserRole.student),
                ),
              ],
            ),
          );
          },
        ),
      ),
    );
    nameCtrl.dispose();
    pinCtrl.dispose();
    // v2.13：dialog 被异常关闭（极少数，barrier 不可点空白取消）时
    // 以「学生」兜底——兑现上方注释承诺的「仍写学生兜底，避免永远弹窗」。
    final role = picked?.role ?? UserRole.student;
    await FirstRunStore.instance.setRole(role);
    if (picked != null) {
      // 只有真的点了角色卡才改名 / 设 PIN：异常关闭走兜底，默认档案不动。
      final id = AccountsStore.instance.activeId;
      if (id != null) {
        await AccountsStore.instance.rename(id, picked.name);
        if (picked.pin.isNotEmpty) {
          await AccountsStore.instance.setPin(id, picked.pin);
        }
      }
    }
    if (!mounted) return;
    setState(() {}); // dashboard 立刻反映新角色（错题本卡显隐）
  }

  // ── v2.19.68 P2-6：进入课堂大屏时 AI Key 自检提醒 ───────────────
  //
  // 老师上课才发现拍题/讲题稿不可用（AI 未配置）太晚——进入课堂大屏
  // 这一刻做一次存在性检查（⛔ 不做联网连接测试）：AiSettingsStore 已配
  // apiKey 则静默跳过；为空弹一次性 SnackBar 指路设置页。「一次性」=
  // 每次进入课堂只提示一条（激光笔/聚光灯/高对比等其它 controller
  // notify 不触发；退出再进未配置才再提醒）。
  //
  // 挂点：课堂模式没有任何独立"横幅"组件——快捷条即入场标志，HomeShell
  // 监听 PresentModeController（本人已监听 rebuild，这里是副监听）。
  // 读配置可能走磁盘（LocalSecureStore 同步读），异常一律静默——
  // 自检提醒绝不能打断上课动线。
  void _onPresentModeChanged() {
    final now = PresentModeController.instance.enabled;
    final prev = _presentWasEnabled;
    _presentWasEnabled = now;
    // 只在「进入」跳变触发；首帧基线（prev == null，含开机即课堂态）
    // 也算进入——持久化开着课堂模式的老师重启后同样需要提醒。
    if (prev != null && prev == now) return;
    if (!now) return;
    _probeAiKeyOnPresentEnter();
  }

  Future<void> _probeAiKeyOnPresentEnter() async {
    AiConfig cfg;
    try {
      cfg = await AiSettingsStore.load();
    } catch (_) {
      return; // 读配置失败：静默（不联网、不阻塞课堂）
    }
    if (cfg.apiKey.isNotEmpty) return; // 已配置：静默跳过
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('上课前建议先在设置页配置 AI（拍题/讲题稿需要）'),
      duration: Duration(seconds: 4),
      behavior: SnackBarBehavior.floating,
    ));
  }

  /// Wave2 拖图入窗：原生侧拖入回调（Windows runner WM_DROPFILES）。
  /// 路径列表 → 取第一张图片 → 广播给 FileDropBus；全非图片给
  /// SnackBar 人话提示（拖拽是显式动作，无反馈 = 用户以为拖丢了）。
  /// v2.19.67 P2 #5：takeImage 改异步（exists/readAsBytes 不再同步
  /// 阻塞 UI 线程），回调随之 async；回调来自 MethodChannel（异步
  /// 上下文），HomeShell 常驻，mounted 校验后用根 ScaffoldMessenger
  /// 弹条，SnackBar 不依赖某页 Scaffold。
  Future<void> _onFilesDropped(List<String> paths) async {
    final img = await FileDropBus.takeImage(paths);
    if (img != null) {
      FileDropBus.instance.publish(img);
      return;
    }
    if (mounted) {
      // v2.19.67 P2 #2：补 .jpeg——与 file_drop_bus.takeImage 的实际
      // 过滤表（png/jpg/jpeg/webp/bmp/gif）一致，文案不再少列一种。
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              '拖入的不是图片：请拖 png / jpg / jpeg / webp / bmp / gif 图片')));
    }
  }

  /// Wave2 拖图入窗：兜底消费——拍题对话框没开时替它开框并自动识别。
  ///
  /// 让出一拍（Duration.zero）再查 hasConsumer：对话框在场时它自己
  /// 已同步消费本事件（broadcast 同轮分发），这里退避免双开；不在场
  /// 才开新框，图经 initialImage 带入（broadcast 流不回放历史事件）。
  /// v2.19.67 P2 #3 双开竞态兜底：从「让出一拍」到对话框 initState
  /// claim() 之间有一个窗口——连拖两下会两次通过 hasConsumer 检查，
  /// 叠出两个识别框。`_dropDialogOpening` 在开框前置位、对话框路由
  /// 完成（pop）/失败后复位（whenComplete），正在开框时忽略后续事件。
  /// 消费协议详见 file_drop_bus.dart 文件头。
  Future<void> _onDroppedImage(PickedImage img) async {
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    if (FileDropBus.instance.hasConsumer || _dropDialogOpening) return;
    _dropDialogOpening = true;
    await showScanUploadDialog(context, initialImage: img)
        .whenComplete(() => _dropDialogOpening = false);
  }

  @override
  void dispose() {
    GuideController.instance.removeListener(_onGuideChanged);
    // v2.19.68 P2-6：课堂模式监听随壳销毁。
    PresentModeController.instance.removeListener(_onPresentModeChanged);
    if (ModuleFillBus.navigator == _fillNavigator) {
      ModuleFillBus.navigator = null;
      _fillNavigator = null;
    }
    _guideEntry?.remove();
    // v2.12 R1 C P0 #8：取消 offstage 治理 Timer，避免 leak。
    _offstageTimer?.cancel();
    _offstageTimer = null;
    // Wave2 拖图入窗：取消兜底订阅（initFileDrop 的 handler 不需要
    // 反注册——HomeShell 即 App 根壳，销毁 = App 退出）。
    _fileDropSub?.cancel();
    _fileDropSub = null;
    super.dispose();
  }

  // ---- v2.2 新手引导 ----
  OverlayEntry? _guideEntry;

  /// 本次会话是否已自动开过引导（防重入：rebuild / 返回首页 / 重新
  /// didChangeDependencies 都不该再弹一次）。
  bool _autoGuideStarted = false;

  /// 首启自动开启新手引导。
  ///
  /// 两个触发点都在 FirstRunStore.load() 之后：首启角色 dialog 走完、
  /// 非首启直接判断。已走过一遍（guideDone）就什么都不做——老师仍可从
  /// 「设置 → 新手引导」手动重看。切页交给 _onGuideChanged →
  /// _syncGuidePage，这里不另开导航。
  void _autoStartGuideIfNeeded() {
    if (FirstRunStore.debugSuppressAutoGuide) return;
    if (_autoGuideStarted || !mounted) return;
    if (FirstRunStore.instance.guideDone) return;
    _autoGuideStarted = true;
    if (GuideController.instance.active) {
      // 已有一轮引导在跑（壳重建 / 测试重复泵 app）：补挂 overlay，
      // 不重置步骤。
      _onGuideChanged();
      return;
    }
    // 直接 start()：overlay 本身在下一帧才 build（OverlayEntry 插入即排帧），
    // 不必再套 addPostFrameCallback——dialog 刚关时可能没有待渲染帧，
    // postFrame 回调会一直挂着，首启就永远不弹引导。
    GuideController.instance.start();
  }

  /// 引导状态机监听：active 时把 GuideOverlay 插到顶层 Overlay
  /// （盖住 Rail/底导/FAB 一切），步骤变化时驱动切页 + 重建 overlay。
  void _onGuideChanged() {
    final g = GuideController.instance;
    if (g.active && _guideEntry == null) {
      _guideEntry = OverlayEntry(
          builder: (_) => GuideOverlay(
              // v2.19.26：导航 rail 阈值 840→600，与 Flutter 官方
              // adaptive 文档一致（"bottom nav <600 / rail ≥600"）。
              // 平板 3:4 竖屏（768/834 宽）由此从底导升级为 rail，
              // 更像平板且 rail 已有纵向滚动兜底；桌面窄窗同享。
              wide: MediaQuery.of(context).size.width >= 600));
      Overlay.of(context).insert(_guideEntry!);
      _syncGuidePage();
    } else if (!g.active && _guideEntry != null) {
      _guideEntry?.remove();
      _guideEntry = null;
    } else if (g.active) {
      _syncGuidePage();
      _guideEntry?.markNeedsBuild();
    }
  }

  /// 引导步骤切页：目标页不同于当前页时切过去；等切页渲染完成后
  /// 重建 overlay（目标 widget 坐标在新帧才有效）。
  ///
  /// v2.19.30 加固：切页/推进后把挖孔目标滚进视口（Scrollable.
  /// ensureVisible）——单列长页的引导目标常在首屏外（设置页回退
  /// 单列后 AI 节 y≈1400），目标 RenderBox 在缓存区、坐标屏外，
  /// 气泡按 rect 定位跟着出屏，「下一步」永不可点（guide_test
  /// 步骤推进实锤卡死）。ensureVisible 动画落定后再重定位气泡。
  void _syncGuidePage() {
    final g = GuideController.instance;
    // v2.19.26：与 build 的导航阈值同步（840→600，见 build 注释）。
    final wide = MediaQuery.of(context).size.width >= 600;
    final steps = g.stepsFor(wide: wide);
    final step = steps[g.stepIndex.clamp(0, steps.length - 1)];
    final page = step.pageIndex;

    // v2.19.30（DeepSeek P1-1）：目标 Element 可能因宿主 ListView
    // 缓存回收而暂不在树（用户从设置页底部开引导，AI 节已滚出
    // cacheExtent 被销毁）——空 ctx 时 postFrame 延迟重试 2 帧，
    // 配合设置页 cacheExtent:2000 双保险；重试仍失败则放弃（气泡
    // 居中可点，不卡死）。
    var revealAttempts = 0;

    void revealTarget() {
      final ctx = step.target?.currentContext;
      if (ctx == null) {
        if (revealAttempts < 2) {
          revealAttempts++;
          WidgetsBinding.instance.addPostFrameCallback((_) => revealTarget());
        }
        return;
      }
      // v2.19.30 修复：ensureVisible 返回 Future——滚动动画**完成后**
      // 才重建气泡。原实现在动画起点 markNeedsBuild 一次，气泡按
      // 起点坐标（屏外）定位后不再更新，「下一步」永不可点。
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 250),
        alignment: 0.35,
      ).then((_) {
        if (mounted) _guideEntry?.markNeedsBuild();
      });
    }

    if (page >= 0 && page != _index) {
      _select(page);
      WidgetsBinding.instance.addPostFrameCallback((_) => revealTarget());
    } else {
      // 同页推进（下一步不换页）：目标可能仍在屏外，同样滚入。
      WidgetsBinding.instance.addPostFrameCallback((_) => revealTarget());
    }
  }

  /// 上一次 didChangeDependencies 时的「窄/宽」档（null = 尚未初始化）。
  /// v2.20.0：把「首帧按 600 定一次」换成「跨档位才重置，同档缩放不覆盖
  /// 用户手动选择」——原来 _navInitialized 只认首帧，1400 桌面窗口拖到
  /// 390 手机档后面板仍按桌面档展开（画布被面板占住、☰ 语义反了），
  /// 反向 390→1400 也会把折叠态带进桌面。
  bool? _wasNarrowBand;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 窄屏（无 Rail，如安卓竖屏）默认折叠，画布最大化。
    // v2.19.26：阈值与 build 同步（840→600）。
    // v2.20.0：只在**跨档位**时把 _navCollapsed 重置为该档默认值；
    // 同一档内窗口缩放（1400→1600、390→430）保留用户手动选的 ☰ 状态。
    final narrow = MediaQuery.of(context).size.width < 600;
    if (_wasNarrowBand == null) {
      _wasNarrowBand = narrow;
      _navCollapsed = narrow;
      return;
    }
    if (_wasNarrowBand != narrow) {
      _wasNarrowBand = narrow;
      _navCollapsed = narrow;
      // 导航形态切换（Rail ↔ 底导）后选中项可能在新区间外，等本帧
      // layout 完再拉进视口。
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _revealSelectedNavItem());
    }
  }

  @override
  Widget build(BuildContext context) {
    // v2.19.26 导航 rail 阈值 840→600（Flutter 官方 adaptive 文档：
    // "bottom nav bar for windows <600, rail ≥600"）。平板 3:4 竖屏
    // （768/834 宽）由此命中 rail 导航——横屏默认、竖屏亦可的
    // 平板双形态基础；rail 超高时已有纵向滚动兜底。
    final wide = MediaQuery.of(context).size.width >= 600;
    // v2.21.0：仅桌面宽档展开文字侧栏；平板/窄窗保留紧凑 Rail。
    // 同一目录、同一单栏滚动与选中揭示，不折叠、不双列。
    final extendedNav = MediaQuery.of(context).size.width >= 1200;

    // v2.22.0：所有页面保留下方同一个「问 AI」习惯入口。
    // 页内按钮只承载该页的上下文讲解，不再决定全局 FAB 是否出现。
    const showGlobalAiFab = true;

    // v2.12 R1 C P0 #8：每页包 `Visibility(visible: !_shouldOffstage(i),
    // maintainState: true)`——超过 5 分钟未访问的页"挂起"（不绘制
    // 但保留 State）。重新 tap 时 `_lastAccess[i] = now` + `setState`
    // 让 _shouldOffstage(i) 返 false → 立即恢复 visible + state。
    // 比 Offstage 兼容性更好（Offstage 会触发 MediaQuery 重算）。
    //
    // v2.19.52（找茬 P1 修复）：每页再包一层 PageActivationMarker——
    // IndexedStack 内 10 页的键宿主（Alt+数字/Ctrl+S/Alt+K）handler
    // 同时存活，仅靠 ModalRoute.isCurrent 判不出「非激活页」，需要
    // marker.index == scope.currentIndex 这一道闸（见
    // lib/ui/page_activation.dart 文件头）。_buildPages() 提升为
    // 单次调用（原循环里每轮调两遍是浪费，行为不变）。
    final pages = _buildPages();
    final body = RepaintBoundary(
      key: appCanvasKey,
      child: PageActivationScope(
        currentIndex: _index,
        // v2.19.54：? 键快捷键速览宿主（在 Scope 之下读 currentIndex，
        // 在 IndexedStack 之外避免给每页各挂一枚）。
        child: ShortcutCheatsheet(
          child: IndexedStack(
            index: _index,
            children: [
              for (var i = 0; i < pages.length; i++)
                Visibility(
                  visible: !_shouldOffstage(i),
                  maintainState: true,
                  maintainSize: false,
                  maintainAnimation: true,
                  child: PageActivationMarker(
                    pageIndex: i,
                    child: pages[i],
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    // 双向跳转回程横幅（在 RepaintBoundary 截图边界外，
    // 不影响 golden；消费 AppColors token 故不得 const 实例化）。
    final content = Column(
      children: [
        if (_returnToIndex != null) _buildReturnBanner(_returnToIndex!),
        Expanded(child: body),
      ],
    );

    final shortcuts = Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.digit1): _NavIntent(0),
        const SingleActivator(LogicalKeyboardKey.digit2): _NavIntent(1),
        const SingleActivator(LogicalKeyboardKey.digit3): _NavIntent(2),
        const SingleActivator(LogicalKeyboardKey.digit4): _NavIntent(3),
        const SingleActivator(LogicalKeyboardKey.digit5): _NavIntent(4),
        const SingleActivator(LogicalKeyboardKey.digit6): _NavIntent(5),
        const SingleActivator(LogicalKeyboardKey.digit7): _NavIntent(6),
        const SingleActivator(LogicalKeyboardKey.digit8): _NavIntent(7),
        const SingleActivator(LogicalKeyboardKey.digit9): _NavIntent(8),
        const SingleActivator(LogicalKeyboardKey.digit0): _NavIntent(9),
        // v2.19.68 P2-7：F11 无边框全屏（老师投影刚需，零 plugin 走
        // MethodChannel biology/window）。F11 无输入框冲突，不需要
        // _NavIntent 那套 EditableText 焦点守卫；非 Windows 平台
        // WindowChannel.toggleFullscreen() 内部 no-op 返回 false。
        const SingleActivator(LogicalKeyboardKey.f11): const _FullscreenIntent(),
        const SingleActivator(LogicalKeyboardKey.keyA, control: true):
            const _AiIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          _NavIntent: CallbackAction<_NavIntent>(
            onInvoke: (intent) {
              // v2.19.15（DeepSeek 找茬 🔴1）：数字键导航必须守卫输入框
              // 焦点——EditableText 不消费原始键事件，连锁面板交换值框
              // 输 35% 时按 3/5 会把整页切走。
              // v2.19.26 定谳修复（三找茬代理交叉 + widget 实测）：
              // 旧守卫 `focus.context.widget is EditableText` 恒 false——
              // TextField 的焦点挂在内部 Focus widget 上（SDK
              // editable_text.dart Focus 包裹），primaryFocus 的
              // context.widget 是 Focus 不是 EditableText。实测聚焦
              // 输入框按 digit3 直接切页（套路卡搜索框输「9331」
              // 按到第 2 个键就被切走）。改祖先查找。
              final focus = FocusManager.instance.primaryFocus;
              if (focus?.context != null &&
                  focus!.context!
                          .findAncestorWidgetOfExactType<EditableText>() !=
                      null) {
                return null;
              }
              _select(intent.index);
              return null;
            },
          ),
          _AiIntent: CallbackAction<_AiIntent>(
            onInvoke: (intent) {
              showAiAssistant(context);
              return null;
            },
          ),
          // v2.19.68 P2-7：F11 → Windows 无边框全屏切换。unawaited：
          // 平台通道异步，结果（进入/还原）由窗口形态变化本身呈现，
          // 失败由 WindowChannel 内部吞掉静默降级。
          _FullscreenIntent: CallbackAction<_FullscreenIntent>(
            onInvoke: (intent) {
              unawaited(WindowChannel.toggleFullscreen());
              return null;
            },
          ),
        },
        child: Focus(autofocus: true, child: content),
      ),
    );

    // v2.10 入口分离：拍题（上传题目图片→AI 识别→填入模块）与问 AI
    //（画布截图问答）拆成两个独立入口——问 AI 不再内嵌拍题按钮，
    // 避免 AI 把软件内置截图误当题目上传形成识别死循环。
    // 拍题入口两个模式都呈现（学生刷题也能用）。
    // v2.12.0+2 hotfix（老师 persona 反馈）：课堂模式不再隐藏拍题 FAB
    //——老师上课时用 PresentMode 演示，但**有拍学生板书的需求**
    //（学生写到黑板上的题目老师想拍下来让该生下去算），拍题 FAB 必须
    // 可见。但课堂模式为防误触加 "长按 1 秒解锁"（白板手指/教鞭容易
    // 误碰），且触发后弹横幅「课堂模式中，拍题结果仅入错题本不广播
    // 到大屏」——课堂演示"焦点在大屏"，拍题结果不应意外投射。
    //   - 学生角色：FAB 缩到 0.7×（避免占据大屏空间）+ 长按 1 秒解锁
    //   - 老师角色：FAB 全尺寸（老师全功能使用）+ 长按 1 秒解锁
    //   - 老师角色额外提供「广播到大屏」切换（独立开关，默认关）
    final fab = ListenableBuilder(
      listenable: PresentModeController.instance,
      builder: (ctx, _) {
        final inClass = PresentModeController.instance.enabled;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // v2.12.0+2 hotfix：拍题 FAB 永远可见（v2.11 课堂模式
            // 隐藏的回归被老师 persona 报告为 P0）。课堂模式下由
            // _ScanFab 内部决定尺寸 + 长按解锁策略。
            _ScanFab(inClass: inClass),
            // v2.22.0：全局「问 AI」在每页常驻；页内上下文动作不再
            // 影响这枚统一入口，也不改变 FAB 列与课堂快捷条的位置。
            if (showGlobalAiFab) ...[
              const SizedBox(height: 10),
              FloatingActionButton.extended(
                key: GuideKeys.aiFab, // 新手引导高亮目标
                onPressed: () => showAiAssistant(context),
                backgroundColor: AppColors.teal,
                // v2.12 单一事实源: 浅色 white / 暗色墨绿,见
                // theme.dart AppColors.onTeal & ColorScheme.onPrimary
                foregroundColor: AppColors.onTeal,
                elevation: 0,
                highlightElevation: 0,
                icon: const Icon(Icons.psychology_outlined),
                label: const Text('问 AI'),
              ),
            ],
          ],
        );
      },
    );

    if (wide) {
      // 桌面端：左侧 NavigationRail 常驻（v3.7 ☰ 不再隐藏导航，
      // 只折叠系谱左控制面板）。
      // v2.19.67（用户裁定）：撤销 v2.19.31 R13-3 的「课堂模式双列
      // rail」——两列 NavigationRail 并排在用户眼里就是「双层导航栏」。
      // 改回单列 rail + SDK 自管纵向滚动（scrollable 兜底末项可达），
      // 标签 maxLines:1 禁止换行折叠（大字号下宁可省略号，不折行）。
      return Scaffold(
        body: Row(
          children: [
            // v2.19.67：旧 rail 在 LayoutBuilder 内直读
            // PresentModeController.instance.enabled，课堂模式切换后
            // minWidth 不随 notifier 重建（隐性 bug）；新写法经
            // ListenableBuilder 监听，切换即时生效。
            ListenableBuilder(
              listenable: PresentModeController.instance,
              builder: (ctx, _) {
                final inClass = PresentModeController.instance.enabled;
                return NavigationRail(
                  key: GuideKeys.navRail, // 新手引导高亮目标
                  extended: extendedNav,
                  leading: extendedNav ? _buildNavigationBrand() : null,
                  minExtendedWidth: inClass ? 240 : 184,
                  // v2.22.0：Rail 显示的是**可见**目的地（套路卡等隐藏页
                  // 不在此列）⇒ selectedIndex 必须是**可见索引**，不是
                  // pageIndex；当前页不可见 ⇒ null（不高亮任何项，绝不
                  // 越界/错位高亮）。
                  selectedIndex:
                      _visibleNavIndex < 0 ? null : _visibleNavIndex,
                  // 回调给的是**可见索引** ⇒ 换回 pageIndex 再切页
                  // （_select 的入参语义仍是 pageIndex，数字键/深链不变）。
                  onDestinationSelected: (visibleIndex) =>
                      _select(_navVisibleIndexes[visibleIndex]),
                  labelType: extendedNav
                      ? NavigationRailLabelType.none
                      : NavigationRailLabelType.all,
                  minWidth: inClass ? 104 : 72,
                  scrollable: true,
                  destinations: [
                    // v2.20.0：目的地/图标/短标签一律读导航目录
                    // （app_navigation.dart）；label 上挂 GlobalKey 供
                    // _select 后 ensureVisible 把选中项拉进视口。
                    // v2.22.0：只渲染**可见**目的地；Key 仍按完整
                    // pageIndex 取（_railItemKeys 与 _bottomItemKeys 同
                    // 一索引空间），保证 Rail 与底导不错位。
                    for (final navIndex in _navVisibleIndexes)
                      NavigationRailDestination(
                        icon: Icon(_nav[navIndex].icon),
                        selectedIcon: Icon(_nav[navIndex].selectedIcon),
                        // v2.19.67：单行标签——旧实现窄栏/大字号下
                        // 「遗传图谱」折成两行，视觉上像导航栏被折叠。
                        label: Text(
                          _nav[navIndex].shortName,
                          key: _railItemKeys[navIndex],
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                );
              },
            ),
            VerticalDivider(width: 1, color: AppColors.border),
            // v2.2 全局安全区：顶部让出状态栏/摄像头挖孔（安卓实测遮挡），
            // 底部让出手势条。桌面 MediaQuery.padding=0 时零间距，
            // golden/布局不受影响；页面内 AppBar(primary) 的 padding
            // 被外层 SafeArea 消费，不会重复加高。
            // v2.7 课堂快捷条：Stack 浮层（右下、FAB 上方），仅课堂模式渲染
            // （学生模式零像素变化）；聚光灯按钮仅系谱页（index 1）可用。
            Expanded(
              child: Stack(
                children: [
                  SafeArea(child: shortcuts),
                  Positioned(
                    // v2.19.68（GUI 看官 P1）：150 是「悬在右缘 80% 高度」
                    // ——正压 9331 变式速查徽章/结果徽章/首页卡片。改真正
                    // 右下贴底：FAB 列 = 拍题 40 + 间距 10 + AI 56 = 106，
                    // Scaffold endFloat 底距 16 → 列顶在 bottom 122，再留
                    // 12px 净空 = 134（条底缘贴 FAB 列上沿，不再压内容列）。
                    // 收起成把手后同锚点（把手 40px 圆，仍在 FAB 列上方）。
                    // v2.20.0：全局问 AI FAB 在页内有入口的页面隐藏 ⇒ 列
                    // 只剩拍题 40，条随之下移（见 _quickBarBottom）。
                    right: 16,
                    bottom: _quickBarBottom(withAiFab: showGlobalAiFab),
                    child:
                        ClassroomQuickBar(spotlightAvailable: _index == 1,
                          onOpenInference: () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) => GeneticDiseasePage(
                                    focusInference: true)),
                          ),
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: fab,
      );
    }

    // 移动端：底部横向滚动导航栏常驻（2.2 批次4a 含首页共 10 项，
    // 窄屏水平滑动可达；☰ 只折叠系谱控制面板）
    return Scaffold(
      // v2.7 课堂快捷条：浮于内容右下（底导 + FAB 上方），仅课堂模式渲染
      body: Stack(
        children: [
          SafeArea(child: shortcuts),
          Positioned(
            // v2.19.68：与宽屏分支同步贴底（134，见上方注释）——底导在
            // body Stack 之外，FAB 列同样占 bottom 122，条贴其上沿。
            // v2.20.0：与宽屏同一条动态计算（隐藏全局 AI FAB 时下移），
            // 不手写第二个 134（两分支各写一遍必然漂移）。
            right: 12,
            bottom: _quickBarBottom(withAiFab: showGlobalAiFab),
            child: ClassroomQuickBar(spotlightAvailable: _index == 1,
              onOpenInference: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) =>
                        GeneticDiseasePage(focusInference: true)),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildMobileNavBar(),
      floatingActionButton: fab,
    );
  }

  /// v2.21.0 宽档侧栏品牌区：只呈现产品身份，不新增导航项或按钮。
  Widget _buildNavigationBrand() {
    return Padding(
      key: const Key('navigation_brand'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.tealWash,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.biotech_outlined, size: 25, color: AppColors.teal),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Biology', style: AppText.sectionTitle),
              Text('遗传计算工作台',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.caption.copyWith(color: AppColors.steel)),
            ],
          ),
        ],
      ),
    );
  }

  /// v2.0 移动端底导：横向滚动（导航一律常驻，可滑到全部条目）。
  /// v2.2：SafeArea(top:false) 让出底部手势条/导航条（安卓实测遮挡）。
  Widget _buildMobileNavBar() {
    return SafeArea(
      top: false,
      child: Material(
        key: GuideKeys.navBar, // 新手引导高亮目标
        color: AppColors.surface,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          child: Row(
            children: [
              // v2.2 移动端完整导航入口（固定最左）：底导项多文字小
              // 易迷路——「全部」弹出全功能面板：完整名称+用途教学，
              // 点哪去哪（教用户正确调用全部功能）。
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _showAllNavSheet,
                child: Container(
                  width: 62,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.apps_outlined,
                          size: 22, color: AppColors.teal),
                      const SizedBox(height: 2),
                      Text('全部',
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.teal,
                          )),
                    ],
                  ),
                ),
              ),
              // v2.22.0：底导只渲染**可见**目的地（套路卡等隐藏页撤下
              // 独立入口）；Key 数组仍按**完整 pageIndex** 取
              // （_bottomItemKeys 与 _railItemKeys 同一索引空间），
              // onTap 也传 pageIndex ⇒ 手动导航语义不变、不错位。
              for (final navIndex in _navVisibleIndexes)
                InkWell(
                  // v2.20.0：整项挂 GlobalKey——_select 后按 key 调
                  // ensureVisible 把选中项横向滚进视口（横向滚动条上
                  // 最新选中项常在屏外，看不到高亮）。
                  key: _bottomItemKeys[navIndex],
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _select(navIndex),
                  child: Container(
                    width: 62,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: navIndex == _index
                          ? AppColors.tealWash
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          navIndex == _index
                              ? _nav[navIndex].selectedIcon
                              : _nav[navIndex].icon,
                          size: 22,
                          color: navIndex == _index
                              ? AppColors.teal
                              : AppColors.steel,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _nav[navIndex].shortName,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: navIndex == _index
                                ? AppColors.teal
                                : AppColors.graphite,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavIntent extends Intent {
  final int index;
  const _NavIntent(this.index);
}

class _AiIntent extends Intent {
  const _AiIntent();
}

/// v2.19.68 P2-7：F11 无边框全屏（Windows；其它平台 no-op）。
class _FullscreenIntent extends Intent {
  const _FullscreenIntent();
}

// ============================================================================
// v2.12.0+2 hotfix: 拍题 FAB（_ScanFab）
// ----------------------------------------------------------------------------
// 老师 persona 报告 P0：v2.11 把拍题 FAB 在课堂模式整体隐藏
// （main.dart:562-577 的 `!inClass` 条件），但老师上课用 PresentMode
// 演示时**有拍学生板书的需求**——学生写到黑板上的题目老师想拍下来
// 让该生下去算。这个隐藏等于砍掉了一个老师工作流核心功能，必须修。
//
// 修法：
//   1. 永远可见（去掉 `!inClass` 条件）。
//   2. 课堂模式下加"PIN 锁"防误触——白板手指/教鞭/激光笔容易误碰 FAB：
//        - 短按 → SnackBar 提示「课堂模式为防误触已关闭单击，请长按拍题」
//          （v2.19.68 P2-4：单击静默修复——文案点名被拦事实 + 出路，
//          且提示只从 FAB onPressed 一条路出，不再双弹）
//        - 长按 1 秒 → 真正触发 + 横幅「课堂模式中，拍题结果仅入错题本
//          不广播到大屏」（课堂演示"焦点在大屏"，拍题结果不应投射）
//   3. 老师角色额外提供「广播到大屏」开关：FAB 全尺寸 + 触发后弹底部
//      sheet 让老师选「仅入错题本（默认）/ 广播到大屏」。学生的 banner
//      强调"不广播"，老师的 banner 强调"可切换"。
//   4. 学生角色课堂模式：FAB 缩到 0.7×（避免占据大屏空间）；非课堂模式
//      全尺寸 + 直接 tap 触发。
//
// 设计取舍：长按进度环用 setState 推动 + AnimatedBuilder 平滑过渡。
// 课堂模式开启/关闭由 ListenableBuilder 监听 PresentModeController，
// 模式变化时通过 ListenableBuilder 自动 rebuild（widget 内不重复订阅）。
// ============================================================================

/// 拍题 FAB 长按解锁所需时长（毫秒）。1 秒足够防误触，又不会让老师
/// 觉得"卡"。
const int _kScanFabHoldMs = 1000;

class _ScanFab extends StatefulWidget {
  /// 当前是否在课堂模式（PresentModeController.instance.enabled）。
  /// 由父级 ListenableBuilder 注入；本 widget 不重复订阅控制器。
  final bool inClass;
  const _ScanFab({required this.inClass});

  @override
  State<_ScanFab> createState() => _ScanFabState();
}

class _ScanFabState extends State<_ScanFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _holdCtrl;
  bool _holding = false;
  bool _unlocked = false; // 标记本次 down→up 周期内 Timer 已 fire 过 _onUnlocked
  // 课堂模式长按 1 秒解锁：用 Timer 自管（不用 GestureDetector.onLongPress，
  // FAB 内部 InkWell 与 onLongPress 在 hit-test 链路上的竞争容易让长按
  // 不触发——既有踩坑实锤）。Listener 接收所有 pointer 事件，最稳。
  Timer? _holdTimer;

  @override
  void initState() {
    super.initState();
    _holdCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _kScanFabHoldMs),
    )..addListener(() {
        if (mounted) setState(() {});
      });
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _holdCtrl.dispose();
    super.dispose();
  }

  /// 当前用户角色。null = 尚未选择（首启态），按学生策略走。
  UserRole? get _role => FirstRunStore.instance.currentRole();

  /// 是否老师角色（决定 FAB 全尺寸 + "广播"选项）。
  bool get _isTeacher => _role == UserRole.teacher;

  /// 课堂模式下学生角色 FAB 缩到 0.7×；其他场景 1×。
  double get _iconScale {
    if (widget.inClass && !_isTeacher) return 0.7;
    return 1.0;
  }

  /// 课堂模式学生：FAB.small（40 物理尺寸）；其他：FAB.small 仍 40，
  /// 课堂模式学生额外 0.7× 让视觉更小。原始 v2.10 拍题 FAB 即
  /// `FloatingActionButton.small` + `size:20` 图标——保持组件类型不变
  /// 以避免破坏 FAB 间距/边距的视觉一致性，仅缩图标尺寸。
  double get _iconSize => 20 * _iconScale;

  void _onPointerDown(PointerDownEvent _) {
    if (!widget.inClass) return;
    setState(() {
      _holding = true;
      _unlocked = false;
    });
    _holdCtrl.forward(from: 0);
    _holdTimer?.cancel();
    _holdTimer = Timer(const Duration(milliseconds: _kScanFabHoldMs), () {
      if (!mounted) return;
      if (_unlocked) return; // 防止 up 期间 Timer 重复触发
      _unlocked = true;
      _onUnlocked();
    });
  }

  void _onPointerUp(PointerUpEvent _) {
    if (!widget.inClass) return;
    _holdTimer?.cancel();
    final wasHolding = _holding;
    _holdCtrl.stop();
    _holdCtrl.value = 0;
    if (wasHolding) setState(() => _holding = false);
    // v2.19.68 P2-4：提示只从 FAB onPressed（_onTap）一条路出——旧实现
    // Listener 松手路径 + FAB onPressed 各弹一条，单击提示排队两遍；
    // 这里只负责复位状态（_unlocked 保持原值，_onTap 靠它跳过已解锁
    // 动线的重复提示），不再抢着提示。
  }

  void _onPointerCancel(PointerCancelEvent _) {
    if (!widget.inClass) return;
    _holdTimer?.cancel();
    _holdCtrl.stop();
    _holdCtrl.value = 0;
    if (_holding) setState(() => _holding = false);
    _unlocked = false;
  }

  void _onTap() {
    if (widget.inClass) {
      // v2.19.68 P2-4（老师实测两次单击静默）：单击分支给出明确人话提示，
      // 说明单击被防误触策略拦下、出路是长按；本次已长按解锁（_unlocked，
      // Listener 在松手时置位）则不再叠提示——解锁动线已有横幅/sheet。
      if (_unlocked) return;
      _showHoldHint();
    } else {
      showScanUploadDialog(context);
    }
  }

  /// 长按 1 秒解锁后真正开拍题 dialog。先弹课堂 banner 给老师/学生
  /// 看明白"拍题结果只入错题本不广播"，老师额外有"广播到大屏"开关。
  void _onUnlocked() {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (widget.inClass) {
      if (_isTeacher) {
        // 老师：弹底部 sheet 让选"仅入错题本 / 广播到大屏"。
        _showTeacherBroadcastSheet(messenger);
      } else {
        // 学生：横幅提示"只入错题本"，然后开 dialog。
        messenger?.showSnackBar(_classroomSnackBar(
          '课堂模式中，拍题结果仅入错题本不广播到大屏',
        ));
        showScanUploadDialog(context);
      }
    } else {
      // 非课堂模式：直接开 dialog（保留原 v2.10 行为）。
      showScanUploadDialog(context);
    }
  }

  /// 课堂模式单击（未达长按阈值）的防误触提示。v2.19.68 P2-4：文案从
  /// 「长按 1 秒解锁拍题」改成点名单击被拦 + 出路的完整句——老师实测
  /// 旧文案被读成"没反应"，新文案一次说清规则。
  void _showHoldHint() {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(_classroomSnackBar(
      '课堂模式为防误触已关闭单击，请长按拍题',
    ));
  }

  /// 老师角色"广播"选项 sheet。
  ///
  /// v2.13 R3 P0-B1：实际广播通道尚未接通（全 lib grep「广播」只
  /// 有文案、0 处实现），原「广播到大屏」是假按钮——点了只开拍题
  /// dialog + SnackBar，什么都没广播，也无"未接通"提示。现在按
  /// 班级共性错卡先例改成**锁样式占位**：按钮 disabled + 「敬请期待
  /// v2.13」副标题，点击只弹"开发中"提示、绝不开 dialog。未来接入
  /// 广播通道时再恢复 FilledButton.onPressed（本 UI 结构不破坏）。
  void _showTeacherBroadcastSheet(ScaffoldMessengerState? messenger) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '课堂模式拍题',
                  style: AppText.label.copyWith(color: AppColors.ink),
                ),
                const SizedBox(height: 4),
                Text(
                  '选择拍题结果的去向（默认仅入错题本）',
                  style: AppText.caption.copyWith(color: AppColors.graphite),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(sheetCtx).pop();
                          messenger?.showSnackBar(_classroomSnackBar(
                            '课堂模式中，拍题结果仅入错题本不广播到大屏',
                          ));
                          showScanUploadDialog(context);
                        },
                        style: OutlinedButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                          side: BorderSide(color: AppColors.teal),
                          foregroundColor: AppColors.teal,
                        ),
                        child: const Text('仅入错题本'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        // v2.13 R3 P0-B1：按钮本体 disabled（onPressed: null），
                        // 点击仍给"敬请期待"反馈——参考班级共性错卡先例
                        // （锁样式占位 + SnackBar），不假装可广播，也绝不开
                        // 拍题 dialog。
                        onTap: () {
                          messenger?.showSnackBar(_classroomSnackBar(
                            '广播到大屏：该功能开发中，该功能随版本更新逐步开放',
                          ));
                        },
                        child: FilledButton(
                          onPressed: null,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.border,
                            disabledBackgroundColor: AppColors.border,
                            foregroundColor: AppColors.steel,
                            disabledForegroundColor: AppColors.steel,
                            padding:
                                const EdgeInsets.symmetric(vertical: 10),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.lock_outline,
                                      size: 16, color: AppColors.steel),
                                  const SizedBox(width: 4),
                                  Text(
                                    '广播到大屏',
                                    style: AppText.label.copyWith(
                                        color: AppColors.steel),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                // R6 老师走查：不写死版本号——占位文案只说
                                // 「开发中」，不承诺具体版本上线。
                                '开发中',
                                style: AppText.caption.copyWith(
                                    color: AppColors.steel),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  SnackBar _classroomSnackBar(String msg) {
    return SnackBar(
      content: Text(msg),
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.graphite,
    );
  }

  @override
  Widget build(BuildContext context) {
    final iconSize = _iconSize;
    final fabCore = FloatingActionButton.small(
      heroTag: 'scanFab',
      tooltip: widget.inClass
          ? '拍题识别（课堂模式：长按 1 秒解锁）'
          : '拍题识别（上传题目图片）',
      onPressed: _onTap,
      backgroundColor: AppColors.canvas,
      foregroundColor: AppColors.teal,
      elevation: 0,
      highlightElevation: 0,
      shape: CircleBorder(side: BorderSide(color: AppColors.teal)),
      child: Icon(Icons.add_photo_alternate_outlined, size: iconSize),
    );

    // 非课堂模式：保持 v2.10 行为（直接 tap 触发）。
    if (!widget.inClass) return fabCore;

    // 课堂模式：包 Listener + 自管 Timer 实现"短按提示 / 长按 1 秒解锁"。
    // 用 Listener 而非 GestureDetector 是因为 FAB 内部 InkWell 与
    // GestureDetector.onLongPress 在 hit-test 链路上竞争会导致长按
    // 不触发（既有踩坑实锤）；Listener 接收所有 pointer 事件最稳。
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: Stack(
        alignment: Alignment.center,
        children: [
          fabCore,
          // 长按进度环：仅在 _holding=true 时显示，透明度随 _holdCtrl
          // 线性增长；松开/取消时由 _onPointerUp/Cancel 重置 _holdCtrl
          // 并触发 setState，环随之消失。
          if (_holding)
            IgnorePointer(
              child: SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  value: _holdCtrl.value,
                  strokeWidth: 2.5,
                  color: AppColors.teal,
                  backgroundColor: AppColors.teal.withAlpha(40),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
