/// 会话列表 —— 移植自鸿蒙版 `ui/ChatScreen.ets` 的列表部分 + `SessionRow.ets`。
library;

import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/small_parts.dart';
import '../l10n/strings.dart';
import '../state/harness_view_model.dart';
import 'chat_screen.dart';
import 'widgets.dart';

class SessionsScreen extends StatelessWidget {
  const SessionsScreen({super.key, required this.viewModel, this.onOpenChat});

  final HarnessViewModel viewModel;
  final VoidCallback? onOpenChat;

  Strings get s => viewModel.strings;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: viewModel,
      builder: (BuildContext context, _) {
        final state = viewModel.state;
        final sessions = state.sessions;
        final groups = <String, List<ChatSession>>{};
        for (final session in sessions) {
          final key = sessionGroupOf(session.updatedAt);
          groups.putIfAbsent(key, () => <ChatSession>[]).add(session);
        }
        const order = <String>[
          sessionGroupToday,
          sessionGroupYesterday,
          sessionGroupWeek,
          sessionGroupEarlier,
        ];
        return Scaffold(
          appBar: AppBar(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(s.get('sessions_title')),
                Text(
                  s.format('sessions_count', <String, String>{'count': '${sessions.length}'}),
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            actions: <Widget>[
              if (supportsArchiveListing(state.bridgeCapabilities))
                IconButton(
                  tooltip: s.get('archived_sessions'),
                  onPressed: () => _openArchived(context),
                  icon: const Icon(Icons.inventory_2_outlined),
                ),
              IconButton(
                tooltip: s.get('refresh'),
                onPressed: viewModel.refreshDashboard,
                icon: state.busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: state.busy ? null : viewModel.createSession,
            tooltip: s.get('new_session'),
            child: const Icon(Icons.add),
          ),
          body: Column(
            children: <Widget>[
              if (state.error != null) ErrorBar(message: state.error!, onDismiss: viewModel.clearError),
              if (state.notice != null) NoticeBar(message: state.notice!, onDismiss: viewModel.clearNotice),
              Expanded(
                child: sessions.isEmpty
                    ? EmptyState(text: s.get('no_sessions'))
                    : RefreshIndicator(
                        onRefresh: viewModel.refreshDashboard,
                        child: ListView(
                          padding: const EdgeInsets.only(bottom: 88),
                          children: <Widget>[
                            for (final key in order)
                              if ((groups[key] ?? const <ChatSession>[]).isNotEmpty) ...<Widget>[
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
                                  child: Text(
                                    key,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                                for (final session in groups[key]!) _row(context, session),
                              ],
                          ],
                        ),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _row(BuildContext context, ChatSession session) {
    final scheme = Theme.of(context).colorScheme;
    final title = session.displayTitle().isEmpty ? s.get('unnamed_session') : session.displayTitle();
    return InkWell(
      onTap: () async {
        await viewModel.selectSession(session.id);
        if (context.mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (BuildContext context) => ChatScreen(viewModel: viewModel),
            ),
          );
          onOpenChat?.call();
        }
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
        child: Row(
          children: <Widget>[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: scheme.surfaceContainerHighest, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: const Text('💬', style: TextStyle(fontSize: 16)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: <Widget>[
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: session.running ? const Color(0xFF2E9E5B) : scheme.outline,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        session.running ? s.get('running') : s.get('idle'),
                        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                      ),
                      if (session.workspaceTitle != null && session.workspaceTitle!.isNotEmpty) ...<Widget>[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            session.workspaceTitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                      if (session.cwd.isNotEmpty) ...<Widget>[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            session.cwd,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: scheme.outline),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 18),
              onSelected: (String value) async {
                if (value == 'rename') {
                  final name = await textInputDialog(
                    context,
                    title: s.get('rename'),
                    initialValue: session.displayTitle(),
                  );
                  if (name != null && name.trim().isNotEmpty) {
                    await viewModel.renameSession(session.id, name);
                  }
                } else if (value == 'archive') {
                  await viewModel.archiveSession(session.id);
                } else if (value == 'fork') {
                  await viewModel.forkSession(session.id);
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(value: 'rename', child: Text(s.get('rename'))),
                PopupMenuItem<String>(value: 'fork', child: Text(s.get('fork'))),
                PopupMenuItem<String>(value: 'archive', child: Text(s.get('archive'))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openArchived(BuildContext context) {
    viewModel.refreshArchivedSessions();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => AnimatedBuilder(
        animation: viewModel,
        builder: (BuildContext context, _) {
          final archived = viewModel.state.archivedSessions;
          return SafeArea(
            child: archived.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('—')),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Text(
                          s.get('archived_sessions'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      for (final session in archived)
                        ListTile(
                          dense: true,
                          title: Text(
                            session.displayTitle().isEmpty
                                ? s.get('unnamed_session')
                                : session.displayTitle(),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          s.get('archive_unsupported'),
                          style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }
}
