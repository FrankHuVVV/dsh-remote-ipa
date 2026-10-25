/// 宽松 JSON 取值 —— 移植自鸿蒙版 `core/JsonAccess.ts`。
///
/// 服务端会漏字段、发 null、把数字发成字符串。这里的取值为**全部返回可空**，
/// 认不出就返回 null，绝不抛异常：一次字段缺失不该让整页数据打挂。
library;

import 'dart:convert';

/// 任意形态 → `Map<String, dynamic>`；不是映射返回 null。
Map<String, dynamic>? asMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    final out = <String, dynamic>{};
    value.forEach((dynamic key, dynamic v) {
      out['$key'] = v;
    });
    return out;
  }
  return null;
}

/// 取原始值（不转换）。
Object? raw(Object? map, String key) {
  final m = asMap(map);
  if (m == null) {
    return null;
  }
  return m[key];
}

/// 取子对象。
Map<String, dynamic>? obj(Object? map, String key) => asMap(raw(map, key));

/// 取数组（非数组一律空列表）。
List<Object?> arr(Object? map, String key) {
  final value = raw(map, key);
  if (value is List) {
    return value;
  }
  return const <Object?>[];
}

/// 取对象数组：非对象元素被丢弃。
List<Map<String, dynamic>> objArr(Object? map, String key) {
  final out = <Map<String, dynamic>>[];
  for (final item in arr(map, key)) {
    final m = asMap(item);
    if (m != null) {
      out.add(m);
    }
  }
  return out;
}

/// 取字符串；数字 / 布尔不转（那是 `eventDataString` 的口径，不是这里的）。
String? stringOrNull(Object? map, String key) {
  final value = raw(map, key);
  return value is String ? value : null;
}

/// 取数字（整数与小数都收）。
num? numOrNull(Object? map, String key) {
  final value = raw(map, key);
  if (value is num) {
    return value;
  }
  return null;
}

/// 取整数：接受整数值的 double，拒绝 3.5 / NaN / Infinity。
int? intOrNull(Object? map, String key) {
  final value = raw(map, key);
  if (value is int) {
    return value;
  }
  if (value is double && value.isFinite && value == value.truncateToDouble()) {
    return value.toInt();
  }
  return null;
}

/// 取布尔：只认真正的布尔，不把 `"true"` 当 true。
bool? boolOrNull(Object? map, String key) {
  final value = raw(map, key);
  return value is bool ? value : null;
}

/// 取字符串数组：非字符串元素丢弃。
List<String> stringArr(Object? map, String key) {
  final out = <String>[];
  for (final item in arr(map, key)) {
    if (item is String) {
      out.add(item);
    }
  }
  return out;
}

/// 解析 JSON 文本；失败返回 null（不抛）。
Object? parseJson(String text) {
  if (text.isEmpty) {
    return null;
  }
  try {
    return jsonDecode(text);
  } on FormatException {
    return null;
  }
}

/// 解析成对象；失败返回 null。
Map<String, dynamic>? parseMap(String text) => asMap(parseJson(text));

/// 编码为 UTF-8 字节。
List<int> utf8Encode(String text) => utf8.encode(text);

/// UTF-8 字节解码（坏字节按替换字符处理，不抛）。
String utf8Decode(List<int> bytes) => utf8.decode(bytes, allowMalformed: true);
