/// 共享小组件 —— 品牌标、状态点、空态、错误条、分节标题。
///
/// 这些是「看一眼就知道在哪」的锚点：品牌标在连接页与抽屉里同一份实现，
/// 字形图标（💬 📁 🧩 🧠 ⚙）与鸿蒙版逐字相同，省掉两套图片资源。
library;

import 'package:flutter/material.dart';

import '../core/connection_models.dart';
import '../l10n/strings.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      alignment: Alignment.center,
      child: Text(
        'DSH',
        style: TextStyle(
          color: scheme.onPrimary,
          fontWeight: FontWeight.w800,
          fontSize: size * 0.3,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// 在线 / 离线小圆点 + 文字。
class StatusLabel extends StatelessWidget {
  const StatusLabel({super.key, required this.label, required this.active});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = active ? const Color(0xFF2E9E5B) : scheme.outline;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }
}

/// 分节图标字形（与鸿蒙版一致）。
String sectionGlyphFor(String section) {
  switch (section) {
    case 'chat':
      return '💬';
    case 'files':
      return '📁';
    case 'plugins':
      return '🧩';
    case 'models':
      return '🧠';
    default:
      return '⚙';
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle!,
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          if (action != null) ...<Widget>[const SizedBox(height: 12), action!],
        ],
      ),
    );
  }
}

/// 顶部错误条：`state.error` 的唯一出口（报完必须清掉，否则每次重绘都弹一遍）。
class ErrorBar extends StatelessWidget {
  const ErrorBar({super.key, required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          children: <Widget>[
            Icon(Icons.error_outline, size: 18, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: scheme.onErrorContainer, fontSize: 13),
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              icon: Icon(Icons.close, size: 18, color: scheme.onErrorContainer),
              tooltip: Strings.of('zh-CN').get('close'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 中性提示条（归档成功、插件需重启之类）。
class NoticeBar extends StatelessWidget {
  const NoticeBar({super.key, required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          children: <Widget>[
            Icon(Icons.info_outline, size: 18, color: scheme.onSecondaryContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(color: scheme.onSecondaryContainer, fontSize: 13),
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              icon: Icon(Icons.close, size: 18, color: scheme.onSecondaryContainer),
            ),
          ],
        ),
      ),
    );
  }
}

String endpointKindLabel(EndpointKind kind) {
  switch (kind) {
    case EndpointKind.lan:
      return 'LAN';
    case EndpointKind.virtualNet:
      return 'VPN';
    case EndpointKind.wan:
      return 'WAN';
    case EndpointKind.unknown:
      return '—';
  }
}

Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmLabel,
  String? cancelLabel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (BuildContext context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(cancelLabel ?? '取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel ?? '确定'),
        ),
      ],
    ),
  );
  return result ?? false;
}

Future<String?> textInputDialog(
  BuildContext context, {
  required String title,
  String initialValue = '',
  String? hint,
}) =>
    showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        final controller = TextEditingController(text: initialValue);
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(hintText: hint),
            onSubmitted: (String value) => Navigator.of(context).pop(value),
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
