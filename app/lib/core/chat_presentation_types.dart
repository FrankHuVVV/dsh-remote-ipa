/// 聊天呈现模型的**数据形状**（从 `chat_presentation.dart` 拆出，拆法对齐鸿蒙版）。
///
/// 只装类型与常量，不含任何解析逻辑 —— 这样 UI 可以只 import 形状而不拖入工具解析。
library;

/// 实时行的 seq 占位：保证它们排在历史之后。
const int liveSeq = 2147483647;

/// 交接说明里给机器读的那一行的标记。
const String handoffSourceMarker = '[Image: source: ';

/// 交接说明里给人看的那一行的开头。
const String handoffPreambleMarker = '🖼️ 图片 ';

/// 交接附件的 id 前缀。
const String handoffAttachmentPrefix = 'handoff:';

enum ChatItemKind { user, assistant, reasoning, context, tool, failure }

/// 一轮模型运行的**终局失败**。
class ChatTurnFailure {
  ChatTurnFailure({this.message = '', this.code, this.stopped = false});

  final String message;

  /// null = 服务端没给 code；空串 = 给了但为空（必须原样显示）。
  final String? code;
  final bool stopped;

  /// 给人看的标题用 key 表达，具体语言交给界面。
  String get titleKey => stopped ? 'turn_stopped_title' : 'turn_failed_title';
}

/// 会话历史里的一个图片附件（只有引用，没有字节）。
class ChatAttachment {
  ChatAttachment({
    this.attachmentId = '',
    this.mediaType = '',
    this.width = 0,
    this.height = 0,
    this.bytes = 0,
    this.name,
    this.handoffPath,
  });

  final String attachmentId;
  final String mediaType;
  final int width;
  final int height;
  final int bytes;
  final String? name;

  /// 纯文本模型发图时落到工作区的**绝对路径**（非交接图为 null）。
  final String? handoffPath;
}

/// 一次工具调用的完整明细。
class ToolCallDetail {
  ToolCallDetail({
    this.callId = '',
    this.name = '',
    this.argumentsJson = '',
    this.result,
    this.failed = false,
    this.durationMs,
  });

  final String callId;
  final String name;
  final String argumentsJson;

  /// null = 还没有 `tool/result`；空串是合法的「有结果但没文字」。
  final String? result;
  final bool failed;
  final int? durationMs;
}

class ChatDisplayItem {
  ChatDisplayItem({
    required this.id,
    required this.seq,
    required this.kind,
    this.title,
    this.body = '',
    this.streaming = false,
    this.attachments = const <ChatAttachment>[],
    this.actions = const <String>[],
    this.tools = const <ToolCallDetail>[],
    this.failure,
    this.time = 0,
  });

  final String id;
  final int seq;
  final ChatItemKind kind;
  final String? title;
  final String body;
  final bool streaming;
  final List<ChatAttachment> attachments;
  final List<String> actions;
  final List<ToolCallDetail> tools;
  final ChatTurnFailure? failure;

  /// 服务端事件帧的时间（毫秒）。**0 表示没有时间**，界面不显示时间戳。
  final int time;

  ChatDisplayItem withMerged({
    required String id,
    required String title,
    required String body,
    required List<String> actions,
    required List<ToolCallDetail> tools,
  }) =>
      ChatDisplayItem(
        id: id,
        seq: seq,
        kind: kind,
        title: title,
        body: body,
        streaming: streaming,
        attachments: attachments,
        actions: actions,
        tools: tools,
        failure: failure,
        time: time,
      );
}

class ChatDelta {
  const ChatDelta(this.sessionId, this.turn, this.step, this.index, this.kind, this.text);

  final String sessionId;
  final int turn;
  final int step;
  final int index;
  final ChatItemKind kind;
  final String text;
}

class LiveChatBlock {
  const LiveChatBlock(this.index, this.kind, this.text);

  final int index;
  final ChatItemKind kind;
  final String text;
}

/// 流式状态：**只装当前这一段（turn+step）**。
class LiveChatState {
  LiveChatState({
    required this.sessionId,
    required this.turn,
    required this.step,
    this.blocks = const <LiveChatBlock>[],
    this.revision = 0,
  });

  final String sessionId;
  final int turn;
  final int step;
  final List<LiveChatBlock> blocks;
  final int revision;

  LiveChatState append(ChatDelta delta) {
    final sameScope =
        sessionId == delta.sessionId && turn == delta.turn && step == delta.step;
    final base = sameScope
        ? this
        : LiveChatState(sessionId: delta.sessionId, turn: delta.turn, step: delta.step);

    final next = <LiveChatBlock>[];
    var existing = -1;
    for (var i = 0; i < base.blocks.length; i++) {
      if (base.blocks[i].index == delta.index) {
        existing = i;
        break;
      }
    }
    if (existing < 0) {
      next.addAll(base.blocks);
      next.add(LiveChatBlock(delta.index, delta.kind, delta.text));
    } else {
      for (var i = 0; i < base.blocks.length; i++) {
        final previous = base.blocks[i];
        if (i != existing) {
          next.add(previous);
          continue;
        }
        // 同一 index 但 kind 变了：整段换掉，不拼接。
        final text = previous.kind == delta.kind ? previous.text + delta.text : delta.text;
        next.add(LiveChatBlock(delta.index, delta.kind, text));
      }
    }
    next.sort((a, b) => a.index - b.index);
    return LiveChatState(
      sessionId: base.sessionId,
      turn: base.turn,
      step: base.step,
      blocks: next,
      revision: base.revision + 1,
    );
  }

  List<ChatDisplayItem> displayItems() {
    final out = <ChatDisplayItem>[];
    for (final block in blocks) {
      // 只含空白的增量也算「有内容」，照旧显示（判据是 isEmpty，不是 isBlank）。
      if (block.text.isEmpty) {
        continue;
      }
      out.add(ChatDisplayItem(
        id: 'live-$turn-$step-${block.index}-${block.kind.name}',
        seq: liveSeq,
        kind: block.kind,
        body: block.text,
        streaming: true,
      ));
    }
    return out;
  }
}

/// agent 显式交付给用户的一个文件（`deliverables/presented`）。
class ChatDeliverable {
  const ChatDeliverable(this.path, this.description, this.seq);

  final String path;
  final String? description;
  final int seq;
}

// ---------------------------------------------------------------------------
