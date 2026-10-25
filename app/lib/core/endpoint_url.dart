/// 端点地址归一化 —— 逐条移植鸿蒙版 `core/EndpointUrl.ts`。
///
/// 与协议对齐的要点：接口前缀 `/api/v1` **不是**地址的一部分；
/// 用户填的基地址可以带也可以不带，归一化后必须恰好带一次。
///
/// 全部用字符串操作实现，不依赖 `Uri` 的宽松解析：同一份口径既跑在 App 里，
/// 也跑在纯 Dart 单测里，行为必须一致。
library;

/// 接口前缀。
const String apiSuffix = '/api/v1';

bool _startsWithHttp(String url) =>
    url.startsWith('http://') || url.startsWith('https://');

/// 取 URL 中「协议 + 主机」之后、不含查询串与锚点的路径部分（保持原编码）。
String encodedPathOf(String url) {
  final schemeEnd = url.indexOf('://');
  if (schemeEnd < 0) {
    return '';
  }
  var rest = url.substring(schemeEnd + 3);
  final hash = rest.indexOf('#');
  if (hash >= 0) {
    rest = rest.substring(0, hash);
  }
  final query = rest.indexOf('?');
  if (query >= 0) {
    rest = rest.substring(0, query);
  }
  final slash = rest.indexOf('/');
  if (slash < 0) {
    return '/';
  }
  return rest.substring(slash);
}

/// 严格归一：去首尾空白与尾斜杠，必须以 `http(s)://` 开头（否则抛错），
/// 路径不以 `/api/v1` 结尾则追加。
///
/// 这是**唯一故意抛异常**的归一入口：调用点都在「用户正在输入」的界面上，
/// 让他立刻看到地址写错，比拿着坏地址去请求好。
String normalizeEndpoint(String value) {
  final input = value.trim().replaceAll(RegExp(r'/+$'), '');
  if (!_startsWithHttp(input)) {
    throw const FormatException('Endpoint must start with http:// or https://');
  }
  final path = encodedPathOf(input).replaceAll(RegExp(r'/+$'), '');
  return path.endsWith(apiSuffix) ? input : '$input$apiSuffix';
}

/// 去掉末尾的 `/api/v1`（大小写敏感），再去尾斜杠。
String stripApiSuffix(String value) {
  var v = value;
  if (v.endsWith(apiSuffix)) {
    v = v.substring(0, v.length - apiSuffix.length).replaceAll(RegExp(r'/+$'), '');
  }
  return v;
}

/// 配置导入口径的基地址归一：去首尾空白与尾斜杠、去掉 `/api/v1`、协议名小写。幂等，不抛。
String shareNormalizeBaseUrl(String raw) {
  var value = raw.trim().replaceAll(RegExp(r'/+$'), '');
  value = stripApiSuffix(value);
  final lower = value.toLowerCase();
  if (lower.startsWith('http://')) {
    return 'http://${value.substring(7)}';
  }
  if (lower.startsWith('https://')) {
    return 'https://${value.substring(8)}';
  }
  return value;
}

/// HostStore 口径的基地址归一：缺协议补 `http://`，严格归一后去掉 `/api/v1`；
/// 严格归一抛错时退回「补协议后的原文」。
String storeNormalizeBaseUrl(String raw) {
  final trimmed = raw.trim().replaceAll(RegExp(r'/+$'), '');
  if (trimmed.isEmpty) {
    return '';
  }
  final withScheme = _startsWithHttp(trimmed) ? trimmed : 'http://$trimmed';
  try {
    return stripApiSuffix(normalizeEndpoint(withScheme));
  } on FormatException {
    return withScheme;
  }
}

/// 基础校验：去掉 `/api/v1` 之后是一个带主机名的 http(s) 地址。
bool isUsableBaseUrl(String raw) {
  final normalized = shareNormalizeBaseUrl(raw);
  int schemeLength;
  if (normalized.startsWith('http://')) {
    schemeLength = 7;
  } else if (normalized.startsWith('https://')) {
    schemeLength = 8;
  } else {
    return false;
  }
  final authority = normalized.substring(schemeLength).split('/').first;
  final host = authority.split(':').first;
  return host.trim().isNotEmpty;
}

/// 从基地址取主机名：去协议、路径、查询串、锚点与端口；IPv6 去掉方括号。
String hostNameOf(String baseUrl) {
  final withoutScheme =
      baseUrl.replaceFirst(RegExp(r'^http://'), '').replaceFirst(RegExp(r'^https://'), '');
  var authority = withoutScheme.split('/').first;
  authority = authority.split('?').first;
  authority = authority.split('#').first;
  String host;
  if (authority.startsWith('[')) {
    final close = authority.indexOf(']');
    host = close > 0 ? authority.substring(0, close).replaceFirst('[', '') : authority;
  } else {
    host = authority.split(':').first;
  }
  return host.trim().isNotEmpty ? host : baseUrl.trim();
}
