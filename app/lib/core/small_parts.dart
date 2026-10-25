/// 小工具模块合集 —— 逐条移植鸿蒙版 `core/` 里那些「一条规则一个文件」的小件。
///
/// 全部纯逻辑、无平台依赖、可单测。平台相关的实现见 `lib/platform/`。
library;

import 'chat_presentation.dart';

// ---------------------------------------------------------------------------
// 字号
// ---------------------------------------------------------------------------

const double fontScaleDefault = 1.0;
const double fontScaleMin = 0.8;
const double fontScaleMax = 1.5;

/// 归一化字号倍数：坏值（NaN / 越界 / 非数字）回落到 1.0。
///
/// 一个坏偏好绝不能变成「整个界面用 NaN 尺寸测量」—— 那是白屏且不崩，最难查的一种。
double normalizeFontScale(double? value) {
  if (value == null || value.isNaN || value.isInfinite) {
    return fontScaleDefault;
  }
  if (value < fontScaleMin) {
    return fontScaleMin;
  }
  if (value > fontScaleMax) {
    return fontScaleMax;
  }
  return (value * 10).round() / 10;
}

/// 实际生效的字号倍数：跟随系统时这层不做缩放。
double effectiveFontScale({required bool followsSystem, required double scale}) =>
    followsSystem ? 1.0 : normalizeFontScale(scale);

// ---------------------------------------------------------------------------
// 主题
// ---------------------------------------------------------------------------

const String themeModeSystem = 'system';
const String themeModeLight = 'light';
const String themeModeDark = 'dark';

/// 归一化主题档位。存的是线上取值而不是枚举序数（升级安全）；认不出的回落跟随系统。
String normalizeThemeMode(String? raw) {
  switch (raw) {
    case themeModeLight:
    case themeModeDark:
    case themeModeSystem:
      return raw!;
    default:
      return themeModeSystem;
  }
}

// ---------------------------------------------------------------------------
// 发送方式
// ---------------------------------------------------------------------------

const String sendModeQueue = 'queue';
const String sendModeSteer = 'steer';

String oppositeSendMode(String mode) => mode == sendModeSteer ? sendModeQueue : sendModeSteer;

String normalizeSendMode(String? raw) => raw == sendModeSteer ? sendModeSteer : sendModeQueue;

// ---------------------------------------------------------------------------
// 大小 / 体积格式化
// ---------------------------------------------------------------------------

/// 人类可读体积（二进制单位，与文件页一致）。
String formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  const units = <String>['KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = -1;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${oneDecimal(value)} ${units[unit]}';
}

// ---------------------------------------------------------------------------
// 会话分组（列表页按「今天 / 昨天 / 本周 / 更早」）
// ---------------------------------------------------------------------------

const String sessionGroupToday = '今天';
const String sessionGroupYesterday = '昨天';
const String sessionGroupWeek = '本周';
const String sessionGroupEarlier = '更早';

/// 按 `updatedAt`（毫秒）把会话分档；`0`（没有时间）落进「更早」。
String sessionGroupOf(int updatedAt, {DateTime? now}) {
  if (updatedAt <= 0) {
    return sessionGroupEarlier;
  }
  final current = now ?? DateTime.now();
  final at = DateTime.fromMillisecondsSinceEpoch(updatedAt);
  final today = DateTime(current.year, current.month, current.day);
  final day = DateTime(at.year, at.month, at.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) {
    return sessionGroupToday;
  }
  if (diff == 1) {
    return sessionGroupYesterday;
  }
  if (diff < 7) {
    return sessionGroupWeek;
  }
  return sessionGroupEarlier;
}

// ---------------------------------------------------------------------------
// 时间标签（消息气泡内的 `12:50`）
// ---------------------------------------------------------------------------

String twoDigits(int value) => value < 10 ? '0$value' : '$value';

/// 消息时间标签。`0` 表示「没有时间」，返回 null（界面不显示）。
String? chatTimeLabel(int timeMs, {DateTime? now}) {
  if (timeMs <= 0) {
    return null;
  }
  final at = DateTime.fromMillisecondsSinceEpoch(timeMs);
  final current = now ?? DateTime.now();
  final sameDay = at.year == current.year && at.month == current.month && at.day == current.day;
  final hhmm = '${twoDigits(at.hour)}:${twoDigits(at.minute)}';
  if (sameDay) {
    return hhmm;
  }
  if (at.year == current.year) {
    return '${at.month}/${at.day} $hhmm';
  }
  return '${at.year}/${at.month}/${at.day} $hhmm';
}

// ---------------------------------------------------------------------------
// 会话序号监控（断档检测）
// ---------------------------------------------------------------------------

/// 严格跳号才算断档；重复与倒退算去重，不算断档（否则每次重连都白拉一遍）。
class ChatSeqMonitor {
  int? _last;

  int? get last => _last;

  void reset() {
    _last = null;
  }

  /// 返回 true 表示「历史与事件流之间有洞，必须重拉」。
  bool observe(int seq) {
    final previous = _last;
    if (previous == null) {
      _last = seq;
      return false;
    }
    if (seq <= previous) {
      return false;
    }
    final gap = seq > previous + 1;
    _last = seq;
    return gap;
  }
}

// ---------------------------------------------------------------------------
// 能力位
// ---------------------------------------------------------------------------

const String archiveListCapability = 'session-archive-list-v1';
const List<String> requiredCapabilities = <String>['approvals-v1', 'questions-v1'];

/// 从 `connection.ready` 的 data 读能力清单：读不到（缺字段 / 空数组）返回 null（未知）。
Set<String>? parseCapabilities(Map<String, dynamic>? data) {
  if (data == null) {
    return null;
  }
  final declared = data['capabilities'];
  final out = <String>{};
  if (declared is List) {
    for (final item in declared) {
      if (item is String) {
        out.add(item);
      }
    }
  }
  return out.isEmpty ? null : out;
}

String? bridgeVersionOf(Map<String, dynamic>? data) {
  final value = data?['bridgeVersion'];
  return value is String ? value : null;
}

/// 读不到能力清单时返回 false（不显示归档入口）——这是安全方向。
bool supportsArchiveListing(Set<String>? capabilities) =>
    capabilities != null && capabilities.contains(archiveListCapability);

List<String> missingRequiredCapabilities(Set<String> capabilities) => [
      for (final name in requiredCapabilities)
        if (!capabilities.contains(name)) name,
    ];

// ---------------------------------------------------------------------------
// 请求闸（防止同一次点击重复发请求）
// ---------------------------------------------------------------------------

/// 简单互斥闸：`run` 进行中时再次调用直接返回 null。
class RequestGate {
  bool _busy = false;

  bool get busy => _busy;

  Future<T?> run<T>(Future<T> Function() action) async {
    if (_busy) {
      return null;
    }
    _busy = true;
    try {
      return await action();
    } finally {
      _busy = false;
    }
  }
}

// ---------------------------------------------------------------------------
// 事件防抖（列表刷新）
// ---------------------------------------------------------------------------

/// 把一阵密集事件合并成一次「稍后执行」。
class EventDebouncer {
  EventDebouncer(this.delay, this.action);

  final Duration delay;
  final void Function() action;
  int _generation = 0;

  void trigger() {
    _generation++;
    final mine = _generation;
    Future<void>.delayed(delay, () {
      if (mine == _generation) {
        action();
      }
    });
  }
}

// ---------------------------------------------------------------------------
// 聊天可见项（历史 + 实时，去重排序）
// ---------------------------------------------------------------------------

/// 合并历史项与实时项：实时项永远排在最后，且同一 id 不重复。
List<ChatDisplayItem> chatVisibleItems(
  List<ChatDisplayItem> history,
  List<ChatDisplayItem> live,
) {
  final seen = <String>{for (final item in history) item.id};
  final out = <ChatDisplayItem>[...history];
  for (final item in live) {
    if (seen.add(item.id)) {
      out.add(item);
    }
  }
  out.sort((a, b) {
    if (a.seq != b.seq) {
      return a.seq.compareTo(b.seq);
    }
    return a.id.compareTo(b.id);
  });
  return out;
}
