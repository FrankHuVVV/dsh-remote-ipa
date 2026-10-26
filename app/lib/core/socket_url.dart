/// WebSocket 地址换算。
///
/// 服务端契约要求「同源 http(s) URL，由底层做协议升级」——那是鸿蒙/OkHttp 的口径。
/// Dart 的 `dart:io WebSocket` 只认 `ws://` / `wss://`，直接传 `https://` 会抛
/// `WebSocketException: Unsupported URL scheme 'https'`（0.2.2 真机实测）。
///
/// 所以换算只发生在**平台层入口**这一处：core 仍然只产出同源 http(s)，可单测、可换实现。
library;

/// `http://` → `ws://`，`https://` → `wss://`；已是 ws/wss 或无法解析时原样返回。
String socketUrlOf(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) {
    return url;
  }
  switch (uri.scheme) {
    case 'https':
      return uri.replace(scheme: 'wss').toString();
    case 'http':
      return uri.replace(scheme: 'ws').toString();
    default:
      return url;
  }
}
