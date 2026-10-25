/// 一条聊天消息 —— 移植自鸿蒙版 `ui/ChatMessage.ets` / `MessageParts.ets`。
///
/// 六种形态各有各的版式：用户气泡 / 助手正文 / 思考折叠 / 上下文折叠 / 工具卡片 / 失败行。
/// 判据一律来自 `ChatDisplayItem.kind`，界面不自己猜事件类型。
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../core/chat_presentation.dart';
import '../core/small_parts.dart';
import '../l10n/strings.dart';
import 'message_body.dart';

class ChatMessageView extends StatelessWidget {
  const ChatMessageView({
    super.key,
    required this.item,
    required this.strings,
    required this.showContext,
    required this.attachmentImages,
    required this.attachmentFailures,
    required this.attachmentLoading,
    required this.onLoadAttachment,
    required this.onAnswer,
    this.onExportImage,
    this.onFork,
  });

  final ChatDisplayItem item;
  final Strings strings;
  final bool showContext;
  final Map<String, List<int>> attachmentImages;
  final Map<String, String> attachmentFailures;
  final Set<String> attachmentLoading;
  final void Function(ChatAttachment attachment) onLoadAttachment;
  final void Function(String text) onAnswer;
  final Future<void> Function(String name, List<int> bytes)? onExportImage;
  final void Function(ChatDisplayItem item)? onFork;

  @override
  Widget build(BuildContext context) {
    switch (item.kind) {
      case ChatItemKind.user:
        return _user(context);
      case ChatItemKind.assistant:
        return _assistant(context);
      case ChatItemKind.reasoning:
        return _reasoning(context);
      case ChatItemKind.context:
        return showContext ? _context(context) : const SizedBox.shrink();
      case ChatItemKind.tool:
        return _tool(context);
      case ChatItemKind.failure:
        return _failure(context);
    }
  }

  Widget _meta(BuildContext context) {
    final label = chatTimeLabel(item.time);
    if (label == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.outline),
      ),
    );
  }

  Widget _attachments(BuildContext context) {
    if (item.attachments.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (final attachment in item.attachments)
            _attachment(context, attachment),
        ],
      ),
    );
  }

  Widget _attachment(BuildContext context, ChatAttachment attachment) {
    final scheme = Theme.of(context).colorScheme;
    final bytes = attachmentImages[attachment.attachmentId];
    final failure = attachmentFailures[attachment.attachmentId];
    final loading = attachmentLoading.contains(attachment.attachmentId);
    final name = attachment.name ?? attachment.mediaType;
    final isImage = attachment.mediaType.startsWith('image/') ||
        (attachment.handoffPath != null && attachment.mediaType.isNotEmpty);

    if (bytes != null && isImage) {
      return GestureDetector(
        onTap: () => _showFullImage(context, bytes, name),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.memory(
            Uint8List.fromList(bytes),
            width: 180,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          ),
        ),
      );
    }

    return InkWell(
      onTap: failure == null && !loading ? () => onLoadAttachment(attachment) : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              isImage ? Icons.image_outlined : Icons.attach_file,
              size: 16,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                failure ?? (loading ? '…' : name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: failure == null ? null : scheme.error),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFullImage(BuildContext context, List<int> bytes, String name) {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            InteractiveViewer(
              child: Image.memory(Uint8List.fromList(bytes), fit: BoxFit.contain),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(name, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  if (onExportImage != null) ...<Widget>[
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: () => onExportImage!(name, bytes),
                      child: Text(strings.get('save_to_files')),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _user(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        margin: const EdgeInsets.only(left: 48, top: 10),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
            bottomLeft: Radius.circular(14),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (item.body.isNotEmpty)
              SelectableText(
                item.body,
                style: TextStyle(color: scheme.onPrimaryContainer, height: 1.4),
              ),
            _attachments(context),
            if (item.seq > 0 && onFork != null)
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 15,
                  tooltip: strings.get('fork'),
                  onPressed: () => onFork!(item),
                  icon: Icon(Icons.call_split, color: scheme.onPrimaryContainer.withValues(alpha: 0.7)),
                ),
              ),
            _meta(context),
          ],
        ),
      ),
    );
  }

  Widget _assistant(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, right: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          MessageBodyView(
            body: item.body,
            strings: strings,
            onAnswer: onAnswer,
          ),
          if (item.streaming)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SizedBox(
                width: 45,
                child: LinearProgressIndicator(minHeight: 2),
              ),
            ),
          _meta(context),
        ],
      ),
    );
  }

  Widget _reasoning(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 8, right: 24),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: scheme.outlineVariant, width: 2)),
      ),
      padding: const EdgeInsets.only(left: 10),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 6),
          dense: true,
          title: Text(
            strings.get('reasoning'),
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          children: <Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(
                item.body,
                style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _context(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8, right: 24),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '${strings.get('context_injected')}${item.title == null ? '' : ' · ${item.title}'}',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
            if (item.body.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: SelectableText(
                  item.body,
                  maxLines: 6,
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _tool(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = item.title ?? strings.get('tools_ran');
    return Container(
      margin: const EdgeInsets.only(top: 8, right: 8),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          leading: Icon(
            item.tools.any((ToolCallDetail t) => t.failed) ? Icons.error_outline : Icons.terminal,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
          title: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          subtitle: item.body.isEmpty
              ? null
              : Text(
                  item.body,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
          children: <Widget>[
            for (final tool in item.tools) ToolCallTile(tool: tool, strings: strings),
            if (item.attachments.isNotEmpty) _attachments(context),
          ],
        ),
      ),
    );
  }

  Widget _failure(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final failure = item.failure;
    final title = failure == null
        ? strings.get('turn_failed_title')
        : strings.get(failure.titleKey);
    final code = failure?.code;
    return Container(
      margin: const EdgeInsets.only(top: 10, right: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.error.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.report_gmailerrorred, size: 18, color: scheme.error),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onErrorContainer),
              ),
            ],
          ),
          if (failure != null && failure.message.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SelectableText(
                failure.message,
                style: TextStyle(fontSize: 12.5, color: scheme.onErrorContainer),
              ),
            ),
          if (code != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: SelectableText(
                strings.format('error_code', <String, String>{'code': code}),
                style: TextStyle(fontSize: 11, color: scheme.onErrorContainer.withValues(alpha: 0.8)),
              ),
            ),
        ],
      ),
    );
  }
}

/// 一次工具调用的明细：参数原文（美化后）+ 结果 + 成败 + 耗时。
class ToolCallTile extends StatelessWidget {
  const ToolCallTile({super.key, required this.tool, required this.strings});

  final ToolCallDetail tool;
  final Strings strings;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final duration = tool.durationMs;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  tool.name.isEmpty ? 'tool' : tool.name,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              if (duration != null)
                Text(
                  formatToolDuration(duration),
                  style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                ),
              if (tool.failed)
                Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(Icons.close, size: 13, color: scheme.error),
                ),
            ],
          ),
          if (tool.argumentsJson.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              prettyToolArguments(tool.argumentsJson),
              style: const TextStyle(fontFamily: 'Menlo', fontSize: 11, height: 1.4),
            ),
          ],
          if (tool.result != null && tool.result!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              '→',
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
            SelectableText(
              tool.result!,
              style: const TextStyle(fontFamily: 'Menlo', fontSize: 11, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}
