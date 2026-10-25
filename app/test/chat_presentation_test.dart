import 'dart:convert';

import 'package:dsh_companion_ios/core/chat_presentation.dart';
import 'package:dsh_companion_ios/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

HistoryEntry entry(String type, int seq, Object? data, {Object? view, int time = 0}) => HistoryEntry(
      event: SessionEvent(type: type, seq: seq, time: time, data: data),
      view: view,
    );

void main() {
  group('displayItemsOf', () {
    test('用户消息 + 助手正文 + 思考分开成项', () {
      final history = ChatHistory(events: <HistoryEntry>[
        entry('user/message', 1, <String, dynamic>{
          'source': <String, dynamic>{'kind': 'user'},
          'content': <Object>[
            <String, dynamic>{'type': 'text', 'text': '你好'},
          ],
        }),
        entry('assistant/message', 2, <String, dynamic>{
          'message': <String, dynamic>{
            'content': <Object>[
              <String, dynamic>{'type': 'reasoning', 'text': '想一想'},
              <String, dynamic>{'type': 'text', 'text': '你好！'},
            ],
          },
        }),
      ]);
      final items = displayItemsOf(history);
      expect(items.map((ChatDisplayItem i) => i.kind), <ChatItemKind>[
        ChatItemKind.user,
        ChatItemKind.reasoning,
        ChatItemKind.assistant,
      ]);
      expect(items.last.body, '你好！');
    });

    test('只发图不打字的用户消息不消失', () {
      final history = ChatHistory(events: <HistoryEntry>[
        entry('user/message', 1, <String, dynamic>{
          'source': <String, dynamic>{'kind': 'user'},
          'content': <Object>[
            <String, dynamic>{
              'type': 'image',
              'attachment': <String, dynamic>{
                'attachmentId': 'sha256:aa',
                'mediaType': 'image/png',
                'width': 10,
                'height': 20,
                'bytes': 30,
              },
            },
          ],
        }),
      ]);
      final items = displayItemsOf(history);
      expect(items, hasLength(1));
      expect(items.single.attachments.single.attachmentId, 'sha256:aa');
    });

    test('上下文注入不按用户消息渲染，标题取 kind', () {
      final history = ChatHistory(events: <HistoryEntry>[
        entry('user/message', 1, <String, dynamic>{
          'source': <String, dynamic>{'kind': 'plugin', 'plugin': 'dsh-memory'},
          'content': <Object>[
            <String, dynamic>{'type': 'text', 'text': '记忆库'},
          ],
        }),
      ]);
      final items = displayItemsOf(history);
      expect(items.single.kind, ChatItemKind.context);
      expect(items.single.title, 'dsh-memory');
    });

    test('交接说明被摘掉，交接路径变成 handoff 附件', () {
      final history = ChatHistory(events: <HistoryEntry>[
        entry('user/message', 1, <String, dynamic>{
          'source': <String, dynamic>{'kind': 'user'},
          'content': <Object>[
            <String, dynamic>{
              'type': 'text',
              'text': '看一下这张图\n🖼️ 图片 1「shot.jpg」\n[Image: source: /tmp/a shot.jpg]',
            },
          ],
        }),
      ]);
      final item = displayItemsOf(history).single;
      expect(item.body, '看一下这张图');
      expect(item.attachments.single.handoffPath, '/tmp/a shot.jpg');
      expect(item.attachments.single.attachmentId.startsWith('handoff:'), isTrue);
      expect(item.attachments.single.mediaType, 'image/jpeg');
    });

    test('工具结果按 callId 配对，结果进 details', () {
      final history = ChatHistory(events: <HistoryEntry>[
        entry('tool/call', 2, <String, dynamic>{
          'turn': 1,
          'step': 1,
          'callId': 'c1',
          'name': 'bash',
          'arguments': '{"command":"ls"}',
        }, time: 1000),
        entry('tool/result', 3, <String, dynamic>{
          'message': <String, dynamic>{
            'toolCallId': 'c1',
            'isError': false,
            'content': <Object>[
              <String, dynamic>{'type': 'text', 'text': 'a.txt'},
            ],
          },
        }, time: 1200),
      ]);
      final item = displayItemsOf(history).single;
      expect(item.kind, ChatItemKind.tool);
      expect(item.title, '执行了命令');
      expect(item.tools.single.result, 'a.txt');
      expect(item.tools.single.durationMs, 200);
    });

    test('连续工具合并一行，中间夹正文则断开', () {
      ChatDisplayItem tool(int seq, String name) => ChatDisplayItem(
            id: '$seq-tool',
            seq: seq,
            kind: ChatItemKind.tool,
            title: toolActionsFor(name, null).join('，'),
            body: name,
            actions: toolActionsFor(name, null),
            tools: <ToolCallDetail>[ToolCallDetail(name: name)],
          );
      final items = <ChatDisplayItem>[
        tool(1, 'bash'),
        tool(2, 'edit'),
        ChatDisplayItem(id: 'x', seq: 3, kind: ChatItemKind.assistant, body: '好'),
        tool(4, 'read'),
      ];
      final merged = mergeToolRuns(items);
      expect(merged, hasLength(3));
      expect(merged.first.title, '执行了命令，修改了文件');
      expect(merged.first.tools, hasLength(2));
      expect(merged.last.title, '读取了文件');
    });

    test('历史 turn/end 失败渲染为失败行；空 code 保留空串', () {
      final history = ChatHistory(events: <HistoryEntry>[
        entry('turn/end', 9, <String, dynamic>{
          'reason': <String, dynamic>{
            'kind': 'error',
            'error': <String, dynamic>{'message': '限流', 'code': ''},
          },
        }),
      ]);
      final item = displayItemsOf(history).single;
      expect(item.kind, ChatItemKind.failure);
      expect(item.failure!.message, '限流');
      expect(item.failure!.code, '');
    });

    test('退出登录的 aborted 渲染为 stopped 失败行', () {
      final history = ChatHistory(events: <HistoryEntry>[
        entry('turn/end', 9, <String, dynamic>{
          'reason': <String, dynamic>{
            'kind': 'aborted',
            'reason': <String, dynamic>{'kind': 'hook', 'reason': 'deepseek-account/signed-out'},
          },
        }),
      ]);
      final item = displayItemsOf(history).single;
      expect(item.failure!.stopped, isTrue);
      expect(item.failure!.code, 'ACCOUNT_SIGNED_OUT');
    });

    test('max-tokens 收尾不渲染为失败', () {
      final history = ChatHistory(events: <HistoryEntry>[
        entry('turn/end', 9, <String, dynamic>{
          'reason': <String, dynamic>{'kind': 'max-tokens'},
        }),
      ]);
      expect(displayItemsOf(history), isEmpty);
    });

    test('工具耗时倒退时不给值', () {
      expect(toolDurationMs(2000, 1000), isNull);
      expect(toolDurationMs(1000, null), isNull);
      expect(toolDurationMs(1000, 1500), 500);
    });

    test('耗时格式', () {
      expect(formatToolDuration(999), '999 ms');
      expect(formatToolDuration(1234), '1.2 s');
      expect(formatToolDuration(65000), '1m 5s');
      expect(formatToolDuration(3700000), '1h 1m');
    });

    test('参数格式化失败时原样返回', () {
      expect(prettyToolArguments('not json'), 'not json');
      expect(prettyToolArguments('{"a":1}').contains('\n'), isTrue);
    });

    test('argumentsSummary 取第一个非空键的第一行', () {
      final summary = argumentsSummary(jsonEncode(<String, dynamic>{
        'description': '读取配置\n后续',
        'path': '/x',
      }));
      expect(summary, '读取配置');
      expect(argumentsSummary('oops'), isNull);
    });
  });

  group('LiveChatState', () {
    test('同 turn/step 增量按 index 追加', () {
      var state = LiveChatState(sessionId: 's', turn: 1, step: 1);
      state = state.append(const ChatDelta('s', 1, 1, 0, ChatItemKind.assistant, '你'));
      state = state.append(const ChatDelta('s', 1, 1, 0, ChatItemKind.assistant, '好'));
      expect(state.blocks.single.text, '你好');
      expect(state.revision, 2);
    });

    test('turn/step 变化时整段换掉（上一段由 REST 历史补回）', () {
      var state = LiveChatState(sessionId: 's', turn: 1, step: 1);
      state = state.append(const ChatDelta('s', 1, 1, 0, ChatItemKind.assistant, '旧'));
      state = state.append(const ChatDelta('s', 1, 2, 0, ChatItemKind.assistant, '新'));
      expect(state.blocks.single.text, '新');
      expect(state.step, 2);
    });

    test('同一 index 换 kind 时整段替换而不是拼接', () {
      var state = LiveChatState(sessionId: 's', turn: 1, step: 1);
      state = state.append(const ChatDelta('s', 1, 1, 0, ChatItemKind.reasoning, '想'));
      state = state.append(const ChatDelta('s', 1, 1, 0, ChatItemKind.assistant, '说'));
      expect(state.blocks.single.text, '说');
      expect(state.blocks.single.kind, ChatItemKind.assistant);
    });

    test('displayItems 跳过空串但保留纯空白', () {
      var state = LiveChatState(sessionId: 's', turn: 1, step: 1);
      state = state.append(const ChatDelta('s', 1, 1, 0, ChatItemKind.assistant, ' '));
      state = state.append(const ChatDelta('s', 1, 1, 1, ChatItemKind.assistant, ''));
      final items = state.displayItems();
      expect(items, hasLength(1));
      expect(items.single.streaming, isTrue);
      expect(items.single.seq, liveSeq);
    });
  });

  group('事件帧解析', () {
    WorkspaceEvent event(String type, Object? data) => WorkspaceEvent(type: type, data: data);

    test('chatDelta 缺字段返回 null（不猜默认值）', () {
      expect(chatDelta(event('chat.message.delta', <String, dynamic>{'kind': 'text'})), isNull);
      expect(
        chatDelta(event('chat.message.delta', <String, dynamic>{
          'kind': 'text',
          'sessionId': 's',
          'turn': 1,
          'step': 1,
          'index': 0,
          'text': 'hi',
        }))!.text,
        'hi',
      );
    });

    test('chatDelta 只认 text / reasoning', () {
      expect(
        chatDelta(event('chat.message.delta', <String, dynamic>{
          'kind': 'tool',
          'sessionId': 's',
          'turn': 1,
          'step': 1,
          'index': 0,
          'text': 'x',
        })),
        isNull,
      );
    });

    test('chatTurnFailure 从 chat.turn.failed 取 failure', () {
      final failure = chatTurnFailure(event('chat.turn.failed', <String, dynamic>{
        'failure': <String, dynamic>{'message': '额度用尽', 'code': 'QUOTA'},
      }));
      expect(failure!.message, '额度用尽');
      expect(failure.code, 'QUOTA');
    });
  });
}
