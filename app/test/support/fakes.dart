/// 测试替身：内存存储、假 HTTP、假 WS、假定时器。
///
/// 这些替身让 core 与 state 层完全脱离平台：单测不碰网络、不睡觉、不读钥匙串。
library;

import 'dart:async';
import 'dart:convert';

import 'package:dsh_companion_ios/core/dsh_client.dart';
import 'package:dsh_companion_ios/core/host_store.dart';

class MemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> values = <String, String>{};

  @override
  String? getString(String key) => values[key];

  @override
  void putString(String key, String value) => values[key] = value;

  @override
  void remove(String key) => values.remove(key);
}

/// 「加密」= 反转 + Base64，足以断言「明文没有直接落盘」。
class MemorySecretBox implements SecretBox {
  int encryptions = 0;

  @override
  Future<String> encrypt(String plaintext) async {
    encryptions++;
    final reversed = plaintext.split('').reversed.join();
    return 'box:${base64Encode(utf8.encode(reversed))}';
  }

  @override
  Future<String?> decrypt(String ciphertext) async {
    if (!ciphertext.startsWith('box:')) {
      return null;
    }
    try {
      final reversed = utf8.decode(base64Decode(ciphertext.substring(4)));
      return reversed.split('').reversed.join();
    } on Object {
      return null;
    }
  }
}

class FakeHttpTransport implements HttpTransport {
  FakeHttpTransport();

  final List<HttpRequest> requests = <HttpRequest>[];
  final Map<String, HttpResponse> _routes = <String, HttpResponse>{};
  Object? error;

  void route(String method, String url, {int status = 200, Object? body, Map<String, String>? headers}) {
    _routes['$method $url'] = HttpResponse(
      status: status,
      headers: <String, String>{
        for (final entry in (headers ?? const <String, String>{}).entries)
          entry.key.toLowerCase(): entry.value,
      },
      body: body == null
          ? const <int>[]
          : (body is String ? utf8.encode(body) : (body as List<int>)),
    );
  }

  @override
  Future<HttpResponse> request(HttpRequest request) async {
    requests.add(request);
    if (error != null) {
      throw error!;
    }
    final response = _routes['${request.method} ${request.url}'];
    if (response != null) {
      return response;
    }
    // 前缀匹配必须同时认方法：同一路径的 GET / POST 会互相遮蔽。
    // 再按「最长 URL 优先」：否则 `/chat/sessions` 会把 `/chat/sessions/s1/messages` 吃掉。
    final candidates = _routes.entries
        .where((MapEntry<String, HttpResponse> entry) =>
            entry.key.startsWith('${request.method} ') &&
            request.url.startsWith(entry.key.split(' ').skip(1).join(' ')))
        .toList()
      ..sort((MapEntry<String, HttpResponse> a, MapEntry<String, HttpResponse> b) =>
          b.key.length - a.key.length);
    if (candidates.isNotEmpty) {
      return candidates.first.value;
    }
    return HttpResponse(status: 404, headers: const <String, String>{}, body: utf8.encode('{"error":{"code":"ROUTE_NOT_FOUND","message":"no route"}}'));
  }
}

class FakeWebSocketTransport implements WebSocketTransport {
  FakeWebSocketTransport();

  final List<String> urls = <String>[];

  /// 由测试手动推送事件。
  void Function(String text)? emit;
  void Function()? connection;

  @override
  EventSocketHandle open(String url, Map<String, String> headers, WebSocketCallbacks callbacks) {
    urls.add(url);
    emit = callbacks.onMessage;
    connection = callbacks.onOpen;
    scheduleMicrotask(callbacks.onOpen);
    return _FakeHandle(callbacks);
  }
}

class _FakeHandle implements EventSocketHandle {
  _FakeHandle(this.callbacks);

  final WebSocketCallbacks callbacks;
  bool closed = false;

  @override
  void close() {
    closed = true;
  }
}

class FakeTimerBridge implements TimerBridge {
  final Map<int, void Function()> _pending = <int, void Function()>{};
  int _next = 0;

  /// 立即执行所有挂起的回调（替代真实的等待）。
  void flush() {
    final actions = List<void Function()>.of(_pending.values);
    _pending.clear();
    for (final action in actions) {
      action();
    }
  }

  @override
  int schedule(int delayMs, void Function() action) {
    final handle = _next++;
    _pending[handle] = action;
    return handle;
  }

  @override
  void cancel(int handle) => _pending.remove(handle);
}
