import 'package:dsh_companion_ios/core/permission_presets.dart';
import 'package:dsh_companion_ios/core/socket_url.dart';
import 'package:dsh_companion_ios/core/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('socketUrlOf', () {
    test('https 换成 wss（dart:io 只认 ws/wss）', () {
      expect(socketUrlOf('https://relay.example.com/api/v1/events'),
          'wss://relay.example.com/api/v1/events');
    });

    test('http 换成 ws，保留端口与查询串', () {
      expect(socketUrlOf('http://192.168.1.2:3090/api/v1/events?x=1'),
          'ws://192.168.1.2:3090/api/v1/events?x=1');
    });

    test('已经是 ws/wss 时原样返回', () {
      expect(socketUrlOf('wss://a/events'), 'wss://a/events');
      expect(socketUrlOf('ws://a/events'), 'ws://a/events');
    });

    test('无法解析时原样返回', () {
      expect(socketUrlOf('not a url'), 'not a url');
    });
  });

  group('权限档位', () {
    test('目录只有两项时补齐只读与自动审查，顺序固定', () {
      final catalog = PermissionSelect(
        currentValue: 'auto',
        options: <PermissionOption>[
          PermissionOption(value: 'workspace-write', name: '工作区内修改'),
          PermissionOption(value: 'danger-full-access', name: '完全权限'),
        ],
      );
      final presets = permissionPresetsFor(catalog);
      expect(presets.map((PermissionPreset p) => p.value), <String>[
        'read-only',
        'workspace-write',
        'auto',
        'danger-full-access',
      ]);
    });

    test('目录里多出的自定义值追加在最后', () {
      final catalog = PermissionSelect(
        currentValue: 'custom',
        options: <PermissionOption>[PermissionOption(value: 'custom', name: '自定义')],
      );
      final presets = permissionPresetsFor(catalog);
      expect(presets.last.value, 'custom');
      expect(presets.length, 5);
    });

    test('目录为 null 时仍给四档', () {
      expect(permissionPresetsFor(null), hasLength(4));
    });

    test('当前值优先投影（PC 端切到 auto 后高亮 auto）', () {
      final catalog = PermissionSelect(currentValue: 'danger-full-access');
      expect(
        permissionCurrentValue(catalog: catalog, projectionValue: 'auto'),
        'auto',
      );
      expect(
        permissionCurrentValue(catalog: catalog, projectionValue: ''),
        'danger-full-access',
      );
    });

    test('中英文案', () {
      final readOnly = canonicalPermissionPresets.first;
      expect(readOnly.label('zh-CN'), '只读');
      expect(readOnly.label('en'), 'Read-only');
    });

    test('说明取目录里的 description', () {
      final catalog = PermissionSelect(options: <PermissionOption>[
        PermissionOption(value: 'read-only', name: '只读', description: '只能读取'),
      ]);
      expect(permissionPresetDescription(catalog, 'read-only'), '只能读取');
      expect(permissionPresetDescription(catalog, 'auto'), isNull);
    });
  });
}
