/// 聊天页 —— 移植自鸿蒙版 `ui/ChatScreen.ets` / `ChatDetail.ets` / `ChatComposer.ets`。
///
/// 三条交互纪律（都来自源工程的真机反馈）：
/// 1. **审批住输入区上方**：内核正阻塞着等决定，把它藏进菜单等于让整轮卡死；
/// 2. **问答不顶掉输入框**：问题属于「补交」，Agent 已经继续跑了，所以是一张可折叠卡片；
/// 3. **滚动中不跟随**：用户往上翻历史时，新消息只更新未读计数，不抢滚动位置。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';

import '../core/chat_presentation.dart';
import '../core/composer_suggestions.dart';
import '../core/mention_query.dart';
import '../core/models.dart';
import '../core/permission_presets.dart';
import '../core/session_stats.dart';
import '../l10n/strings.dart';
import '../core/small_parts.dart';
import '../state/harness_state.dart';
import '../state/harness_view_model.dart';
import 'chat_message.dart';
import 'files_screen.dart';
import 'session_insights.dart';
import 'widgets.dart';

part 'chat_composer.dart';
part 'chat_insights.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.viewModel});

  final HarnessViewModel viewModel;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _composer = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<PendingAttachment> _attachments = <PendingAttachment>[];
  bool _nearBottom = true;
  int _lastItemCount = 0;

  HarnessViewModel get vm => widget.viewModel;
  Strings get s => vm.strings;

  @override
  void initState() {
    super.initState();
    vm.addListener(_onVmChanged);
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
  }

  @override
  void dispose() {
    vm.removeListener(_onVmChanged);
    _scroll.dispose();
    _composer.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) {
      return;
    }
    final position = _scroll.position;
    final nearBottom = position.maxScrollExtent - position.pixels < 80;
    if (nearBottom != _nearBottom) {
      setState(() => _nearBottom = nearBottom);
    }
  }

  void _onVmChanged() {
    final count = vm.state.visibleItems.length;
    if (count != _lastItemCount) {
      _lastItemCount = count;
      if (_nearBottom) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToBottom());
      }
    }
  }

  /// 供 part 扩展触发的重建（`setState` 是 protected，扩展里不能直接调）。
  void _refresh([VoidCallback? mutate]) {
    if (mutate == null) {
      setState(() {});
    } else {
      setState(mutate);
    }
  }

  void _jumpToBottom() {
    if (!_scroll.hasClients) {
      return;
    }
    _scroll.jumpTo(_scroll.position.maxScrollExtent);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: vm,
      builder: (BuildContext context, _) {
        final state = vm.state;
        final session = state.currentSession;
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  session == null || session.displayTitle().isEmpty
                      ? s.get('unnamed_session')
                      : session.displayTitle(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                Text(
                  _headerSubtitle(session),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            actions: <Widget>[
              _modelButton(context, state),
              IconButton(
                tooltip: s.get('todos'),
                onPressed: () => _showInsights(context),
                icon: const Icon(Icons.dashboard_customize_outlined),
              ),
              if (session != null && session.running)
                IconButton(
                  tooltip: s.get('cancel_run'),
                  onPressed: vm.cancelRun,
                  icon: const Icon(Icons.stop_circle_outlined),
                ),
              PopupMenuButton<String>(
                onSelected: (String value) => _onMenu(value, session),
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(value: 'rename', child: Text(s.get('rename'))),
                  PopupMenuItem<String>(value: 'fork', child: Text(s.get('fork'))),
                  PopupMenuItem<String>(value: 'archive', child: Text(s.get('archive'))),
                ],
              ),
            ],
          ),
          body: Column(
            children: <Widget>[
              if (state.error != null) ErrorBar(message: state.error!, onDismiss: vm.clearError),
              if (state.notice != null) NoticeBar(message: state.notice!, onDismiss: vm.clearNotice),
              _permissionBar(context, state),
              if (state.approvals.isNotEmpty) _approvalCard(context, state),
              if (state.questions.isNotEmpty) _questionCards(context, state),
              Expanded(child: _messages(context, state)),
              _composerBar(context, state),
            ],
          ),
        );
      },
    );
  }

  Widget _modelButton(BuildContext context, HarnessState state) {
    final current = state.sessionModels?.current;
    final label = current == null || current.model.isEmpty ? s.get('models') : current.model;
    return TextButton(
      onPressed: () => _showModelSheet(context),
      child: Text(label, style: const TextStyle(fontSize: 12)),
    );
  }

  Future<void> _onMenu(String value, ChatSession? session) async {
    final id = session?.id;
    if (id == null) {
      return;
    }
    switch (value) {
      case 'rename':
        final title = await textInputDialog(
          context,
          title: s.get('rename'),
          initialValue: session?.displayTitle() ?? '',
        );
        if (title != null && title.trim().isNotEmpty) {
          await vm.renameSession(id, title);
        }
        break;
      case 'fork':
        final ok = await confirmDialog(
          context,
          title: s.get('fork'),
          message: s.get('fork_confirm'),
          confirmLabel: s.get('confirm'),
          cancelLabel: s.get('cancel'),
        );
        if (ok) {
          await vm.forkSession(id);
        }
        break;
      case 'archive':
        await vm.archiveSession(id);
        if (mounted) {
          Navigator.of(context).maybePop();
        }
        break;
    }
  }

  Widget _messages(BuildContext context, HarnessState state) {
    if (state.history == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final items = state.visibleItems;
    if (items.isEmpty) {
      return EmptyState(text: s.get('empty_chat'));
    }
    final hasMore = state.history?.hasMore ?? false;
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      itemCount: items.length + (hasMore ? 1 : 0),
      itemBuilder: (BuildContext context, int index) {
        if (hasMore && index == 0) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: TextButton(
                onPressed: vm.loadOlder,
                child: Text(s.get('load_older')),
              ),
            ),
          );
        }
        final item = items[hasMore ? index - 1 : index];
        return ChatMessageView(
          item: item,
          strings: s,
          showContext: state.showContext,
          attachmentImages: state.attachmentImages,
          attachmentFailures: state.attachmentFailures,
          attachmentLoading: state.attachmentLoading,
          onLoadAttachment: vm.loadAttachment,
          onAnswer: (String text) => vm.sendMessage(text),
          onOpenPath: (String path) => unawaited(_openChatPath(path)),
          onSaveToAlbum: (String name, List<int> bytes) => _saveImageToAlbum(name, bytes),
          onExportImage: (String name, List<int> bytes) => vm.exportBytes(name, bytes),
          onFork: (ChatDisplayItem chatItem) async {
            final ok = await confirmDialog(
              context,
              title: s.get('fork'),
              message: s.get('fork_confirm'),
              confirmLabel: s.get('confirm'),
              cancelLabel: s.get('cancel'),
            );
            if (ok && chatItem.seq > 0) {
              await vm.forkSession(state.selectedSessionId!, atSeq: chatItem.seq);
            }
          },
        );
      },
    );
  }

  // ————————————————— 审批 —————————————————

  Widget _approvalCard(BuildContext context, HarnessState state) {
    final scheme = Theme.of(context).colorScheme;
    final approval = state.approvals.first;
    final deciding = state.approvalKind == ApprovalUiKind.deciding;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.tertiary.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.gpp_maybe_outlined, size: 18, color: scheme.onTertiaryContainer),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${s.get('approval_title')} · ${approval.toolName}',
                  style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onTertiaryContainer),
                ),
              ),
              if (state.approvals.length > 1)
                Text(
                  '1/${state.approvals.length}',
                  style: TextStyle(fontSize: 11, color: scheme.onTertiaryContainer),
                ),
            ],
          ),
          if (approval.reason != null && approval.reason!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SelectableText(
                approval.reason!,
                style: TextStyle(fontSize: 12.5, color: scheme.onTertiaryContainer),
              ),
            ),
          if (approval.detail != null && approval.detail!.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(6),
              ),
              child: SelectableText(
                approval.detail!,
                maxLines: 6,
                style: const TextStyle(fontFamily: 'Menlo', fontSize: 11),
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              FilledButton(
                onPressed: deciding ? null : () => vm.decideApproval(approval, allowOnce: true),
                child: Text(s.get('approval_allow_once')),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: deciding ? null : () => vm.decideApproval(approval, allowOnce: false),
                child: Text(s.get('approval_reject')),
              ),
              const Spacer(),
              if (deciding) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
        ],
      ),
    );
  }

  // ————————————————— 问答 —————————————————

  Widget _questionCards(BuildContext context, HarnessState state) {
    final scheme = Theme.of(context).colorScheme;
    final set = state.questions.first;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.secondary.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            s.get('question_title'),
            style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onSecondaryContainer),
          ),
          for (final question in set.questions)
            _questionField(context, set, question, state),
        ],
      ),
    );
  }

  Widget _questionField(
    BuildContext context,
    PendingQuestionSet set,
    ChatQuestion question,
    HarnessState state,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final answered = state.answeredCallIds.contains(set.callId);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            question.header == null ? question.question : '${question.header} · ${question.question}',
            style: TextStyle(fontSize: 13, color: scheme.onSecondaryContainer),
          ),
          const SizedBox(height: 6),
          if (question.options.isEmpty)
            _freeTextAnswer(context, set, question, answered)
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final option in question.options)
                  ActionChip(
                    label: Text(option.label, style: const TextStyle(fontSize: 12)),
                    onPressed: answered
                        ? null
                        : () => vm.answerQuestions(set.callId, <QuestionAnswer>[
                              QuestionAnswer(id: question.id, selected: <String>[option.label]),
                            ]),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _freeTextAnswer(
    BuildContext context,
    PendingQuestionSet set,
    ChatQuestion question,
    bool answered,
  ) {
    final controller = TextEditingController();
    return Row(
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: controller,
            enabled: !answered,
            decoration: InputDecoration(hintText: s.get('question_free_text')),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: answered
              ? null
              : () {
                  final text = controller.text.trim();
                  if (text.isEmpty) {
                    return;
                  }
                  vm.answerQuestions(set.callId, <QuestionAnswer>[
                    QuestionAnswer(id: question.id, selected: const <String>[], custom: text),
                  ]);
                },
          child: Text(s.get('question_submit')),
        ),
      ],
    );
  }

  // ————————————————— 头部 / 权限 / 图片路径 —————————————————

  String _headerSubtitle(ChatSession? session) {
    if (session == null) {
      return s.get('idle');
    }
    final parts = <String>[session.running ? s.get('running') : s.get('idle')];
    final workspace = session.workspaceTitle ?? (session.workspaceId == null ? '' : session.workspaceId!);
    if (workspace.isNotEmpty) {
      parts.add(workspace);
    }
    if (session.cwd.isNotEmpty) {
      parts.add(session.cwd);
    }
    return parts.join(' · ');
  }

  /// 会话内的权限档位按钮条。
  ///
  /// 候选项 = 目录（`/chat/permission-presets`）+ 内置四档（目录缺 `read-only` / `auto`）；
  /// 当前值优先取**会话投影**，所以 PC 端切到 auto 后手机上高亮也在 auto。
  Widget _permissionBar(BuildContext context, HarnessState state) {
    final catalog = state.permissionCatalog;
    final presets = permissionPresetsFor(catalog);
    final projection = state.history == null
        ? ''
        : (permissionSelectOf(state.history!)?.currentValue ?? '');
    final current = permissionCurrentValue(catalog: catalog, projectionValue: projection);
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        itemCount: presets.length,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (BuildContext context, int index) {
          final preset = presets[index];
          final selected = preset.value == current;
          return ChoiceChip(
            label: Text(
              preset.label(state.languageTag),
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
            selected: selected,
            showCheckmark: true,
            selectedColor: scheme.primaryContainer,
            side: BorderSide(
              color: selected ? scheme.primary : scheme.outlineVariant,
            ),
            onSelected: (_) => _confirmPermission(preset, catalog),
          );
        },
      ),
    );
  }

  Future<void> _confirmPermission(PermissionPreset preset, PermissionSelect? catalog) async {
    final projection = vm.state.history == null
        ? ''
        : (permissionSelectOf(vm.state.history!)?.currentValue ?? '');
    final current = permissionCurrentValue(catalog: catalog, projectionValue: projection);
    if (preset.value == current) {
      return;
    }
    final ok = await confirmDialog(
      context,
      title: s.get('switch_permission'),
      message: permissionPresetDescription(catalog, preset.value) ??
          preset.label(vm.state.languageTag),
      confirmLabel: s.get('confirm'),
      cancelLabel: s.get('cancel'),
    );
    if (ok) {
      await vm.selectPermissionPreset(preset.value);
    }
  }

  /// 把聊天里的图片存进系统相册（只申请「添加」权限，不申请读取整库）。
  Future<void> _saveImageToAlbum(String name, List<int> bytes) async {
    try {
      var granted = await Gal.hasAccess(toAlbum: true);
      if (!granted) {
        granted = await Gal.requestAccess(toAlbum: true);
      }
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.get('album_denied'))));
        }
        return;
      }
      final baseName = name.replaceAll(RegExp(r'\.[^./]+$'), '');
      await Gal.putImageBytes(Uint8List.fromList(bytes), name: baseName.isEmpty ? 'DSH' : baseName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.get('saved_to_album'))));
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.get('album_failed').replaceAll('{reason}', '$error'))),
        );
      }
    }
  }

  Future<void> _openChatPath(String path) async {
    final opened = await vm.openChatPath(path);
    if (!mounted) {
      return;
    }
    if (opened) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (BuildContext context) => FileViewerScreen(viewModel: vm),
        ),
      );
      return;
    }
    final failure = vm.state.fileError;
    if (failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure)));
    }
  }

  void _showModelSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) {
        return AnimatedBuilder(
          animation: vm,
          builder: (BuildContext context, _) {
            final models = vm.state.sessionModels;
            final current = models?.current;
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
                          child: Text(
                            s.get('session_models'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        StatusLabel(
                          label: models?.routable == true ? s.get('model_routable') : s.get('model_not_routable'),
                          active: models?.routable == true,
                        ),
                      ],
                    ),
                  ),
                  if (models == null)
                    EmptyState(text: s.get('loading'))
                  else
                    for (final group in models.groups) ...<Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                        child: Text(
                          group.name.isEmpty ? group.id : group.name,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      for (final model in group.models)
                        ListTile(
                          dense: true,
                          title: Text(model.name.isEmpty ? model.id : model.name),
                          subtitle: model.description == null ? null : Text(model.description!),
                          trailing: current != null &&
                                  current.provider == group.id &&
                                  current.model == model.id
                              ? const Icon(Icons.check, size: 18)
                              : null,
                          onTap: () async {
                            await vm.selectModel(ModelSelection(provider: group.id, model: model.id));
                            if (context.mounted) {
                              Navigator.of(context).pop();
                            }
                          },
                        ),
                    ],
                  if (models != null && models.failures.isNotEmpty) ...<Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(
                        s.get('model_failures'),
                        style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                    for (final failure in models.failures)
                      ListTile(
                        dense: true,
                        title: Text(failure.provider),
                        subtitle: Text(failure.message, style: const TextStyle(fontSize: 11)),
                      ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }
}
