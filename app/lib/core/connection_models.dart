/// 连接层模型 —— 移植自鸿蒙版 `core/ConnectionModels.ts`。
///
/// 三个实体刻意分开，别合并：
/// - `Host` = 一台电脑（用户视角，有名字、有凭据）；
/// - `Endpoint` = 这台电脑的一个可达地址（一台电脑可以有任意多个）；
/// - `Credential` 挂在 Host 上，**不挂在地址上** —— 换地址不等于换身份。
library;

import 'json.dart';
import 'endpoint_url.dart';

/// 地址类型：决定选路加权与界面标注。
enum EndpointKind { lan, virtualNet, wan, unknown }

/// 凭据种类。iOS 侧只发设备令牌，另外两种留给「账号密码」的未来方案。
enum CredentialKind { deviceToken, password, customPassword }

String endpointKindToWire(EndpointKind kind) {
  switch (kind) {
    case EndpointKind.lan:
      return 'LAN';
    case EndpointKind.virtualNet:
      return 'VIRTUAL_NET';
    case EndpointKind.wan:
      return 'WAN';
    case EndpointKind.unknown:
      return 'UNKNOWN';
  }
}

EndpointKind endpointKindFromWire(String? raw) {
  switch (raw) {
    case 'LAN':
      return EndpointKind.lan;
    case 'VIRTUAL_NET':
      return EndpointKind.virtualNet;
    case 'WAN':
      return EndpointKind.wan;
    default:
      return EndpointKind.unknown;
  }
}

String credentialKindToWire(CredentialKind kind) {
  switch (kind) {
    case CredentialKind.password:
      return 'PASSWORD';
    case CredentialKind.customPassword:
      return 'CUSTOM_PASSWORD';
    case CredentialKind.deviceToken:
      return 'DEVICE_TOKEN';
  }
}

CredentialKind credentialKindFromWire(String? raw) {
  switch (raw) {
    case 'PASSWORD':
      return CredentialKind.password;
    case 'CUSTOM_PASSWORD':
      return CredentialKind.customPassword;
    default:
      return CredentialKind.deviceToken;
  }
}

/// 按地址猜类型：只做粗判，绝不抛异常（猜错只影响排序加权，真实可用性由探活决定）。
EndpointKind inferEndpointKind(String baseUrl) {
  var host = baseUrl.trim();
  if (host.startsWith('http://')) {
    host = host.substring(7);
  }
  if (host.startsWith('https://')) {
    host = host.substring(8);
  }
  final slash = host.indexOf('/');
  if (slash >= 0) {
    host = host.substring(0, slash);
  }
  final colon = host.indexOf(':');
  if (colon >= 0) {
    host = host.substring(0, colon);
  }
  host = host.toLowerCase();
  if (host.isEmpty) {
    return EndpointKind.unknown;
  }
  if (host == 'localhost' || host == '127.0.0.1' || host == '::1') {
    return EndpointKind.lan;
  }
  if (host.endsWith('.local')) {
    return EndpointKind.lan;
  }
  final parts = host.split('.');
  if (parts.length != 4) {
    return EndpointKind.unknown;
  }
  final octets = <int>[];
  for (final part in parts) {
    final n = int.tryParse(part);
    if (n == null || n < 0 || n > 255 || '$n' != part) {
      return EndpointKind.unknown;
    }
    octets.add(n);
  }
  final a = octets[0];
  final b = octets[1];
  if (a == 10) {
    return EndpointKind.lan;
  }
  if (a == 192 && b == 168) {
    return EndpointKind.lan;
  }
  if (a == 172 && b >= 16 && b <= 31) {
    return EndpointKind.lan;
  }
  if (a == 100 && b >= 64 && b <= 127) {
    return EndpointKind.virtualNet;
  }
  if (a == 169 && b == 254) {
    return EndpointKind.lan;
  }
  return EndpointKind.wan;
}

/// 一台电脑的一个可达地址。
class Endpoint {
  Endpoint({
    this.id = '',
    this.label = '',
    this.baseUrl = '',
    this.kind = EndpointKind.unknown,
    this.enabled = true,
    this.lastLatencyMs,
    this.lastCheckedAt,
    this.lastError,
  });

  String id;
  String label;

  /// 不含 `/api/v1` 的基地址。
  String baseUrl;
  EndpointKind kind;
  bool enabled;
  int? lastLatencyMs;
  int? lastCheckedAt;
  String? lastError;

  /// 由 label + baseUrl 构造：baseUrl 归一为不含 `/api/v1` 的基地址，kind 自动推断。
  factory Endpoint.create(String label, String baseUrl, String id) {
    final normalized = stripApiSuffix(normalizeEndpoint(baseUrl));
    return Endpoint(
      id: id,
      label: label.trim().isNotEmpty ? label : normalized,
      baseUrl: normalized,
      kind: inferEndpointKind(normalized),
    );
  }

  Endpoint withProbe(int? latencyMs, String? error, int checkedAt) => Endpoint(
        id: id,
        label: label,
        baseUrl: baseUrl,
        kind: kind,
        enabled: enabled,
        lastLatencyMs: latencyMs,
        lastCheckedAt: checkedAt,
        lastError: error,
      );

  Endpoint copy() => Endpoint(
        id: id,
        label: label,
        baseUrl: baseUrl,
        kind: kind,
        enabled: enabled,
        lastLatencyMs: lastLatencyMs,
        lastCheckedAt: lastCheckedAt,
        lastError: lastError,
      );

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'label': label,
        'baseUrl': baseUrl,
        'kind': endpointKindToWire(kind),
        'enabled': enabled,
        'lastLatencyMs': lastLatencyMs,
        'lastCheckedAt': lastCheckedAt,
        'lastError': lastError,
      };

  factory Endpoint.fromJson(Object? map) => Endpoint(
        id: stringOrNull(map, 'id') ?? '',
        label: stringOrNull(map, 'label') ?? '',
        baseUrl: stringOrNull(map, 'baseUrl') ?? '',
        kind: endpointKindFromWire(stringOrNull(map, 'kind')),
        enabled: boolOrNull(map, 'enabled') ?? true,
        lastLatencyMs: intOrNull(map, 'lastLatencyMs'),
        lastCheckedAt: intOrNull(map, 'lastCheckedAt'),
        lastError: stringOrNull(map, 'lastError'),
      );
}

/// 主机凭据。**明文不得落盘 / 不得写日志 / 不得进崩溃上报。**
class Credential {
  Credential({
    this.kind = CredentialKind.deviceToken,
    this.secret = '',
    this.deviceId,
    this.deviceName,
    this.scopes = const <String>[],
    this.issuedAt = 0,
    this.expiresAt,
  });

  CredentialKind kind;
  String secret;
  String? deviceId;
  String? deviceName;
  List<String> scopes;
  int issuedAt;
  int? expiresAt;

  bool isExpired(int now) => expiresAt != null && expiresAt! <= now;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'kind': credentialKindToWire(kind),
        'secret': secret,
        'deviceId': deviceId,
        'deviceName': deviceName,
        'scopes': scopes,
        'issuedAt': issuedAt,
        'expiresAt': expiresAt,
      };

  factory Credential.fromJson(Object? map) => Credential(
        kind: credentialKindFromWire(stringOrNull(map, 'kind')),
        secret: stringOrNull(map, 'secret') ?? '',
        deviceId: stringOrNull(map, 'deviceId'),
        deviceName: stringOrNull(map, 'deviceName'),
        scopes: stringArr(map, 'scopes'),
        issuedAt: intOrNull(map, 'issuedAt') ?? 0,
        expiresAt: intOrNull(map, 'expiresAt'),
      );
}

/// 一台电脑。
class Host {
  Host({
    required this.id,
    required this.displayName,
    this.endpoints = const <Endpoint>[],
    this.preferredEndpointId,
    this.credential,
    this.createdAt = 0,
    this.updatedAt = 0,
  });

  String id;
  String displayName;
  List<Endpoint> endpoints;
  String? preferredEndpointId;
  Credential? credential;
  int createdAt;
  int updatedAt;

  Endpoint? endpoint(String? id) {
    if (id == null) {
      return null;
    }
    for (final e in endpoints) {
      if (e.id == id) {
        return e;
      }
    }
    return null;
  }

  /// 参与探活的地址：启用中且地址非空。
  List<Endpoint> activeEndpoints() =>
      [for (final e in endpoints) if (e.enabled && e.baseUrl.trim().isNotEmpty) e];

  Host withEndpointProbe(String endpointId, int? latencyMs, String? error, int checkedAt) {
    final next = <Endpoint>[
      for (final e in endpoints)
        if (e.id == endpointId) e.withProbe(latencyMs, error, checkedAt) else e,
    ];
    return copy()
      ..endpoints = next
      ..updatedAt = checkedAt;
  }

  Host withPreferred(String? endpointId) => copy()..preferredEndpointId = endpointId;

  Host copy() => Host(
        id: id,
        displayName: displayName,
        endpoints: [for (final e in endpoints) e.copy()],
        preferredEndpointId: preferredEndpointId,
        credential: credential == null ? null : Credential.fromJson(credential!.toMap()),
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'displayName': displayName,
        'endpoints': [for (final e in endpoints) e.toMap()],
        'preferredEndpointId': preferredEndpointId,
        'credential': credential?.toMap(),
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  factory Host.fromJson(Object? map) {
    final rawEndpoints = objArr(map, 'endpoints');
    final credMap = obj(map, 'credential');
    return Host(
      id: stringOrNull(map, 'id') ?? '',
      displayName: stringOrNull(map, 'displayName') ?? '',
      endpoints: [for (final e in rawEndpoints) Endpoint.fromJson(e)],
      preferredEndpointId: stringOrNull(map, 'preferredEndpointId'),
      credential: credMap == null ? null : Credential.fromJson(credMap),
      createdAt: intOrNull(map, 'createdAt') ?? 0,
      updatedAt: intOrNull(map, 'updatedAt') ?? 0,
    );
  }
}

/// 一次探活的结果。
class EndpointProbe {
  const EndpointProbe(this.endpointId, this.ok, this.latencyMs, this.error);

  factory EndpointProbe.success(String endpointId, int latencyMs) =>
      EndpointProbe(endpointId, true, latencyMs, null);

  factory EndpointProbe.failure(String endpointId, String error) =>
      EndpointProbe(endpointId, false, null, error);

  final String endpointId;
  final bool ok;
  final int? latencyMs;
  final String? error;
}

/// 选路规则（与鸿蒙版 `EndpointSelection.rank` 同一套，单测锁死）：
/// 1. 只保留「成功且有延迟」的探活；全失败返回空。
/// 2. 主键：延迟升序。
/// 3. 局域网近似即优先：LAN 且延迟 ≤ 最快 × 1.5 并入第 0 档。
/// 4. 并列：preferredEndpointId 优先，其次 lastCheckedAt（null 视为最旧）。
class EndpointSelection {
  static const double lanLatencyTolerance = 1.5;

  static List<EndpointProbe> rank(
    List<EndpointProbe> probes,
    List<Endpoint> endpoints,
    String? preferredId,
  ) {
    final ok = [
      for (final p in probes)
        if (p.ok && p.latencyMs != null) p,
    ];
    if (ok.isEmpty) {
      return const <EndpointProbe>[];
    }
    var fastest = 9007199254740991;
    for (final p in ok) {
      final latency = p.latencyMs!;
      if (latency < fastest) {
        fastest = latency;
      }
    }
    final kindById = <String, EndpointKind>{};
    final checkedById = <String, int>{};
    for (final e in endpoints) {
      kindById[e.id] = e.kind;
      checkedById[e.id] = e.lastCheckedAt ?? -9007199254740991;
    }
    int tierOf(EndpointProbe p) {
      final kind = kindById[p.endpointId];
      if (kind == EndpointKind.lan && p.latencyMs! <= fastest * lanLatencyTolerance) {
        return 0;
      }
      return 1;
    }

    int checkedOf(EndpointProbe p) => checkedById[p.endpointId] ?? -9007199254740991;

    final sorted = List<EndpointProbe>.of(ok);
    sorted.sort((x, y) {
      final tier = tierOf(x) - tierOf(y);
      if (tier != 0) {
        return tier;
      }
      final latency = x.latencyMs! - y.latencyMs!;
      if (latency != 0) {
        return latency;
      }
      final px = x.endpointId == preferredId ? 0 : 1;
      final py = y.endpointId == preferredId ? 0 : 1;
      if (px != py) {
        return px - py;
      }
      return checkedOf(x) - checkedOf(y);
    });
    return sorted;
  }
}

/// 选路结果。
class ConnectionTarget {
  const ConnectionTarget(this.host, this.endpoint, this.probes);

  final Host host;
  final Endpoint endpoint;
  final List<EndpointProbe> probes;
}
