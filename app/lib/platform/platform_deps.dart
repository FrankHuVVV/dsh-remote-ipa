/// 平台能力 —— 对应鸿蒙版 `platform/Platform.ets`。
///
/// 这一层是**唯一**碰系统 API 的地方（时间、时区、UUID、设备名），因此也是唯一
/// 无法离线单测的一层。逻辑层只通过 [PlatformDeps] 拿这些值。
library;

import 'dart:math';

import 'package:flutter_timezone/flutter_timezone.dart';

class PlatformDeps {
  PlatformDeps({String Function()? uuid, Future<String> Function()? timeZone, String Function()? deviceName})
      : _uuid = uuid ?? _defaultUuid,
        _timeZone = timeZone ?? _defaultTimeZone,
        _deviceName = deviceName ?? (() => 'iPhone');

  final String Function() _uuid;
  final Future<String> Function() _timeZone;
  final String Function() _deviceName;

  String newId() => _uuid();

  /// IANA 时区 id（如 `Asia/Shanghai`）；取不到时退回本地偏移形式。
  Future<String> timeZoneId() async {
    try {
      final info = await _timeZone();
      return info.trim();
    } on Object {
      final offset = DateTime.now().timeZoneOffset;
      final sign = offset.isNegative ? '-' : '+';
      final hours = offset.inHours.abs().toString().padLeft(2, '0');
      final minutes = offset.inMinutes.abs().remainder(60).toString().padLeft(2, '0');
      return 'UTC$sign$hours:$minutes';
    }
  }

  String deviceName() => _deviceName();

  static String _defaultUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    final chars = bytes.map(hex).join();
    return '${chars.substring(0, 8)}-${chars.substring(8, 12)}-${chars.substring(12, 16)}-'
        '${chars.substring(16, 20)}-${chars.substring(20)}';
  }

  static Future<String> _defaultTimeZone() async =>
      (await FlutterTimezone.getLocalTimezone()).identifier;
}
