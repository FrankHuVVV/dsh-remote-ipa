import 'package:dsh_companion_ios/core/chat_presentation.dart';
import 'package:dsh_companion_ios/core/small_parts.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('字号 / 主题 / 发送方式', () {
    test('字号归一化：坏值回落 1.0，越界夹紧', () {
      expect(normalizeFontScale(null), 1.0);
      expect(normalizeFontScale(double.nan), 1.0);
      expect(normalizeFontScale(0.1), 0.8);
      expect(normalizeFontScale(9), 1.5);
      expect(normalizeFontScale(1.24), 1.2);
    });

    test('跟随系统时这一层不缩放', () {
      expect(effectiveFontScale(followsSystem: true, scale: 1.4), 1.0);
      expect(effectiveFontScale(followsSystem: false, scale: 1.4), 1.4);
    });

    test('主题档位归一化，认不出的回落 system', () {
      expect(normalizeThemeMode('dark'), 'dark');
      expect(normalizeThemeMode('LIGHT'), 'system');
      expect(normalizeThemeMode(null), 'system');
    });

    test('发送方式只认 queue / steer', () {
      expect(normalizeSendMode('steer'), 'steer');
      expect(normalizeSendMode('STEER'), 'queue');
      expect(oppositeSendMode('steer'), 'queue');
      expect(oppositeSendMode('queue'), 'steer');
    });
  });

  group('体积与时间', () {
    test('体积格式', () {
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(3 * 1024 * 1024), '3.0 MB');
    });

    test('同一会话分组', () {
      final now = DateTime(2026, 10, 25, 20);
      int at(DateTime value) => value.millisecondsSinceEpoch;
      expect(sessionGroupOf(at(DateTime(2026, 10, 25, 9)), now: now), sessionGroupToday);
      expect(sessionGroupOf(at(DateTime(2026, 10, 24, 9)), now: now), sessionGroupYesterday);
      expect(sessionGroupOf(at(DateTime(2026, 10, 21, 9)), now: now), sessionGroupWeek);
      expect(sessionGroupOf(at(DateTime(2026, 9, 1)), now: now), sessionGroupEarlier);
      expect(sessionGroupOf(0, now: now), sessionGroupEarlier);
    });

    test('消息时间标签：0 表示没有时间', () {
      final now = DateTime(2026, 10, 25, 20, 30);
      final today = DateTime(2026, 10, 25, 12, 50);
      expect(chatTimeLabel(today.millisecondsSinceEpoch, now: now), '12:50');
      expect(chatTimeLabel(0, now: now), isNull);
      final other = DateTime(2026, 3, 4, 8, 5);
      expect(chatTimeLabel(other.millisecondsSinceEpoch, now: now), '3/4 08:05');
    });
  });

  group('ChatSeqMonitor', () {
    test('首个序号建立基线', () {
      final monitor = ChatSeqMonitor();
      expect(monitor.observe(5), isFalse);
      expect(monitor.last, 5);
    });

    test('严格跳号才要求 resync', () {
      final monitor = ChatSeqMonitor()..observe(5);
      expect(monitor.observe(6), isFalse);
      expect(monitor.observe(9), isTrue);
    });

    test('重复与倒退不算断档', () {
      final monitor = ChatSeqMonitor()..observe(9);
      expect(monitor.observe(9), isFalse);
      expect(monitor.observe(3), isFalse);
      expect(monitor.last, 9);
    });

    test('reset 后重新找起点', () {
      final monitor = ChatSeqMonitor()..observe(9);
      monitor.reset();
      expect(monitor.observe(1), isFalse);
    });
  });

  group('能力位', () {
    test('空清单与缺字段都算未知（不报警告）', () {
      expect(parseCapabilities(null), isNull);
      expect(parseCapabilities(<String, dynamic>{}), isNull);
      expect(parseCapabilities(<String, dynamic>{'capabilities': <Object>[]}), isNull);
    });

    test('数字元素不进能力集', () {
      final caps = parseCapabilities(<String, dynamic>{
        'capabilities': <Object>['approvals-v1', 42],
      });
      expect(caps, <String>{'approvals-v1'});
    });

    test('归档入口按能力位守卫', () {
      expect(supportsArchiveListing(null), isFalse);
      expect(supportsArchiveListing(<String>{'approvals-v1'}), isFalse);
      expect(supportsArchiveListing(<String>{'session-archive-list-v1'}), isTrue);
    });

    test('缺失的必需能力位', () {
      expect(missingRequiredCapabilities(<String>{'approvals-v1', 'questions-v1'}), isEmpty);
      expect(missingRequiredCapabilities(<String>{'approvals-v1'}), <String>['questions-v1']);
    });

    test('bridgeVersion 只认字符串', () {
      expect(bridgeVersionOf(<String, dynamic>{'bridgeVersion': '2.0.4'}), '2.0.4');
      expect(bridgeVersionOf(<String, dynamic>{'bridgeVersion': 2}), isNull);
    });
  });

  group('RequestGate', () {
    test('进行中时拒绝第二次调用', () async {
      final gate = RequestGate();
      var started = 0;
      final first = gate.run<int>(() async {
        started++;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return 1;
      });
      final second = await gate.run<int>(() async {
        started++;
        return 2;
      });
      expect(second, isNull);
      expect(await first, 1);
      expect(started, 1);
      expect(gate.busy, isFalse);
    });
  });

  group('chatVisibleItems', () {
    test('历史在前、实时在后，按 id 去重', () {
      ChatDisplayItem item(String id, int seq) => ChatDisplayItem(id: id, seq: seq, kind: ChatItemKind.assistant);
      final merged = chatVisibleItems(<ChatDisplayItem>[item('a', 1), item('b', 2)], <ChatDisplayItem>[item('b', 2), item('c', liveSeq)]);
      expect(merged.map((ChatDisplayItem i) => i.id), <String>['a', 'b', 'c']);
    });
  });
}
