/// 聊天页的输入区与补全（`chat_screen.dart` 的 part 扩展）。
///
/// 拆出来只为守住 900 行预算：这些方法仍然改同一份 `_ChatScreenState`
/// （`_composer` / `_attachments` / `s` / `vm`），行为与拆之前完全一致。
part of 'chat_screen.dart';

extension ChatComposerActions on _ChatScreenState {
  // ————————————————— 输入区 —————————————————

  Widget _composerBar(BuildContext context, HarnessState state) {
    final session = state.currentSession;
    final running = session?.running ?? false;
    final steer = state.busySendMode == sendModeSteer;
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
        ),
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (_attachments.isNotEmpty)
              SizedBox(
                height: 44,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _attachments.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 6),
                  itemBuilder: (BuildContext context, int index) {
                    final attachment = _attachments[index];
                    return Chip(
                      label: Text(
                        attachment.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                      onDeleted: () => _refresh(() => _attachments.removeAt(index)),
                    );
                  },
                ),
              ),
            _suggestions(context, state),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                IconButton(
                  tooltip: s.get('attach'),
                  onPressed: () => _pickAttachment(context),
                  icon: state.attachmentUploading
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.add_circle_outline),
                ),
                if (running)
                  TextButton(
                    onPressed: () => vm.setSendMode(steer ? sendModeQueue : sendModeSteer),
                    child: Text(
                      steer ? s.get('steer') : s.get('queue'),
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                Expanded(
                  child: TextField(
                    controller: _composer,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    onChanged: (_) => _refresh(),
                    decoration: InputDecoration(
                      hintText: s.get('message_hint'),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  onPressed: running ? vm.cancelRun : _send,
                  icon: Icon(running ? Icons.stop : Icons.arrow_upward),
                  tooltip: running ? s.get('stop') : s.get('send'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send() async {
    final text = _composer.text;
    final trimmed = text.trim();
    if (trimmed.isEmpty && _attachments.isEmpty) {
      return;
    }
    if (trimmed.startsWith('/') && _attachments.isEmpty) {
      _composer.clear();
      _refresh();
      await vm.sendCommand(trimmed);
      return;
    }
    _composer.clear();
    final attachments = List<PendingAttachment>.of(_attachments);
    _refresh(_attachments.clear);
    await vm.sendMessage(text, attachments: attachments);
    if (mounted) {
      FocusScope.of(context).unfocus();
    }
  }

  Future<void> _pickAttachment(BuildContext context) async {
    final source = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(s.get('from_gallery')),
              onTap: () => Navigator.of(context).pop('gallery'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_open_outlined),
              title: Text(s.get('from_files')),
              onTap: () => Navigator.of(context).pop('files'),
            ),
          ],
        ),
      ),
    );
    if (source == null) {
      return;
    }
    if (source == 'gallery') {
      await _pickFromGallery();
      return;
    }
    try {
      // file_picker 13 的静态入口（旧版的 `FilePicker.platform.pickFiles` 已移除）。
      final file = await FilePicker.pickFile();
      if (file == null) {
        return;
      }
      final bytes = await file.readAsBytes();
      final lower = file.name.toLowerCase();
      final isImage = lower.endsWith('.png') ||
          lower.endsWith('.jpg') ||
          lower.endsWith('.jpeg') ||
          lower.endsWith('.gif') ||
          lower.endsWith('.webp') ||
          lower.endsWith('.heic');
      final PendingAttachment? attachment = isImage
          ? vm.makeImageAttachment(file.name, bytes)
          : await vm.uploadFileAttachment(file.name, bytes);
      if (attachment != null && mounted) {
        _refresh(() => _attachments.add(attachment));
      }
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.get('pick_file_failed').replaceAll('{reason}', '$error'))),
        );
      }
    }
  }


  Future<void> _pickFromGallery() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 2400,
        imageQuality: 92,
      );
      if (picked == null) {
        return;
      }
      final bytes = await picked.readAsBytes();
      final attachment = vm.makeImageAttachment(picked.name, bytes);
      if (attachment != null && mounted) {
        _refresh(() => _attachments.add(attachment));
      }
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.get('pick_file_failed').replaceAll('{reason}', '$error'))),
        );
      }
    }
  }

  // ————————————————— @ 文件 / `/` 命令补全 —————————————————

  Widget _suggestions(BuildContext context, HarnessState state) {
    final text = _composer.text;
    final scheme = Theme.of(context).colorScheme;
    final commands = commandSuggestions(text, state.commands);
    if (commands.isNotEmpty) {
      return _suggestionPanel(
        context,
        title: s.get('commands'),
        children: <Widget>[
          for (final command in commands)
            ListTile(
              dense: true,
              title: Text('/${command.name}', style: const TextStyle(fontSize: 14)),
              subtitle: command.description.isEmpty
                  ? null
                  : Text(command.description, style: const TextStyle(fontSize: 11)),
              onTap: () => _applyCommand(command),
            ),
        ],
      );
    }
    if (activeStart(text) == null) {
      return const SizedBox.shrink();
    }
    final entries = mentionMatches(state.mentionEntries, mentionQuery(text) ?? '');
    if (entries.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        child: Text(
          state.mentionFailed ? s.get('mention_failed') : s.get('mention_no_entries'),
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
      );
    }
    return _suggestionPanel(
      context,
      title: s.get('mention_hint'),
      children: <Widget>[
        for (final entry in entries)
          ListTile(
            dense: true,
            leading: Text(entry.isDirectory() ? '📁' : '📄', style: const TextStyle(fontSize: 15)),
            title: Text(entry.name, style: const TextStyle(fontSize: 13)),
            onTap: () => _applyMention(entry),
          ),
      ],
    );
  }

  Widget _suggestionPanel(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
            child: Text(title, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 4),
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  void _applyMention(FileEntry entry) {
    final path = vm.mentionAbsolutePath(entry);
    final suffix = entry.isDirectory() ? '/' : ' ';
    final next = applySelection(_composer.text, '$path$suffix');
    _composer.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    _refresh();
  }

  void _applyCommand(CommandDescriptor command) {
    final next = '/${command.name} ';
    _composer.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    _refresh();
  }
}
