/// 构建水印 —— 对应鸿蒙版 `core/BuildStamp.ets`。
///
/// 便于对着截图定位代码：设置页版本行副标题显示提交号。
/// 由 CI 通过 `--dart-define=BUILD_COMMIT=<sha>` 注入；本地构建显示 `dev`。
library;

const String buildCommit = String.fromEnvironment('BUILD_COMMIT', defaultValue: 'dev');
const String buildTime = String.fromEnvironment('BUILD_TIME', defaultValue: '');
const String appVersion = String.fromEnvironment('APP_VERSION', defaultValue: '0.2.2');
const String appBuildNumber = String.fromEnvironment('APP_BUILD_NUMBER', defaultValue: '4');

String get buildStampLine {
  final short = buildCommit.length > 7 ? buildCommit.substring(0, 7) : buildCommit;
  return buildTime.isEmpty ? short : '$short · $buildTime';
}
