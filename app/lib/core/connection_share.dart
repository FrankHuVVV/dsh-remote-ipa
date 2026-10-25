/// 配置导入 —— 移植自鸿蒙版 `core/ConnectionShare.ts`。
///
/// 场景是「人已经出门在外，电脑留在家里」：任何要求配对时电脑在旁的方案都会卡死，
/// 所以把连接信息压成一段能塞进微信的短文本：`DSH1:<Base64URL(JSON)>`。
///
/// 因此解码容错要求高于普通解析：用户粘贴时已经离开电脑，此刻失败就等于整个方案失败。
/// 反过来 `encode` 会严格校验并在坏输入上抛错 —— 生成端人还在电脑旁，能立刻改。
///
/// **安全边界**：这段文本不加密，它本身就是凭据载体（内含设备令牌）。只发给自己。
library;

import 'dart:convert';

import 'connection_models.dart';
import 'endpoint_url.dart';
import 'json.dart';

const String sharePrefix = 'DSH1:';

const String _fallbackHostName = '电脑';

const List<String> _invisibleChars = <String>[
  '\uFEFF',
  '\u200B',
  '\u200C',
  '\u200D',
  '\u2060',
];

/// 分享用地址：只有 label 与 baseUrl（id 用于承载解码端多塞进来的值，可为空）。
class ShareEndpoint {
  const ShareEndpoint({this.label = '', this.baseUrl = '', this.id = ''});

  final String label;
  final String baseUrl;
  final String id;

  factory ShareEndpoint.fromJson(Object? map) => ShareEndpoint(
        label: stringOrNull(map, 'label') ?? '',
        baseUrl: stringOrNull(map, 'baseUrl') ?? '',
        id: stringOrNull(map, 'id') ?? '',
      );
}

/// 解码得到的配置（尚未变成 Host）。
class SharePayload {
  const SharePayload({
    this.displayName = '',
    this.endpoints = const <ShareEndpoint>[],
    this.token,
    this.deviceName,
    this.scopes = const <String>[],
  });

  final String displayName;
  final List<ShareEndpoint> endpoints;
  final String? token;
  final String? deviceName;
  final List<String> scopes;
}

String? _nonEmptyOrNull(String? value) {
  if (value == null) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isNotEmpty ? trimmed : null;
}

List<String> _cleanScopes(List<String> scopes) {
  final out = <String>[];
  for (final s in scopes) {
    final t = s.trim();
    if (t.isNotEmpty) {
      out.add(t);
    }
  }
  return out;
}

String defaultIdFactory() {
  final a = DateTime.now().microsecondsSinceEpoch & 0xFFFFFFFF;
  final b = (DateTime.now().millisecondsSinceEpoch ^ (a << 7)) & 0xFFFFFFFF;
  return '${b.toRadixString(16)}-${a.toRadixString(16)}';
}

/// `DSH1:` 文本的编解码。
class ConnectionShare {
  /// 把配置编码成可粘贴文本。非法输入抛 [FormatException]（唯一故意抛异常处）。
  static String encode(SharePayload payload) {
    final displayName = payload.displayName.trim();
    final endpoints = <ShareEndpoint>[];
    for (final e in payload.endpoints) {
      endpoints.add(ShareEndpoint(
        label: e.label.trim(),
        baseUrl: shareNormalizeBaseUrl(e.baseUrl),
      ));
    }
    if (endpoints.isEmpty) {
      throw const FormatException('至少需要一个地址才能生成配置文本');
    }
    for (final e in endpoints) {
      if (!isUsableBaseUrl(e.baseUrl)) {
        throw FormatException('地址必须是 http:// 或 https:// 开头：${e.baseUrl}');
      }
    }

    final parts = <String>[];
    if (displayName.isNotEmpty) {
      parts.add('"displayName":${jsonEncode(displayName)}');
    }
    final epParts = <String>[];
    for (final e in endpoints) {
      final inner = <String>[];
      if (e.label.isNotEmpty) {
        inner.add('"label":${jsonEncode(e.label)}');
      }
      inner.add('"baseUrl":${jsonEncode(e.baseUrl)}');
      epParts.add('{${inner.join(',')}}');
    }
    parts.add('"endpoints":[${epParts.join(',')}]');
    final token = _nonEmptyOrNull(payload.token);
    if (token != null) {
      parts.add('"token":${jsonEncode(token)}');
    }
    final deviceName = _nonEmptyOrNull(payload.deviceName);
    if (deviceName != null) {
      parts.add('"deviceName":${jsonEncode(deviceName)}');
    }
    final scopes = _cleanScopes(payload.scopes);
    if (scopes.isNotEmpty) {
      parts.add('"scopes":${jsonEncode(scopes)}');
    }

    final body = '{${parts.join(',')}}';
    return sharePrefix + base64Url.encode(utf8.encode(body)).replaceAll('=', '');
  }

  /// 解析用户粘贴的文本。任何失败返回 null，绝不抛。
  static SharePayload? decode(String text) {
    final body = _stripPrefix(_clean(text));
    final bytes = decodeBase64Either(body);
    if (bytes == null) {
      return null;
    }
    final raw = utf8Decode(bytes);
    final map = _parseWire(raw);
    if (map == null) {
      return null;
    }
    final payload = _toPayload(map);
    return _isUsable(payload) ? payload : null;
  }

  /// 把配置变成可入库的 Host：地址 id 沿用 payload 已有的，没有则派生 `<hostId>-ep{n}`。
  static Host buildHost(
    SharePayload payload, {
    String Function()? idFactory,
    int Function()? clock,
  }) {
    final makeId = idFactory ?? defaultIdFactory;
    final now = clock == null ? DateTime.now().millisecondsSinceEpoch : clock();
    final hostId = makeId();

    final endpoints = <Endpoint>[];
    for (var i = 0; i < payload.endpoints.length; i++) {
      final src = payload.endpoints[i];
      final baseUrl = shareNormalizeBaseUrl(src.baseUrl);
      final id = src.id.trim().isNotEmpty ? src.id.trim() : '$hostId-ep${i + 1}';
      final label = src.label.trim().isNotEmpty ? src.label.trim() : baseUrl;
      endpoints.add(Endpoint.create(label, baseUrl, id));
    }

    final token = _nonEmptyOrNull(payload.token);
    final credential = token == null
        ? null
        : Credential(
            kind: CredentialKind.deviceToken,
            secret: token,
            deviceName: _nonEmptyOrNull(payload.deviceName),
            scopes: _cleanScopes(payload.scopes),
            issuedAt: now,
          );

    final displayName =
        payload.displayName.trim().isNotEmpty ? payload.displayName.trim() : _fallbackHostName;

    return Host(
      id: hostId,
      displayName: displayName,
      endpoints: endpoints,
      credential: credential,
      createdAt: now,
      updatedAt: now,
    );
  }

  static bool _isUsable(SharePayload payload) {
    if (payload.endpoints.isEmpty) {
      return false;
    }
    for (final e in payload.endpoints) {
      if (!isUsableBaseUrl(e.baseUrl)) {
        return false;
      }
    }
    return true;
  }

  /// 去掉所有空白（微信换行、邮件折行、全角空格、nbsp）与零宽字符。
  static String _clean(String text) {
    final buffer = StringBuffer();
    for (final rune in text.runes) {
      final ch = String.fromCharCode(rune);
      if (ch.trim().isEmpty) {
        continue;
      }
      if (_invisibleChars.contains(ch)) {
        continue;
      }
      buffer.write(ch);
    }
    return buffer.toString();
  }

  /// 前缀可选、大小写不敏感、允许出现在整段任意位置。
  static String _stripPrefix(String text) {
    final at = text.toUpperCase().indexOf(sharePrefix);
    return at >= 0 ? text.substring(at + sharePrefix.length) : text;
  }

  /// 先按原样解析；失败则截最外层 `{...}` 再试。
  static Map<String, dynamic>? _parseWire(String raw) {
    final direct = parseMap(raw);
    if (direct != null) {
      return direct;
    }
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) {
      return null;
    }
    return parseMap(raw.substring(start, end + 1));
  }

  static SharePayload _toPayload(Map<String, dynamic>? map) {
    final endpoints = <ShareEndpoint>[];
    for (final item in objArr(map, 'endpoints')) {
      final src = ShareEndpoint.fromJson(item);
      endpoints.add(ShareEndpoint(
        label: src.label,
        baseUrl: shareNormalizeBaseUrl(src.baseUrl),
        id: src.id.trim(),
      ));
    }
    return SharePayload(
      displayName: (stringOrNull(map, 'displayName') ?? '').trim(),
      endpoints: endpoints,
      token: _nonEmptyOrNull(stringOrNull(map, 'token')),
      deviceName: _nonEmptyOrNull(stringOrNull(map, 'deviceName')),
      scopes: _cleanScopes(stringArr(map, 'scopes')),
    );
  }
}

/// 宽容 Base64 解码：先只保留字母表字符，长度 `%4==1` 判死，补填充，先 URL-safe 再标准字母表。
List<int>? decodeBase64Either(String input) {
  final filtered = StringBuffer();
  for (final rune in input.runes) {
    final ch = String.fromCharCode(rune);
    final isAlphaNum = RegExp(r'[A-Za-z0-9]').hasMatch(ch);
    if (isAlphaNum || ch == '+' || ch == '/' || ch == '-' || ch == '_' || ch == '=') {
      filtered.write(ch);
    }
  }
  var body = filtered.toString();
  if (body.isEmpty || body.length % 4 == 1) {
    return null;
  }
  while (body.length % 4 != 0) {
    body += '=';
  }
  for (final decoder in <Base64Codec>[base64Url, base64]) {
    try {
      return decoder.decode(body);
    } on FormatException {
      continue;
    }
  }
  return null;
}
