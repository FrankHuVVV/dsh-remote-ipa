/// 线上模型 —— **会话域**：会话、工作区、Agent 预设、审批、问答、命令、待办、权限选择。
library;

import 'json.dart';

class ChatSession {
  ChatSession({
    this.id = '',
    this.rootId = '',
    this.cwd = '',
    this.cwdAbsolute,
    this.updatedAt = 0,
    this.running = false,
    this.blank = false,
    this.title,
    this.workspaceId,
    this.workspaceTitle,
    this.agentPreset,
    this.parentSessionId,
    this.origin,
    this.pendingInteraction,
  });

  String id;
  String rootId;

  /// 会话工作目录**相对授权根**的路径。空串是合法值（工作目录就是根本身）。
  String cwd;

  /// 工作目录的绝对路径（老服务端不返回时为 null）。
  String? cwdAbsolute;
  int updatedAt;
  bool running;
  bool blank;
  String? title;
  String? workspaceId;
  String? workspaceTitle;
  String? agentPreset;
  String? parentSessionId;
  String? origin;
  String? pendingInteraction;

  String displayTitle() => title ?? '';

  ChatSession withRunning(bool running) => copy()..running = running;

  ChatSession copy() => ChatSession(
        id: id,
        rootId: rootId,
        cwd: cwd,
        cwdAbsolute: cwdAbsolute,
        updatedAt: updatedAt,
        running: running,
        blank: blank,
        title: title,
        workspaceId: workspaceId,
        workspaceTitle: workspaceTitle,
        agentPreset: agentPreset,
        parentSessionId: parentSessionId,
        origin: origin,
        pendingInteraction: pendingInteraction,
      );

  factory ChatSession.fromJson(Object? map) => ChatSession(
        id: stringOrNull(map, 'id') ?? '',
        rootId: stringOrNull(map, 'rootId') ?? '',
        cwd: stringOrNull(map, 'cwd') ?? '',
        cwdAbsolute: stringOrNull(map, 'cwdAbsolute'),
        updatedAt: intOrNull(map, 'updatedAt') ?? 0,
        running: boolOrNull(map, 'running') ?? false,
        blank: boolOrNull(map, 'blank') ?? false,
        title: stringOrNull(map, 'title'),
        workspaceId: stringOrNull(map, 'workspaceId'),
        workspaceTitle: stringOrNull(map, 'workspaceTitle'),
        agentPreset: stringOrNull(map, 'agentPreset'),
        parentSessionId: stringOrNull(map, 'parentSessionId'),
        origin: stringOrNull(map, 'origin'),
        pendingInteraction: stringOrNull(map, 'pendingInteraction'),
      );
}

class CreatedSession {
  CreatedSession({this.id = '', this.agentPreset});

  String id;
  String? agentPreset;

  factory CreatedSession.fromJson(Object? map) => CreatedSession(
        id: stringOrNull(map, 'id') ?? '',
        agentPreset: stringOrNull(map, 'agentPreset'),
      );
}

class RenamedSession {
  RenamedSession({this.title = '', this.seq = 0});

  String title;
  int seq;

  factory RenamedSession.fromJson(Object? map) => RenamedSession(
        title: stringOrNull(map, 'title') ?? '',
        seq: intOrNull(map, 'seq') ?? 0,
      );
}

class ChatWorkspace {
  ChatWorkspace({
    this.id = '',
    this.title = '',
    this.rootId = '',
    this.path = '',
    this.createdAt = '',
    this.updatedAt = '',
  });

  String id;
  String title;
  String rootId;
  String path;
  String createdAt;
  String updatedAt;

  factory ChatWorkspace.fromJson(Object? map) => ChatWorkspace(
        id: stringOrNull(map, 'id') ?? '',
        title: stringOrNull(map, 'title') ?? '',
        rootId: stringOrNull(map, 'rootId') ?? '',
        path: stringOrNull(map, 'path') ?? '',
        createdAt: stringOrNull(map, 'createdAt') ?? '',
        updatedAt: stringOrNull(map, 'updatedAt') ?? '',
      );
}

class AgentPreset {
  AgentPreset({
    this.id = '',
    this.name = '',
    this.description,
    this.trust = 'system',
    this.isDefault = false,
    this.available = true,
  });

  String id;
  String name;
  String? description;
  String trust;
  bool isDefault;
  bool available;

  factory AgentPreset.fromJson(Object? map) => AgentPreset(
        id: stringOrNull(map, 'id') ?? '',
        name: stringOrNull(map, 'name') ?? '',
        description: stringOrNull(map, 'description'),
        trust: stringOrNull(map, 'trust') ?? 'system',
        isDefault: boolOrNull(map, 'isDefault') ?? false,
        available: boolOrNull(map, 'available') ?? true,
      );
}

// ---------------------------------------------------------------------------
// 审批
// ---------------------------------------------------------------------------

class PendingApproval {
  PendingApproval({
    this.id = '',
    this.sessionId = '',
    this.toolName = '',
    this.reason,
    this.detail,
    this.risk = '',
    this.requestedAt = 0,
  });

  String id;
  String sessionId;
  String toolName;
  String? reason;
  String? detail;
  String risk;
  int requestedAt;

  factory PendingApproval.fromJson(Object? map) => PendingApproval(
        id: stringOrNull(map, 'id') ?? '',
        sessionId: stringOrNull(map, 'sessionId') ?? '',
        toolName: stringOrNull(map, 'toolName') ?? '',
        reason: stringOrNull(map, 'reason'),
        detail: stringOrNull(map, 'detail'),
        risk: stringOrNull(map, 'risk') ?? '',
        requestedAt: intOrNull(map, 'requestedAt') ?? 0,
      );
}

/// 审批决定：只有「本次放行」与「拒绝」，没有永久放行。
const String approvalOutcomeAllowedOnce = 'allowed-once';
const String approvalOutcomeRejected = 'rejected';

// ---------------------------------------------------------------------------
// 问答（ask_user_question）
// ---------------------------------------------------------------------------

/// 唯一支持远程回答的状态。
const String questionStateContinued = 'continued';

class QuestionOption {
  QuestionOption({this.label = '', this.description});

  String label;
  String? description;

  factory QuestionOption.fromJson(Object? map) => QuestionOption(
        label: stringOrNull(map, 'label') ?? '',
        description: stringOrNull(map, 'description'),
      );
}

class ChatQuestion {
  ChatQuestion({
    this.id = '',
    this.question = '',
    this.header,
    this.detail,
    this.options = const <QuestionOption>[],
    this.multiSelect = false,
  });

  String id;
  String question;
  String? header;
  String? detail;
  List<QuestionOption> options;
  bool multiSelect;

  bool isFreeText() => options.isEmpty;

  factory ChatQuestion.fromJson(Object? map) => ChatQuestion(
        id: stringOrNull(map, 'id') ?? '',
        question: stringOrNull(map, 'question') ?? '',
        header: stringOrNull(map, 'header'),
        detail: stringOrNull(map, 'detail'),
        options: [for (final o in objArr(map, 'options')) QuestionOption.fromJson(o)],
        multiSelect: boolOrNull(map, 'multiSelect') ?? false,
      );
}

class PendingQuestionSet {
  PendingQuestionSet({
    this.callId = '',
    this.state = '',
    this.questions = const <ChatQuestion>[],
    this.viaBridge = false,
  });

  String callId;
  String state;
  List<ChatQuestion> questions;
  bool viaBridge;

  bool isAnswerable() => state == questionStateContinued;

  factory PendingQuestionSet.fromJson(Object? map) => PendingQuestionSet(
        callId: stringOrNull(map, 'callId') ?? '',
        state: stringOrNull(map, 'state') ?? '',
        questions: [for (final q in objArr(map, 'questions')) ChatQuestion.fromJson(q)],
        viaBridge: boolOrNull(map, 'viaBridge') ?? false,
      );
}

/// 一道题的答案。
class QuestionAnswer {
  QuestionAnswer({this.id = '', this.selected = const <String>[], this.custom = ''});

  String id;
  List<String> selected;

  /// 自由文本。默认空串，编码时为空就**不写** `custom` 键。
  String custom;

  Map<String, dynamic> toMap() {
    final out = <String, dynamic>{'id': id, 'selected': selected};
    if (custom.isNotEmpty) {
      out['custom'] = custom;
    }
    return out;
  }
}

// ---------------------------------------------------------------------------
// 命令 / 待办 / 权限选择
// ---------------------------------------------------------------------------

class CommandInput {
  CommandInput({this.hint = ''});

  String hint;

  factory CommandInput.fromJson(Object? map) => CommandInput(hint: stringOrNull(map, 'hint') ?? '');
}

class CommandDescriptor {
  CommandDescriptor({this.name = '', this.description = '', this.input});

  String name;
  String description;
  CommandInput? input;

  factory CommandDescriptor.fromJson(Object? map) => CommandDescriptor(
        name: stringOrNull(map, 'name') ?? '',
        description: stringOrNull(map, 'description') ?? '',
        input: obj(map, 'input') == null ? null : CommandInput.fromJson(obj(map, 'input')),
      );
}

class CommandResult {
  CommandResult({this.kind = '', this.text, this.sourceEventSeq});

  String kind;
  String? text;
  int? sourceEventSeq;

  factory CommandResult.fromJson(Object? map) => CommandResult(
        kind: stringOrNull(map, 'kind') ?? '',
        text: stringOrNull(map, 'text'),
        sourceEventSeq: intOrNull(map, 'sourceEventSeq'),
      );
}

class CommandExecution {
  CommandExecution({this.commandId = '', CommandResult? result})
      : result = result ?? CommandResult();

  String commandId;
  CommandResult result;

  factory CommandExecution.fromJson(Object? map) => CommandExecution(
        commandId: stringOrNull(map, 'commandId') ?? '',
        result: CommandResult.fromJson(obj(map, 'result')),
      );
}

class TodoItem {
  TodoItem({this.content = '', this.status = ''});

  String content;
  String status;

  factory TodoItem.fromJson(Object? map) => TodoItem(
        content: stringOrNull(map, 'content') ?? '',
        status: stringOrNull(map, 'status') ?? '',
      );
}
