// account_data_section.dart —— 设置页「账号与数据」分区（v2.24）。
//
// 职责：多档案的增删改切 + 整机数据的一键打包带走 / 原地恢复。
//
// 为什么单独成文件而不塞进 settings_page.dart：设置页已近千行，再塞
// 两节交互（含若干对话框）会突破可维护上限；这里只依赖
// AccountsStore / BackupService 的公开 API，可独立测试。
//
// 视觉沿用设置页单列平铺：节标题 + 说明小字 + 按钮行。无卡片、无阴影、无 emoji。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_version.dart';
import '../../services/app_restart.dart';
import '../../services/backup_service.dart';
import '../../state/accounts_store.dart';
import '../../state/mistake_book.dart' show MistakeBookExporter;
import '../../theme.dart';
import '../../ui/json_pick.dart';
import '../../ui/share_file.dart';

class AccountDataSection extends StatefulWidget {
  const AccountDataSection({super.key});

  @override
  State<AccountDataSection> createState() => _AccountDataSectionState();
}

class _AccountDataSectionState extends State<AccountDataSection> {
  bool _busy = false;
  String? _status;

  /// 最近一次导出的包路径。安卓上它落在应用私有目录，用户拿不到，
  /// 需要靠「分享数据包」经系统分享面板发出去。
  String? _lastExportPath;

  AccountsStore get _store => AccountsStore.instance;

  String _pad(int v) => v.toString().padLeft(2, '0');

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  Future<void> _run(Future<void> Function() job) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await job();
    } catch (e) {
      if (mounted) setState(() => _status = '操作失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 切档后若无法自重启（安卓 / Web / 非 Windows），用不可关闭的对话框
  /// 挡住后续操作。
  ///
  /// 必须挡住——select() 已把 accountDataDir 指向新档案，而错题本、历史、
  /// 会话等单例仍持有旧档案的内存副本；此时任何一次保存都会把旧数据写进
  /// 新档案目录。只弹一条 SnackBar 等于放行。
  Future<void> _afterSwitch() async {
    final out = await restartApp();
    if (out == RestartOutcome.relaunched) return;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('请重启应用完成切换'),
          content: Text(out == RestartOutcome.needManual
              ? '账号已切换。请关闭本应用后重新打开，下次启动会直接进入该账号。'
              : '切换已写入，但自动重启失败。请手动关闭并重新打开应用。'),
          actions: [
            FilledButton(
              onPressed: () => SystemNavigator.pop(),
              child: const Text('退出应用'),
            ),
          ],
        ),
      ),
    );
  }

  // ── 档案增删改切 ────────────────────────────────────────────

  Future<void> _create() async {
    // 建完立刻重启（切档必然重启）：先说清代价，否则用户填了一半的东西没了。
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建账号'),
        content: Text(
          '新建后会立即重启应用以进入新账号，未保存的输入会丢失。继续吗？'
          '${_store.active?.hasPin == false ? '\n\n注意：当前账号「${_store.active?.name ?? ''}」没有 PIN，'
              '这台电脑上任何人都能点进去。建好新账号后，建议切回它设置一个 PIN。' : ''}'
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('继续新建')),
        ],
      ),
    );
    if (go != true) return;
    final r = await _askNamePin(title: '新建账号');
    if (r == null) return;
    await _run(() async {
      final p = await _store.create(r.name, r.pin);
      // 用 selectAndUnlock：切档必然重启，不写一次性解锁标记的话，
      // 重启后用户还得在门禁上再选一次刚建的账号。
      await _store.selectAndUnlock(p.id);
      setState(() => _status = '已新建「${p.name}」，重启后生效。');
      await _afterSwitch();
    });
  }

  Future<void> _rename(AccountProfile p) async {
    final c = TextEditingController(text: p.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名账号'),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(
              labelText: '账号名称', hintText: '例如 张老师 / 高一(3)班'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(c.text),
              child: const Text('确定')),
        ],
      ),
    );
    c.dispose();
    if (name == null || name.trim().isEmpty) return;
    await _run(() async {
      await _store.rename(p.id, name.trim());
      setState(() => _status = '已重命名为「${name.trim()}」。');
    });
  }

  Future<void> _switchTo(AccountProfile p) async {
    if (p.id == _store.activeId) {
      _toast('已经是当前账号');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('切换账号'),
        content: Text('切换到「${p.name}」需要重启应用，当前未保存的输入会丢失。现在切换吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('切换并重启')),
        ],
      ),
    );
    if (ok != true) return;
    // 有 PIN 的档案必须切换前验一次：selectAndUnlock 会写一次性解锁标记，
    // 重启后凭它直接进门——不验等于谁点一下都能进别人的档案。
    if (p.hasPin) {
      final pin = await _askPin('切换到「${p.name}」');
      if (pin == null || !mounted) return;
      final pinOk = await _store.verifyPin(p.id, pin);
      if (!pinOk) {
        _toast('PIN 不正确，未切换');
        return;
      }
      if (!mounted) return;
    }
    await _run(() async {
      // 同上：切换后重启要直接进门，不再要求重选。
      await _store.selectAndUnlock(p.id);
      await _afterSwitch();
    });
  }

  // ── 打包 / 恢复 ────────────────────────────────────────────

  Future<void> _export() async {
    final pwd = await _askPassphrase(title: '打包全部账号数据', confirm: true);
    if (pwd == null) return;
    await _run(() async {
      final r = await BackupService.export(passphrase: pwd, appVersion: appVersionNumber);
      setState(() {
        _lastExportPath = r.ok ? r.path : null;
        _status = r.ok
            ? '已导出 ${r.fileCount} 个文件（${(r.bytes / 1024).toStringAsFixed(1)} KB）：'
                '${r.path}'
                '${MistakeBookExporter.isAndroidExport ? '（应用私有目录，需用「分享数据包」发出去）' : ''}'
            : '导出失败：${r.error}';
      });
    });
  }

  /// 安卓导出的包在应用私有目录里，文件管理器看不到，必须经系统分享面板
  /// 发到微信 / 网盘 / 邮件才算真的「带得走」。
  Future<void> _shareExport() async {
    final path = _lastExportPath;
    if (path == null) return;
    final err = await shareFile(path, mimeType: 'application/octet-stream');
    if (!mounted || err == null) return;
    setState(() => _status = '分享失败：$err');
  }

  Future<void> _restore() async {
    final picked = await pickJsonFile();
    if (picked == null || !mounted) return;
    final pwd = await _askPassphrase(title: '从数据包恢复', confirm: false);
    if (pwd == null || !mounted) return;
    // 先只解密不写盘：恢复一进去就删 accounts/，用户必须在覆盖前看到
    // 包里到底有什么、包里没有的账号会消失。口令错也在这里挡住。
    final info =
        await BackupService.inspect(raw: picked.content, passphrase: pwd);
    if (!mounted) return;
    if (!info.ok) {
      setState(() => _status = '恢复失败：${info.error}');
      return;
    }
    final created = info.createdAt;
    final stamp = created == null
        ? '未知'
        : '${created.year}-${_pad(created.month)}-${_pad(created.day)} '
            '${_pad(created.hour)}:${_pad(created.minute)}';
    final names =
        info.accountNames.isEmpty ? '（无）' : info.accountNames.join('、');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认覆盖本机数据'),
        content: Text('包内账号：$names（共 ${info.accountNames.length} 个）\n'
            '导出时间：$stamp · 文件数：${info.fileCount}\n\n'
            '恢复会先清空本机现有的 accounts/，包里没有的账号会从本机消失'
            '（可从 _restore_backup_ 快照手工找回）。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('覆盖并恢复')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      final r = await BackupService.restore(raw: picked.content, passphrase: pwd);
      setState(() {
        _status = r.ok
            ? '已恢复 ${r.accountCount} 个账号、${r.fileCount} 个文件。'
                '${r.backupDir == null ? '' : ' 覆盖前快照：${r.backupDir}'}'
            : '恢复失败：${r.error}';
      });
      // restore() 一进去就删 accounts/ 再逐文件写，失败也可能已经动过磁盘
      //（口令与格式在 inspect 里验过了）。所以成败都必须重启：进程带着旧
      // 内存跑在已被清空的目录上，下一次保存就会把它写回去。
      await _afterSwitch();
    });
  }

  // ── 对话框 ────────────────────────────────────────────────

  /// 切换账号前的 PIN 校验框。只返回输入值，判定交给调用方（要提示得出来）。
  Future<String?> _askPin(String title) async {
    final ctrl = TextEditingController();
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 4,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: '4 位 PIN',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.length != 4) return;
              Navigator.of(ctx).pop(v);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return res;
  }

  Future<_NamePin?> _askNamePin({
    required String title,
    bool hideName = false,
    String initialName = '',
  }) async {
    final nameCtrl = TextEditingController(text: initialName);
    final pinCtrl = TextEditingController();
    String? err;
    final res = await showDialog<_NamePin>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hideName)
                Text('给「$initialName」设置启动 PIN。')
              else
                TextField(
                  controller: nameCtrl,
                  autofocus: true,
                  decoration: const InputDecoration(
                      labelText: '账号名称', hintText: '例如 张老师 / 高一(3)班'),
                ),
              const SizedBox(height: 14),
              TextField(
                controller: pinCtrl,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 4,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: '4 位 PIN（留空 = 不设）',
                  helperText: 'PIN 只阻止同机误看，不加密数据文件',
                ),
              ),
              if (err != null)
                Text(err!,
                    style: TextStyle(color: AppColors.lethal, fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: const Text('取消')),
            FilledButton(
              onPressed: () {
                final pin = pinCtrl.text.trim();
                if (pin.isNotEmpty && !RegExp(r'^\d{4}$').hasMatch(pin)) {
                  setLocal(() => err = 'PIN 必须是 4 位数字');
                  return;
                }
                final name = hideName ? initialName : nameCtrl.text.trim();
                if (!hideName && name.isEmpty) {
                  setLocal(() => err = '请填写账号名称');
                  return;
                }
                Navigator.of(ctx).pop(_NamePin(name, pin));
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
    pinCtrl.dispose();
    return res;
  }

  Future<String?> _askPassphrase({
    required String title,
    required bool confirm,
  }) async {
    final a = TextEditingController();
    final b = TextEditingController();
    String? err;
    // 口令是唯一凭据又全掩码：错一个字符只会得到「文件已损坏」，
    // 给一个自己按下去的显示开关，比让用户逐位重打便宜。
    var show = false;
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '整包用这个口令做 AES-256-GCM 加密。换一台机器恢复时必须输入同一口令，'
                '口令丢了数据包就打不开了。',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: a,
                autofocus: true,
                obscureText: !show,
                decoration: InputDecoration(
                  labelText: '口令（至少 6 位）',
                  suffixIcon: IconButton(
                    tooltip: show ? '隐藏口令' : '显示口令',
                    onPressed: () => setLocal(() => show = !show),
                    icon: Icon(
                      show
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 18,
                    ),
                  ),
                ),
              ),
              if (confirm) ...[
                const SizedBox(height: 10),
                TextField(
                  controller: b,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '再输一次'),
                ),
              ],
              if (err != null)
                Text(err!,
                    style: TextStyle(color: AppColors.lethal, fontSize: 12)),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: const Text('取消')),
            FilledButton(
              onPressed: () {
                final v = a.text;
                if (v.length < 6) {
                  setLocal(() => err = '口令至少 6 位');
                  return;
                }
                if (confirm && v != b.text) {
                  setLocal(() => err = '两次输入不一致');
                  return;
                }
                Navigator.of(ctx).pop(v);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
    a.dispose();
    b.dispose();
    return res;
  }

  // ── 渲染 ──────────────────────────────────────────────────

  Widget _header(BuildContext context, String title, String? desc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppText.sectionTitle),
        if (desc != null) ...[
          const SizedBox(height: 6),
          Text(desc, style: Theme.of(context).textTheme.bodySmall),
        ],
        const SizedBox(height: 14),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = _store.accounts;
    final activeId = _store.activeId;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(
          context,
          '账号与数据',
          '每个账号有独立的数据目录（错题本、AI 对话、计算历史、拍题题库、偏好全部隔离）。'
              'PIN 只在启动时挡住同机误看，数据文件本身不加密；'
              '不设 PIN 的档案，这台电脑上任何人都能进。',
        ),
        for (final p in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(
                  p.id == activeId
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 16,
                  color: p.id == activeId ? AppColors.teal : AppColors.steel,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${p.name}${p.hasPin ? ' · 已设 PIN' : ''}${p.id == activeId ? ' · 当前' : ''}',
                    style: AppText.label,
                  ),
                ),
                if (p.id != activeId)
                  TextButton(
                      onPressed: _busy ? null : () => _switchTo(p),
                      child: const Text('切换')),
                // 设置页只管理当前档案：改别人的名字 / PIN 等于绕过对方的门禁
                // （setPin 不校验旧值），删别人档案更不该在这里发生。
                IconButton(
                  tooltip: p.id == activeId ? '重命名' : '请先切换到该账号',
                  onPressed:
                      _busy || p.id != activeId ? null : () => _rename(p),
                  icon: const Icon(Icons.drive_file_rename_outline, size: 18),
                ),
                IconButton(
                  tooltip: p.id == activeId
                      ? (p.hasPin ? '修改 PIN' : '设置 PIN')
                      : '请先切换到该账号',
                  onPressed: _busy || p.id != activeId
                      ? null
                      : () => _editPinWithName(p),
                  icon: const Icon(Icons.pin_outlined, size: 18),
                ),
                IconButton(
                  // 删档要把数据目录搬走，而进程里各 store 仍握着它的内存副本；
                  // 启动页没有这些单例，是唯一安全的删除入口。
                  tooltip:
                      p.id == activeId ? '请到启动页删除该账号' : '请先切换到该账号',
                  onPressed: null,
                  icon: const Icon(Icons.delete_outline, size: 18),
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : _create,
              icon: const Icon(Icons.person_add_alt, size: 18),
              label: const Text('新建账号'),
            ),
            FilledButton.icon(
              onPressed: _busy ? null : _export,
              icon: const Icon(Icons.inventory_2_outlined, size: 18),
              label: const Text('一键打包带走'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _restore,
              icon: const Icon(Icons.settings_backup_restore, size: 18),
              label: const Text('从数据包恢复'),
            ),
            // 安卓的包落在应用私有目录，文件管理器看不到：不分享出去等于没导出。
            if (MistakeBookExporter.isAndroidExport && _lastExportPath != null)
              OutlinedButton.icon(
                onPressed: _busy ? null : _shareExport,
                icon: const Icon(Icons.ios_share, size: 18),
                label: const Text('分享数据包'),
              ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _store.lock,
              icon: const Icon(Icons.lock_outline, size: 18),
              label: const Text('锁定并返回选人页'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          '打包内容：本机全部账号的数据目录（错题本、AI 对话记录、计算历史、拍题题库、'
          '操作与偏好配置），也会带上 _trash_accounts 里已删除账号的数据'
          '（删除因此是可逆的）。不含 .machine.key（本机机器密钥）与恢复快照。',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (_busy) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(minHeight: 2),
        ],
        if (_status != null) ...[
          const SizedBox(height: 10),
          SelectableText(_status!, style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
  }

  /// PIN 对话框标题需要带账号名，但 _askNamePin 的 hideName 分支只认 initialName。
  Future<void> _editPinWithName(AccountProfile p) async {
    // 纵深防御：setPin 不校验旧 PIN，跨档案改 PIN 等于绕过对方门禁。
    if (p.id != _store.activeId) {
      _toast('请先切换到该账号');
      return;
    }
    final r = await _askNamePin(
      title: p.hasPin ? '修改 PIN' : '设置 PIN',
      hideName: true,
      initialName: p.name,
    );
    if (r == null) return;
    await _run(() async {
      await _store.setPin(p.id, r.pin);
      setState(() => _status = r.pin.isEmpty ? '已取消 PIN。' : 'PIN 已更新，下次启动生效。');
    });
  }
}

class _NamePin {
  const _NamePin(this.name, this.pin);
  final String name;
  final String pin;
}
