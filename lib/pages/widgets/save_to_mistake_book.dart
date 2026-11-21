// save_to_mistake_book.dart —— 「存入错题本」共享按钮（v2.13）
//
// 学生高频缺口（2026-09-12 学生 persona 走查 P1#4）：计算器页算完题想收进
// 错题本，原来要切错题本页 + 点 + + 5 字段表单，4 步摩擦。RedFox 错题整理
// 方法论检索同日照证「抄题耗时」是错题整理失败首因——本题干/答案由调用方
// 自动拼装，学生零抄写一键收录。
//
// 语义 = 收藏本题：stem/correctAnswer 自动拼装；userAnswer 留空（错题本
// 卡片渲染为「待补充」，见 mistake_book_page.dart）→ 与拍题/表单入口同款
// 链路入队 AI 自动整理（500ms debounce 后台归类）。
//
// errorType 用 other（非「概念错」）：收藏题尚未作答，错因待 AI 整理覆写——
// 依赖 AI 覆写策略（mistake_book.dart：只跳过 aiSummary 非空的 entry），
// 若未来 AI 策略改动跳过已填 errorType，此处会静默错位。
//
// 老师角色守卫（同 scan_upload_dialog.dart R4-1 P0 方案 A）：错题本是学生
// 私人空间；老师写入 = 数据进不可见错题本 + AI 整理照跑耗额度写不可见
// 条目。守卫为 SnackBar 说明，不写入。
//
// 放在 pages/widgets/（非 ui/）：SnackBar 带「去错题本」导航 action，
// 依赖具体页面 MistakeBookPage——pages 层组件允许依赖 pages。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../state/first_run_store.dart';
import '../../state/mistake_book.dart';
import '../../theme.dart';
import '../mistake_book_page.dart';

/// 通用「存入错题本」按钮：挂载在任何「算完题/看完结果」的场景。
class SaveToMistakeBookButton extends StatelessWidget {
  const SaveToMistakeBookButton({
    super.key,
    required this.stem,
    required this.correctAnswer,
    required this.subjectArea,
    // R5 老师走查：练习判错等场景学生的作答要进错题本——复习会话的
    // 「你当时写」和 AI 错因归类都依赖这个信号（默认空 = 收藏语义）。
    this.userAnswer = '',
    this.srcModule,
    this.srcParams,
  });

  /// 题干（调用方自动拼装，如 'AaBb × AaBb 杂交，F₂ 表型比与基因型比？'）。
  final String stem;

  /// 正确答案（比例/结论文本）。
  final String correctAnswer;

  /// 考点/模块标签（错题本「考点」字段，供筛选）。
  final String subjectArea;

  /// 用户的（错误）作答；空 = 未作答/收藏语义。
  ///
  /// ⛔ 调用侧纪律：这里只收**学生真的写下的东西**。屏上占位串——为「这一项
  /// 没有值」而写的字样，如系谱练习原先的 `?? '（未选择）'`——不是作答：它
  /// 非空 ⇒ 刷新错答那道闸把它当成一次真实错答观测 ⇒ 条目里已有的真错答被
  /// 刷成占位符，复习会话「你当时写：…」印出来的就是那个占位符。
  /// **没作答就传空串。**
  final String userAnswer;

  /// 来源工具的 moduleId（如 'cross_mono'）。不传 = 这道题不是从工具存
  /// 进来的，错题本里不会出现「回来源工具重算」按钮。
  final String? srcModule;

  /// 存进来那一刻的参数（`{'p1':…, 'p2':…}`，连锁互换页另有 `{'r':…}`）。
  final Map<String, String>? srcParams;

  void _save(BuildContext context) {
    saveToMistakeBook(
      context,
      stem: stem,
      correctAnswer: correctAnswer,
      subjectArea: subjectArea,
      userAnswer: userAnswer,
      srcModule: srcModule,
      srcParams: srcParams,
    );
  }

  @override
  Widget build(BuildContext context) {
    // v2.19.13（学生找茬 🔴2 修正）：按钮内的快捷键已移除——快捷键
    // 沿**焦点链**冒泡，TextField 有焦点时根本到不了按钮子树；页面
    // 级绑定由 SaveMistakeKeyHost 提供（v2.19.55 起全部页统一，见
    // save_mistake_key_host.dart）。Tooltip 保留键位提示。
    return Tooltip(
      message: '存入错题本（Ctrl+S）',
      child: TextButton.icon(
        onPressed: () => _save(context),
        icon: const Icon(Icons.bookmark_add_outlined, size: 18),
        label: const Text('存入错题本'),
        // v2.13 评审：莫兰迪 token 对齐——默认 primary 色偏蓝紫，
        // 换 graphite 系（暗/浅/高对比三套实时派生）。
        style: TextButton.styleFrom(foregroundColor: AppColors.graphite),
      ),
    );
  }
}

/// v2.19.11：存错题逻辑提取为顶层函数——「存入错题本」按钮与页面级
/// 快捷键（Ctrl+S，学生走查 #3 键盘党缺口）共用同一入口，行为严格一致。
void saveToMistakeBook(
  BuildContext context, {
  required String stem,
  required String correctAnswer,
  required String subjectArea,
  String userAnswer = '',
  // 调用方（计算器页）把自己记下来，复习时能一键回到那道题。
  // 不传 = 老语义（手加/无来源），复习会话与列表里不会有那枚按钮。
  String? srcModule,
  Map<String, String>? srcParams,
}) {
  final messenger = ScaffoldMessenger.of(context);
  // v2.19.13（学生找茬 🔴2 配套）：页面级快捷键在结果未算出时按
  // Ctrl+S → 空答案入库是垃圾数据，守卫提示先计算。
  // v2.19.54：clearSnackBars 与老师守卫路径对齐——空答案守卫不该排在
  // 别的 SnackBar（如快捷键指引）后面让学生等几秒才看到。
  if (correctAnswer.isEmpty) {
    messenger.clearSnackBars();
    messenger.showSnackBar(
        const SnackBar(content: Text('先算出结果，再存入错题本')));
    return;
  }
  if (FirstRunStore.instance.currentRole() == UserRole.teacher) {
    messenger.clearSnackBars();
    messenger.showSnackBar(const SnackBar(
        content:
            Text('错题本是学生功能，老师模式下不可写入；如需收藏请先切换使用角色')));
    return;
  }
  final r = MistakeBook.instance.addOrFind(
    stem: stem,
    userAnswer: userAnswer,
    correctAnswer: correctAnswer,
    errorType: MistakeErrorType.other,
    subjectArea: subjectArea,
    srcModule: srcModule,
    srcParams: srcParams,
  );
  messenger.clearSnackBars();
  if (!r.isNew) {
    // R5 学生走查：重复存入（连点/多入口）只提示已在库，不重复入队
    // AI 整理、不给「撤销」（旧条目不是这次写入的）。
    messenger.showSnackBar(
      SnackBar(
        persist: false,
        content: Row(
          children: [
            const Expanded(child: Text('这道題已在错题本里')),
            TextButton(
              onPressed: () {
                messenger.hideCurrentSnackBar();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => MistakeBookPage()),
                );
              },
              child: const Text('去错题本'),
            ),
          ],
        ),
      ),
    );
    return;
  }
  final added = r.entry;
  // 与拍题/表单入口同款：入队 AI 自动整理（不依赖 widget 存活）。
  MistakeBook.instance.debugEnqueueAiOrganize(added.id);
  messenger.showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 5),
      // SnackBar 带 action 时 Flutter 默认 persist=true → 永不 dismiss，
      // 5 秒窗口失效。显式 false（同 mistake_book_page / scan dialog）。
      persist: false,
      // 自定义 Row 内容：单 action 槽装不下「撤销 + 去错题本」两个操作
      //（UX 走查 2026-09-12：存入后想立刻确认收录，给一键跳转）。
      content: Row(
        children: [
          const Expanded(child: Text('已加入错题本')),
          TextButton(
            onPressed: () => MistakeBook.instance.delete(added.id),
            child: const Text('撤销'),
          ),
          TextButton(
            onPressed: () {
              messenger.hideCurrentSnackBar();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => MistakeBookPage()),
              );
            },
            child: const Text('去错题本'),
          ),
        ],
      ),
    ),
  );
}

/// v2.19.55：原 `SaveToMistakeBookShortcuts`（CallbackShortcuts 形态）已删除——
/// 全部 8 处用法迁移到 `save_mistake_key_host.dart` 的 [SaveMistakeKeyHost]
/// （HardwareKeyboard 族：焦点落在页面子树外也收得到键 + 按下现取 payload +
/// 激活页闸 + 输入焦点让路）。删除理由存档：CallbackShortcuts 沿焦点链冒泡，
/// 焦点落在页面子树之外（push 返回后的 Navigator Scope）时按了没反应；
/// 且构造参数形态在「输入改了宿主没重建」时存旧题干。存题语义本体是
/// 顶层 [saveToMistakeBook] 函数，按钮与新宿主共用，未受影响。
