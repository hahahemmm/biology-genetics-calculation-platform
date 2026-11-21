// platform_storage_web.dart —— Web 平台存储实现（localStorage，同步 API）。
// 仅 Web 构建编译（条件导入：调用方
// `import 'platform_storage_io.dart' if (dart.library.html) 'platform_storage_web.dart';`）。
//
// v2.11 M1：从 lib/pages/settings_storage_web.dart 迁移到 lib/storage/
// 中性层（与 platform_storage_io.dart 同目录），调用方 import 路径
// 由 'pages/settings_storage_*.dart' 改为 'storage/platform_storage_*.dart'。
//
// v2.11 M7：dart:html → package:web + dart:js_interop 迁移
// Flutter SDK 已弃用 dart:html（`deprecated_member_use` warning + 计划移除），
// 改用 web 1.1.1：Storage 接口直接返回 String?/String（不需要 .toDart 转换，
// 因为 IDL 类型本身就是 string，与 dart:html 的 dynamic getter 不同）。
//
// v2.0：Web 端设置与会话历史持久化到浏览器 localStorage。
import 'package:web/web.dart' as web;

/// 当前是否为 Web 平台。
bool get isWebStorage => true;

/// v2.24：档案 key 前缀（`acct.<id>.`）。local 档案留空串 = 沿用老 key，
/// 浏览器里已有的数据升级后仍然读得到。
String? accountKeyPrefix;

/// v2.24：Web 端没有文件系统，与 io 版同签名——恒 null，只为条件导入编译。
String? accountDataDir;

/// v2.24：实际落盘 key。多档案隔离全靠前缀，不加前缀的只有账号清单。
String _k(String key) =>
    (accountKeyPrefix == null || accountKeyPrefix!.isEmpty)
        ? key
        : '$accountKeyPrefix$key';

String? storageGet(String key) => web.window.localStorage.getItem(_k(key));

Future<void> storageSet(String key, String value) async {
  web.window.localStorage.setItem(_k(key), value);
}

/// v2.24：不加前缀——账号清单是跨档案的全局元数据。
String? storageGetRaw(String key) => web.window.localStorage.getItem(key);

Future<void> storageSetRaw(String key, String value) async {
  web.window.localStorage.setItem(key, value);
}

/// v2.24：删单个 key（加前缀）。
Future<void> storageRemove(String key) async {
  web.window.localStorage.removeItem(_k(key));
}

/// v2.24：按前缀清空一个档案的全部 key（删账号用）。
///
/// Storage 没有 key 枚举 API，只能按 length + key(i) 收集后再删；
/// `accounts_json`（清单自身）永不参与清理——local 档案前缀是空串，
/// 不排除它就会把账号列表本身删掉。
Future<void> storageRemoveByPrefix(String prefix) async {
  final ls = web.window.localStorage;
  final doomed = <String>[];
  for (var i = 0; i < ls.length; i++) {
    final k = ls.key(i);
    if (k == null || k == 'accounts_json') continue;
    if (k.startsWith(prefix)) doomed.add(k);
  }
  for (final k in doomed) {
    ls.removeItem(k);
  }
}

/// v2.24：清空「local 档案」的全部 key。
///
/// local 用空前缀，不能走 storageRemoveByPrefix('')——startsWith('') 恒真，
/// 会把其它档案和清单一起删光。这里改成「删掉所有不带 acct. 前缀的 key」，
/// 正好等于 local 的数据域。整机重置必须用它，否则重置后旧数据原样回来
/// 且不再要 PIN（等于绕过门禁）。
Future<void> storageRemoveLocalKeys() async {
  final ls = web.window.localStorage;
  final doomed = <String>[];
  for (var i = 0; i < ls.length; i++) {
    final k = ls.key(i);
    if (k == null || k == 'accounts_json') continue;
    if (!k.startsWith('acct.')) doomed.add(k);
  }
  for (final k in doomed) {
    ls.removeItem(k);
  }
}
/// v2.11 M8：Web 端无文件系统——返 null。
/// 调用方（scan_bank_store / history_store）看到这个 null 时走
/// localStorage 路径（`storageGet` / `storageSet`）。
String? userAppDir() => null;

/// v2.24：与 io 版同签名（条件导入编译期要求）；Web 端恒 null。
String? baseAppDir() => null;

/// v2.13 R3 W1：与 io 版本保持同签名（条件导入编译期要求）。
/// Web 端无文件系统、无需等待——直接返。
Future<void> ensureAppDirReady() async {}
