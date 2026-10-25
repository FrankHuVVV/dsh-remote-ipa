/// 输入框两个补全面板的判据 —— 移植自鸿蒙版 `core/ComposerSuggestions.ts`。
///
/// 判据抽出来而不是写在界面里：面板可见性有两处消费者（画面板、关手势），
/// 各写一份迟早会漂移；过滤/排序/限量是纯字符串逻辑，值得单测。
library;

import 'mention_query.dart';
import 'models.dart';

/// `@` 面板候选上限（列表可滚动，截太狠等于让人找不到）。
const int mentionLimit = 50;

/// `/` 命令面板候选上限（命令本来就少）。
const int commandLimit = 5;

/// `@` 面板此刻列出的候选：目录优先，其次按小写名升序。
List<FileEntry> mentionMatches(List<FileEntry>? entries, String query) {
  if (entries == null) {
    return const <FileEntry>[];
  }
  final lower = query.toLowerCase();
  final matched = <FileEntry>[
    for (final entry in entries)
      if (entry.name.toLowerCase().contains(lower)) entry,
  ];
  matched.sort((FileEntry a, FileEntry b) {
    final aDir = a.isDirectory();
    final bDir = b.isDirectory();
    if (aDir != bDir) {
      return aDir ? -1 : 1;
    }
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return matched.take(mentionLimit).toList();
}

/// `/` 命令面板此刻会显示哪几条（空 = 不显示）。
///
/// 判据：整行以斜杠开头，且斜杠之后到末尾**没有空白**（中间一空格就说明在打参数）。
List<CommandDescriptor> commandSuggestions(String value, List<CommandDescriptor> commands) {
  if (!value.startsWith('/')) {
    return const <CommandDescriptor>[];
  }
  final query = value.substring(1);
  for (final ch in query.split('')) {
    if (isKotlinWhitespace(ch)) {
      return const <CommandDescriptor>[];
    }
  }
  final lower = query.toLowerCase();
  return <CommandDescriptor>[
    for (final command in commands)
      if (command.name.toLowerCase().startsWith(lower)) command,
  ].take(commandLimit).toList();
}

/// 输入框上方是否有补全面板开着。
///
/// 两个面板互斥：`/` 只在整行以斜杠开头时出，`@` 只在光标落在一个提及词里时出。
bool composerOverlayActive(String value, List<CommandDescriptor> commands) =>
    activeStart(value) != null || commandSuggestions(value, commands).isNotEmpty;
