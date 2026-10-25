import 'package:dsh_companion_ios/core/gen_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('splitMessageBody', () {
    test('纯文本原样一段', () {
      final segments = splitMessageBody('你好\n世界');
      expect(segments, hasLength(1));
      expect(segments.single.kind, MessageSegmentKind.prose);
      expect(segments.single.text, '你好\n世界');
    });

    test('dsh-ui 围栏切成 文字 + 卡片 + 文字', () {
      final body = '前文\n```dsh-ui\n{"items":[]}\n```\n后文';
      final segments = splitMessageBody(body);
      expect(segments.map((MessageSegment s) => s.kind), <MessageSegmentKind>[
        MessageSegmentKind.prose,
        MessageSegmentKind.ui,
        MessageSegmentKind.prose,
      ]);
      expect(segments[0].text, '前文');
      expect(segments[1].text.trim(), '{"items":[]}');
      expect(segments[2].text, '后文');
    });

    test('```json dsh-ui 也认（模型两种写法都有）', () {
      final segments = splitMessageBody('```json dsh-ui\n{"items":[{"type":"text","content":"x"}]}\n```');
      expect(segments.single.kind, MessageSegmentKind.ui);
    });

    test('未闭合围栏整段保留（流式输出中）', () {
      final body = '前文\n```dsh-ui\n{"items":';
      final segments = splitMessageBody(body);
      expect(segments, hasLength(1));
      expect(segments.single.kind, MessageSegmentKind.prose);
      expect(segments.single.text, body);
    });

    test('正文中间的裸围栏不算卡片边界', () {
      final body = '示例：\n```\ncode\n```\n结束';
      final segments = splitMessageBody(body);
      expect(segments, hasLength(1));
      expect(segments.single.kind, MessageSegmentKind.prose);
    });

    test('dsh-ui-bad 不认（不吞别的语言名）', () {
      final body = '```dsh-ui-bad\n{"items":[]}\n```';
      expect(splitMessageBody(body).single.kind, MessageSegmentKind.prose);
    });
  });

  group('parseGenUi', () {
    test('合法 spec 读出 title / gap / items', () {
      final spec = parseGenUi('{"title":"概览","gap":16,"items":[{"type":"text","content":"hi"}]}');
      expect(spec, isNotNull);
      expect(spec!.title, '概览');
      expect(spec.gap, 16);
      expect(spec.items.single.type, 'text');
    });

    test('未知 type 被丢弃，但其余照常', () {
      final spec = parseGenUi(
          '{"items":[{"type":"text","content":"a"},{"type":"wormhole"},{"type":"badge","label":"b"}]}');
      expect(spec!.items.map((GenUiNode n) => n.type), <String>['text', 'badge']);
    });

    test('坏 JSON / items 为空 / 非对象返回 null', () {
      expect(parseGenUi('{oops'), isNull);
      expect(parseGenUi('{"items":[]}'), isNull);
      expect(parseGenUi('[]'), isNull);
    });

    test('缺 gap 时默认 12', () {
      expect(parseGenUi('{"items":[{"type":"text","content":"x"}]}')!.gap, 12);
    });

    test('children 只收支持的类型', () {
      final spec = parseGenUi(
          '{"items":[{"type":"card","items":[{"type":"text","content":"a"},{"type":"nope"}]}]}');
      final children = genUiChildren(spec!.items.single);
      expect(children, hasLength(1));
      expect(children.single.type, 'text');
    });

    test('list 条目接受纯字符串与对象，空标题丢弃', () {
      final spec = parseGenUi(
          '{"items":[{"type":"list","items":["甲",{"title":"乙","desc":"说明"},{"title":"  "},{"label":"丙"}]}]}');
      final items = genUiListItems(spec!.items.single);
      expect(items.map((GenUiListItem i) => i.title), <String>['甲', '乙', '丙']);
      expect(items[1].desc, '说明');
    });

    test('button 文案回退 label → content → title', () {
      final spec = parseGenUi(
          '{"items":[{"type":"button","label":"确定"},{"type":"button","content":"继续"},{"type":"button","title":"好"}]}');
      expect(genUiLabel(spec!.items[0]), '确定');
      expect(genUiLabel(spec.items[1]), '继续');
      expect(genUiLabel(spec.items[2]), '好');
    });

    test('table 的列与行按标量转字符串', () {
      final spec = parseGenUi(
          '{"items":[{"type":"table","columns":["a",1],"rows":[["x",2],[true,null]]}]}');
      final node = spec!.items.single;
      expect(genUiTableColumns(node), <String>['a', '1']);
      expect(genUiTableRows(node), <List<String>>[
        <String>['x', '2'],
        <String>['true', ''],
      ]);
    });

    test('chart 缺 value 的柱子丢弃', () {
      final spec = parseGenUi(
          '{"items":[{"type":"chart","data":[{"label":"a","value":3},{"label":"b"}]}]}');
      expect(genUiBars(spec!.items.single), hasLength(1));
    });
  });

  group('inlineMarkup', () {
    test('剥掉粗体 / 高亮 / 代码 / 链接 / 删除线 / 斜体', () {
      expect(inlineMarkup('**粗** ==高亮== `code` [文字](https://x) ~~删~~ *斜*'),
          '粗 高亮 code 文字 删 斜');
    });

    test('图片语法保留替代文字', () {
      expect(inlineMarkup('![截图](a.png)'), '截图');
    });

    test('下划线系不解析：变量名不能被改坏', () {
      expect(inlineMarkup('entry_default'), 'entry_default');
      expect(inlineMarkup('__init__'), '__init__');
    });
  });

  group('表格列宽', () {
    test('装得下就均分', () {
      expect(genUiTableColumnWidth(300, 3), 100);
    });

    test('装不下退回下限', () {
      expect(genUiTableColumnWidth(120, 3), genUiTableMinColumnWidth);
    });

    test('无界 / 非法宽度退回下限（不许返回 Infinity / NaN）', () {
      expect(genUiTableColumnWidth(double.infinity, 2), genUiTableMinColumnWidth);
      expect(genUiTableColumnWidth(0, 2), genUiTableMinColumnWidth);
      expect(genUiTableColumnWidth(-10, 2), genUiTableMinColumnWidth);
      expect(genUiTableColumnWidth(300, 0), genUiTableMinColumnWidth);
    });
  });

  test('数字格式：整数不带小数，否则一位', () {
    expect(formatGenUiNumber(3), '3');
    expect(formatGenUiNumber(3.0), '3');
    expect(formatGenUiNumber(3.14159), '3.1');
  });
}
