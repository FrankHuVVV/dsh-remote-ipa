import 'package:dsh_companion_ios/core/models.dart';
import 'package:dsh_companion_ios/core/workspace_groups.dart';
import 'package:flutter_test/flutter_test.dart';

ChatSession session(
  String id, {
  String? workspaceId,
  String? workspaceTitle,
  int updatedAt = 0,
  String cwd = '',
}) =>
    ChatSession(
      id: id,
      workspaceId: workspaceId,
      workspaceTitle: workspaceTitle,
      updatedAt: updatedAt,
      cwd: cwd,
    );

void main() {
  test('按工作区分组，组内按更新时间倒序', () {
    final groups = groupSessionsByWorkspace(<ChatSession>[
      session('a', workspaceId: 'w1', workspaceTitle: 'dsh-remote', updatedAt: 100),
      session('b', workspaceId: 'w1', workspaceTitle: 'dsh-remote', updatedAt: 300),
      session('c', workspaceId: 'w2', workspaceTitle: 'blender', updatedAt: 200),
    ]);
    expect(groups.map((WorkspaceGroup g) => g.key), <String>['w1', 'w2']);
    expect(groups.first.sessions.map((ChatSession s) => s.id), <String>['b', 'a']);
    expect(groups.first.title, 'dsh-remote');
    expect(groups.first.lastUpdated, 300);
  });

  test('组间按组内最新会话倒序', () {
    final groups = groupSessionsByWorkspace(<ChatSession>[
      session('old', workspaceId: 'w-old', updatedAt: 100),
      session('new', workspaceId: 'w-new', updatedAt: 900),
    ]);
    expect(groups.first.key, 'w-new');
  });

  test('没有工作区的会话归入未分组并排最后', () {
    final groups = groupSessionsByWorkspace(<ChatSession>[
      session('none', updatedAt: 9999),
      session('w', workspaceId: 'w1', workspaceTitle: 'ws', updatedAt: 1),
    ]);
    expect(groups.last.isUngrouped, isTrue);
    expect(groups.last.sessions.single.id, 'none');
  });

  test('workspaceId 缺失时用 workspaceTitle 当组键', () {
    final groups = groupSessionsByWorkspace(<ChatSession>[
      session('a', workspaceTitle: 'ten-class', updatedAt: 10),
    ]);
    expect(groups.single.key, 'ten-class');
  });

  test('空列表返回空分组', () {
    expect(groupSessionsByWorkspace(<ChatSession>[]), isEmpty);
  });
}
