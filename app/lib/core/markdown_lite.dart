/// 轻量 Markdown —— 移植自鸿蒙版 `core/MarkdownLite.ts`。
///
/// 只做「聊天与文件预览真的会遇到」的那一档：标题 / 无序与有序列表 / 引用 / 围栏代码块 /
/// GFM 表格 / 分隔线 / 段落。**不用 WebView**：这些块全部由 Flutter 原生组件渲染，
/// 不可信文件因此拿不到执行权。
///
/// 两条不变量（单测锁死）：
/// 1. 同一行的行内标记解析后拼接起来**逐字符等于原文** —— 不许吞字、不许造字；
/// 2. 认不出的行一律退化为段落，绝不丢内容。
library;

/// 一个 Markdown 块。
sealed class MdBlock {
  const MdBlock();
}

class MdHeading extends MdBlock {
  const MdHeading(this.level, this.text);

  final int level;
  final String text;
}

class MdParagraph extends MdBlock {
  const MdParagraph(this.text);

  final String text;
}

class MdBulletItem {
  const MdBulletItem(this.level, this.text, this.marker);

  final int level;
  final String text;
  final String marker;
}

class MdBullets extends MdBlock {
  const MdBullets(this.items);

  final List<MdBulletItem> items;
}

class MdOrderedItem {
  const MdOrderedItem(this.level, this.number, this.text);

  final int level;
  final int number;
  final String text;
}

class MdOrdered extends MdBlock {
  const MdOrdered(this.items);

  final List<MdOrderedItem> items;
}

class MdQuote extends MdBlock {
  const MdQuote(this.text);

  final String text;
}

class MdCode extends MdBlock {
  const MdCode(this.language, this.code);

  final String language;
  final String code;
}

class MdTable extends MdBlock {
  const MdTable(this.header, this.rows, this.alignments);

  final List<String> header;
  final List<List<String>> rows;

  /// `l` / `c` / `r` / `n`（未声明）。
  final List<String> alignments;
}

class MdRule extends MdBlock {
  const MdRule();
}

/// 行内片段。
class MdSpan {
  const MdSpan(
    this.text, {
    this.strong = false,
    this.emphasized = false,
    this.code = false,
    this.linkUrl,
  });

  final String text;
  final bool strong;
  final bool emphasized;
  final bool code;
  final String? linkUrl;
}

/// Markdown 解析入口。
class MarkdownLite {
  const MarkdownLite();

  /// 切成块。空文本返回空列表。
  List<MdBlock> parseBlocks(String source) {
    final lines = source.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
    final out = <MdBlock>[];
    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      if (line.trim().isEmpty) {
        i++;
        continue;
      }

      // 围栏代码块
      final fence = _fenceOf(line);
      if (fence != null) {
        final buffer = <String>[];
        i++;
        while (i < lines.length && !_closesFence(lines[i], fence.marker)) {
          buffer.add(lines[i]);
          i++;
        }
        if (i < lines.length) {
          i++;
        }
        out.add(MdCode(fence.language, buffer.join('\n')));
        continue;
      }

      // ATX 标题
      final heading = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(line);
      if (heading != null) {
        out.add(MdHeading(heading.group(1)!.length, _trimTrailingHashes(heading.group(2)!)));
        i++;
        continue;
      }

      // 分隔线（必须早于列表：`---` 也像列表项）
      if (RegExp(r'^\s{0,3}([-*_])(\s*\1){2,}\s*$').hasMatch(line)) {
        out.add(const MdRule());
        i++;
        continue;
      }

      // 表格：当前行含 `|`，下一行是分隔行
      if (line.contains('|') && i + 1 < lines.length && _isTableSeparator(lines[i + 1])) {
        final header = _splitRow(line);
        final alignments = _alignmentsOf(lines[i + 1]);
        final rows = <List<String>>[];
        i += 2;
        while (i < lines.length && lines[i].contains('|') && lines[i].trim().isNotEmpty) {
          rows.add(_splitRow(lines[i]));
          i++;
        }
        out.add(MdTable(header, rows, alignments));
        continue;
      }

      // 引用
      if (RegExp(r'^\s{0,3}>\s?').hasMatch(line)) {
        final buffer = <String>[];
        while (i < lines.length && RegExp(r'^\s{0,3}>\s?').hasMatch(lines[i])) {
          buffer.add(lines[i].replaceFirst(RegExp(r'^\s{0,3}>\s?'), ''));
          i++;
        }
        out.add(MdQuote(buffer.join('\n')));
        continue;
      }

      // 无序列表
      final bullet = RegExp(r'^(\s*)([-*+])\s+(.*)$').firstMatch(line);
      if (bullet != null) {
        final items = <MdBulletItem>[];
        while (i < lines.length) {
          final m = RegExp(r'^(\s*)([-*+])\s+(.*)$').firstMatch(lines[i]);
          if (m == null) {
            break;
          }
          items.add(MdBulletItem(_indentLevel(m.group(1)!), m.group(3)!, m.group(2)!));
          i++;
        }
        out.add(MdBullets(items));
        continue;
      }

      // 有序列表
      final ordered = RegExp(r'^(\s*)(\d{1,9})[.)]\s+(.*)$').firstMatch(line);
      if (ordered != null) {
        final items = <MdOrderedItem>[];
        while (i < lines.length) {
          final m = RegExp(r'^(\s*)(\d{1,9})[.)]\s+(.*)$').firstMatch(lines[i]);
          if (m == null) {
            break;
          }
          items.add(MdOrderedItem(
            _indentLevel(m.group(1)!),
            int.tryParse(m.group(2)!) ?? 1,
            m.group(3)!,
          ));
          i++;
        }
        out.add(MdOrdered(items));
        continue;
      }

      // 段落：吃到空行或下一个块起始为止
      final buffer = <String>[];
      while (i < lines.length && lines[i].trim().isNotEmpty) {
        if (buffer.isNotEmpty && _startsBlock(lines[i], lines, i)) {
          break;
        }
        buffer.add(lines[i]);
        i++;
      }
      out.add(MdParagraph(buffer.join('\n')));
    }
    return out;
  }

  /// 行内解析：把 `**粗**` / `*斜*` / `` `代码` `` / `[文字](链接)` 拆成片段。
  ///
  /// 不变量：所有片段的 [MdSpan.text] 依次拼接 == 原文（链接只丢 `[`、`]`、`(url)` 这些语法字符）。
  List<MdSpan> parseInline(String source) {
    final spans = <MdSpan>[];
    final buffer = StringBuffer();
    var i = 0;

    void flush() {
      if (buffer.isNotEmpty) {
        spans.add(MdSpan(buffer.toString()));
        buffer.clear();
      }
    }

    while (i < source.length) {
      final ch = source[i];

      // 行内代码：优先于其它标记，内部不再解析
      if (ch == '`') {
        final end = source.indexOf('`', i + 1);
        if (end > i + 1) {
          flush();
          spans.add(MdSpan(source.substring(i + 1, end), code: true));
          i = end + 1;
          continue;
        }
        buffer.write(ch);
        i++;
        continue;
      }

      // 链接 [text](url)
      if (ch == '[') {
        final close = source.indexOf('](', i + 1);
        if (close > 0) {
          final urlEnd = source.indexOf(')', close + 2);
          if (urlEnd > close + 2) {
            flush();
            final label = source.substring(i + 1, close);
            final url = source.substring(close + 2, urlEnd).trim();
            spans.addAll(_withLink(parseInline(label), url));
            i = urlEnd + 1;
            continue;
          }
        }
        buffer.write(ch);
        i++;
        continue;
      }

      // 粗体 / 斜体
      if (ch == '*' || ch == '_') {
        final doubleMarker = i + 1 < source.length && source[i + 1] == ch;
        final marker = doubleMarker ? ch + ch : ch;
        final end = source.indexOf(marker, i + marker.length);
        if (end > i + marker.length) {
          flush();
          final inner = source.substring(i + marker.length, end);
          final children = parseInline(inner);
          for (final child in children) {
            spans.add(MdSpan(
              child.text,
              strong: child.strong || doubleMarker,
              emphasized: child.emphasized || !doubleMarker,
              code: child.code,
              linkUrl: child.linkUrl,
            ));
          }
          i = end + marker.length;
          continue;
        }
        buffer.write(ch);
        i++;
        continue;
      }

      buffer.write(ch);
      i++;
    }
    flush();
    return spans;
  }

  static List<MdSpan> _withLink(List<MdSpan> spans, String url) => [
        for (final s in spans)
          MdSpan(
            s.text,
            strong: s.strong,
            emphasized: s.emphasized,
            code: s.code,
            linkUrl: url,
          ),
      ];

  static ({String marker, String language})? _fenceOf(String line) {
    final m = RegExp(r'^\s*(`{3,}|~{3,})\s*([^`\s]*)\s*$').firstMatch(line);
    if (m == null) {
      return null;
    }
    return (marker: m.group(1)!, language: m.group(2) ?? '');
  }

  static bool _closesFence(String line, String marker) {
    final fence = _fenceOf(line);
    if (fence == null) {
      return false;
    }
    return fence.marker.startsWith(marker.substring(0, 1)) &&
        fence.marker.length >= marker.length &&
        fence.language.isEmpty;
  }

  static String _trimTrailingHashes(String text) =>
      text.replaceFirst(RegExp(r'\s+#+\s*$'), '').trimRight();

  static int _indentLevel(String indent) {
    var width = 0;
    for (final unit in indent.split('')) {
      width += unit == '\t' ? 4 : 1;
    }
    return width ~/ 2;
  }

  static bool _isTableSeparator(String line) =>
      RegExp(r'^\s*\|?\s*:?-{1,}:?\s*(\|\s*:?-{1,}:?\s*)*\|?\s*$').hasMatch(line) &&
      line.contains('-');

  static List<String> _splitRow(String line) {
    var body = line.trim();
    if (body.startsWith('|')) {
      body = body.substring(1);
    }
    if (body.endsWith('|')) {
      body = body.substring(0, body.length - 1);
    }
    return [for (final cell in body.split('|')) cell.trim()];
  }

  static List<String> _alignmentsOf(String line) => [
        for (final cell in _splitRow(line))
          if (cell.startsWith(':') && cell.endsWith(':'))
            'c'
          else if (cell.endsWith(':'))
            'r'
          else if (cell.startsWith(':'))
            'l'
          else
            'n',
      ];

  static bool _startsBlock(String line, List<String> lines, int index) {
    if (_fenceOf(line) != null) {
      return true;
    }
    if (RegExp(r'^(#{1,6})\s+').hasMatch(line)) {
      return true;
    }
    if (RegExp(r'^\s{0,3}([-*_])(\s*\1){2,}\s*$').hasMatch(line)) {
      return true;
    }
    if (RegExp(r'^(\s*)([-*+])\s+').hasMatch(line)) {
      return true;
    }
    if (RegExp(r'^(\s*)(\d{1,9})[.)]\s+').hasMatch(line)) {
      return true;
    }
    if (RegExp(r'^\s{0,3}>\s?').hasMatch(line)) {
      return true;
    }
    if (line.contains('|') && index + 1 < lines.length && _isTableSeparator(lines[index + 1])) {
      return true;
    }
    return false;
  }
}
