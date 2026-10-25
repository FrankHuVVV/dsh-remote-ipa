/// 渲染一份 `dsh-ui` spec —— 移植自鸿蒙版 `ui/GenUiCard.ets`。
///
/// 三条不许简化的点：
/// 1. **未知组件整条丢弃**，不画空壳（空壳比不画更像界面坏了）；
/// 2. **交互组件真的能回话**：`radio`/`submit`/`button` 点下去把答案当普通用户消息发进会话；
/// 3. **表格横向滚动容器套在表格外面**，列宽由 [genUiTableColumnWidth] 定死，否则列会叠成一团。
///
/// 与鸿蒙版的一处平台差异：那边没有成对容器色，语气色只能画竖条 + 标题；
/// Flutter 有 `*Container` 成对色，这里可以直接给 `callout` 上容器底色。
library;

import 'package:flutter/material.dart';

import '../core/gen_ui.dart';
import '../l10n/strings.dart';

class GenUiCardView extends StatefulWidget {
  const GenUiCardView({
    super.key,
    required this.spec,
    required this.onAnswer,
    required this.strings,
  });

  final GenUiSpec spec;

  /// 交互组件的回话：调用方把它当一条普通用户消息发出去。
  final void Function(String text) onAnswer;
  final Strings strings;

  @override
  State<GenUiCardView> createState() => _GenUiCardViewState();
}

class _GenUiCardViewState extends State<GenUiCardView> {
  /// 节点键 → 当前选中项（`radio` / `submit`）。
  final Map<String, int> _selected = <String, int>{};

  String _key(GenUiNode node, int index) => '$index-${node.type}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final width = constraints.maxWidth.isFinite ? constraints.maxWidth : 320.0;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (widget.spec.title != null && widget.spec.title!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    inlineMarkup(widget.spec.title!),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
              for (var i = 0; i < widget.spec.items.length; i++)
                Padding(
                  padding: EdgeInsets.only(top: i == 0 ? 0 : 8),
                  child: _node(context, widget.spec.items[i], i, width),
                ),
            ],
          ),
        );
      },
    );
  }

  Color _toneColor(String? tone, {bool badge = false}) {
    final scheme = Theme.of(context).colorScheme;
    switch (tone) {
      case 'error':
      case 'danger':
        return scheme.error;
      case 'warning':
      case 'warn':
        return const Color(0xFFB26A00);
      case 'success':
        return const Color(0xFF2E7D32);
      default:
        return badge ? scheme.primary : scheme.onSurfaceVariant;
    }
  }

  Widget _node(BuildContext context, GenUiNode node, int index, double availableWidth) {
    final scheme = Theme.of(context).colorScheme;
    final key = _key(node, index);
    switch (node.type) {
      case 'text':
        final size = switch (genUiStr(node, 'size')) {
          'h1' => 26.0,
          'h2' => 22.0,
          'h3' => 18.0,
          'muted' => 15.0,
          'caption' => 12.0,
          _ => 15.0,
        };
        final muted = genUiStr(node, 'size') == 'muted' || genUiStr(node, 'size') == 'caption';
        return Text(
          genUiInlineText(node),
          style: TextStyle(fontSize: size, height: 1.45, color: muted ? scheme.onSurfaceVariant : null),
        );
      case 'list':
      case 'timeline':
        return _list(node);
      case 'keyvalue':
        return _keyValue(node);
      case 'table':
        return _table(node, availableWidth);
      case 'callout':
        return _callout(node);
      case 'steps':
        return _steps(node);
      case 'stat':
        return _stat(node);
      case 'badge':
        return _badge(node);
      case 'progress':
        return _progress(node);
      case 'chart':
        return _chart(node);
      case 'code':
      case 'json':
        return _code(node, node.type == 'json' ? 'json' : genUiStr(node, 'lang'));
      case 'diff':
        return _diff(node);
      case 'divider':
        return Divider(color: scheme.outlineVariant, height: 12);
      case 'spacer':
        return const SizedBox(height: 8);
      case 'card':
        return _layout(node, 'col', index, availableWidth);
      case 'row':
      case 'col':
      case 'grid':
        return _layout(node, node.type, index, availableWidth);
      case 'button':
        return _button(node);
      case 'radio':
      case 'submit':
        return _form(node, key);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _list(GenUiNode node) {
    final scheme = Theme.of(context).colorScheme;
    final items = genUiListItems(node);
    final title = genUiTitle(node);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (title != null && title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(inlineMarkup(title),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('·', style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant)),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(item.title, style: const TextStyle(fontSize: 15)),
                      if (item.desc != null && item.desc!.isNotEmpty)
                        Text(item.desc!,
                            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _keyValue(GenUiNode node) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final pair in genUiPairs(node))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(
                  width: 110,
                  child: Text(pair.key,
                      style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant)),
                ),
                Expanded(child: Text(pair.value, style: const TextStyle(fontSize: 14))),
              ],
            ),
          ),
      ],
    );
  }

  Widget _table(GenUiNode node, double availableWidth) {
    final scheme = Theme.of(context).colorScheme;
    final columns = genUiTableColumns(node);
    if (columns.isEmpty) {
      return const SizedBox.shrink();
    }
    final rows = genUiTableRows(node);
    final columnWidth = genUiTableColumnWidth(availableWidth - 24, columns.length);
    final title = genUiTitle(node);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (title != null && title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(inlineMarkup(title),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        // 横向滚动容器必须在表格**外面**：套进表格会破坏列宽计算。
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                child: Row(
                  children: <Widget>[
                    for (final column in columns)
                      SizedBox(
                        width: columnWidth,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(column,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                      ),
                  ],
                ),
              ),
              Divider(height: 1, color: scheme.outlineVariant),
              for (final row in rows)
                Row(
                  children: <Widget>[
                    for (var i = 0; i < columns.length; i++)
                      SizedBox(
                        width: columnWidth,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(i < row.length ? row[i] : '',
                              style: const TextStyle(fontSize: 12)),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _callout(GenUiNode node) {
    final scheme = Theme.of(context).colorScheme;
    final tone = _toneColor(genUiStr(node, 'tone'));
    final title = genUiTitle(node);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: tone, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (title != null && title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(inlineMarkup(title),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: tone)),
            ),
          Text(genUiInlineText(node), style: const TextStyle(fontSize: 15, height: 1.45)),
        ],
      ),
    );
  }

  Widget _steps(GenUiNode node) {
    final scheme = Theme.of(context).colorScheme;
    final steps = genUiSteps(node);
    final current = genUiInt(node, 'current') ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < current ? scheme.primary : scheme.surfaceContainerHighest,
                  ),
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontSize: 12,
                      color: i < current ? scheme.onPrimary : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(steps[i].key,
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                      if (steps[i].value != null && steps[i].value!.isNotEmpty)
                        Text(steps[i].value!,
                            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _stat(GenUiNode node) {
    final scheme = Theme.of(context).colorScheme;
    final label = genUiStr(node, 'label');
    final delta = genUiStr(node, 'delta');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (label != null)
          Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text(genUiStr(node, 'value') ?? '',
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w600)),
            if (delta != null)
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 3),
                child: Text(
                  delta,
                  style: TextStyle(
                    fontSize: 14,
                    color: delta.startsWith('-') ? scheme.error : const Color(0xFF2E7D32),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _badge(GenUiNode node) {
    final tone = _toneColor(genUiStr(node, 'tone'), badge: true);
    final icon = genUiStr(node, 'icon');
    final label = genUiStr(node, 'label') ?? '';
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(icon == null ? label : '$icon $label',
            style: TextStyle(fontSize: 12, color: tone)),
      ),
    );
  }

  Widget _progress(GenUiNode node) {
    final value = genUiNumber(node, 'value');
    if (value == null) {
      // 读不出 value 就整条不画：一个 0% 的条会让人以为任务没开始。
      return const SizedBox.shrink();
    }
    final label = genUiStr(node, 'label');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (label != null) Text(label, style: const TextStyle(fontSize: 15)),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: (value / 100).clamp(0.0, 1.0)),
      ],
    );
  }

  Widget _chart(GenUiNode node) {
    final scheme = Theme.of(context).colorScheme;
    final bars = genUiBars(node);
    if (bars.isEmpty) {
      return const SizedBox.shrink();
    }
    var max = 0.0;
    var total = 0.0;
    for (final bar in bars) {
      if (bar.value > max) {
        max = bar.value.toDouble();
      }
      total += bar.value;
    }
    if (max <= 0) {
      max = 1;
    }
    final donut = genUiStr(node, 'kind') == 'donut';
    final title = genUiTitle(node);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (title != null && title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(inlineMarkup(title),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        for (final bar in bars)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(child: Text(bar.key, style: const TextStyle(fontSize: 12))),
                    Text(
                      donut
                          ? '${total == 0 ? 0 : (bar.value / total * 100).truncate()}% · ${formatGenUiNumber(bar.value)}'
                          : formatGenUiNumber(bar.value),
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                LinearProgressIndicator(value: (bar.value / max).clamp(0.0, 1.0)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _code(GenUiNode node, String? lang) {
    final scheme = Theme.of(context).colorScheme;
    final code = genUiStr(node, 'code') ?? genUiInlineText(node);
    if (code.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (lang != null && lang.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(lang,
                  style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(
              code,
              style: const TextStyle(fontFamily: 'Menlo', fontSize: 12, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _diff(GenUiNode node) {
    final scheme = Theme.of(context).colorScheme;
    final diffs = genUiDiffs(node);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final diff in diffs)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (diff.path != null)
                  Text(diff.path!,
                      style: const TextStyle(fontFamily: 'Menlo', fontSize: 11)),
                if (diff.oldText != null && diff.oldText!.trim().isNotEmpty)
                  Text('− ${diff.oldText}',
                      style: TextStyle(fontFamily: 'Menlo', fontSize: 11, color: scheme.error)),
                if (diff.newText != null && diff.newText!.trim().isNotEmpty)
                  Text('+ ${diff.newText}',
                      style: TextStyle(fontFamily: 'Menlo', fontSize: 11, color: scheme.primary)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _layout(GenUiNode node, String kind, int index, double availableWidth) {
    final scheme = Theme.of(context).colorScheme;
    final children = genUiChildren(node);
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    final title = genUiTitle(node);
    final inner = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (title != null && title.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(inlineMarkup(title),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        if (kind == 'row')
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              for (var i = 0; i < children.length; i++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i == children.length - 1 ? 0 : 8),
                    child: _node(context, children[i], index * 100 + i, availableWidth),
                  ),
                ),
            ],
          )
        else
          for (var i = 0; i < children.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 6),
              child: _node(context, children[i], index * 100 + i, availableWidth),
            ),
      ],
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: inner,
    );
  }

  Widget _button(GenUiNode node) {
    final label = genUiLabel(node) ?? '';
    if (label.isEmpty) {
      return const SizedBox.shrink();
    }
    final enabled = genUiStr(node, 'action') != null;
    return OutlinedButton(
      // 不带 action 就是禁用态（照网页版）：点了没反应只会被理解成 App 坏了。
      onPressed: enabled ? () => widget.onAnswer(label) : null,
      child: Text(label),
    );
  }

  Widget _form(GenUiNode node, String key) {
    final options = genUiListItems(node);
    if (options.isEmpty) {
      return const SizedBox.shrink();
    }
    final prompt = genUiLabel(node) ?? widget.strings.get('confirm');
    final defaultSelected = genUiStr(node, 'selected');
    final selected = _selected[key] ?? options.indexWhere((GenUiListItem o) => o.desc == defaultSelected);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (var i = 0; i < options.length; i++)
          InkWell(
            onTap: () => setState(() => _selected[key] = i),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: <Widget>[
                  Icon(
                    selected == i ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: Text(options[i].title, style: const TextStyle(fontSize: 15))),
                ],
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: FilledButton.tonal(
            onPressed: selected >= 0 ? () => widget.onAnswer(options[selected].title) : null,
            child: Text(prompt),
          ),
        ),
      ],
    );
  }
}
