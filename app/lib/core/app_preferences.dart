/// 纯偏好 —— 移植自鸿蒙版 `core/AppPreferences.ts`。
///
/// 与 `HostStore` 的分工：那里存**凭据与主机**（整份加密、损坏时容错），
/// 这里存**纯偏好**（明文即可，丢失只影响一次点击行为），刻意不共用一套容错路径。
///
/// 读取一律带兜底：偏好损坏或键缺失时回落默认值，绝不抛异常 ——
/// 一个设置项的取值问题不该让聊天界面起不来。
library;

import 'host_store.dart';
import 'small_parts.dart';

const String keyBusySendMode = 'busy_send_mode';
const String keyShowContext = 'show_context';
const String keyFontScale = 'font_scale';
const String keyFontFollowsSystem = 'font_follows_system';
const String keyThemeMode = 'theme_mode';
const String keyLanguageTag = 'language_tag';

class AppPreferences {
  AppPreferences(this.store);

  final KeyValueStore store;

  /// 智能体运行时，发送按钮的默认行为。只认 `queue` / `steer`，认不出回落排队。
  String get busySendMode => normalizeSendMode(store.getString(keyBusySendMode));

  set busySendMode(String value) => store.putString(keyBusySendMode, normalizeSendMode(value));

  /// 另一个模式：长按发送键走它。
  String get alternateSendMode => oppositeSendMode(busySendMode);

  /// 聊天页是否显示上下文注入块。默认 **false**：那些是系统每轮塞进来的东西。
  bool get showContext => _getBool(keyShowContext, false);

  set showContext(bool value) => _putBool(keyShowContext, value);

  /// 字号倍数（0.8–1.5，步进 0.1）。坏值回落 1.0。
  double get fontScale => normalizeFontScale(double.tryParse(store.getString(keyFontScale) ?? '') ?? 1.0);

  set fontScale(double value) => store.putString(keyFontScale, normalizeFontScale(value).toString());

  /// 是否跟随系统字号。默认 **true**：不擅自把用户调大的字号缩回去。
  bool get fontFollowsSystem => _getBool(keyFontFollowsSystem, true);

  set fontFollowsSystem(bool value) => _putBool(keyFontFollowsSystem, value);

  /// 主题档位（`system` / `light` / `dark`）。
  String get themeMode => normalizeThemeMode(store.getString(keyThemeMode));

  set themeMode(String value) => store.putString(keyThemeMode, normalizeThemeMode(value));

  /// 界面语言（BCP-47）。也作为 `Accept-Language` 出海。
  String get languageTag {
    final raw = store.getString(keyLanguageTag);
    if (raw == null || raw.isEmpty) {
      return 'zh-CN';
    }
    return raw.toLowerCase().startsWith('en') ? 'en' : 'zh-CN';
  }

  set languageTag(String value) =>
      store.putString(keyLanguageTag, value.toLowerCase().startsWith('en') ? 'en' : 'zh-CN');

  bool _getBool(String key, bool fallback) {
    final raw = store.getString(key);
    if (raw == null) {
      return fallback;
    }
    return raw == 'true';
  }

  void _putBool(String key, bool value) => store.putString(key, value ? 'true' : 'false');
}
