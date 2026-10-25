/// 会话执行统计 —— 移植自鸿蒙版 `core/SessionStats.ts`。
///
/// 只做**能证明**的那部分：轮次 / 助手消息 / 工具调用 / 事件数 / 最新序号。
/// **刻意不做 Token 用量与上下文占用**：服务端契约里不可证，按字符数估算会把「不知道」
/// 伪装成「知道」，而用户会拿它做决策 —— 一个不可靠的数字比没有数字更坏。
library;

import 'models.dart';

class SessionStats {
  const SessionStats({
    this.turns = 0,
    this.assistantMessages = 0,
    this.toolCalls = 0,
    this.events = 0,
    this.lastSeq,
  });

  final int turns;
  final int assistantMessages;
  final int toolCalls;
  final int events;
  final int? lastSeq;

  bool get isEmpty => events == 0;
}

/// 与渲染同源的三个事件类型名。
const String statsEventUser = 'user/message';
const String statsEventAssistant = 'assistant/message';
const String statsEventTool = 'tool/call';

/// 从历史里数出执行统计。`history == null` 返回空统计（面板显示「暂无数据」）。
SessionStats sessionStatsOf(ChatHistory? history) {
  if (history == null || history.events.isEmpty) {
    return const SessionStats();
  }
  var turns = 0;
  var assistants = 0;
  var tools = 0;
  // seq 取**最大**而不是最后一条：历史数组不保证有序（翻页合并后尤其）。
  var maxSeq = history.events.first.event.seq;
  for (final entry in history.events) {
    switch (entry.event.type) {
      case statsEventUser:
        turns++;
      case statsEventAssistant:
        assistants++;
      case statsEventTool:
        tools++;
    }
    if (entry.event.seq > maxSeq) {
      maxSeq = entry.event.seq;
    }
  }
  return SessionStats(
    turns: turns,
    assistantMessages: assistants,
    toolCalls: tools,
    events: history.events.length,
    lastSeq: maxSeq,
  );
}
