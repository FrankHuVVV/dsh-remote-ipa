/// 平台 HTTP 实现 —— 对应鸿蒙版 `platform/HttpTransport.ets`。
///
/// 只做「把 [HttpRequest] 变成一次真实请求」：不重试、不缓存、不改写 URL。
/// 响应头一律转小写（`HttpResponse.header` 的契约）。
library;

import 'dart:async';

import 'package:http/http.dart' as http;

import '../core/dsh_client.dart';

class HttpTransportImpl implements HttpTransport {
  HttpTransportImpl({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<HttpResponse> request(HttpRequest request) async {
    final uri = Uri.parse(request.url);
    final headers = <String, String>{...request.headers};
    final body = request.body;

    final future = _client.send(http.Request(request.method, uri)
      ..headers.addAll(headers)
      ..bodyBytes = body ?? const <int>[]);

    final streamed = await future.timeout(
      Duration(milliseconds: request.connectTimeoutMs + request.readTimeoutMs),
      onTimeout: () => throw TimeoutException('request timeout', Duration(milliseconds: request.readTimeoutMs)),
    );
    final bytes = await streamed.stream.toBytes().timeout(
          Duration(milliseconds: request.readTimeoutMs),
          onTimeout: () =>
              throw TimeoutException('read timeout', Duration(milliseconds: request.readTimeoutMs)),
        );
    final responseHeaders = <String, String>{};
    streamed.headers.forEach((key, value) {
      responseHeaders[key.toLowerCase()] = value;
    });
    return HttpResponse(status: streamed.statusCode, headers: responseHeaders, body: bytes);
  }

  void close() => _client.close();
}

/// 平台定时器（WS 退避用）。
class TimerBridgeImpl implements TimerBridge {
  final Map<int, Timer> _timers = <int, Timer>{};
  int _next = 0;

  @override
  int schedule(int delayMs, void Function() action) {
    final handle = _next++;
    _timers[handle] = Timer(Duration(milliseconds: delayMs), () {
      _timers.remove(handle);
      action();
    });
    return handle;
  }

  @override
  void cancel(int handle) {
    _timers.remove(handle)?.cancel();
  }

  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }
}
