/// 文件页 —— 移植自鸿蒙版 `ui/FilesScreen.ets` / `EditorPane.ets` 的浏览 + 预览 + 编辑。
///
/// 客户端**不拥有**服务器的绝对路径：所有读写都用「rootId + 相对路径」，
/// 授权边界永远由服务端判定（`PATH_OUTSIDE_ROOTS` 是正常结果，不是故障）。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/models.dart';
import '../core/small_parts.dart';
import '../l10n/strings.dart';
import '../state/harness_state.dart';
import '../state/harness_view_model.dart';
import 'markdown_view.dart';
import 'widgets.dart';

class FilesScreen extends StatelessWidget {
  const FilesScreen({super.key, required this.viewModel});

  final HarnessViewModel viewModel;

  Strings get s => viewModel.strings;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: viewModel,
      builder: (BuildContext context, _) {
        final state = viewModel.state;
        final roots = state.roots;
        return Scaffold(
          appBar: AppBar(
            title: Text(s.get('files_title')),
            actions: <Widget>[
              if (roots.length > 1)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.folder_outlined),
                  tooltip: s.get('roots'),
                  onSelected: viewModel.selectRoot,
                  itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                    for (final root in roots)
                      PopupMenuItem<String>(value: root.id, child: Text(root.label)),
                  ],
                ),
              IconButton(
                tooltip: s.get('upload'),
                onPressed: roots.isEmpty ? null : () => _upload(context),
                icon: const Icon(Icons.upload_file_outlined),
              ),
              IconButton(
                tooltip: s.get('trash'),
                onPressed: () => _openTrash(context),
                icon: const Icon(Icons.delete_outline),
              ),
              IconButton(
                tooltip: s.get('refresh'),
                onPressed: roots.isEmpty ? null : () => viewModel.openDirectory(state.currentPath),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: Column(
            children: <Widget>[
              if (state.error != null) ErrorBar(message: state.error!, onDismiss: viewModel.clearError),
              if (state.fileError != null)
                ErrorBar(message: state.fileError!, onDismiss: () => viewModel.openDirectory(state.currentPath)),
              if (roots.isEmpty)
                EmptyState(text: s.get('no_roots'))
              else ...<Widget>[
                _breadcrumb(context, state),
                Expanded(child: _list(context, state)),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _breadcrumb(BuildContext context, HarnessState state) {
    final scheme = Theme.of(context).colorScheme;
    final rootLabel = state.roots
        .where((RootView root) => root.id == state.selectedRootId)
        .map((RootView root) => root.label)
        .fold<String>('', (String acc, String label) => label);
    final segments = state.currentPath.split('/').where((String part) => part.isNotEmpty).toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: <Widget>[
            InkWell(
              onTap: () => viewModel.openDirectory(''),
              child: Text(
                rootLabel.isEmpty ? '/' : rootLabel,
                style: TextStyle(fontSize: 12, color: scheme.primary),
              ),
            ),
            for (var i = 0; i < segments.length; i++) ...<Widget>[
              const Text(' / ', style: TextStyle(fontSize: 12)),
              InkWell(
                onTap: () => viewModel.openDirectory(segments.take(i + 1).join('/')),
                child: Text(
                  segments[i],
                  style: TextStyle(
                    fontSize: 12,
                    color: i == segments.length - 1 ? scheme.onSurface : scheme.primary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _list(BuildContext context, HarnessState state) {
    final directory = state.directory;
    if (state.fileLoading && directory == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (directory == null) {
      return EmptyState(text: s.get('empty_directory'));
    }
    final entries = directory.entries;
    return ListView.separated(
      itemCount: entries.length + (state.currentPath.isEmpty ? 0 : 1),
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (BuildContext context, int index) {
        if (state.currentPath.isNotEmpty && index == 0) {
          return ListTile(
            leading: const Icon(Icons.arrow_upward, size: 18),
            title: Text(s.get('parent_directory'), style: const TextStyle(fontSize: 13)),
            onTap: () {
              final parts = state.currentPath.split('/')..removeLast();
              viewModel.openDirectory(parts.where((String p) => p.isNotEmpty).join('/'));
            },
          );
        }
        final entry = entries[state.currentPath.isEmpty ? index : index - 1];
        return ListTile(
          leading: Text(
            entry.isDirectory() ? '📁' : _fileGlyph(entry.name),
            style: const TextStyle(fontSize: 18),
          ),
          title: Text(entry.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: entry.isDirectory()
              ? null
              : Text(
                  formatBytes(entry.size),
                  style: const TextStyle(fontSize: 11),
                ),
          onTap: () async {
            if (entry.isDirectory()) {
              await viewModel.openDirectory(entry.path);
            } else {
              await viewModel.openFile(entry);
              if (context.mounted) {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (BuildContext context) => FileViewerScreen(viewModel: viewModel),
                  ),
                );
              }
            }
          },
        );
      },
    );
  }

  Future<void> _upload(BuildContext context) async {
    try {
      final file = await FilePicker.pickFile();
      if (file == null) {
        return;
      }
      final bytes = await file.readAsBytes();
      await viewModel.uploadIntoCurrentDirectory(file.name, bytes);
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.get('io_error').replaceAll('{reason}', '$error'))),
        );
      }
    }
  }

  void _openTrash(BuildContext context) {
    unawaited(viewModel.refreshTrash());
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) => AnimatedBuilder(
        animation: viewModel,
        builder: (BuildContext context, _) {
          final entries = viewModel.state.trash;
          return SafeArea(
            child: entries.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(child: Text(s.get('no_trash'))),
                  )
                : ListView(
                    shrinkWrap: true,
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Text(s.get('trash'),
                            style: Theme.of(context).textTheme.titleMedium),
                      ),
                      for (final entry in entries)
                        ListTile(
                          dense: true,
                          leading: const Text('🗑', style: TextStyle(fontSize: 15)),
                          title: Text(entry.path,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13)),
                          subtitle: Text(formatBytes(entry.size),
                              style: const TextStyle(fontSize: 11)),
                          trailing: TextButton(
                            onPressed: () => viewModel.restoreTrashEntry(entry.id),
                            child: Text(s.get('restore')),
                          ),
                        ),
                    ],
                  ),
          );
        },
      ),
    );
  }
  String _fileGlyph(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.md') || lower.endsWith('.markdown')) return '📝';
    if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.heic')) {
      return '🖼️';
    }
    if (lower.endsWith('.json') || lower.endsWith('.yaml') || lower.endsWith('.yml')) return '🧾';
    return '📄';
  }
}

/// 单文件预览 / 编辑页。
class FileViewerScreen extends StatefulWidget {
  const FileViewerScreen({super.key, required this.viewModel});

  final HarnessViewModel viewModel;

  @override
  State<FileViewerScreen> createState() => _FileViewerScreenState();
}

class _FileViewerScreenState extends State<FileViewerScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _preview = true;
  bool _seeded = false;

  HarnessViewModel get vm => widget.viewModel;
  Strings get s => vm.strings;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: vm,
      builder: (BuildContext context, _) {
        final document = vm.state.document;
        if (!_seeded && document?.text != null) {
          _controller.text = document!.text!;
          _seeded = true;
        }
        final name = document?.entry.name ?? '';
        final isMarkdown = name.toLowerCase().endsWith('.md') || name.toLowerCase().endsWith('.markdown');
        final canEdit = document != null && document.text != null && !document.skippedForSize;
        return Scaffold(
          appBar: AppBar(
            title: Text(name.isEmpty ? s.get('file_preview') : name),
            actions: <Widget>[
              if (isMarkdown && document?.text != null)
                IconButton(
                  tooltip: _preview ? s.get('source') : s.get('markdown_preview'),
                  onPressed: () => setState(() => _preview = !_preview),
                  icon: Icon(_preview ? Icons.code : Icons.visibility_outlined),
                ),
              IconButton(
                tooltip: s.get('export'),
                onPressed: document == null ? null : () => vm.exportCurrentDocument(),
                icon: const Icon(Icons.ios_share),
              ),
              if (canEdit && (!isMarkdown || !_preview))
                TextButton(
                  onPressed: () async {
                    final ok = await vm.saveDocument(_controller.text);
                    if (ok && mounted) {
                      setState(() => _seeded = false);
                    }
                  },
                  child: Text(s.get('file_save')),
                ),
            ],
          ),
          body: _body(context, document, isMarkdown),
        );
      },
    );
  }

  Widget _body(BuildContext context, OpenDocument? document, bool isMarkdown) {
    final scheme = Theme.of(context).colorScheme;
    if (document == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (document.skippedForSize) {
      return EmptyState(
        text: s.get('file_too_large'),
      );
    }
    final isImage = (document.contentType ?? '').startsWith('image/');
    if (isImage) {
      final bytes = document.bytes;
      if (bytes == null) {
        return EmptyState(text: s.get('binary_file'));
      }
      return InteractiveViewer(
        child: Center(child: Image.memory(Uint8List.fromList(bytes), fit: BoxFit.contain)),
      );
    }
    final text = document.text;
    if (text == null) {
      return EmptyState(text: s.get('binary_file'));
    }
    if (isMarkdown && _preview) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: MarkdownView(text),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(10),
      child: TextField(
        controller: _controller,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        style: const TextStyle(fontFamily: 'Menlo', fontSize: 12.5, height: 1.45),
        decoration: InputDecoration(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          filled: true,
          fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.25),
        ),
        onChanged: (String value) => _seeded = true,
      ),
    );
  }
}
