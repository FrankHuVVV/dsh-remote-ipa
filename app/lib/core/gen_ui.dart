/// `dsh-ui` 卡片：正文切分 + 解析 —— 移植自鸿蒙版 `core/GenUiBlocks.ts`。
///
/// 三段式：**切分（[splitMessageBody]）→ 解析（[parseGenUi]）→ 分发（UI 层按 type 画）**。
///
/// 三条硬规则（每条都对应一个真实的坑）：
/// 1. **必须有闭合围栏才切**：流式输出时开头 ``` 已到、结尾还没到，此时切出去会得到半截
///    JSON，卡片解析必然失败；未闭合就整段按原文保留，退化为「显示原始代码块」。
/// 2. **只看行首的围栏头**：正文中间出现的 ``` 是代码块，不能当卡片边界。
/// 3. **围栏内容原样透传**：解析失败由 UI 回落到原始代码块，不能因为一张坏卡片让整条消息消失。
library;

import 'json.dart';
import 'text.dart';

const String _fenceMark = '```';
const String _langMark = 'dsh-ui';

final RegExp _whitespace = RegExp(r'[ \t]+');

enum MessageSegmentKind { prose, ui }

/// 正文里被切出来的一段：普通文字，或一个 dsh-ui 卡片（原始 JSON）。
class MessageSegment {
  const MessageSegment(this.kind, this.text);

  factory MessageSegment.prose(String text) => MessageSegment(MessageSegmentKind.prose, text);

  factory MessageSegment.ui(String json) => MessageSegment(MessageSegmentKind.ui, json);

  final MessageSegmentKind kind;
  final String text;
}

/// 一个组件节点：保留原始 JSON 供渲染器读取。
class GenUiNode {
  const GenUiNode(this.type, this.value);

  final String type;
  final Map<String, dynamic> value;
}

class GenUiSpec {
  const GenUiSpec({this.title, this.gap = 12, this.items = const <GenUiNode>[]});

  final String? title;
  final int gap;
  final List<GenUiNode> items;
}

/// 一条列表项（`items` 允许纯字符串，也允许 `{title,desc}` 对象）。
class GenUiListItem {
  const GenUiListItem(this.title, [this.desc]);

  final String title;
  final String? desc;
}

/// 只列「我们真的渲染了」的类型：认不得就整条跳过，而不是画个空壳。
const Set<String> genUiSupportedTypes = <String>{
  'text',
  'row',
  'col',
  'grid',
  'card',
  'divider',
  'spacer',
  'stat',
  'badge',
  'progress',
  'list',
  'table',
  'keyvalue',
  'timeline',
  'code',
  'json',
  'diff',
  'callout',
  'steps',
  'chart',
  'button',
  'radio',
  'submit',
};

/// 复刻 `JsonPrimitive.content` 家族：数字/布尔也给字符串，null 给空。
String _primitiveText(Object? value) {
  if (value is String) {
    return value;
  }
  if (value is num) {
    return '$value';
  }
  if (value is bool) {
    return value ? 'true' : 'false';
  }
  return '';
}

String _removePrefix(String value, String prefix) =>
    value.startsWith(prefix) ? value.substring(prefix.length) : value;

/// 围栏头是否是 dsh-ui 卡片：判据是标记里**含有** `dsh-ui`，不是位置或顺序。
///
/// 于是 ` ```dsh-ui ` 与 ` ```json dsh-ui ` 都认；` ```dsh-ui-bad ` 不认（否则会吞掉别的语言名）。
bool _isGenUiInfo(String line) {
  if (!line.startsWith(_fenceMark)) {
    return false;
  }
  final info = trimText(_removePrefix(trimText(line), _fenceMark));
  if (info.isEmpty) {
    return false;
  }
  return info.split(_whitespace).contains(_langMark);
}

/// 从 [from] 起找下一个 dsh-ui 围栏头的起始下标。
int? _fenceHeadAt(String body, int from) {
  var lineStart = from;
  while (lineStart <= body.length) {
    var lineEnd = body.indexOf('\n', lineStart);
    if (lineEnd < 0) {
      lineEnd = body.length;
    }
    final line = body.substring(lineStart, lineEnd);
    // 只认行首的围栏；缩进过的不是卡片边界。
    if (line.startsWith(_fenceMark) && _isGenUiInfo(line)) {
      return lineStart;
    }
    if (lineEnd >= body.length) {
      break;
    }
    lineStart = lineEnd + 1;
  }
  return null;
}

/// 把助手正文按 dsh-ui 围栏切开。未闭合 / 空卡片都不切。
List<MessageSegment> splitMessageBody(String body) {
  final segments = <MessageSegment>[];
  var cursor = 0;
  while (cursor < body.length) {
    final open = _fenceHeadAt(body, cursor);
    if (open == null) {
      break;
    }
    final headEnd = body.indexOf('\n', open);
    if (headEnd < 0) {
      return <MessageSegment>[MessageSegment.prose(body)];
    }
    final close = body.indexOf(_fenceMark, headEnd + 1);
    if (close < 0) {
      return <MessageSegment>[MessageSegment.prose(body)];
    }
    final before = trimText(body.substring(cursor, open));
    if (before.isNotEmpty) {
      segments.add(MessageSegment.prose(before));
    }
    final json = body.substring(headEnd + 1, close);
    if (isNotBlank(json)) {
      segments.add(MessageSegment.ui(json));
    }
    final after = body.indexOf('\n', close + _fenceMark.length);
    cursor = after < 0 ? body.length : after + 1;
  }
  final tail = trimText(body.substring(cursor));
  if (tail.isNotEmpty) {
    segments.add(MessageSegment.prose(tail));
  }
  if (segments.isEmpty) {
    return <MessageSegment>[MessageSegment.prose(body)];
  }
  return segments;
}

GenUiNode? _genUiNodeOf(Object? element) {
  final value = asMap(element);
  if (value == null) {
    return null;
  }
  final type = stringOrNull(value, 'type');
  if (type == null || !isNotBlank(type)) {
    return null;
  }
  if (!genUiSupportedTypes.contains(type)) {
    return null;
  }
  return GenUiNode(type, value);
}

/// 解析一段 dsh-ui JSON。返回 null = 这条卡片无法显示（UI 回落到原始代码块）。
GenUiSpec? parseGenUi(String source) {
  final root = parseMap(source);
  if (root == null) {
    return null;
  }
  final items = <GenUiNode>[];
  for (final raw in arr(root, 'items')) {
    final node = _genUiNodeOf(raw);
    if (node != null) {
      items.add(node);
    }
  }
  if (items.isEmpty) {
    return null;
  }
  return GenUiSpec(
    title: stringOrNull(root, 'title'),
    gap: intOrNull(root, 'gap') ?? 12,
    items: items,
  );
}

/// `items` 里的子节点；布局容器（row/col/grid/card）用。
List<GenUiNode> genUiChildren(GenUiNode node) => <GenUiNode>[
      for (final raw in arr(node.value, 'items'))
        if (_genUiNodeOf(raw) != null) _genUiNodeOf(raw)!,
    ];

/// `list` 的条目：先按原语看，再按对象取标题；标题为空白的条目丢弃。
List<GenUiListItem> genUiListItems(GenUiNode node) {
  final out = <GenUiListItem>[];
  for (final entry in arr(node.value, 'items')) {
    final text = (entry is String || entry is num || entry is bool) ? _primitiveText(entry) : null;
    if (text != null) {
      if (isNotBlank(text)) {
        out.add(GenUiListItem(text));
      }
      continue;
    }
    final map = asMap(entry);
    if (map == null) {
      continue;
    }
    final title = stringOrNull(map, 'title') ??
        stringOrNull(map, 'label') ??
        stringOrNull(map, 'content');
    if (title == null || isBlank(title)) {
      continue;
    }
    out.add(GenUiListItem(title, stringOrNull(map, 'desc')));
  }
  return out;
}

/// `button` 的文案。
String? genUiLabel(GenUiNode node) =>
    stringOrNull(node.value, 'label') ??
    stringOrNull(node.value, 'content') ??
    stringOrNull(node.value, 'title');

/// 卡片式节点的标题。
String? genUiTitle(GenUiNode node) =>
    stringOrNull(node.value, 'title') ?? stringOrNull(node.value, 'label');

String? genUiStr(GenUiNode node, String key) => stringOrNull(node.value, key);

int? genUiInt(GenUiNode node, String key) => intOrNull(node.value, key);

num? genUiNumber(GenUiNode node, String key) => numOrNull(node.value, key);

bool? genUiBool(GenUiNode node, String key) => boolOrNull(node.value, key);

/// 剥离行内标记：`**` / `==` / 反引号 / 链接 / 删除线 / 单星斜体。
///
/// **刻意不认下划线系**：`_` 在标识符里大量出现（`entry_default`、`__init__`），
/// 正则判断不出词边界，会把变量名改得面目全非。少认两种写法好过改坏正文。
String inlineMarkup(String raw) => raw
    .replaceAll('**', '')
    .replaceAll('==', '')
    .replaceAllMapped(RegExp(r'`([^`]*)`'), (Match m) => m.group(1) ?? '')
    .replaceAllMapped(RegExp(r'!\[([^\]]*)\]\(([^)]*)\)'), (Match m) => m.group(1) ?? '')
    .replaceAllMapped(RegExp(r'\[([^\]]*)\]\(([^)]*)\)'), (Match m) => m.group(1) ?? '')
    .replaceAllMapped(RegExp(r'~~([^~]*)~~'), (Match m) => m.group(1) ?? '')
    .replaceAllMapped(RegExp(r'\*([^*\s](?:[^*]*[^*\s])?)\*'), (Match m) => m.group(1) ?? '');

/// 取字段正文并剥掉行内标记（默认取 `content`）。
String genUiInlineText(GenUiNode node, [String key = 'content']) =>
    inlineMarkup(genUiStr(node, key) ?? '');

/// `table` 的列。
List<String> genUiTableColumns(GenUiNode node) => <String>[
      for (final value in arr(node.value, 'columns')) _primitiveText(value),
    ];

/// `table` 的行。
List<List<String>> genUiTableRows(GenUiNode node) => <List<String>>[
      for (final raw in arr(node.value, 'rows'))
        if (raw is List) <String>[for (final cell in raw) _primitiveText(cell)],
    ];

/// `keyvalue` 的行。
List<MapEntry<String, String>> genUiPairs(GenUiNode node) => <MapEntry<String, String>>[
      for (final pair in objArr(node.value, 'pairs'))
        if (stringOrNull(pair, 'key') != null)
          MapEntry(stringOrNull(pair, 'key')!, stringOrNull(pair, 'value') ?? ''),
    ];

/// `steps` 的步骤。
List<MapEntry<String, String?>> genUiSteps(GenUiNode node) => <MapEntry<String, String?>>[
      for (final step in objArr(node.value, 'steps'))
        MapEntry(stringOrNull(step, 'title') ?? '', stringOrNull(step, 'desc')),
    ];

/// `chart` 的柱子（读不出数字的项丢弃）。
List<MapEntry<String, num>> genUiBars(GenUiNode node) => <MapEntry<String, num>>[
      for (final entry in objArr(node.value, 'data'))
        if (numOrNull(entry, 'value') != null)
          MapEntry(stringOrNull(entry, 'label') ?? '', numOrNull(entry, 'value')!),
    ];

/// `diff` 的改动。
List<({String? path, String? oldText, String? newText})> genUiDiffs(GenUiNode node) =>
    <({String? path, String? oldText, String? newText})>[
      for (final diff in objArr(node.value, 'diffs'))
        (
          path: stringOrNull(diff, 'path'),
          oldText: stringOrNull(diff, 'oldText'),
          newText: stringOrNull(diff, 'newText'),
        ),
    ];

/// 表格列宽下限（vp）：96 ≈ 两三个汉字加内边距，再窄就只能看省略号。
const double genUiTableMinColumnWidth = 96;

/// 一列该占多宽。可用宽度无界 / 非法时退回下限 —— 宁可横向滚，也不要算出 0 或 NaN。
double genUiTableColumnWidth(double availableVp, int columnCount) {
  if (columnCount <= 0) {
    return genUiTableMinColumnWidth;
  }
  if (!availableVp.isFinite || availableVp <= 0) {
    return genUiTableMinColumnWidth;
  }
  final width = availableVp / columnCount;
  return width < genUiTableMinColumnWidth ? genUiTableMinColumnWidth : width;
}

/// 数字格式：整数不带小数，否则一位小数。
String formatGenUiNumber(num value) {
  if (value is int || value == value.truncateToDouble()) {
    return '${value.truncate()}';
  }
  return '${(value * 10).round() / 10}';
}
