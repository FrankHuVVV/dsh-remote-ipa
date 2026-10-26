/// 聊天页呈现模型 —— 移植自鸿蒙版 `core/ChatPresentation*.ts`。
///
/// 这是「服务端事件 → 界面能看到的一行行东西」之间唯一的接缝：聊天页不直接读事件，
/// 只读这里吐出来的 ChatDisplayItem。
///
/// 三条取向：
/// 1. **只认能读懂的**：`step/end`、`turn/start` 这类生命周期事件一律不渲染；
/// 2. **不猜**：参数解析失败就原样给原始文本，工具结果配不上 callId 就整条不显示；
/// 3. **分清「空串」与「没有」**：失败行的 `code` 空串是合法值（免费额度限流的 code 就是 `""`）。
///
/// 本文件按鸿蒙版的拆法分成三份：类型（`chat_presentation_types.dart`）、
/// 工具取值与合并（`chat_tools.dart`）、事件解析与条目构造（本文件）。
/// 对外仍然只 `import 'chat_presentation.dart'` —— 下面两个 export 把名字原样转出去。
library;

import 'chat_presentation_types.dart';
import 'chat_tools.dart';
import 'json.dart';
import 'models.dart';
import 'text.dart';

export 'chat_presentation_types.dart';
export 'chat_tools.dart';

// 事件 → 显示项
// ---------------------------------------------------------------------------

/// 从 `chat.message.delta` 取出增量；五个必填字段缺一个就返回 null，绝不填默认值。
ChatDelta? chatDelta(WorkspaceEvent event) {
  if (event.type != 'chat.message.delta') {
    return null;
  }
  final value = event.dataMap();
  if (value == null) {
    return null;
  }
  final kindText = stringOrNull(value, 'kind');
  final ChatItemKind kind;
  if (kindText == 'text') {
    kind = ChatItemKind.assistant;
  } else if (kindText == 'reasoning') {
    kind = ChatItemKind.reasoning;
  } else {
    return null;
  }
  final sessionId = stringOrNull(value, 'sessionId');
  final turn = intOrNull(value, 'turn');
  final step = intOrNull(value, 'step');
  final index = intOrNull(value, 'index');
  final text = stringOrNull(value, 'text');
  if (sessionId == null || turn == null || step == null || index == null || text == null) {
    return null;
  }
  return ChatDelta(sessionId, turn, step, index, kind, text);
}

/// 从 `chat.turn.failed` 取出失败详情。
ChatTurnFailure? chatTurnFailure(WorkspaceEvent event) {
  if (event.type != 'chat.turn.failed') {
    return null;
  }
  final value = event.dataMap();
  if (value == null) {
    return null;
  }
  final failure = obj(value, 'failure');
  if (failure == null) {
    return null;
  }
  return ChatTurnFailure(
    message: stringOrNull(failure, 'message') ?? '',
    // 空串 code 要留空串，不能退回 null。
    code: stringOrNull(failure, 'code'),
    stopped: boolOrNull(failure, 'stopped') ?? false,
  );
}

/// 历史 → 显示项（含相邻工具调用合并）。
List<ChatDisplayItem> displayItemsOf(ChatHistory history) {
  final results = toolResultsByCallId(history.events);
  final items = <ChatDisplayItem>[];
  for (final entry in history.events) {
    items.addAll(oneEntryItems(entry, results));
  }
  return mergeToolRuns(items);
}

List<TodoItem> todoItemsOf(ChatHistory history) {
  final projections = asMap(history.projections);
  final values = obj(projections, 'values');
  if (values == null) {
    return const <TodoItem>[];
  }
  final out = <TodoItem>[];
  for (final item in arr(values, 'todos')) {
    final map = asMap(item);
    if (map == null) {
      continue;
    }
    final content = stringOrNull(map, 'content');
    if (content == null || isBlank(content)) {
      continue;
    }
    if (stringOrNull(map, 'status') == null) {
      continue;
    }
    out.add(TodoItem.fromJson(map));
  }
  return out;
}

PermissionSelect? permissionSelectOf(ChatHistory history) {
  final projections = asMap(history.projections);
  final values = obj(projections, 'values');
  if (values == null) {
    return null;
  }
  final raw = obj(values, 'permissions');
  if (raw == null) {
    return null;
  }
  final currentValue = stringOrNull(raw, 'currentValue');
  if (currentValue == null) {
    return null;
  }
  final options = <PermissionOption>[];
  for (final item in arr(raw, 'options')) {
    final option = asMap(item);
    if (option == null) {
      continue;
    }
    final value = stringOrNull(option, 'value');
    final name = stringOrNull(option, 'name');
    if (value == null || name == null) {
      continue;
    }
    options.add(PermissionOption(
      value: value,
      name: name,
      description: stringOrNull(option, 'description'),
    ));
  }
  return PermissionSelect(options: options, currentValue: currentValue);
}

/// 会话里被显式交付的文件；同一路径保留**最后一次**的说明。
List<ChatDeliverable> deliverablesOf(ChatHistory history) {
  final out = <String, ChatDeliverable>{};
  for (final entry in history.events) {
    final event = entry.event;
    if (event.type != 'deliverables/presented') {
      continue;
    }
    final data = event.dataMap();
    if (data == null) {
      continue;
    }
    for (final item in arr(data, 'files')) {
      final file = asMap(item);
      if (file == null) {
        continue;
      }
      final path = stringOrNull(file, 'path');
      if (path == null || isBlank(path)) {
        continue;
      }
      out[path] = ChatDeliverable(path, stringOrNull(file, 'description'), event.seq);
    }
  }
  return out.values.toList();
}

/// 从附件 id 里解出交接路径；不是交接附件返回 null。
String? handoffPathOf(String attachmentId) {
  if (!attachmentId.startsWith(handoffAttachmentPrefix)) {
    return null;
  }
  final path = attachmentId.substring(handoffAttachmentPrefix.length);
  return isNotBlank(path) ? path : null;
}

// ---------------------------------------------------------------------------
// 条目构造
// ---------------------------------------------------------------------------

List<ChatDisplayItem> oneEntryItems(HistoryEntry entry, Map<String, ToolResultInfo> results) {
  switch (entry.event.type) {
    case 'user/message':
      return userItems(entry.event);
    case 'assistant/message':
      return assistantItems(entry.event);
    case 'tool/call':
      return <ChatDisplayItem>[toolItem(entry, results)];
    case 'turn/end':
      final item = turnEndItem(entry.event);
      return item == null ? const <ChatDisplayItem>[] : <ChatDisplayItem>[item];
    default:
      return const <ChatDisplayItem>[];
  }
}

/// 历史里的 `turn/end` 帧 → 失败行；不是失败整条不渲染。
ChatDisplayItem? turnEndItem(SessionEvent event) {
  final data = event.dataMap();
  if (data == null) {
    return null;
  }
  final reason = obj(data, 'reason');
  if (reason == null) {
    return null;
  }
  ChatTurnFailure? failure;
  final kind = stringOrNull(reason, 'kind');
  if (kind == 'error') {
    final errorObj = obj(reason, 'error');
    var message = stringOrNull(errorObj, 'message');
    message ??= stringOrNull(reason, 'error');
    failure = ChatTurnFailure(message: message ?? '', code: stringOrNull(errorObj, 'code'));
  } else if (kind == 'aborted') {
    final inner = obj(reason, 'reason');
    if (stringOrNull(inner, 'kind') == 'hook' &&
        stringOrNull(inner, 'reason') == 'deepseek-account/signed-out') {
      failure = ChatTurnFailure(code: 'ACCOUNT_SIGNED_OUT', stopped: true);
    }
  }
  if (failure == null) {
    return null;
  }
  final code = failure.code;
  if (isBlank(failure.message) && (code == null || code.isEmpty)) {
    return null;
  }
  return ChatDisplayItem(
    id: '${event.seq}-turn-failure',
    seq: event.seq,
    kind: ChatItemKind.failure,
    failure: failure,
    time: event.time,
  );
}

List<ChatDisplayItem> userItems(SessionEvent event) {
  final data = event.dataMap();
  if (data == null) {
    return const <ChatDisplayItem>[];
  }
  final source = obj(data, 'source');
  final kind = stringOrNull(source, 'kind');
  final isUser = kind == 'user';
  final parts = contentTextParts(raw(data, 'content'));

  final handoffPaths = <String>[];
  if (isUser) {
    for (final part in parts) {
      for (final path in handoffPathsIn(part)) {
        if (!handoffPaths.contains(path)) {
          handoffPaths.add(path);
        }
      }
    }
  }

  final String body;
  if (isUser) {
    // 按**行**摘而不是整条 part 摘：万一说明和用户正文同处一条 part，
    // 整条摘掉会把用户自己打的话一起吞了。
    body = [
      for (final part in parts)
        if (isNotBlank(stripHandoffLines(part))) stripHandoffLines(part),
    ].join('\n\n');
  } else {
    body = contentText(raw(data, 'content'));
  }

  final attachments = contentAttachments(raw(data, 'content'));
  for (final path in handoffPaths) {
    attachments.add(handoffAttachment(path));
  }

  if (isUser) {
    // 判据是「有文字**或**有附件」：只发图不打字的消息不能消失。
    if (isBlank(body) && attachments.isEmpty) {
      return const <ChatDisplayItem>[];
    }
    return <ChatDisplayItem>[
      ChatDisplayItem(
        id: '${event.seq}-user',
        seq: event.seq,
        kind: ChatItemKind.user,
        body: body,
        attachments: attachments,
        time: event.time,
      ),
    ];
  }
  return <ChatDisplayItem>[
    ChatDisplayItem(
      id: '${event.seq}-context',
      seq: event.seq,
      kind: ChatItemKind.context,
      title: contextLabel(source),
      body: body,
      attachments: attachments,
      time: event.time,
    ),
  ];
}

List<ChatAttachment> contentAttachments(Object? content) {
  if (content is! List) {
    return <ChatAttachment>[];
  }
  final out = <ChatAttachment>[];
  for (final item in content) {
    final value = asMap(item);
    if (value == null || stringOrNull(value, 'type') != 'image') {
      continue;
    }
    final attachment = obj(value, 'attachment');
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

String stripHandoffLines(String part) {
  final kept = <String>[];
  for (final line in kotlinLines(part)) {
    if (line.contains(handoffSourceMarker) || trimStartWs(line).startsWith(handoffPreambleMarker)) {
      continue;
    }
    kept.add(line);
  }
  return trimText(kept.join('\n'));
}

List<String> handoffPathsIn(String part) {
  final out = <String>[];
  final pattern = RegExp(r'\[Image: source:\s*(.+)]');
  for (final match in pattern.allMatches(part)) {
    final path = trimText(match.group(1) ?? '');
    if (isNotBlank(path)) {
      out.add(path);
    }
  }
  return out;
}

ChatAttachment handoffAttachment(String path) {
  var name = afterLast(path, '/');
  if (isBlank(name)) {
    name = path;
  }
  return ChatAttachment(
    attachmentId: handoffAttachmentPrefix + path,
    mediaType: handoffMediaType(name),
    name: name,
    handoffPath: path,
  );
}

String handoffMediaType(String name) {
  final ext = afterLastOrEmpty(name, '.').toLowerCase();
  switch (ext) {
    case 'png':
      return 'image/png';
    case 'jpg':
    case 'jpeg':
      return 'image/jpeg';
    case 'webp':
      return 'image/webp';
    case 'gif':
      return 'image/gif';
    case 'bmp':
      return 'image/bmp';
    case 'heic':
      return 'image/heic';
    case 'heif':
      return 'image/heif';
    case 'avif':
      return 'image/avif';
    default:
      return '';
  }
}

List<ChatDisplayItem> assistantItems(SessionEvent event) {
  final outer = event.dataMap();
  if (outer == null) {
    return const <ChatDisplayItem>[];
  }
  final message = obj(outer, 'message');
  final scope = message ?? outer;
  final content = raw(scope, 'content');

  if (content is! List) {
    final text = contentText(content);
    if (isNotBlank(text)) {
      return <ChatDisplayItem>[
        ChatDisplayItem(
          id: '${event.seq}-assistant',
          seq: event.seq,
          kind: ChatItemKind.assistant,
          body: text,
          time: event.time,
        ),
      ];
    }
    return const <ChatDisplayItem>[];
  }

  final result = <ChatDisplayItem>[];
  final prose = <String>[];
  // 图片与交接说明可能夹在正文块之间；先攒着，flush 时挂到「前一发起」上，
  // 这样图片会出现在它本该出现的位置，而不是全堆到消息末尾。
  final pending = <ChatAttachment>[];

  void flush() {
    if (prose.isEmpty && pending.isEmpty) {
      return;
    }
    result.add(ChatDisplayItem(
      id: '${event.seq}-assistant-${result.length}',
      seq: event.seq,
      kind: ChatItemKind.assistant,
      body: prose.join('\n\n'),
      attachments: <ChatAttachment>[...pending],
      time: event.time,
    ));
    prose.clear();
    pending.clear();
  }

  for (final item in content) {
    final value = asMap(item);
    if (value == null) {
      continue;
    }
    final type = stringOrNull(value, 'type');
    if (type == 'text') {
      final text = stringOrNull(value, 'text');
      if (text == null) {
        continue;
      }
      // 交接说明（纯文本模型把图落到工作区）也会出现在助手正文里：
      // 把标记行摘掉，路径变成可显示的附件（与用户消息同一套口径）。
      for (final path in handoffPathsIn(text)) {
        pending.add(handoffAttachment(path));
      }
      final stripped = stripHandoffLines(text);
      if (isNotBlank(stripped)) {
        prose.add(stripped);
      }
    } else if (type == 'reasoning') {
      flush();
      final reasoning = stringOrNull(value, 'text');
      if (reasoning != null && isNotBlank(reasoning)) {
        result.add(ChatDisplayItem(
          id: '${event.seq}-reasoning-${result.length}',
          seq: event.seq,
          kind: ChatItemKind.reasoning,
          body: reasoning,
          time: event.time,
        ));
      }
    } else if (type == 'image') {
      // 助手消息里的图片块：历史里是 {type:image, attachment:{attachmentId,...}}。
      // 以前这里不认 image，于是「模型回复的图」在 iOS 上整类消失。
      flush();
      final images = contentAttachments(<Object?>[value]);
      if (images.isNotEmpty) {
        result.add(ChatDisplayItem(
          id: '${event.seq}-assistant-image-${result.length}',
          seq: event.seq,
          kind: ChatItemKind.assistant,
          body: '',
          attachments: images,
          time: event.time,
        ));
      }
    }
  }
  flush();
  return result;
}

// ---------------------------------------------------------------------------
String contentText(Object? content) {
  final parts = contentTextParts(content);
  return [for (final part in parts) if (isNotBlank(part)) part].join('\n\n');
}

List<String> contentTextParts(Object? content) {
  if (content == null) {
    return const <String>[];
  }
  if (content is String) {
    return <String>[content];
  }
  if (content is num) {
    return <String>['$content'];
  }
  if (content is bool) {
    return <String>[content ? 'true' : 'false'];
  }
  if (content is! List) {
    return const <String>[];
  }
  final out = <String>[];
  for (final item in content) {
    final value = asMap(item);
    if (value == null) {
      continue;
    }
    final type = stringOrNull(value, 'type');
    if (type == 'text' || type == 'reasoning') {
      final text = stringOrNull(value, 'text');
      if (text != null) {
        out.add(text);
      }
    }
  }
  return out;
}

String? contextLabel(Map<String, dynamic>? source) {
  if (source == null) {
    return null;
  }
  final kind = stringOrNull(source, 'kind');
  if (kind == 'agent-instructions') {
    final labels = _arrayLabels(source, 'changes', 'path');
    return labels.isEmpty ? null : labels;
  }
  if (kind == 'session-reference') {
    final labels = _arrayLabels(source, 'references', 'label');
    return labels.isEmpty ? null : labels;
  }
  if (kind == 'plugin') {
    return stringOrNull(source, 'plugin') ?? kind;
  }
  if (kind == 'skill-invocation') {
    return stringOrNull(source, 'name') ?? kind;
  }
  return kind;
}

String _arrayLabels(Map<String, dynamic> source, String arrayKey, String labelKey) {
  final labels = <String>[];
  for (final item in arr(source, arrayKey)) {
    final map = asMap(item);
    if (map == null) {
      continue;
    }
    final label = stringOrNull(map, labelKey);
    if (label != null && isNotBlank(label)) {
      labels.add(label);
    }
  }
  return labels.join('、');
}
