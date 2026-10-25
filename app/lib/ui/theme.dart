/// 主题 —— 对应鸿蒙版 `core/ThemeMode.ts` + 系统配色。
///
/// 三档：跟随系统 / 浅色 / 深色。**存的是线上取值**（`system` / `light` / `dark`），
/// 不是枚举序数：升级后深浅互换是源工程踩过的坑，存名字才升级安全。
library;

import 'package:flutter/material.dart';

import '../core/small_parts.dart';

/// 品牌主色（与鸿蒙版图标同一个蓝）。
const Color brandBlue = Color(0xFF2F6BFF);

ThemeData buildAppTheme({required Brightness brightness}) {
  final scheme = ColorScheme.fromSeed(
    seedColor: brandBlue,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    visualDensity: VisualDensity.adaptivePlatformDensity,
  );
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.6),
      space: 1,
      thickness: 0.6,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: scheme.surface,
      selectedItemColor: scheme.primary,
      unselectedItemColor: scheme.onSurfaceVariant,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      isDense: true,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(color: scheme.onInverseSurface),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
    ),
  );
}

ThemeMode themeModeOf(String raw) {
  switch (normalizeThemeMode(raw)) {
    case themeModeLight:
      return ThemeMode.light;
    case themeModeDark:
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}
