import 'package:dsh_companion_ios/core/models.dart';
import 'package:dsh_companion_ios/core/session_stats.dart';
import 'package:dsh_companion_ios/core/trajectory.dart';
import 'package:flutter_test/flutter_test.dart';

HistoryEntry entry(String type, int seq, {int time = 0, Object? data}) => HistoryEntry(
      event: SessionEvent(type: type, seq: seq, time: time, data: data),
    );

void main() {
  group('sessionStatsOf', () {
    test('按类型计数，lastSeq 取最大值（历史数组可能无序）', () {
      final history = ChatHistory(events: <HistoryEntry>[
        entry('user/message', 9),
        entry('assistant/message', 3),
        entry('tool/call', 7),
        entry('tool/call', 8),
        entry('step/end', 1),
      ]);
      final stats = sessionStatsOf(history);
      expect(stats.turns, 1);
      expect(stats.assistantMessages, 1);
      expect(stats.toolCalls, 2);
      expect(stats.events, 5);
      expect(stats.lastSeq, 9);
      expect(stats.isEmpty, isFalse);
    });

    test('null / 空历史返回空统计', () {
      expect(sessionStatsOf(null).isEmpty, isTrue);
      expect(sessionStatsOf(ChatHistory()).isEmpty, isTrue);
    });
  });

  group('trajectoryOf', () {
    test('按 turn 升序分组，组内按 seq 升序', () {
      final history = ChatHistory(events: <HistoryEntry>[
        entry('assistant/message', 5, data: <String, dynamic>{'turn': 2}),
        entry('user/message', 1, data: <String, dynamic>{'turn': 1}),
        entry('tool/call', 3, data: <String, dynamic>{'turn': 1, 'name': 'bash'}),
        entry('assistant/message', 2, data: <String, dynamic>{'turn': 1}),
      ]);
      final turns = trajectoryOf(history);
      expect(turns.map((TrajectoryTurn t) => t.turn), <int>[1, 2]);
      expect(turns.first.nodes.map((TrajectoryNode n) => n.seq), <int>[1, 2, 3]);
      expect(turns.first.nodes.last.label, 'bash');
    });

    test('取不到 turn 的归入 unknownTurn，不丢弃', () {
      final history = ChatHistory(events: <HistoryEntry>[entry('step/end', 4)]);
      final turns = trajectoryOf(history);
      expect(turns.single.turn, unknownTurn);
      expect(turns.single.nodes.single.eventType, 'step/end');
      expect(turns.single.nodes.single.kind, TrajectoryNodeKind.other);
    });

    test('null 历史返回空', () {
      expect(trajectoryOf(null), isEmpty);
    });

    test('轮次耗时：单调时给差值', () {
      final turn = TrajectoryTurn(1, <TrajectoryNode>[
        const TrajectoryNode(seq: 1, time: 1000, kind: TrajectoryNodeKind.user, eventType: 'user/message'),
        const TrajectoryNode(seq: 2, time: 3500, kind: TrajectoryNodeKind.assistant, eventType: 'assistant/message'),
      ]);
      expect(turn.durationMillis, 2500);
      expect(turn.startedAt, 1000);
      expect(turn.endedAt, 3500);
    });

    test('轮次耗时：时间倒退 / 跨度为 0 / 节点不足都给 null', () {
      final backward = TrajectoryTurn(1, <TrajectoryNode>[
        const TrajectoryNode(seq: 1, time: 2000, kind: TrajectoryNodeKind.user, eventType: 'user/message'),
        const TrajectoryNode(seq: 2, time: 1000, kind: TrajectoryNodeKind.user, eventType: 'user/message'),
      ]);
      expect(backward.durationMillis, isNull);

      final zero = TrajectoryTurn(1, <TrajectoryNode>[
        const TrajectoryNode(seq: 1, time: 1000, kind: TrajectoryNodeKind.user, eventType: 'user/message'),
        const TrajectoryNode(seq: 2, time: 1000, kind: TrajectoryNodeKind.user, eventType: 'user/message'),
      ]);
      expect(zero.durationMillis, isNull);

      expect(TrajectoryTurn(1, const <TrajectoryNode>[]).durationMillis, isNull);
    });

    test('工具计数', () {
      final turn = TrajectoryTurn(1, <TrajectoryNode>[
        const TrajectoryNode(seq: 1, time: 0, kind: TrajectoryNodeKind.tool, eventType: 'tool/call'),
        const TrajectoryNode(seq: 2, time: 0, kind: TrajectoryNodeKind.tool, eventType: 'tool/call'),
        const TrajectoryNode(seq: 3, time: 0, kind: TrajectoryNodeKind.user, eventType: 'user/message'),
      ]);
      expect(turn.toolCalls, 2);
    });
  });

  group('shortDuration', () {
    test('不足一分钟给秒（一位小数）', () {
      expect(shortDuration(12345), '12.3s');
      expect(shortDuration(9990), '9.9s');
      expect(shortDuration(999), '0.9s');
    });

    test('超过一分钟给 m:ss', () {
      expect(shortDuration(65000), '1:05');
      expect(shortDuration(600000), '10:00');
    });
  });
}
