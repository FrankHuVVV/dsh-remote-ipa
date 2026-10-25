/// 会话动作（HarnessViewModel 的 part 扩展）。
///
/// 单独成文件是为了守住 900 行预算；逻辑与字段都属于同一个 library，
/// 因此这里仍可直接改 `state`、调用 `_update` / `_launch`。
part of 'harness_view_model.dart';

extension HarnessChatActions on HarnessViewModel {
  // ---------------------------------------------------------------------------
  // 会话
  // ---------------------------------------------------------------------------

  Future<void> refreshSessions() async {
    final client = _client;
    if (client == null) {
      return;
    }
    try {
      final sessions = await client.sessions();
      _update((s) => s.sessions = sessions);
    } on Object catch (error) {
      _update((s) => s.error = describeError(error, strings));
    }
  }

  Future<void> refreshArchivedSessions() async {
    final client = _client;
    if (client == null || !supportsArchiveListing(state.bridgeCapabilities)) {
      return;
    }
    try {
      final archived = await client.sessions(archived: true);
      _update((s) => s.archivedSessions = archived);
    } on Object catch (error) {
      _update((s) => s.error = describeError(error, strings));
    }
  }

  Future<void> selectSession(String sessionId) async {
    if (state.selectedSessionId != sessionId) {
      _seqMonitor.reset();
      _update((s) {
        s.selectedSessionId = sessionId;
        s.history = null;
        s.liveChat = null;
        s.visibleItems = <ChatDisplayItem>[];
        s.approvals = <PendingApproval>[];
        s.approvalKind = ApprovalUiKind.none;
        s.questions = <PendingQuestionSet>[];
        s.commands = <CommandDescriptor>[];
        s.sessionModels = null;
        s.permissionCatalog = null;
        s.lastEventSeq = null;
        s.baselineCursor = null;
      });
    }
    _sessionGeneration++;
    await loadHistory();
    await Future.wait(<Future<void>>[
      refreshApprovals(),
      refreshQuestions(),
      refreshCommands(),
      refreshSessionModels(),
      refreshPermissionCatalog(),
    ]);
  }

  Future<void> loadHistory({bool older = false}) async {
    final client = _client;
    final sessionId = state.selectedSessionId;
    if (client == null || sessionId == null) {
      return;
    }
    final generation = _sessionGeneration;
    try {
      ChatHistory? olderPage;
      if (older) {
        final firstSeq = _oldestSeq();
        olderPage = await client.history(sessionId, beforeSeq: firstSeq, maxMessages: 60);
      }
      final page = olderPage ?? await client.history(sessionId, maxMessages: 60);
      if (generation != _sessionGeneration || sessionId != state.selectedSessionId) {
        return;
      }
      _update((s) {
        if (olderPage != null && s.history != null) {
          final merged = <HistoryEntry>[...page.events, ...s.history!.events];
          final seen = <String>{};
          final unique = <HistoryEntry>[
            for (final entry in merged)
              if (seen.add('${entry.event.seq}-${entry.event.type}')) entry,
          ];
          unique.sort((a, b) => a.event.seq.compareTo(b.event.seq));
          s.history = ChatHistory(events: unique, hasMore: page.hasMore, projections: page.projections);
        } else {
          s.history = page;
        }
        s.todos = todoItemsOf(s.history!);
        s.deliverables = deliverablesOf(s.history!);
        _recomputeVisible(s);
      });
    } on Object catch (error) {
      _update((s) => s.error = describeError(error, strings));
    }
  }

  Future<void> loadOlder() => loadHistory(older: true);

  int? _oldestSeq() {
    final history = state.history;
    if (history == null || history.events.isEmpty) {
      return null;
    }
    var min = 1 << 60;
    for (final entry in history.events) {
      if (entry.event.seq > 0 && entry.event.seq < min) {
        min = entry.event.seq;
      }
    }
    return min == 1 << 60 ? null : min;
  }

  void _recomputeVisible(HarnessState s) {
    final historyItems = s.history == null ? <ChatDisplayItem>[] : displayItemsOf(s.history!);
    final liveItems = s.liveChat?.displayItems() ?? <ChatDisplayItem>[];
    s.visibleItems = chatVisibleItems(historyItems, liveItems);
  }

  /// 新建会话：优先用已有工作区，没有就按第一个授权根建一个。
  Future<void> createSession() async {
    final client = _client;
    if (client == null) {
      return;
    }
    await _launch(() async {
      String? workspaceId = state.chatWorkspaces.isEmpty ? null : state.chatWorkspaces.first.id;
      if (workspaceId == null) {
        final root = state.roots.isEmpty ? null : state.roots.first;
        if (root == null) {
          throw StateError(strings.get('no_roots'));
        }
        final workspace = await client.createChatWorkspace(root.id, '');
        _update((s) => s.chatWorkspaces = <ChatWorkspace>[...s.chatWorkspaces, workspace]);
        workspaceId = workspace.id;
      }
      final created = await client.createSession(workspaceId);
      await refreshSessions();
      await selectSession(created.id);
    });
  }

  Future<void> sendMessage(String text, {bool? steer, List<PendingAttachment> attachments = const <PendingAttachment>[]}) async {
    final client = _client;
    final sessionId = state.selectedSessionId;
    if (client == null || sessionId == null) {
      return;
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty && attachments.isEmpty) {
      return;
    }
    await _launch(() async {
      final parts = <PromptPart>[
        if (trimmed.isNotEmpty) PromptPart.text(trimmed),
        for (final attachment in attachments) attachment.part,
      ];
      await client.sendMessage(sessionId, parts, steer: steer ?? state.busySendMode == sendModeSteer);
      await loadHistory();
    });
  }

  Future<void> sendCommand(String line) async {
    final client = _client;
    final sessionId = state.selectedSessionId;
    if (client == null || sessionId == null) {
      return;
    }
    await _launch(() async {
      final execution = await client.executeCommand(sessionId, line);
      final text = execution.result.text;
      if (text != null && text.isNotEmpty) {
        _update((s) => s.notice = text);
      }
      await loadHistory();
    });
  }

  Future<void> cancelRun() async {
    final client = _client;
    final sessionId = state.selectedSessionId;
    if (client == null || sessionId == null) {
      return;
    }
    await _launch(() async {
      await client.cancel(sessionId);
      await refreshSessions();
    });
  }

  Future<void> renameSession(String sessionId, String title) async {
    final client = _client;
    if (client == null) {
      return;
    }
    await _launch(() async {
      await client.renameSession(sessionId, title.trim());
      await refreshSessions();
    });
  }

  Future<void> archiveSession(String sessionId) async {
    final client = _client;
    if (client == null) {
      return;
    }
    await _launch(() async {
      await client.archiveSession(sessionId);
      if (state.selectedSessionId == sessionId) {
        _update((s) => s.selectedSessionId = null);
      }
      await refreshSessions();
      _update((s) => s.notice = strings.get('archive_done'));
    });
  }

  Future<void> forkSession(String sessionId, {int? atSeq}) async {
    final client = _client;
    if (client == null) {
      return;
    }
    await _launch(() async {
      final created = await client.forkSession(sessionId, atSeq: atSeq);
      await refreshSessions();
      if (created.isNotEmpty) {
        await selectSession(created);
      }
      _update((s) => s.notice = strings.get('fork_done'));
    });
  }

  Future<void> refreshCommands() async {
    final client = _client;
    final sessionId = state.selectedSessionId;
    if (client == null || sessionId == null) {
      return;
    }
    try {
      final commands = await client.sessionCommands(sessionId);
      if (sessionId == state.selectedSessionId) {
        _update((s) => s.commands = commands);
      }
    } on Object {
      // 命令清单读不到不影响聊天，静默。
    }
  }

  Future<void> refreshSessionModels() async {
    final client = _client;
    final sessionId = state.selectedSessionId;
    if (client == null || sessionId == null) {
      return;
    }
    try {
      final models = await client.sessionModels(sessionId);
      if (sessionId == state.selectedSessionId) {
        _update((s) => s.sessionModels = models);
      }
    } on Object {
      // 同上。
    }
  }

  Future<void> refreshPermissionCatalog() async {
    final client = _client;
    if (client == null) {
      return;
    }
    try {
      final catalog = await client.permissionPresets();
      _update((s) => s.permissionCatalog = catalog);
    } on Object {
      // 权限目录读不到时菜单保持为空（不是「没有权限可设」）。
    }
  }

  /// 切换权限档位：走 `/permission <preset>` 命令，与鸿蒙版同一条路径。
  ///
  /// 服务端没有单独的「改权限」端点 —— 权限是会话命令的语法，硬造一个 PATCH 只会
  /// 与内核口径分裂。
  Future<void> selectPermissionPreset(String preset) async {
    final client = _client;
    final sessionId = state.selectedSessionId;
    if (client == null || sessionId == null || preset.isEmpty) {
      return;
    }
    await _launch(() async {
      final execution = await client.executeCommand(sessionId, '/permission $preset');
      final text = execution.result.text;
      await refreshPermissionCatalog();
      if (text != null && text.trim().isNotEmpty) {
        _update((s) => s.notice = text);
      }
    });
  }

  Future<void> selectModel(ModelSelection selection) async {
    final client = _client;
    final sessionId = state.selectedSessionId;
    if (client == null || sessionId == null) {
      return;
    }
    await _launch(() async {
      final selected = await client.selectModel(sessionId, selection);
      _update((s) {
        s.sessionModels = s.sessionModels == null
            ? null
            : (s.sessionModels!..current = selected);
      });
    });
  }

  Future<void> refreshApprovals() async {
    final client = _client;
    final sessionId = state.selectedSessionId;
    if (client == null || sessionId == null) {
      return;
    }
    try {
      final approvals = await client.pendingApprovals(sessionId);
      if (sessionId != state.selectedSessionId) {
        return;
      }
      _update((s) {
        s.approvals = approvals;
        s.approvalKind = approvals.isEmpty ? ApprovalUiKind.none : ApprovalUiKind.pending;
        if (s.decidingApproval != null && !approvals.any((a) => a.id == s.decidingApproval!.id)) {
          s.decidingApproval = null;
        }
      });
    } on Object {
      // 审批面板读失败不弹全局错误：会话照常可读。
    }
  }

  Future<void> decideApproval(PendingApproval approval, {required bool allowOnce}) async {
    final client = _client;
    final sessionId = state.selectedSessionId;
    if (client == null || sessionId == null) {
      return;
    }
    _update((s) {
      s.approvalKind = ApprovalUiKind.deciding;
      s.decidingApproval = approval;
    });
    try {
      await client.decideApproval(sessionId, approval.id, allowOnce);
    } on Object catch (error) {
      _update((s) => s.error = describeError(error, strings));
    } finally {
      await refreshApprovals();
    }
  }

  Future<void> refreshQuestions() async {    final client = _client;
    final sessionId = state.selectedSessionId;
    if (client == null || sessionId == null) {
      return;
    }
    try {
      final sets = await client.pendingQuestions(sessionId);
      if (sessionId != state.selectedSessionId) {
        return;
      }
      _update((s) => s.questions = <PendingQuestionSet>[
            for (final set in sets)
              if (set.isAnswerable()) set,
          ]);
    } on Object {
      // 兼容旧服务端：没有这个端点时静默（能力位会提示缺 questions-v1）。
    }
  }

  Future<void> answerQuestions(String callId, List<QuestionAnswer> answers) async {
    final client = _client;
    final sessionId = state.selectedSessionId;
    if (client == null || sessionId == null) {
      return;
    }
    _update((s) => s.answeringCallId = callId);
    try {
      await client.answerQuestions(sessionId, callId, answers);
      _update((s) {
        s.answeredCallIds = <String>{...s.answeredCallIds, callId};
        s.questions = <PendingQuestionSet>[
          for (final q in s.questions)
            if (q.callId != callId) q,
        ];
      });
    } on Object catch (error) {
      _update((s) => s.error = describeError(error, strings));
    } finally {
      _update((s) => s.answeringCallId = null);
    }
  }

  /// 取一张历史图片的字节（两步：先拿 id / 路径，再取字节）。
  ///
  /// 普通附件走 `attachments/{id}?sessionId=`；交接图（纯文本模型把图落到工作区）走
  /// `roots/resolve` + 读文件 —— 它的字节根本不在附件存储里。
  Future<void> loadAttachment(ChatAttachment attachment) async {
    final client = _client;
    final sessionId = state.selectedSessionId;
    final id = attachment.attachmentId;
    if (client == null || sessionId == null) {
      return;
    }
    if (state.attachmentImages.containsKey(id) || state.attachmentLoading.contains(id)) {
      return;
    }
    _update((s) => s.attachmentLoading = <String>{...s.attachmentLoading, id});
    try {
      final List<int> bytes;
      final handoff = attachment.handoffPath;
      if (handoff != null) {
        final resolved = await client.resolvePath(handoff);
        if (resolved == null) {
          throw StateError(strings.get('unknown_error').replaceAll('{reason}', 'PATH_OUTSIDE_ROOTS'));
        }
        bytes = (await client.readFile(resolved.rootId, resolved.path)).bytes;
      } else {
        bytes = await client.readAttachment(sessionId, id);
      }
      _update((s) {
        s.attachmentImages = <String, List<int>>{...s.attachmentImages, id: bytes};
        s.attachmentLoading = <String>{...s.attachmentLoading}..remove(id);
      });
    } on Object catch (error) {
      final message = describeError(error, strings);
      _update((s) {
        s.attachmentFailures = <String, String>{...s.attachmentFailures, id: message};
        s.attachmentLoading = <String>{...s.attachmentLoading}..remove(id);
      });
    }
  }

  /// 把一张图片做成内联 part（发送时 base64 直接进消息，不先上传）。
  PendingAttachment? makeImageAttachment(String name, List<int> bytes) {
    if (bytes.length > 8 * 1024 * 1024) {
      _update((s) => s.error = strings.get('file_too_large'));
      return null;
    }
    final mediaType = _contentTypeOf(name) ?? 'image/png';
    return PendingAttachment(
      id: deps.platform.newId(),
      part: PromptPart.image(mediaType, base64Encode(bytes), name: name),
      name: name,
      sizeBytes: bytes.length,
      imageBytes: bytes,
    );
  }

  /// 把普通文件换成 `receiptId`（文件本身不进工作区，只给这一条消息一张临时凭证）。
  Future<PendingAttachment?> uploadFileAttachment(String name, List<int> bytes) async {
    final client = _client;
    final sessionId = state.selectedSessionId;
    if (client == null || sessionId == null) {
      return null;
    }
    if (bytes.length > 24 * 1024 * 1024) {
      _update((s) => s.error = strings.get('file_too_large'));
      return null;
    }
    _update((s) => s.attachmentUploading = true);
    try {
      final uploaded = await client.uploadAttachment(sessionId, bytes, name);
      return PendingAttachment(
        id: deps.platform.newId(),
        part: PromptPart.file(uploaded.receiptId),
        name: uploaded.name.isEmpty ? name : uploaded.name,
        sizeBytes: bytes.length,
      );
    } on Object catch (error) {
      _update((s) => s.error = describeError(error, strings));
      return null;
    } finally {
      _update((s) => s.attachmentUploading = false);
    }
  }
}
