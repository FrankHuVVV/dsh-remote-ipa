/// 会话洞察：待办 / 交付物 / 执行统计 / 执行轨迹。
///
/// 这四块都从**已有历史**里算，不需要服务端额外配合：
/// - 待办来自 `projections.values.todos`；
/// - 交付物来自 `deliverables/presented`；
/// - 统计来自事件计数；
/// - 轨迹按 `turn` 分组、组内按 `seq` 排序，认不得的事件保留类型原名。
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/session_stats.dart';
import '../core/small_parts.dart';
import '../core/trajectory.dart';
import '../l10n/strings.dart';
import '../state/harness_state.dart';
import 'widgets.dart';

/// 底部面板：待办 + 交付物 + 两个入口。
class SessionInsightsSheet extends StatelessWidget {
  const SessionInsightsSheet({
    super.key,
    required this.state,
    required this.strings,
    required this.onOpenDeliverable,
    required this.onOpenStats,
    required this.onOpenTrajectory,
  });

  final HarnessState state;
  final Strings strings;
  final void Function(String path) onOpenDeliverable;
  final VoidCallback onOpenStats;
  final VoidCallback onOpenTrajectory;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 16),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(strings.get('todos'),
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                Text(
                  '${state.todos.length}',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (state.todos.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(strings.get('no_todos'),
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            )
          else
            for (final todo in state.todos)
              ListTile(
                dense: true,
                leading: Icon(_todoIcon(todo.status), size: 18),
                title: Text(todo.content, style: const TextStyle(fontSize: 13)),
                subtitle: Text(todo.status, style: const TextStyle(fontSize: 11)),
              ),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(strings.get('deliverables'),
                style: Theme.of(context).textTheme.titleMedium),
          ),
          if (state.deliverables.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text('—', style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            )
          else
            for (final deliverable in state.deliverables)
              ListTile(
                dense: true,
                leading: const Text('📄', style: TextStyle(fontSize: 16)),
                title: Text(
                  deliverable.path.split('/').last,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
                subtitle: deliverable.description == null
                    ? Text(deliverable.path, style: const TextStyle(fontSize: 11))
                    : Text(deliverable.description!, style: const TextStyle(fontSize: 11)),
                onTap: () => onOpenDeliverable(deliverable.path),
              ),
          const Divider(height: 24),
          ListTile(
            dense: true,
            leading: const Icon(Icons.insights_outlined, size: 18),
            title: Text(strings.get('stats'), style: const TextStyle(fontSize: 14)),
            onTap: () {
              Navigator.of(context).pop();
              onOpenStats();
            },
          ),
          ListTile(
            dense: true,
            leading: const Icon(Icons.timeline, size: 18),
            title: Text(strings.get('trajectory'), style: const TextStyle(fontSize: 14)),
            onTap: () {
              Navigator.of(context).pop();
              onOpenTrajectory();
            },
          ),
        ],
      ),
    );
  }

  IconData _todoIcon(String status) {
    switch (status) {
      case 'completed':
        return Icons.check_circle_outline;
      case 'in_progress':
        return Icons.radio_button_checked;
      default:
        return Icons.radio_button_unchecked;
    }
  }
}

/// 执行统计面板。**刻意不显示 Token 用量 / 上下文占用**：读不到就不编。
class SessionStatsView extends StatelessWidget {
  const SessionStatsView({super.key, required this.stats, required this.strings});

  final SessionStats stats;
  final Strings strings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (stats.isEmpty) {
      return EmptyState(text: strings.get('stats_empty'));
    }
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: <Widget>[
              Expanded(child: Text(label, style: const TextStyle(fontSize: 13))),
              Text(value,
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600, color: scheme.primary)),
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        row(strings.get('turns'), '${stats.turns}'),
        row(strings.get('assistant_messages'), '${stats.assistantMessages}'),
        row(strings.get('tool_calls'), '${stats.toolCalls}'),
        row(strings.get('events'), '${stats.events}'),
        if (stats.lastSeq != null) row(strings.get('last_seq'), '#${stats.lastSeq}'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Text(
            strings.get('stats_tokens_note'),
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// 执行轨迹页：按轮次分组，组内按 seq；**不做类型过滤**。
class TrajectoryScreen extends StatelessWidget {
  const TrajectoryScreen({super.key, required this.history, required this.strings});

  final ChatHistory? history;
  final Strings strings;

  @override
  Widget build(BuildContext context) {
    final turns = trajectoryOf(history);
    return Scaffold(
      appBar: AppBar(title: Text(strings.get('trajectory'))),
      body: turns.isEmpty
          ? EmptyState(text: strings.get('stats_empty'))
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: <Widget>[
                for (final turn in turns) _turn(context, turn),
              ],
            ),
    );
  }

  Widget _turn(BuildContext context, TrajectoryTurn turn) {
    final scheme = Theme.of(context).colorScheme;
    final duration = turn.durationMillis;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: double.infinity,
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  turn.turn == unknownTurn
                      ? strings.get('unknown_turn')
                      : strings.format('turn', <String, String>{'n': '${turn.turn}'}),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              if (duration != null)
                Text(shortDuration(duration),
                    style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
              const SizedBox(width: 8),
              Text('${turn.toolCalls}',
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            ],
          ),
        ),
        for (final node in turn.ordered) _node(context, node),
      ],
    );
  }

  Widget _node(BuildContext context, TrajectoryNode node) {
    final scheme = Theme.of(context).colorScheme;
    final label = node.label ?? node.eventType;
    return InkWell(
      onTap: () => _showRaw(context, node),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Row(
          children: <Widget>[
            Text(_glyph(node.kind), style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            Text('#${node.seq}',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
            const SizedBox(width: 8),
            Text(
              chatTimeLabel(node.time) ?? '—',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  String _glyph(TrajectoryNodeKind kind) {
    switch (kind) {
      case TrajectoryNodeKind.user:
        return '👤';
      case TrajectoryNodeKind.assistant:
        return '🤖';
      case TrajectoryNodeKind.tool:
        return '🛠';
      case TrajectoryNodeKind.deliverable:
        return '📦';
      case TrajectoryNodeKind.turnEnd:
        return '🏁';
      case TrajectoryNodeKind.other:
        return '·';
    }
  }

  void _showRaw(BuildContext context, TrajectoryNode node) {
    final raw = node.raw == null ? 'null' : const JsonEncoder.withIndent('  ').convert(node.raw);
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: Text(node.eventType),
        content: SingleChildScrollView(
          child: SelectableText(
            raw,
            style: const TextStyle(fontFamily: 'Menlo', fontSize: 11.5, height: 1.4),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(strings.get('close')),
          ),
        ],
      ),
    );
  }
}
