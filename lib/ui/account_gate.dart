// account_gate.dart —— 档案门禁（v2.24）。
//
// 挂点：MaterialApp.home = AccountGate(child: HomeShell())。单档案无 PIN
// 时 AccountsStore.load() 已把 unlocked 置 true，直接放行——老用户升级
// 后看不到任何新界面；多档案或有 PIN 才拦。
//
// 文案纪律：PIN 只挡「同机顺手看一眼」，磁盘文件本身不加密，页面底部
// 如实写明，不制造安全感幻觉。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/app_restart.dart';
import '../state/accounts_store.dart';
import '../theme.dart';

class AccountGate extends StatefulWidget {
  const AccountGate({super.key, required this.child});

  final Widget child;

  @override
  State<AccountGate> createState() => _AccountGateState();
}

class _AccountGateState extends State<AccountGate> {
  /// 正在等 PIN 的账号 id（null = 没有展开的输入框）。
  String? _pinFor;
  final TextEditingController _pinCtrl = TextEditingController();
  // 新建对话框的输入控制器挂在 State 上：showDialog 返回时路由退场动画
  // 还在跑，当场 dispose 会让动画里的 TextField 用到已销毁的控制器。
  final TextEditingController _newNameCtrl = TextEditingController();
  final TextEditingController _newPinCtrl = TextEditingController();
  String? _pinError;
  bool _busy = false;

  /// 「忘记 PIN」面板是否展开（只对当前展开 PIN 输入框的那个账号有效）。
  bool _forgotOpen = false;

  @override
  void dispose() {
    _pinCtrl.dispose();
    _newNameCtrl.dispose();
    _newPinCtrl.dispose();
    super.dispose();
  }

  /// 改动已生效但本平台无法自重启时的提示页（切档 / 删当前档 / 整机重置共用）。
  bool _needsRestart = false;
  String _restartTitle = '';
  String _restartBody = '';

  /// 进入某个档案。
  ///
  /// 当前档案直接放行；切到**别的**档案必须重启进程——切换前绝不能
  /// markUnlocked，否则界面会用旧档案的内存数据冒充新档案（学生 B 看到
  /// 老师 A 的错题本是最坏情况）。
  Future<void> _enter(AccountProfile a) async {
    final store = AccountsStore.instance;
    if (store.activeId == a.id) {
      store.markUnlocked();
      if (mounted) setState(() {});
      return;
    }
    await store.selectAndUnlock(a.id);
    await _restartOrNotice(
      '已切换到「${a.name}」',
      '切换账号需要重启应用。请关闭本应用后重新打开，下次启动会直接进入该账号，'
      '不再要求重新选择。',
    );
  }

  /// 改动已落盘但当前平台没法自重启：先挡住主界面，再让用户退出重开。
  ///
  /// 为什么先置 _needsRestart 再 await：整机重置会把 unlocked 置 true，
  /// 晚一帧就会用旧档案的内存数据把主界面渲染出来。
  Future<void> _restartOrNotice(String title, String body) async {
    if (mounted) {
      setState(() {
        _needsRestart = true;
        _restartTitle = title;
        _restartBody = body;
      });
    }
    // Windows 上进程马上退出，Web 上页面马上重载，这里不必等结果。
    await restartApp();
  }

  Future<void> _tapAccount(AccountProfile a) async {
    if (_busy) return;
    if (!a.hasPin) {
      await _enter(a);
      return;
    }
    setState(() {
      _pinFor = a.id;
      _pinError = null;
      _pinCtrl.clear();
      _forgotOpen = false;
    });
  }

  Future<void> _submitPin(String id, String pin) async {
    if (_busy || pin.length != 4) return;
    setState(() => _busy = true);
    final ok = await AccountsStore.instance.verifyPin(id, pin);
    if (!mounted) return;
    if (!ok) {
      // 错一次就清空重输：4 位数字逐位改太难读，直接重来更快。
      setState(() {
        _busy = false;
        _pinError = 'PIN 不正确';
        _pinCtrl.clear();
      });
      return;
    }
    setState(() {
      _busy = false;
      _pinFor = null;
      _pinError = null;
    });
    for (final a in AccountsStore.instance.accounts) {
      if (a.id == id) {
        await _enter(a);
        return;
      }
    }
  }

  Future<void> _showCreateDialog(AccountsStore store) async {
    final nameCtrl = _newNameCtrl;
    final pinCtrl = _newPinCtrl;
    nameCtrl.clear();
    pinCtrl.clear();
    String? error;
    final result = await showDialog<({String name, String pin})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('新建账号'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                maxLength: 20,
                decoration: const InputDecoration(
                  labelText: '账号名字',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: pinCtrl,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 4,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: '4 位 PIN（可留空）',
                  counterText: '',
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error ?? '',
                    style: AppText.caption.copyWith(color: AppColors.lethal)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                final pin = pinCtrl.text;
                if (name.isEmpty) {
                  setDialogState(() => error = '账号名字不能为空');
                  return;
                }
                if (pin.isNotEmpty && pin.length != 4) {
                  setDialogState(() => error = 'PIN 必须是 4 位数字');
                  return;
                }
                Navigator.of(ctx).pop((name: name, pin: pin));
              },
              child: const Text('创建'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final p = await store.create(result.name, result.pin);
      if (!mounted) return;
      await _enter(p);
    } catch (e) {
      debugPrint('[biology] 新建账号失败: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('新建账号失败，请重试')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AccountsStore.instance,
      builder: (context, _) {
        if (_needsRestart) return _buildRestartNotice();
        if (AccountsStore.instance.unlocked) return widget.child;
        return _buildGate();
      },
    );
  }

  /// 已切档但当前平台没法自重启（安卓 / Web / 非 Windows 桌面）。
  ///
  /// 此时绝不能放行进主界面——内存里还是旧档案的数据。只给一条明确的
  /// 出路：退出应用由用户重新打开（安卓 SystemNavigator.pop 会关掉 Activity）。
  Widget _buildRestartNotice() {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_restartTitle, style: AppText.sectionTitle),
                const SizedBox(height: 10),
                Text(
                  _restartBody,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => SystemNavigator.pop(),
                  child: const Text('退出应用'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  Widget _buildGate() {
    final store = AccountsStore.instance;
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('选择账号',
                    style: AppText.pageTitle, textAlign: TextAlign.center),
                const SizedBox(height: 6),
                Text('每个账号的错题本、会话与设置各自独立',
                    style: AppText.caption, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                for (final a in store.accounts) ..._accountEntry(a),
                const SizedBox(height: 6),
                Center(
                  child: TextButton(
                    onPressed: _busy ? null : () => _showCreateDialog(store),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.teal,
                      textStyle: AppText.action,
                    ),
                    child: const Text('新建账号'),
                  ),
                ),
                const SizedBox(height: 18),
                Text('PIN 只防同机误看，数据文件本身未加密',
                    style: AppText.caption, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 忘记 PIN 的出路：如实说明 PIN 不含加密，再给「删档重来」。
  ///
  /// 不提供「绕过 PIN 进入」或「重置 PIN」——PIN 是门禁不是密钥，能绕过就
  /// 等于没有，而能重置别人 PIN 等于任何人拿到设备就能接管对方档案。
  /// 单档删除要验该档 PIN，所以忘了 PIN 的唯一出路是整机重置（可逆：进回收站）。
  Widget _buildForgotPanel(AccountProfile a) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('PIN 不加密数据，只是启动时的一道门禁。',
            style: AppText.caption),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: _busy ? null : () => _confirmDeleteProfile(a),
          child: const Text('删除此账号档案'),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _busy ? null : _confirmResetAll,
            child: const Text('重置这台电脑上的全部账号'),
          ),
        ),
      ],
    );
  }

  /// 整机重置：忘记 PIN 时唯一的出路，先把代价说清再动手。
  Future<void> _confirmResetAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重置这台电脑上的全部账号'),
        content: const Text('全部账号会移到 _trash_accounts（不会被物理删除），'
            '本机回到刚装好的状态。确定继续吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('重置')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await AccountsStore.instance.resetAllProfiles();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('重置失败：$e')));
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    await _restartOrNotice(
      '已重置全部账号',
      '账号数据已移入 _trash_accounts。请关闭本应用后重新打开，'
      '下次启动会回到刚装好的状态。',
    );
  }

  Future<void> _confirmDeleteProfile(AccountProfile a) async {
    // 控制器挂在 State 上：showDialog 返回时退场动画还在用 TextField，
    // 当场 dispose 会踩到已销毁的控制器（同 _newNameCtrl 的理由）。
    final ctrl = _newNameCtrl;
    ctrl.clear();
    // PIN 校验要和账号名确认在同一个对话框里完成：分两步会让「名对了但
    // PIN 错」白白删掉一次输入。
    final pinCtrl = _newPinCtrl;
    pinCtrl.clear();
    String? err;
    String? pinErr;
    var verifying = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('删除「${a.name}」'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(a.hasPin
                  ? '这个档案设了 PIN：先输入该档案的 4 位 PIN，再逐字输入账号名。'
                      '数据目录会移到应用目录下的 _trash_accounts，可手工找回。'
                      '忘记 PIN 的话：先关掉这个对话框，再点面板里的'
                      '「重置这台电脑上的全部账号」。'
                  : '数据目录会移到应用目录下的 _trash_accounts，可手工找回；'
                      '下次打包会一并带走。输入账号名逐字确认：'),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: '账号名',
                  hintText: a.name,
                  errorText: err,
                ),
              ),
              if (a.hasPin) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: pinCtrl,
                  enabled: !verifying,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 4,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: '该档案的 4 位 PIN',
                    counterText: '',
                    errorText: pinErr,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('取消')),
            FilledButton(
              onPressed: verifying
                  ? null
                  : () async {
                      if (ctrl.text.trim() != a.name) {
                        setLocal(() => err = '账号名不一致');
                        return;
                      }
                      if (a.hasPin) {
                        // 只认该档案自己的 PIN：同名谁都会打，PIN 才是门。
                        setLocal(() => verifying = true);
                        final pinOk = await AccountsStore.instance
                            .verifyPin(a.id, pinCtrl.text);
                        if (!ctx.mounted) return;
                        if (!pinOk) {
                          setLocal(() {
                            verifying = false;
                            pinErr = 'PIN 不正确';
                            pinCtrl.clear();
                          });
                          return;
                        }
                        setLocal(() => verifying = false);
                      }
                      Navigator.of(ctx).pop(true);
                    },
              child: const Text('删除'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    // 必须在 remove 之前取：删完 activeId 已经指向别人了。
    final wasActive = AccountsStore.instance.activeId == a.id;
    setState(() => _busy = true);
    try {
      await AccountsStore.instance.remove(a.id);
      if (!mounted) return;
      setState(() {
        _forgotOpen = false;
        _pinFor = null;
        _pinError = null;
        _pinCtrl.clear();
      });
      if (wasActive) {
        // 删的是当前档案：数据目录已被搬走，而各 store 的内存副本还在，
        // 不重启就有把旧数据写进剩下档案的风险。
        await _restartOrNotice(
          '已删除「${a.name}」',
          '被删的是当前账号，数据目录已移入 _trash_accounts。'
          '请关闭本应用后重新打开，下次启动会进入剩下的账号。',
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('已移入应用目录下的 _trash_accounts，可手工找回；下次打包会一并带走'),
      ));
    } on StateError catch (e) {
      // 最后一个账号 / 当前账号：remove 明确拒绝，把原因原样显示，不崩。
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('删除失败：$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  List<Widget> _accountEntry(AccountProfile a) {
    final waiting = _pinFor == a.id;
    return <Widget>[
      Material(
        color: waiting ? AppColors.tealWash : AppColors.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusInput),
        child: InkWell(
          onTap: _busy ? null : () => _tapAccount(a),
          borderRadius: BorderRadius.circular(AppTheme.radiusInput),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              border: Border.all(
                  color: waiting ? AppColors.teal : AppColors.border),
              borderRadius: BorderRadius.circular(AppTheme.radiusInput),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(a.name, style: AppText.label),
                      const SizedBox(height: 2),
                      Text(
                          a.hasPin ? '已设 4 位 PIN' : '没有 PIN：这台电脑上任何人都能进',
                          style: AppText.caption),
                    ],
                  ),
                ),
                // 每一行都给删除入口：无 PIN 的档案进不了「忘记 PIN」面板，
                // 没有这颗按钮就永远删不掉（删除只是移入 _trash_accounts）。
                IconButton(
                  tooltip: '删除这个账号档案',
                  visualDensity: VisualDensity.compact,
                  onPressed:
                      _busy ? null : () => _confirmDeleteProfile(a),
                  icon: Icon(Icons.delete_outline,
                      size: 16, color: AppColors.steel),
                ),
                Icon(Icons.chevron_right, size: 18, color: AppColors.steel),
              ],
            ),
          ),
        ),
      ),
      if (waiting)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _pinCtrl,
                autofocus: true,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                obscureText: true,
                maxLength: 4,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: AppText.monoSmall,
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '输入 4 位 PIN',
                  errorText: _pinError,
                  isDense: true,
                ),
                onChanged: (v) {
                  if (_pinError != null) setState(() => _pinError = null);
                  if (v.length == 4) _submitPin(a.id, v);
                },
              ),
              // 忘了 PIN 是真实场景（换手机 / 学生自己设的）；不给一条
              // 说清代价的出路，用户只能删库重装。
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() => _forgotOpen = !_forgotOpen),
                  child: const Text('忘记 PIN？'),
                ),
              ),
              if (_forgotOpen) _buildForgotPanel(a),
            ],
          ),
        ),
      const SizedBox(height: 8),
    ];
  }
}
