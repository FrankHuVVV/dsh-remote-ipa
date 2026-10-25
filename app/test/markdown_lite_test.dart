import 'package:dsh_companion_ios/core/markdown_lite.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = MarkdownLite();

  MdBlock single(String source) {
    final blocks = parser.parseBlocks(source);
    expect(blocks, hasLength(1));
    return blocks.single;
  }

  group('块级解析', () {
    test('标题层级', () {
      final heading = single('### 标题') as MdHeading;
      expect(heading.level, 3);
      expect(heading.text, '标题');
    });

    test('标题尾部 # 被去掉', () {
      expect((single('## 标题 ##') as MdHeading).text, '标题');
    });

    test('段落保留软换行', () {
      final paragraph = single('第一行\n第二行') as MdParagraph;
      expect(paragraph.text, '第一行\n第二行');
    });

    test('无序列表（含缩进层级）', () {
      final list = single('- 一\n  - 子\n- 二') as MdBullets;
      expect(list.items, hasLength(3));
      expect(list.items[1].level, 1);
      expect(list.items[2].text, '二');
    });

    test('有序列表', () {
      final list = single('1. 甲\n2. 乙') as MdOrdered;
      expect(list.items.map((MdOrderedItem i) => i.number), <int>[1, 2]);
    });

    test('围栏代码块保留语言与原文', () {
      final code = single('```dart\nvoid main() {}\n```') as MdCode;
      expect(code.language, 'dart');
      expect(code.code, 'void main() {}');
    });

    test('未闭合的围栏吃到结尾（不丢内容）', () {
      final code = single('```\ncode') as MdCode;
      expect(code.code, 'code');
    });

    test('引用', () {
      final quote = single('> 引用\n> 第二行') as MdQuote;
      expect(quote.text, '引用\n第二行');
    });

    test('分隔线', () {
      expect(single('---'), isA<MdRule>());
      expect(single('***'), isA<MdRule>());
    });

    test('GFM 表格与对齐方式', () {
      final table = single('| 名 | 值 |\n|---|:---:|\n| a | 1 |') as MdTable;
      expect(table.header, <String>['名', '值']);
      expect(table.rows.single, <String>['a', '1']);
      expect(table.alignments[1], 'c');
    });

    test('空文本返回空列表', () {
      expect(parser.parseBlocks(''), isEmpty);
      expect(parser.parseBlocks('\n\n'), isEmpty);
    });

    test('认不出的行退化为段落', () {
      expect(single('普通一行'), isA<MdParagraph>());
    });
  });

  group('行内解析', () {
    String joined(String source) => parser.parseInline(source).map((MdSpan s) => s.text).join();

    test('粗体 / 斜体 / 行内代码 / 链接', () {
      final spans = parser.parseInline('**粗** 和 *斜* 与 `code` 和 [链接](https://x.example)');
      expect(spans.any((MdSpan s) => s.strong && s.text == '粗'), isTrue);
      expect(spans.any((MdSpan s) => s.emphasized && s.text == '斜'), isTrue);
      expect(spans.any((MdSpan s) => s.code && s.text == 'code'), isTrue);
      final link = spans.firstWhere((MdSpan s) => s.linkUrl != null);
      expect(link.text, '链接');
      expect(link.linkUrl, 'https://x.example');
    });

    test('未闭合标记原样保留', () {
      expect(joined('**没有闭合'), '**没有闭合');
      expect(joined('a `b'), 'a `b');
    });

    test('行内代码里的星号不再解析', () {
      final spans = parser.parseInline('`a*b*c`');
      expect(spans.single.code, isTrue);
      expect(spans.single.text, 'a*b*c');
    });

    test('不变量：文本拼接后等于原文（不含链接语法字符）', () {
      const source = '前 **粗** 中 *斜* 后';
      expect(joined(source), '前 粗 中 斜 后');
    });

    test('空文本', () {
      expect(parser.parseInline(''), isEmpty);
    });
  });
}
