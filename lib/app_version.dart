// app_version.dart —— 版本号唯一来源。
//
// 界面一律读 [appVersionLabel]；源码与界面都不得写死版本字面量。
// 构建时可用 `--dart-define=APP_VERSION_NUMBER=…` 覆盖缺省号，覆盖值须与
// `flutter build --build-name` 一致，否则 exe/APK 属性与关于页版本号打架
// （本仓库踩过同类事故）。

/// 纯版本号（不含「v」前缀）。
const String appVersionNumber =
    String.fromEnvironment('APP_VERSION_NUMBER', defaultValue: '0.1.0');

/// 面向用户的完整标签。
String get appVersionLabel => 'v$appVersionNumber · 开源版';
