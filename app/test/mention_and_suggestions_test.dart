import 'package:dsh_companion_ios/core/composer_suggestions.dart';
import 'package:dsh_companion_ios/core/mention_query.dart';
import 'package:dsh_companion_ios/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

FileEntry entry(String name, {bool dir = false}) =>
    FileEntry(name: name, path: dir ? 'ws/$name' : 'ws/$name.txt', kind: dir ? 'directory' : 'file');

CommandDescriptor command(String name) => CommandDescriptor(name: name, description: '');

void main() {
  group('activeStart / mentionQuery', () {
    test('行首 @ 命中', () {
      expect(activeStart('@abc'), 0);
      expect(mentionQuery('@abc'), 'abc');
    });

    test('空白后的 @ 命中', () {
      expect(activeStart('看看 @src'), 3);
      expect(mentionQuery('看看 @src'), 'src');
    });

    test('邮箱里的 @ 不算提及', () {
      expect(activeStart('foo@bar.com'), isNull);
    });

    test('词中间换行不算', () {
      expect(activeStart('第一行\n第二行'), isNull);
    });

    test('光标已经离开提及词（后面有空格）不算', () {
      expect(activeStart('@abc def'), isNull);
    });

    test('末尾就是 @ 时查询串为空', () {
      expect(mentionQuery('@'), '');
    });
  });

  group('applySelection', () {
    test('只替换 @…末尾，保留前面的半句', () {
      expect(applySelection('帮我看看 @src', '/w/src/'), '帮我看看 /w/src/');
    });

    test('没有活跃提及时追加', () {
      expect(applySelection('你好', '/w/a.txt'), '你好/w/a.txt');
    });
  });

  group('absolutePath', () {
    test('把 cwd 相对前缀换成绝对前缀', () {
      expect(
        absolutePath(cwdAbsolute: '/root/ws', cwdRelative: 'ws', entryPath: 'ws/a.txt'),
        '/root/ws/a.txt',
      );
    });

    test('cwdRelative 为空（工作目录就是授权根）直接接上', () {
      expect(
        absolutePath(cwdAbsolute: '/root/ws/', cwdRelative: '', entryPath: 'a.txt'),
        '/root/ws/a.txt',
      );
    });

    test('必须带分隔符比对：ws 不匹配 wsx/', () {
      expect(
        absolutePath(cwdAbsolute: '/root', cwdRelative: 'ws', entryPath: 'wsx/a.txt'),
        'wsx/a.txt',
      );
    });

    test('老服务端没有绝对路径时退回相对路径（不硬拼）', () {
      expect(absolutePath(cwdAbsolute: null, cwdRelative: 'ws', entryPath: 'ws/a.txt'), 'ws/a.txt');
    });

    test('条目就是 cwd 本身时返回 cwd 绝对路径', () {
      expect(absolutePath(cwdAbsolute: '/root/ws', cwdRelative: 'ws', entryPath: 'ws'), '/root/ws');
    });
  });

  group('mentionMatches', () {
    test('未加载（null）返回空', () {
      expect(mentionMatches(null, ''), isEmpty);
    });

    test('目录优先，其次小写名升序', () {
      final entries = <FileEntry>[
        entry('b.txt'),
        entry('A.txt'),
        entry('zdir', dir: true),
        entry('adir', dir: true),
      ];
      final matched = mentionMatches(entries, '');
      expect(matched.map((FileEntry e) => e.name), <String>['adir', 'zdir', 'A.txt', 'b.txt']);
    });

    test('大小写不敏感的包含匹配', () {
      final matched = mentionMatches(<FileEntry>[entry('README.md'), entry('a.txt')], 'read');
      expect(matched.single.name, 'README.md');
    });

    test('上限 50 条', () {
      final entries = <FileEntry>[for (var i = 0; i < 80; i++) entry('f$i.txt')];
      expect(mentionMatches(entries, ''), hasLength(50));
    });
  });

  group('commandSuggestions', () {
    test('整行斜杠开头才出面板', () {
      expect(commandSuggestions('/he', <CommandDescriptor>[command('help')]), hasLength(1));
      expect(commandSuggestions('看看 /he', <CommandDescriptor>[command('help')]), isEmpty);
    });

    test('斜杠后有空白说明在打参数，不出面板', () {
      expect(commandSuggestions('/help ', <CommandDescriptor>[command('help')]), isEmpty);
    });

    test('大小写不敏感前缀匹配', () {
      expect(commandSuggestions('/HE', <CommandDescriptor>[command('help')]), hasLength(1));
    });

    test('上限 5 条', () {
      final commands = <CommandDescriptor>[for (var i = 0; i < 9; i++) command('c$i')];
      expect(commandSuggestions('/', commands), hasLength(5));
    });
  });

  test('composerOverlayActive 两个面板任一成立即为真', () {
    expect(composerOverlayActive('@a', const <CommandDescriptor>[]), isTrue);
    expect(composerOverlayActive('/', <CommandDescriptor>[command('help')]), isTrue);
    expect(composerOverlayActive('普通文本', const <CommandDescriptor>[]), isFalse);
  });
}
