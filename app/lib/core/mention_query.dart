/// 输入框 `@` 提及的识别与替换 —— 移植自鸿蒙版 `core/MentionQuery.ts`。
///
/// 纯字符串逻辑：边界多（邮箱、多行、`@` 在词中间），必须可单测。
library;


/// Kotlin 的 `Char.isWhitespace()` 覆盖的那批空白（含全角空格）。
bool isKotlinWhitespace(String ch) {
  final code = ch.runes.isEmpty ? 0 : ch.runes.first;
  if (code == 0x20 || code == 0x09 || code == 0x0A || code == 0x0B || code == 0x0C || code == 0x0D) {
    return true;
  }
  return code == 0x1C || code == 0x1D || code == 0x1E || code == 0x1F || code == 0x1680 ||
      (code >= 0x2000 && code <= 0x200A) ||
      code == 0x2028 ||
      code == 0x2029 ||
      code == 0x202F ||
      code == 0x205F ||
      code == 0x3000;
}

/// 找出当前应当触发补全的那个 `@` 的下标；没有则返回 null。
///
/// 从末尾往回扫：先遇到 `@` 且它前面是行首或空白 → 命中；先遇到空白 → 不命中。
/// 判「前面是行首或空白」是为了不把 `foo@bar.com` 当成提及（否则正常打字会突然弹列表）。
int? activeStart(String value) {
  var i = value.length - 1;
  while (i >= 0) {
    final ch = value[i];
    if (ch == '@') {
      return (i == 0 || isKotlinWhitespace(value[i - 1])) ? i : null;
    }
    if (isKotlinWhitespace(ch)) {
      return null;
    }
    i--;
  }
  return null;
}

/// 当前正在输入的查询串（`@` 之后到末尾）；没有活跃提及返回 null。
String? mentionQuery(String value) {
  final at = activeStart(value);
  return at == null ? null : value.substring(at + 1);
}

/// 把选中的条目插回去：只替换「@…末尾」那一段，保留它前面的内容。
String applySelection(String value, String inserted) {
  final at = activeStart(value);
  if (at == null) {
    return value + inserted;
  }
  return value.substring(0, at) + inserted;
}

/// 条目相对授权根的路径 → 绝对路径（换前缀，不是简单拼接）。
///
/// `cwdAbsolute` 是会话工作目录的绝对路径，`cwdRelative` 是它相对授权根的路径；
/// 列举接口给的是**相对授权根**的路径，所以要把 `cwdRelative` 这段前缀换成 `cwdAbsolute`。
/// 拿不到 `cwdAbsolute` 时返回相对路径（老服务端），不硬拼一个错的绝对路径。
String absolutePath({
  required String? cwdAbsolute,
  required String cwdRelative,
  required String entryPath,
}) {
  final root = cwdAbsolute == null ? '' : cwdAbsolute.trim().replaceAll(RegExp(r'/+$'), '');
  if (root.isEmpty) {
    return entryPath;
  }
  final prefix = cwdRelative.trim().replaceAll(RegExp(r'^/+|/+$'), '');
  String tail;
  if (prefix.isEmpty) {
    tail = entryPath;
  } else if (entryPath == prefix) {
    tail = '';
  } else if (entryPath.startsWith('$prefix/')) {
    // 必须带分隔符比对：否则 "ws" 会误配 "wsx/a.txt"。
    tail = entryPath.substring(prefix.length + 1);
  } else {
    return entryPath;
  }
  final clean = tail.replaceFirst(RegExp(r'^/+'), '');
  return clean.isEmpty ? root : '$root/$clean';
}
