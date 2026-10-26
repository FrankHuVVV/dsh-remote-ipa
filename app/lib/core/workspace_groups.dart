/// 会话按**工作区**分组（0.2.3 起取代按「今天/昨天/本周」分组）。
///
/// 用户的原话是「首页不以今天昨天上周分类，要以不同工作区分类」。实现上是纯函数，
/// 便于单测：
/// - 组键 = `workspaceId`，没有就退化到 `workspaceTitle`，再没有就空串（「未分组」）；
/// - 组按**组内最近更新**倒序（用工作区里最新的会话时间）；
/// - 组内按 `updatedAt` 倒序；
/// - 没有 `updatedAt`（0）的会话排在组内最后，但**不丢**。
library;

import 'models.dart';

class WorkspaceGroup {
  WorkspaceGroup({required this.key, required this.title, required this.sessions, required this.lastUpdated});

  final String key;
  final String title;
  final List<ChatSession> sessions;
  final int lastUpdated;

  bool get isUngrouped => key.isEmpty;
}

List<WorkspaceGroup> groupSessionsByWorkspace(List<ChatSession> sessions) {
  final buckets = <String, List<ChatSession>>{};
  final titles = <String, String>{};
  final latest = <String, int>{};

  for (final session in sessions) {
    final key = (session.workspaceId ?? session.workspaceTitle ?? '').trim();
    buckets.putIfAbsent(key, () => <ChatSession>[]).add(session);
    final title = (session.workspaceTitle ?? '').trim();
    if (title.isNotEmpty && !titles.containsKey(key)) {
      titles[key] = title;
    }
    if (session.updatedAt > (latest[key] ?? 0)) {
      latest[key] = session.updatedAt;
    }
  }

  final groups = <WorkspaceGroup>[
    for (final entry in buckets.entries)
      WorkspaceGroup(
        key: entry.key,
        title: titles[entry.key] ?? '',
        sessions: entry.value.toList()
          ..sort((ChatSession a, ChatSession b) => b.updatedAt.compareTo(a.updatedAt)),
        lastUpdated: latest[entry.key] ?? 0,
      ),
  ];
  groups.sort((WorkspaceGroup a, WorkspaceGroup b) {
    // 「未分组」永远排最后：它不是一个真的工作区。
    if (a.isUngrouped != b.isUngrouped) {
      return a.isUngrouped ? 1 : -1;
    }
    return b.lastUpdated.compareTo(a.lastUpdated);
  });
  return groups;
}
