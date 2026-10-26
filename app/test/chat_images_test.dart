import 'package:dsh_companion_ios/core/chat_presentation.dart';
import 'package:dsh_companion_ios/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

HistoryEntry assistantEntry(int seq, List<Object?> content) => HistoryEntry(
      event: SessionEvent(
        type: 'assistant/message',
        seq: seq,
        time: 1700000000000,
        data: <String, dynamic>{
          'message': <String, dynamic>{'content': content},
        },
      ),
    );

void main() {
  test('助手消息里的图片块不再被丢弃', () {
    final history = ChatHistory(events: <HistoryEntry>[
      assistantEntry(2, <Object?>[
        <String, dynamic>{'type': 'text', 'text': '画好了：'},
        <String, dynamic>{
          'type': 'image',
          'attachment': <String, dynamic>{
            'attachmentId': 'sha256:abc',
            'mediaType': 'image/png',
            'width': 512,
            'height': 512,
            'bytes': 1024,
          },
        },
      ]),
    ]);

    final items = displayItemsOf(history);
    expect(items, hasLength(2));
    expect(items.first.body, '画好了：');
    expect(items.first.attachments, isEmpty);
    expect(items.last.attachments.single.attachmentId, 'sha256:abc');
    expect(items.last.attachments.single.mediaType, 'image/png');
  });

  test('只有图片没有文字的助手消息也会渲染成一项', () {
    final history = ChatHistory(events: <HistoryEntry>[
      assistantEntry(4, <Object?>[
        <String, dynamic>{
          'type': 'image',
          'attachment': <String, dynamic>{'attachmentId': 'sha256:only'},
        },
      ]),
    ]);
    final items = displayItemsOf(history);
    expect(items.single.attachments.single.attachmentId, 'sha256:only');
  });

  test('助手正文里的交接说明被摘掉，路径变成 handoff 附件', () {
    final history = ChatHistory(events: <HistoryEntry>[
      assistantEntry(6, <Object?>[
        <String, dynamic>{
          'type': 'text',
          'text': '图在这里\n🖼️ 图片 1「a.png」\n[Image: source: /w/.dsh-images/a.png]',
        },
      ]),
    ]);
    final item = displayItemsOf(history).single;
    expect(item.body, '图在这里');
    expect(item.attachments.single.handoffPath, '/w/.dsh-images/a.png');
    expect(item.attachments.single.attachmentId.startsWith('handoff:'), isTrue);
  });

  test('交接标记出现在用户消息里仍按原口径处理（不回归）', () {
    final history = ChatHistory(events: <HistoryEntry>[
      HistoryEntry(
        event: SessionEvent(
          type: 'user/message',
          seq: 1,
          data: <String, dynamic>{
            'source': <String, dynamic>{'kind': 'user'},
            'content': <Object?>[
              <String, dynamic>{'type': 'text', 'text': '看这个\n[Image: source: /w/x.jpg]'},
            ],
          },
        ),
      ),
    ]);
    final item = displayItemsOf(history).single;
    expect(item.body, '看这个');
    expect(item.attachments.single.handoffPath, '/w/x.jpg');
  });
}
