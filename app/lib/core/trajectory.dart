/// 「轨迹」页数据 —— 移植自鸿蒙版 `core/Trajectory.ts`。
///
/// 会话流是**给人读的**（只留正文与摘要）；轨迹是**给人查的**：每一轮发生了什么、
/// 各花多久。所以这里**不做过滤**，认不得的事件留成 [TrajectoryNodeKind.other] 并保留类型原名 ——
/// 「这到底是什么」正是排查时要看的。
library;

import 'json.dart';
import 'models.dart';

enum TrajectoryNodeKind { user, assistant, tool, deliverable, turnEnd, other }

/// 时间轴上的一个节点。
class TrajectoryNode {
  const TrajectoryNode({
    required this.seq,
    required this.time,
    required this.kind,
    required this.eventType,
    this.label,
    this.raw,
  });

  final int seq;
  final int time;
  final TrajectoryNodeKind kind;

  /// 事件的**类型原名**（如 `step/end`）—— 认不得时原样显示，不写「其他」。
  final String eventType;
  final String? label;

  /// 原始 `data`，详情里原样展示。
  final Object? raw;
}

/// `turn` 取不到时的归属。用 0 而不是 -1：负数会在排序与展示上制造新特例。
const int unknownTurn = 0;

class TrajectoryTurn {
  TrajectoryTurn(this.turn, this.nodes);

  final int turn;
  final List<TrajectoryNode> nodes;

  List<TrajectoryNode> get ordered => <TrajectoryNode>[...nodes]
    ..sort((TrajectoryNode a, TrajectoryNode b) => a.seq - b.seq);

  int? get startedAt => ordered.isEmpty ? null : ordered.first.time;

  int? get endedAt => ordered.isEmpty ? null : ordered.last.time;

  /// 墙钟跨度；时间不单调、跨度为 0、节点不足两个时返回 null。
  ///
  /// 三种「不给值」都比显示一个数字诚实：乱序说明这份历史的 `time` 不可信；
  /// 零跨度会让人以为「瞬间完成」。
  int? get durationMillis {
    final seq = ordered;
    if (seq.length < 2) {
      return null;
    }
    var previous = seq.first.time;
    for (var i = 1; i < seq.length; i++) {
      if (seq[i].time < previous) {
        return null;
      }
      previous = seq[i].time;
    }
    final start = seq.first.time;
    final end = seq.last.time;
    return end > start ? end - start : null;
  }

  int get toolCalls => nodes.where((TrajectoryNode n) => n.kind == TrajectoryNodeKind.tool).length;
}

/// 把历史折成轨迹：轮次升序、组内按 seq 升序；取不到 turn 的归入 [unknownTurn]（不丢弃）。
List<TrajectoryTurn> trajectoryOf(ChatHistory? history) {
  if (history == null || history.events.isEmpty) {
    return const <TrajectoryTurn>[];
  }
  final grouped = <int, List<TrajectoryNode>>{};
  for (final entry in history.events) {
    final event = entry.event;
    final data = event.dataMap();
    final turn = intOrNull(data, 'turn') ?? unknownTurn;
    grouped.putIfAbsent(turn, () => <TrajectoryNode>[]).add(TrajectoryNode(
      seq: event.seq,
      time: event.time,
      kind: _kindOf(event.type),
      eventType: event.type,
      label: _toolLabelOf(event.type, data),
      raw: event.data,
    ));
  }
  final turns = grouped.keys.toList()..sort();
  return <TrajectoryTurn>[
    for (final turn in turns)
      TrajectoryTurn(
        turn,
        grouped[turn]!.toList()..sort((TrajectoryNode a, TrajectoryNode b) => a.seq - b.seq),
      ),
  ];
}

/// 短耗时：不足一分钟给 `12.3s`，否则 `3:05`。
String shortDuration(int millis) {
  if (millis < 60000) {
    final tenths = millis ~/ 100;
    return '${tenths ~/ 10}.${tenths % 10}s';
  }
  final totalSeconds = millis ~/ 1000;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds < 10 ? '0$seconds' : '$seconds'}';
}

TrajectoryNodeKind _kindOf(String type) {
  switch (type) {
    case 'user/message':
      return TrajectoryNodeKind.user;
    case 'assistant/message':
      return TrajectoryNodeKind.assistant;
    case 'tool/call':
      return TrajectoryNodeKind.tool;
    case 'deliverables/presented':
      return TrajectoryNodeKind.deliverable;
    case 'turn/end':
      return TrajectoryNodeKind.turnEnd;
    default:
      return TrajectoryNodeKind.other;
  }
}

/// 工具标签取 `data.name`；取不到返回 null（UI 用类型名兜底），**不猜**别的字段名。
String? _toolLabelOf(String type, Map<String, dynamic>? data) {
  if (type != 'tool/call') {
    return null;
  }
  final name = stringOrNull(data, 'name');
  return name == null || name.trim().isEmpty ? null : name;
}
