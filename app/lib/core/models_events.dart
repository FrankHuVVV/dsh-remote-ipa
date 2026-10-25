/// 线上模型 —— **事件域**：消息内容（联合）、附件、会话事件与历史、工作区事件。
library;

import 'json.dart';

/// 一条 prompt 内容 —— DSH 内核的 `PromptContentPart` 联合类型。
///
/// 三种形态：`text` / `image`（base64 内联）/ `file`（先上传换 `receiptId`）。
/// 判别器是 `type`，编码时**只写该形态的字段**。
class PromptPart {
  PromptPart._(this.type);

  factory PromptPart.text(String text) => PromptPart._(partTypeText)..text = text;

  factory PromptPart.image(String mediaType, String data, {String? name}) =>
      PromptPart._(partTypeImage)
        ..mediaType = mediaType
        ..data = data
        ..name = name;

  factory PromptPart.file(String receiptId) => PromptPart._(partTypeFile)..receiptId = receiptId;

  String type;
  String text = '';
  String mediaType = 'image/png';
  String data = '';
  String? name;
  String receiptId = '';

  Map<String, dynamic> toMap() {
    switch (type) {
      case partTypeImage:
        return <String, dynamic>{
          'type': partTypeImage,
          'mediaType': mediaType,
          'data': data,
          if (name != null) 'name': name,
        };
      case partTypeFile:
        return <String, dynamic>{'type': partTypeFile, 'receiptId': receiptId};
      default:
        return <String, dynamic>{'type': partTypeText, 'text': text};
    }
  }

  factory PromptPart.fromJson(Object? map) {
    final t = stringOrNull(map, 'type');
    if (t == partTypeImage) {
      return PromptPart.image(
        stringOrNull(map, 'mediaType') ?? 'image/png',
        stringOrNull(map, 'data') ?? '',
        name: stringOrNull(map, 'name'),
      );
    }
    if (t == partTypeFile) {
      return PromptPart.file(stringOrNull(map, 'receiptId') ?? '');
    }
    return PromptPart.text(stringOrNull(map, 'text') ?? '');
  }
}

const String partTypeText = 'text';
const String partTypeImage = 'image';
const String partTypeFile = 'file';

class UploadedAttachment {
  UploadedAttachment({this.receiptId = '', this.name = ''});

  String receiptId;
  String name;

  factory UploadedAttachment.fromJson(Object? map) => UploadedAttachment(
        receiptId: stringOrNull(map, 'receiptId') ?? '',
        name: stringOrNull(map, 'name') ?? '',
      );
}

/// 会话事件（历史里的一条）。
class SessionEvent {
  SessionEvent({
    this.type = '',
    this.seq = 0,
    this.time = 0,
    this.data,
    this.sourceEventSeqs = const <int>[],
    this.surfaceOp,
  });

  String type;
  int seq;
  int time;
  Object? data;
  List<int> sourceEventSeqs;
  Object? surfaceOp;

  Map<String, dynamic>? dataMap() => asMap(data);

  factory SessionEvent.fromJson(Object? map) => SessionEvent(
        type: stringOrNull(map, 'type') ?? '',
        seq: intOrNull(map, 'seq') ?? 0,
        time: intOrNull(map, 'time') ?? 0,
        data: raw(map, 'data'),
        sourceEventSeqs: [
          for (final n in arr(map, 'sourceEventSeqs'))
            if (n is int) n,
        ],
        surfaceOp: raw(map, 'surfaceOp'),
      );
}

class HistoryEntry {
  HistoryEntry({SessionEvent? event, this.view}) : event = event ?? SessionEvent();

  SessionEvent event;
  Object? view;

  factory HistoryEntry.fromJson(Object? map) => HistoryEntry(
        event: SessionEvent.fromJson(obj(map, 'event')),
        view: raw(map, 'view'),
      );
}

class ChatHistory {
  ChatHistory({this.events = const <HistoryEntry>[], this.hasMore = false, this.projections});

  List<HistoryEntry> events;
  bool hasMore;
  Object? projections;

  factory ChatHistory.fromJson(Object? map) => ChatHistory(
        events: [for (final e in objArr(map, 'events')) HistoryEntry.fromJson(e)],
        hasMore: boolOrNull(map, 'hasMore') ?? false,
        projections: raw(map, 'projections'),
      );
}

/// WebSocket `events` 推送的一帧。
class WorkspaceEvent {
  WorkspaceEvent({this.id = '', this.type = '', this.time = 0, this.data});

  String id;
  String type;
  int time;
  Object? data;

  Map<String, dynamic>? dataMap() => asMap(data);

  factory WorkspaceEvent.fromJson(Object? map) => WorkspaceEvent(
        id: stringOrNull(map, 'id') ?? '',
        type: stringOrNull(map, 'type') ?? '',
        time: intOrNull(map, 'time') ?? 0,
        data: raw(map, 'data'),
      );

  static WorkspaceEvent? fromJsonText(String text) {
    final map = parseMap(text);
    return map == null ? null : WorkspaceEvent.fromJson(map);
  }
}

/// 事件载荷里的字符串字段：字符串原样、数字 / 布尔转文本，其余 null。
String? eventDataString(WorkspaceEvent event, String key) {
  final value = raw(event.dataMap(), key);
  if (value is String) {
    return value;
  }
  if (value is num) {
    return '$value';
  }
  if (value is bool) {
    return value ? 'true' : 'false';
  }
  return null;
}

/// 事件载荷里的整数字段：数字型只认整数；字符串型严格十进制解析（`"3"` → 3）。
int? eventDataInt(WorkspaceEvent event, String key) {
  final value = raw(event.dataMap(), key);
  if (value is int) {
    return value;
  }
  if (value is double) {
    return value.isFinite && value == value.truncateToDouble() ? value.toInt() : null;
  }
  if (value is String) {
    return parseStrictInt(value);
  }
  return null;
}

/// 严格十进制解析（不接受空白、小数点、进制前缀），失败返回 null。
int? parseStrictInt(String raw) {
  if (raw.isEmpty) {
    return null;
  }
  var index = 0;
  var negative = false;
  final first = raw.codeUnitAt(0);
  if (first == 0x2D || first == 0x2B) {
    negative = first == 0x2D;
    index = 1;
  }
  if (index >= raw.length) {
    return null;
  }
  var acc = 0;
  while (index < raw.length) {
    final code = raw.codeUnitAt(index);
    if (code < 0x30 || code > 0x39) {
      return null;
    }
    acc = acc * 10 + (code - 0x30);
    index++;
  }
  return negative ? -acc : acc;
}
