/// 工具调用的取值、措辞与合并（从 `chat_presentation.dart` 拆出）。
///
/// 契约：合并是**显示**的合并，不是数据的合并 —— 每一条 `ToolCallDetail` 都必须留着。
library;

import 'chat_presentation_types.dart';
import 'json.dart';
import 'models.dart';
import 'text.dart';

// 工具：动作短语、结果、合并
// ---------------------------------------------------------------------------

class ToolResultInfo {
  const ToolResultInfo(this.text, this.failed, this.time, this.attachments);

  final String text;
  final bool failed;
  final int time;
  final List<ChatAttachment> attachments;
}

/// 工具动作短语，措辞与判定方式照官方 Web 界面还原。
const List<List<String>> innerActions = <List<String>>[
  <String>['tools.edit', '修改了文件'],
  <String>['tools.write', '已写入文件'],
  <String>['tools.read', '读取了文件'],
  <String>['tools.bash', '执行了命令'],
  <String>['tools.grep', '搜索了内容'],
  <String>['tools.glob', '搜索了文件'],
];

const Map<String, String> actionsByName = <String, String>{
  'bash': '执行了命令',
  'pwsh': '执行了命令',
  'read': '读取了文件',
  'write': '已写入文件',
  'edit': '修改了文件',
  'grep': '搜索了内容',
  'glob': '搜索了文件',
  'web_fetch': '已访问网页',
  'web_search': '已搜索网页',
};

List<String> toolActionsFor(String name, String? argumentsRaw) {
  final raw = argumentsRaw ?? '';
  if (name == 'run_code') {
    final out = <String>['运行了代码'];
    for (final entry in innerActions) {
      if (raw.contains(entry[0]) && !out.contains(entry[1])) {
        out.add(entry[1]);
      }
    }
    return out;
  }
  final byName = actionsByName[name];
  if (byName != null) {
    return <String>[byName];
  }
  if (name.startsWith('mcp__')) {
    return <String>['调用了 ${name.substring(5).split('__').join(' · ')}'];
  }
  return <String>[isNotBlank(name) ? name : '工具'];
}

const List<String> argumentSummaryKeys = <String>[
  'description',
  'path',
  'file_path',
  'query',
  'pattern',
  'url',
  'command',
  'name',
  'package',
];

String? argumentsSummary(String? raw) {
  if (raw == null || isBlank(raw)) {
    return null;
  }
  final parsed = parseMap(raw);
  if (parsed == null) {
    return null;
  }
  for (final key in argumentSummaryKeys) {
    final value = stringOrNull(parsed, key);
    if (value != null && isNotBlank(value)) {
      return firstLine(value);
    }
  }
  return null;
}

List<ChatAttachment> _resultAttachments(Map<String, dynamic> message) {
  final content = raw(message, 'content');
  if (content is! List) {
    return <ChatAttachment>[];
  }
  final out = <ChatAttachment>[];
  for (final item in content) {
    final part = asMap(item);
    if (part == null || stringOrNull(part, 'type') != 'image') {
      continue;
    }
    final attachment = obj(part, 'attachment');
    if (attachment == null) {
      continue;
    }
    final id = stringOrNull(attachment, 'attachmentId');
    if (id == null || isBlank(id)) {
      continue;
    }
    out.add(ChatAttachment(
      attachmentId: id,
      mediaType: stringOrNull(attachment, 'mediaType') ?? '',
      width: intOrNull(attachment, 'width') ?? 0,
      height: intOrNull(attachment, 'height') ?? 0,
      bytes: intOrNull(attachment, 'bytes') ?? 0,
      name: stringOrNull(attachment, 'name'),
    ));
  }
  return out;
}

/// 把 `tool/result` 按 callId 建索引：优先 `message.toolCallId`，退路 `message.source.callId`。
Map<String, ToolResultInfo> toolResultsByCallId(List<HistoryEntry> entries) {
  final out = <String, ToolResultInfo>{};
  for (final entry in entries) {
    final event = entry.event;
    if (event.type != 'tool/result') {
      continue;
    }
    final data = event.dataMap();
    if (data == null) {
      continue;
    }
    final message = obj(data, 'message');
    if (message == null) {
      continue;
    }
    var callId = stringOrNull(message, 'toolCallId');
    callId ??= stringOrNull(obj(message, 'source'), 'callId');
    if (callId == null) {
      continue;
    }
    out[callId] = ToolResultInfo(
      toolResultText(message),
      boolOrNull(message, 'isError') ?? false,
      event.time,
      _resultAttachments(message),
    );
  }
  return out;
}

String toolResultText(Map<String, dynamic> message) {
  final content = raw(message, 'content');
  if (content == null) {
    return '';
  }
  if (content is! List) {
    return stringOrNull(message, 'content') ?? '';
  }
  final text = <String>[];
  for (final item in content) {
    final part = asMap(item);
    if (part == null) {
      continue;
    }
    final type = stringOrNull(part, 'type');
    if (type == 'text') {
      final value = stringOrNull(part, 'text');
      if (value != null) {
        text.add(value);
      }
    } else if (type == 'image') {
      final attachment = obj(part, 'attachment');
      var name = stringOrNull(attachment, 'name');
      if (name == null || isBlank(name)) {
        name = 'attachment';
      }
      final width = intOrNull(attachment, 'width') ?? 0;
      final height = intOrNull(attachment, 'height') ?? 0;
      if (width > 0 && height > 0) {
        text.add('[image $name $width×$height]');
      } else {
        text.add('[image $name]');
      }
    }
  }
  return [for (final t in text) if (isNotBlank(t)) t].join('\n\n');
}

/// 耗时；结果早于调用（时钟倒退）返回 null —— 宁可少一行，也不要瞎编。
int? toolDurationMs(int callTime, int? resultTime) {
  if (resultTime == null) {
    return null;
  }
  final delta = resultTime - callTime;
  return delta < 0 ? null : delta;
}

String formatToolDuration(int ms) {
  if (ms < 1000) {
    return '$ms ms';
  }
  if (ms < 60000) {
    return '${oneDecimal(ms / 1000)} s';
  }
  if (ms < 3600000) {
    return '${ms ~/ 60000}m ${(ms % 60000) ~/ 1000}s';
  }
  return '${ms ~/ 3600000}h ${(ms % 3600000) ~/ 60000}m';
}

/// 一位小数（对应 Kotlin `"%.1f"`）。
String oneDecimal(num value) {
  final tenths = (value * 10).round();
  return '${tenths ~/ 10}.${tenths % 10}';
}

String prettyToolArguments(String raw) {
  if (isBlank(raw)) {
    return '';
  }
  final parsed = parseJson(raw);
  if (parsed == null) {
    return raw;
  }
  try {
    return const JsonPretty().format(parsed);
  } on Object {
    return raw;
  }
}

/// 4 空格缩进的 JSON 美化（与 kotlinx `prettyPrint` 同宽）。
class JsonPretty {
  const JsonPretty();

  String format(Object? value) => _encode(value, 0);

  String _encode(Object? value, int depth) {
    final pad = '    ' * depth;
    final innerPad = '    ' * (depth + 1);
    if (value is Map) {
      if (value.isEmpty) {
        return '{}';
      }
      final parts = <String>[];
      value.forEach((key, v) {
        parts.add('$innerPad${_quote('$key')}: ${_encode(v, depth + 1)}');
      });
      return '{\n${parts.join(',\n')}\n$pad}';
    }
    if (value is List) {
      if (value.isEmpty) {
        return '[]';
      }
      final parts = <String>[for (final v in value) '$innerPad${_encode(v, depth + 1)}'];
      return '[\n${parts.join(',\n')}\n$pad]';
    }
    if (value is String) {
      return _quote(value);
    }
    if (value == null) {
      return 'null';
    }
    return '$value';
  }

  String _quote(String value) {
    final buffer = StringBuffer('"');
    for (final rune in value.runes) {
      switch (rune) {
        case 0x22:
          buffer.write(r'\"');
        case 0x5C:
          buffer.write(r'\\');
        case 0x0A:
          buffer.write(r'\n');
        case 0x0D:
          buffer.write(r'\r');
        case 0x09:
          buffer.write(r'\t');
        default:
          if (rune < 0x20) {
            buffer.write('\\u${rune.toRadixString(16).padLeft(4, '0')}');
          } else {
            buffer.writeCharCode(rune);
          }
      }
    }
    buffer.write('"');
    return buffer.toString();
  }
}

ChatDisplayItem toolItem(HistoryEntry entry, Map<String, ToolResultInfo> results) {
  final event = entry.event;
  final data = event.dataMap();
  final name = stringOrNull(data, 'name');
  final view = obj(asMap(entry.view), 'view');
  final viewTitle = stringOrNull(view, 'title');
  final description = stringOrNull(view, 'description');
  final argumentsRaw = stringOrNull(data, 'arguments');
  final actions = toolActionsFor(name ?? '', argumentsRaw);
  final callId = stringOrNull(data, 'callId') ?? '';
  final result = results[callId];

  var body = description ?? '';
  if (description == null) {
    final summary = argumentsSummary(argumentsRaw);
    if (summary != null) {
      body = summary;
    } else if (viewTitle != null) {
      body = viewTitle;
    } else {
      body = name ?? '';
    }
  }

  final detail = ToolCallDetail(
    callId: callId,
    name: name ?? '',
    argumentsJson: argumentsRaw ?? '',
    result: result?.text,
    failed: result?.failed ?? false,
    durationMs: toolDurationMs(event.time, result?.time),
  );

  return ChatDisplayItem(
    id: '${event.seq}-tool',
    seq: event.seq,
    kind: ChatItemKind.tool,
    title: actions.join('，'),
    body: body,
    attachments: result?.attachments ?? const <ChatAttachment>[],
    actions: actions,
    tools: <ToolCallDetail>[detail],
    time: event.time,
  );
}

/// 把**连续**工具调用合并成一项；中间夹了正文就断开。
List<ChatDisplayItem> mergeToolRuns(List<ChatDisplayItem> items) {
  final out = <ChatDisplayItem>[];
  var run = <ChatDisplayItem>[];

  void flush() {
    if (run.isEmpty) {
      return;
    }
    if (run.length == 1) {
      out.add(run.first);
      run = <ChatDisplayItem>[];
      return;
    }
    final actions = <String>[];
    for (final item in run) {
      for (final action in item.actions) {
        if (!actions.contains(action)) {
          actions.add(action);
        }
      }
    }
    final String title;
    if (actions.isEmpty) {
      title = '${run.length} 次工具调用';
    } else if (actions.length > 4) {
      title = '${actions.take(4).join('，')}等';
    } else {
      title = actions.join('，');
    }
    out.add(run.first.withMerged(
      id: 'tools-${run.first.seq}-${run.last.seq}',
      title: title,
      body: [for (final item in run) item.body].join('\n'),
      actions: actions,
      tools: [for (final item in run) ...item.tools],
    ));
    run = <ChatDisplayItem>[];
  }

  for (final item in items) {
    // 带图片的工具结果不参与合并：合并只保留首条 attachments，会把后面的图丢掉。
    if (item.kind == ChatItemKind.tool && item.attachments.isEmpty) {
      run.add(item);
    } else {
      flush();
      out.add(item);
    }
  }
  flush();
  return out;
}
