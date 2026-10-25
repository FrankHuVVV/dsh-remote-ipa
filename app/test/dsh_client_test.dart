import 'dart:convert';

import 'package:dsh_companion_ios/core/dsh_client.dart';
import 'package:dsh_companion_ios/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

DshClient client(FakeHttpTransport http, {String? token = 'tok'}) => DshClient(
      endpoint: 'http://192.168.1.20:3090',
      token: token,
      http: http,
      deps: DshClientDeps(
        newId: () => 'uuid-1',
        timeZoneId: () => 'Asia/Shanghai',
        languageTag: () => 'zh-CN',
        socket: FakeWebSocketTransport(),
        timers: FakeTimerBridge(),
      ),
    );

void main() {
  group('URL 与鉴权', () {
    test('health 走未鉴权裸请求', () async {
      final http = FakeHttpTransport()..route('GET', 'http://192.168.1.20:3090/api/v1/healthz', body: '{"ok":true,"version":"0.2.1"}');
      final health = await client(http).health();
      expect(health.ok, isTrue);
      expect(health.version, '0.2.1');
      expect(http.requests.single.headers, isEmpty);
      expect(http.requests.single.body, isNull);
    });

    test('鉴权请求带 Bearer 与 Accept-Language', () async {
      final http = FakeHttpTransport()..route('GET', 'http://192.168.1.20:3090/api/v1/roots', body: '{"items":[]}');
      await client(http).roots();
      final headers = http.requests.single.headers;
      expect(headers['Authorization'], 'Bearer tok');
      expect(headers['Accept-Language'], 'zh-CN');
      expect(headers['Accept'], 'application/json');
    });

    test('端点归一化：即便调用方没写 /api/v1 也补上', () async {
      final http = FakeHttpTransport()..route('GET', 'http://host:3090/api/v1/healthz', body: '{}');
      final c = DshClient(
        endpoint: 'http://host:3090/',
        token: null,
        http: http,
        deps: DshClientDeps(newId: _id, timeZoneId: _tz, languageTag: _lang),
      );
      await c.health();
      expect(http.requests.single.url, 'http://host:3090/api/v1/healthz');
    });

    test('缺令牌时鉴权请求抛 StateError，且不发请求', () async {
      final http = FakeHttpTransport();
      expect(() => client(http, token: null).roots(), throwsStateError);
      expect(http.requests, isEmpty);
    });
  });

  group('请求体', () {
    test('配对请求体去空白', () async {
      final http = FakeHttpTransport()
        ..route('POST', 'http://192.168.1.20:3090/api/v1/pairings/exchange', body: '{"token":"t","device":{"id":"d"}}');
      final result = await client(http, token: null).pair('  123  ', ' iPhone ');
      expect(result.token, 't');
      final body = jsonDecode(utf8.decode(http.requests.single.body!)) as Map<String, dynamic>;
      expect(body['code'], '123');
      expect(body['deviceName'], 'iPhone');
    });

    test('纯文本消息走旧形状 text + mode', () async {
      final http = FakeHttpTransport()
        ..route('POST', 'http://192.168.1.20:3090/api/v1/chat/sessions/s1/messages', status: 204);
      await client(http).sendText('s1', '你好', steer: true);
      final body = jsonDecode(utf8.decode(http.requests.single.body!)) as Map<String, dynamic>;
      expect(body['text'], '你好');
      expect(body['mode'], 'steer');
      expect(body.containsKey('content'), isFalse);
    });

    test('带附件消息走 content 数组，且按 type 只写该形态字段', () async {
      final http = FakeHttpTransport()
        ..route('POST', 'http://192.168.1.20:3090/api/v1/chat/sessions/s1/messages', status: 204);
      await client(http).sendMessage('s1', <PromptPart>[
        PromptPart.text('看图'),
        PromptPart.image('image/png', 'QUJD', name: 'a.png'),
        PromptPart.file('r1'),
      ]);
      final body = jsonDecode(utf8.decode(http.requests.single.body!)) as Map<String, dynamic>;
      final content = body['content'] as List<dynamic>;
      expect(content, hasLength(3));
      expect((content[1] as Map<String, dynamic>)['mediaType'], 'image/png');
      expect((content[1] as Map<String, dynamic>).containsKey('receiptId'), isFalse);
      expect((content[2] as Map<String, dynamic>)['receiptId'], 'r1');
    });

    test('写文件：无 etag 用 If-None-Match: *，有 etag 用 If-Match', () async {
      final http = FakeHttpTransport()
        ..route('PUT', 'http://192.168.1.20:3090/api/v1/roots/r1/content?path=a.txt', headers: <String, String>{'ETag': 'v2'});
      final c = client(http);
      final etag = await c.writeFile('r1', 'a.txt', utf8.encode('hi'));
      expect(etag, 'v2');
      expect(http.requests.single.headers['If-None-Match'], '*');

      final http2 = FakeHttpTransport()
        ..route('PUT', 'http://192.168.1.20:3090/api/v1/roots/r1/content?path=a.txt', headers: <String, String>{'ETag': 'v3'});
      await client(http2).writeFile('r1', 'a.txt', utf8.encode('hi'), etag: 'v2');
      expect(http2.requests.single.headers['If-Match'], 'v2');
    });

    test('路径段编码：附件 id 里的冒号被编码', () async {
      final http = FakeHttpTransport()
        ..route('GET', 'http://192.168.1.20:3090/api/v1/attachments/sha256%3Aaa?sessionId=s1', body: <int>[1, 2, 3]);
      final bytes = await client(http).readAttachment('s1', 'sha256:aa');
      expect(bytes, <int>[1, 2, 3]);
      expect(
        http.requests.single.url,
        'http://192.168.1.20:3090/api/v1/attachments/sha256%3Aaa?sessionId=s1',
      );
    });
  });

  group('错误映射', () {
    test('非 2xx 解析 code 与 message', () async {
      final http = FakeHttpTransport()
        ..route('GET', 'http://192.168.1.20:3090/api/v1/roots', status: 401, body: '{"error":{"code":"UNAUTHORIZED","message":"bad token"}}');
      await expectLater(
        client(http).roots(),
        throwsA(isA<DshApiException>()
            .having((DshApiException e) => e.status, 'status', 401)
            .having((DshApiException e) => e.code, 'code', 'UNAUTHORIZED')),
      );
    });

    test('resolvePath：授权根外返回 null；ROUTE_NOT_FOUND 必须抛', () async {
      final outside = FakeHttpTransport()
        ..route('GET', 'http://192.168.1.20:3090/api/v1/roots/resolve?path=%2Fetc%2Fpasswd', status: 404,
            body: '{"error":{"code":"PATH_OUTSIDE_ROOTS","message":"nope"}}');
      expect(await client(outside).resolvePath('/etc/passwd'), isNull);

      final old = FakeHttpTransport()
        ..route('GET', 'http://192.168.1.20:3090/api/v1/roots/resolve?path=%2Ftmp%2Fa', status: 404,
            body: '{"error":{"code":"ROUTE_NOT_FOUND","message":"no route"}}');
      await expectLater(client(old).resolvePath('/tmp/a'), throwsA(isA<DshApiException>()));
    });

    test('resolvePath 成功时解析出 rootId', () async {
      final http = FakeHttpTransport()
        ..route('GET', 'http://192.168.1.20:3090/api/v1/roots/resolve?path=%2Fw%2Fa.txt',
            body: '{"rootId":"r1","path":"a.txt","kind":"file","size":3}');
      final resolved = await client(http).resolvePath('/w/a.txt');
      expect(resolved!.rootId, 'r1');
      expect(resolved.size, 3);
    });

    test('404 无错误体时码为 HTTP_ERROR', () async {
      final http = FakeHttpTransport()..route('GET', 'http://192.168.1.20:3090/api/v1/trash', status: 404, body: 'not json');
      await expectLater(
        client(http).trash(),
        throwsA(isA<DshApiException>().having((DshApiException e) => e.code, 'code', 'HTTP_ERROR')),
      );
    });
  });

  group('事件流', () {
    test('WS URL 保持同源 http，不提前改 ws://', () async {
      final http = FakeHttpTransport();
      final socket = FakeWebSocketTransport();
      final c = DshClient(
        endpoint: 'http://192.168.1.20:3090',
        token: 'tok',
        http: http,
        deps: DshClientDeps(
          newId: _id,
          timeZoneId: _tz,
          languageTag: _lang,
          socket: socket,
          timers: FakeTimerBridge(),
        ),
      );
      final channel = c.events(listener: (_) {}, connection: (_) {});
      expect(socket.urls.single, 'http://192.168.1.20:3090/api/v1/events');
      channel.close();
    });

    test('未注入 WS 时打开事件流抛 StateError', () {
      final http = FakeHttpTransport();
      final c = DshClient(
        endpoint: 'http://host:3090',
        token: 't',
        http: http,
        deps: DshClientDeps(newId: _id, timeZoneId: _tz, languageTag: _lang),
      );
      expect(() => c.events(listener: (_) {}, connection: (_) {}), throwsStateError);
    });

    test('打开即上报 onOpen；重复 close 不抛', () async {
      final http = FakeHttpTransport();
      final socket = FakeWebSocketTransport();
      var opens = 0;
      final c = DshClient(
        endpoint: 'http://host:3090',
        token: 't',
        http: http,
        deps: DshClientDeps(
          newId: _id,
          timeZoneId: _tz,
          languageTag: _lang,
          socket: socket,
          timers: FakeTimerBridge(),
        ),
      );
      final channel = c.events(listener: (_) {}, connection: (bool open) {
        if (open) {
          opens++;
        }
      });
      await Future<void>.delayed(Duration.zero);
      expect(socket.urls, hasLength(1));
      expect(opens, 1);
      channel.close();
      channel.close();
    });
  });
}

String _id() => 'id';
String _tz() => 'Asia/Shanghai';
String _lang() => 'zh-CN';
