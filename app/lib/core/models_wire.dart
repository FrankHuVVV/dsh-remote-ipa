/// 线上模型 —— **传输层基础**：健康检查 / 根 / 设备 / 配对 / API 异常。
///
/// 三条贯穿全模型的规矩（来自鸿蒙版 `core/Models.ts` 文件头）：
/// 1. 字段一律给默认值：缺键 / 显式 null / 类型不符 → 退化为默认值，**绝不抛异常**；
/// 2. 编码请求体时 null 一律省略（对齐 kotlinx `encodeDefaults=false`）；
/// 3. 判别联合按 `type` 分派，只写该形态的字段。
library;

import 'dart:convert';

import 'json.dart';

/// 编码为 JSON 文本。所有出站请求体都走这里，避免各处 `jsonEncode` 口径漂移。
String encodeJson(Object? value) => jsonEncode(value);

/// 请求体 JSON 拼装：null 字段不写。
class WireBuilder {
  final Map<String, dynamic> _map = <String, dynamic>{};

  WireBuilder put(String key, Object? value) {
    if (value != null) {
      _map[key] = value;
    }
    return this;
  }

  WireBuilder putIf(bool flag, String key, Object? value) => flag ? put(key, value) : this;

  Map<String, dynamic> buildMap() => _map;

  String build() => encodeJson(_map);
}

/// 健康检查。
class HealthView {
  HealthView({this.ok = false, this.version = '', this.pluginVersion});

  bool ok;
  String version;
  String? pluginVersion;

  factory HealthView.fromJson(Object? map) => HealthView(
        ok: boolOrNull(map, 'ok') ?? false,
        version: stringOrNull(map, 'version') ?? '',
        pluginVersion: stringOrNull(map, 'pluginVersion'),
      );
}

/// 授权根目录。
class RootView {
  RootView({this.id = '', this.label = '', this.createdAt = 0});

  String id;
  String label;
  int createdAt;

  factory RootView.fromJson(Object? map) => RootView(
        id: stringOrNull(map, 'id') ?? '',
        label: stringOrNull(map, 'label') ?? '',
        createdAt: intOrNull(map, 'createdAt') ?? 0,
      );
}

/// 当前设备（服务端视角）。
class DeviceView {
  DeviceView({
    this.id = '',
    this.name = '',
    this.scopes = const <String>[],
    this.rootIds = const <String>[],
  });

  String id;
  String name;
  List<String> scopes;
  List<String> rootIds;

  factory DeviceView.fromJson(Object? map) => DeviceView(
        id: stringOrNull(map, 'id') ?? '',
        name: stringOrNull(map, 'name') ?? '',
        scopes: stringArr(map, 'scopes'),
        rootIds: stringArr(map, 'rootIds'),
      );
}

/// 配对结果。
class PairingResult {
  PairingResult({this.token = '', DeviceView? device}) : device = device ?? DeviceView();

  String token;
  DeviceView device;

  factory PairingResult.fromJson(Object? map) => PairingResult(
        token: stringOrNull(map, 'token') ?? '',
        device: DeviceView.fromJson(obj(map, 'device')),
      );
}

/// 非 2xx 且响应体 `{error:{code,message,requestId?}}` 可解析时抛出的异常。
class DshApiException implements Exception {
  const DshApiException(this.status, this.code, this.message);

  final int status;
  final String code;
  final String message;

  @override
  String toString() => 'DshApiException($status $code): $message';
}
