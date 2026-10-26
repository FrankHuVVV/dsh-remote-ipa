/// 一条消息正文的渲染：Markdown 文字段 + `dsh-ui` 卡片段。
///
/// 切分规则见 `core/gen_ui.dart`：只有**闭合**的 dsh-ui 围栏才切成卡片；解析失败
/// 回落到原始 JSON 代码块 —— 内容不丢，也不会因为一张坏卡片让整条消息消失。
library;

import 'package:flutter/material.dart';

import '../core/gen_ui.dart';
import '../l10n/strings.dart';
import 'gen_ui_card.dart';
import 'markdown_view.dart';

class MessageBodyView extends StatelessWidget {
  const MessageBodyView({
    super.key,
    required this.body,
    required this.strings,
    required this.onAnswer,
    this.enableGenUi = true,
    this.onOpenFile,
  });

  final String body;
  final Strings strings;
  final void Function(String text) onAnswer;
  final bool enableGenUi;

  /// 本地路径链接（模型回复里的图片/文件）交给上层预览。
  final void Function(String path)? onOpenFile;

  @override
  Widget build(BuildContext context) {
    if (!enableGenUi) {
      return MarkdownView(body, onOpenFile: onOpenFile);
    }
    final segments = splitMessageBody(body);
    if (segments.length == 1 && segments.first.kind == MessageSegmentKind.prose) {
      return MarkdownView(segments.first.text, onOpenFile: onOpenFile);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final segment in segments)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: switch (segment.kind) {
              MessageSegmentKind.prose => MarkdownView(segment.text, onOpenFile: onOpenFile),
              MessageSegmentKind.ui => _card(context, segment.text),
            },
          ),
      ],
    );
  }

  Widget _card(BuildContext context, String json) {
    final spec = parseGenUi(json);
    if (spec == null) {
      // 坏卡片：整段原文照显示。比「卡片凭空消失」诚实得多。
      final scheme = Theme.of(context).colorScheme;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              strings.get('genui_fallback'),
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            SelectableText(
              json,
              style: const TextStyle(fontFamily: 'Menlo', fontSize: 11, height: 1.4),
            ),
          ],
        ),
      );
    }
    return GenUiCardView(spec: spec, onAnswer: onAnswer, strings: strings);
  }
}
