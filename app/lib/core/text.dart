/// 文本谓词 —— 移植自鸿蒙版 `core/TextPredicates.ts` / `ChatJson` 的行工具。
///
/// `isBlank` 与「只含空白」不是同一个东西：Dart 的 `String.trim()` 认 Unicode 空白，
/// 这里按同一口径实现，避免全角空格 / nbsp 在消息里被判成「有内容」。
library;

bool isBlank(String? value) => value == null || value.trim().isEmpty;

bool isNotBlank(String? value) => !isBlank(value);

/// 去掉首尾空白（等价 Kotlin `trim()`）。
String trimText(String value) => value.trim();

/// 只去行首空白。
String trimStartWs(String value) =>
    value.replaceFirst(RegExp(r'^[ \t\u000B\u000C\r\n\u0085\u00A0\u1680\u2000-\u200A\u2028\u2029\u202F\u205F\u3000]+'), '');

/// Kotlin `String.lines()` 的等价物：按 `\r\n` / `\n` / `\r` 切，**保留空行**。
List<String> kotlinLines(String value) {
  if (value.isEmpty) {
    return const <String>[];
  }
  return value.split(RegExp(r'\r\n|\n|\r'));
}

/// 第一行（没有换行就是原文）。
String firstLine(String value) {
  final index = value.indexOf('\n');
  if (index < 0) {
    return value;
  }
  return value.substring(0, index).replaceAll(RegExp(r'\r$'), '');
}

/// 最后一个分隔符之后的部分；找不到返回原文。
String afterLast(String value, String separator) {
  final index = value.lastIndexOf(separator);
  return index < 0 ? value : value.substring(index + separator.length);
}

/// 最后一个分隔符之后的部分；找不到返回空串。
String afterLastOrEmpty(String value, String separator) {
  final index = value.lastIndexOf(separator);
  return index < 0 ? '' : value.substring(index + separator.length);
}
