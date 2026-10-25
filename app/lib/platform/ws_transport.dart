/// 平台 WebSocket 实现 —— 对应鸿蒙版 `platform/WebSocketTransport.ets`。
///
/// 契约：传进来的 URL 是**同源 http(s)**，由 `WebSocketChannel` 做协议升级；
/// `onDown` 只报一次（关闭或失败，谁先到算谁）。
library;

import 'dart:async';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/dsh_client.dart';

class WebSocketTransportImpl implements WebSocketTransport {
  const WebSocketTransportImpl();

  @override
  EventSocketHandle open(String url, Map<String, String> headers, WebSocketCallbacks callbacks) =>
      _SocketHandle(url, headers, callbacks);
}

class _SocketHandle implements EventSocketHandle {
  _SocketHandle(String url, Map<String, String> headers, WebSocketCallbacks callbacks) {
    var reportedDown = false;
    void reportDown(String reason) {
      if (reportedDown) {
        return;
      }
      reportedDown = true;
      callbacks.onDown(reason);
    }

    try {
      _channel = IOWebSocketChannel.connect(
        Uri.parse(url),
        headers: headers,
        pingInterval: const Duration(milliseconds: wsPingIntervalMs),
        connectTimeout: const Duration(milliseconds: connectTimeoutMs),
      );
    } on Object catch (error) {
      scheduleMicrotask(() => reportDown('$error'));
      return;
    }
    _channel!.ready.then((_) {
      callbacks.onOpen();
    }).catchError((Object error) {
      reportDown('$error');
    });
    _subscription = _channel!.stream.listen(
      (Object? message) {
        if (message is String) {
          callbacks.onMessage(message);
        } else if (message is List<int>) {
          callbacks.onMessage(String.fromCharCodes(message));
        }
      },
      onError: (Object error) => reportDown('$error'),
      onDone: () => reportDown('closed'),
      cancelOnError: false,
    );
  }

  WebSocketChannel? _channel;
  StreamSubscription<Object?>? _subscription;
  bool _closed = false;

  @override
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _subscription?.cancel();
    _channel?.sink.close();
  }
}
