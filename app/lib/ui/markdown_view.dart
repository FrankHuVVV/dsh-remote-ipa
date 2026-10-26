/// Markdown 渲染 —— 用 Flutter 原生组件画 `MarkdownLite` 切出来的块。
///
/// **不使用 WebView**：聊天与文件预览里的不可信文本只变成文字、方块和 `Text`，
/// 拿不到任何执行权（见 `docs/decisions/ADR-0001-native-rendering-no-webview.md`）。
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/markdown_lite.dart';

class MarkdownView extends StatelessWidget {
  const MarkdownView(
    this.source, {
    super.key,
    this.shrinkWrap = true,
    this.textStyle,
    this.onOpenFile,
  });

  final String source;
  final bool shrinkWrap;
  final TextStyle? textStyle;

  /// 非 http(s) 链接的处理：聊天里的本地路径要交给 ViewModel 去 resolve + 预览，
  /// 而不是丢给系统浏览器（那只会打开一个空白页）。
  final void Function(String path)? onOpenFile;

  @override
  Widget build(BuildContext context) {
    final blocks = const MarkdownLite().parseBlocks(source);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
      children: <Widget>[
        for (var i = 0; i < blocks.length; i++)
          Padding(
            padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
            child: _block(context, blocks[i]),
          ),
      ],
    );
  }

  Widget _block(BuildContext context, MdBlock block) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    switch (block) {
      case MdHeading(:final level, :final text):
        final style = switch (level) {
          1 => theme.textTheme.titleLarge,
          2 => theme.textTheme.titleMedium,
          _ => theme.textTheme.titleSmall,
        };
        return Padding(
          padding: EdgeInsets.only(top: level == 1 ? 6 : 2, bottom: 2),
          child: _inline(context, text, style?.copyWith(fontWeight: FontWeight.w700)),
        );
      case MdParagraph(:final text):
        return _inline(context, text, textStyle ?? theme.textTheme.bodyMedium);
      case MdRule():
        return Divider(color: scheme.outlineVariant, height: 16);
      case MdQuote(:final text):
        return Container(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: scheme.primary.withValues(alpha: 0.5), width: 3)),
          ),
          padding: const EdgeInsets.only(left: 10),
          child: _inline(
            context,
            text,
            (textStyle ?? theme.textTheme.bodyMedium)?.copyWith(color: scheme.onSurfaceVariant),
          ),
        );
      case MdCode(:final language, :final code):
        return _codeBlock(context, language, code);
      case MdBullets(:final items):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final item in items)
              Padding(
                padding: EdgeInsets.only(left: item.level * 14.0, top: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 16,
                      child: Text(
                        item.marker == '-' || item.marker == '*' || item.marker == '+'
                            ? '•'
                            : item.marker,
                        style: textStyle ?? theme.textTheme.bodyMedium,
                      ),
                    ),
                    Expanded(
                      child: _inline(context, item.text, textStyle ?? theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
          ],
        );
      case MdOrdered(:final items):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final item in items)
              Padding(
                padding: EdgeInsets.only(left: item.level * 14.0, top: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 24,
                      child: Text(
                        '${item.number}.',
                        style: (textStyle ?? theme.textTheme.bodyMedium)
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                    Expanded(
                      child: _inline(context, item.text, textStyle ?? theme.textTheme.bodyMedium),
                    ),
                  ],
                ),
              ),
          ],
        );
      case MdTable(:final header, :final rows, :final alignments):
        return _table(context, header, rows, alignments);
    }
  }

  Widget _inline(BuildContext context, String text, TextStyle? style) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final spans = const MarkdownLite().parseInline(text);
    final base = style ?? theme.textTheme.bodyMedium ?? const TextStyle();
    return SelectableText.rich(
      TextSpan(
        children: <InlineSpan>[
          for (final span in spans)
            TextSpan(
              text: span.text,
              style: base.copyWith(
                fontWeight: span.strong ? FontWeight.w700 : null,
                fontStyle: span.emphasized ? FontStyle.italic : null,
                fontFamily: span.code ? 'Menlo' : null,
                backgroundColor: span.code ? scheme.surfaceContainerHighest : null,
                color: span.linkUrl != null ? scheme.primary : null,
                decoration: span.linkUrl != null ? TextDecoration.underline : null,
                decorationColor: span.linkUrl != null ? scheme.primary : null,
              ),
              recognizer: span.linkUrl == null
                  ? null
                  : (TapGestureRecognizer()..onTap = () => _handleLink(context, span.linkUrl!)),
            ),
        ],
      ),
      style: base,
    );
  }

  Widget _codeBlock(BuildContext context, String language, String code) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 6, 0),
            child: Row(
              children: <Widget>[
                Text(
                  language.isEmpty ? 'code' : language,
                  style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                ),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  iconSize: 16,
                  tooltip: 'Copy',
                  onPressed: () => Clipboard.setData(ClipboardData(text: code)),
                  icon: const Icon(Icons.copy_all_outlined),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: SelectableText(
              code,
              style: const TextStyle(fontFamily: 'Menlo', fontSize: 12.5, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _table(BuildContext context, List<String> header, List<List<String>> rows, List<String> alignments) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final columns = header.isEmpty ? 1 : header.length;

    Widget cell(String text, int index, {bool isHeader = false}) {
      final align = index < alignments.length ? alignments[index] : 'n';
      final alignment = align == 'r'
          ? TextAlign.right
          : (align == 'c' ? TextAlign.center : TextAlign.left);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(
          text,
          textAlign: alignment,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: isHeader ? FontWeight.w700 : null,
            backgroundColor: isHeader ? scheme.surfaceContainerHighest : null,
          ),
        ),
      );
    }

    // 横向滚动会给出**无界宽度**，这时候 `FlexColumnWidth` 会把每一列压到接近 0，
    // 于是每个字符各占一行（真机上看到的就是一列竖排文字）。
    // 所以列宽必须自己算成固定值：装得下就铺满，装不下就横向滚。
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final available = constraints.maxWidth.isFinite ? constraints.maxWidth : 320.0;
        final widthPerColumn = (available / columns).clamp(96.0, 320.0).toDouble();
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: widthPerColumn * columns,
            child: Table(
              defaultColumnWidth: FixedColumnWidth(widthPerColumn),
              border: TableBorder.all(color: scheme.outlineVariant, width: 0.6),
              children: <TableRow>[
                TableRow(
                  decoration: BoxDecoration(color: scheme.surfaceContainerHighest.withValues(alpha: 0.5)),
                  children: <Widget>[
                    for (var i = 0; i < columns; i++)
                      cell(i < header.length ? header[i] : '', i, isHeader: true),
                  ],
                ),
                for (final row in rows)
                  TableRow(
                    children: <Widget>[
                      for (var i = 0; i < columns; i++) cell(i < row.length ? row[i] : '', i),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleLink(BuildContext context, String target) async {
    final lower = target.toLowerCase();
    final isWeb = lower.startsWith('http://') || lower.startsWith('https://');
    if (!isWeb) {
      // 模型回复里的「路径链接」：交给上层（ViewModel）去 resolvePath + 预览。
      final handler = onOpenFile;
      if (handler != null) {
        handler(target);
        return;
      }
    }
    final uri = Uri.tryParse(target);
    if (uri == null) {
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(target)));
    }
  }
}
