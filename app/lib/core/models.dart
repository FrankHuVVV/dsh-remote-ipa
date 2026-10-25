/// 线上模型索引（barrel）—— 外部只 `import 'models.dart'`。
///
/// 类按领域拆到下面几个文件里；这里按原样再导出一次。
///
/// | 文件 | 装什么 |
/// | --- | --- |
/// | `models_wire.dart` | 健康检查 / 根 / 设备 / 配对 / 请求体拼装 / API 异常 |
/// | `models_files.dart` | 文件与目录 |
/// | `models_chat.dart` | 会话、审批、问答、命令、待办、权限选择 |
/// | `models_config.dart` | 模型选择、供应商设置、插件清单 |
/// | `models_events.dart` | 消息内容、附件、会话事件与历史、工作区事件 |
library;

export 'models_chat.dart';
export 'models_config.dart';
export 'models_events.dart';
export 'models_files.dart';
export 'models_wire.dart';
