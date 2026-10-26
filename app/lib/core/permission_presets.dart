/// 会话权限档位 —— 移植自鸿蒙版「会话内权限入口」的口径。
///
/// 为什么内置候选：`/chat/permission-presets` 只返回 `workspace-write` / `danger-full-access`，
/// 而 `/permission <preset>` 实际支持 `read-only` 与 `auto`（2026-10-26 真机确认只有两个 chip）。
/// 只按目录渲染的后果是「只读 / 自动审查」永远点不到，且当前值若是 `auto` 时没有任何 chip 高亮。
library;

import 'models.dart';

/// 一个权限档位：线上取值 + 中英文案。
class PermissionPreset {
  const PermissionPreset(this.value, this.zh, this.en);

  final String value;
  final String zh;
  final String en;

  String label(String languageTag) => languageTag.toLowerCase().startsWith('en') ? en : zh;
}

/// 固定顺序（与鸿蒙版会话页一致）：只读 → 工作区内修改 → 自动审查 → 完全权限。
const List<PermissionPreset> canonicalPermissionPresets = <PermissionPreset>[
  PermissionPreset('read-only', '只读', 'Read-only'),
  PermissionPreset('workspace-write', '工作区内修改', 'Workspace write'),
  PermissionPreset('auto', '自动审查', 'Auto review'),
  PermissionPreset('danger-full-access', '完全权限', 'Full access'),
];

/// 目录里出现但不在四档里的值，追加在最后（不丢服务端的能力）。
List<PermissionPreset> permissionPresetsFor(PermissionSelect? catalog) {
  final out = <PermissionPreset>[...canonicalPermissionPresets];
  if (catalog == null) {
    return out;
  }
  final known = <String>{for (final preset in out) preset.value};
  for (final option in catalog.options) {
    if (option.value.isEmpty || known.contains(option.value)) {
      continue;
    }
    known.add(option.value);
    out.add(PermissionPreset(option.value, option.name, option.name));
  }
  return out;
}

/// 当前档位：**优先会话投影**（`projections.values.permissions.currentValue`），
/// 其次权限目录。投影才是权威：PC 端切到 `auto` 后，目录里的 currentValue 可能还是旧值。
String permissionCurrentValue({required PermissionSelect? catalog, required String projectionValue}) {
  if (projectionValue.isNotEmpty) {
    return projectionValue;
  }
  return catalog?.currentValue ?? '';
}

/// 目录里对该档位的说明（没有就返回 null）。
String? permissionPresetDescription(PermissionSelect? catalog, String value) {
  if (catalog == null) {
    return null;
  }
  for (final option in catalog.options) {
    if (option.value == value) {
      return option.description;
    }
  }
  return null;
}
