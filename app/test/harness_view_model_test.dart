import 'dart:convert';

import 'package:dsh_companion_ios/core/app_preferences.dart';
import 'package:dsh_companion_ios/core/chat_presentation.dart';
import 'package:dsh_companion_ios/core/connection_models.dart';
import 'package:dsh_companion_ios/core/connection_share.dart';
import 'package:dsh_companion_ios/core/dsh_client.dart';
import 'package:dsh_companion_ios/core/host_store.dart';
import 'package:dsh_companion_ios/platform/platform_deps.dart';
import 'package:dsh_companion_ios/state/harness_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

const String base = 'http://192.168.1.20:3090/api/v1';

Future<FakeHttpTransport> _routes() async {
  final http = FakeHttpTransport();
  http.route('GET', '$base/healthz', body: '{"ok":true,"version":"0.2.1"}');
  http.route('GET', '$base/devices/self', body: jsonEncode(<String, dynamic>{
    'id': 'dev1',
    'name': 'iPhone',
    'scopes': <String>['chat.read', 'files.read', 'settings.read'],
    'rootIds': <String>['r1'],
  }));
  http.route('GET', '$base/roots', body: jsonEncode(<String, dynamic>{
    'items': <Object>[
      <String, dynamic>{'id': 'r1', 'label': 'workspace', 'createdAt': 1},
    ],
  }));
  http.route('GET', '$base/chat/sessions', body: jsonEncode(<String, dynamic>{
    'items': <Object>[
      <String, dynamic>{
        'id': 's1',
        'rootId': 'r1',
        'cwd': '',
        'title': '修复登录',
        'running': false,
        'updatedAt': 1700000000000,
      },
    ],
  }));
  http.route('GET', '$base/chat/workspaces', body: '{"items":[]}');
  http.route('GET', '$base/chat/agent-presets', body: '{"items":[]}');
  http.route('GET', '$base/settings/providers', body: '{"writable":true,"providers":[]}');
  http.route('GET', '$base/settings/plugins', body: '{"available":true,"items":[]}');
  http.route('GET', '$base/chat/sessions/s1/messages', body: jsonEncode(<String, dynamic>{
    'events': <Object>[
      <String, dynamic>{
        'event': <String, dynamic>{
          'type': 'user/message',
          'seq': 1,
          'time': 1700000000000,
          'data': <String, dynamic>{
            'source': <String, dynamic>{'kind': 'user'},
            'content': <Object>[
              <String, dynamic>{'type': 'text', 'text': '修一下登录'},
            ],
          },
        },
      },
    ],
    'hasMore': false,
  }));
  http.route('GET', '$base/chat/sessions/s1/approvals', body: jsonEncode(<String, dynamic>{
    'items': <Object>[
      <String, dynamic>{
        'id': 'a1',
        'sessionId': 's1',
        'toolName': 'bash',
        'reason': '需要写文件',
        'risk': 'high',
      },
    ],
  }));
  http.route('GET', '$base/chat/sessions/s1/questions', body: '{"items":[]}');
  http.route('GET', '$base/chat/sessions/s1/commands', body: '{"items":[]}');
  http.route('GET', '$base/chat/sessions/s1/models', body: jsonEncode(<String, dynamic>{
    'current': <String, dynamic>{'provider': 'deepseek', 'model': 'v4'},
    'routable': true,
    'groups': <Object>[
      <String, dynamic>{
        'id': 'deepseek',
        'name': 'DeepSeek',
        'models': <Object>[
          <String, dynamic>{'id': 'v4', 'name': 'V4'},
        ],
      },
    ],
  }));
  http.route('GET', '$base/chat/permission-presets', body: '{"currentValue":"auto","options":[]}');
  http.route('POST', '$base/chat/sessions/s1/messages', status: 204);
  http.route('POST', '$base/chat/sessions/s1/approvals/a1/decision', status: 204);
  return http;
}

class VmHarness {
  VmHarness(this.vm, this.http, this.store, this.socket);

  final HarnessViewModel vm;
  final FakeHttpTransport http;
  final MemoryKeyValueStore store;
  final FakeWebSocketTransport socket;
}

Future<VmHarness> build({bool seedHost = true}) async {
  final store = MemoryKeyValueStore();
  final hostStore = HostStore(store, MemorySecretBox());
  if (seedHost) {
    await hostStore.saveHosts(<Host>[
      Host(
        id: 'h1',
        displayName: 'PC',
        endpoints: <Endpoint>[Endpoint.create('家', 'http://192.168.1.20:3090', 'e1')],
        preferredEndpointId: 'e1',
        credential: Credential(secret: 'tok'),
      ),
    ]);
  }
  final http = await _routes();
  final socket = FakeWebSocketTransport();
  final timers = FakeTimerBridge();
  final deps = AppDeps(
    hostStore: hostStore,
    prefs: AppPreferences(store),
    platform: PlatformDeps(
      uuid: () => 'uuid',
      timeZone: () async => 'Asia/Shanghai',
      deviceName: () => 'iPhone',
    ),
    http: http,
    socket: socket,
    timers: timers,
  );
  final vm = HarnessViewModel(deps);
  await vm.init();
  return VmHarness(vm, http, store, socket);
}

void main() {
  test('冷启动自动连接：探活 → 设备 → 快照', () async {
    final h = await build();
    expect(h.vm.state.connected, isTrue);
    expect(h.vm.state.connecting, isFalse);
    expect(h.vm.state.restoring, isFalse);
    expect(h.vm.state.device!.id, 'dev1');
    expect(h.vm.state.sessions.single.title, '修复登录');
    expect(h.vm.state.selectedRootId, 'r1');
    expect(h.vm.state.activeEndpointId, 'e1');
    expect(h.vm.state.endpoint, 'http://192.168.1.20:3090/api/v1');
  });

  test('没有保存的电脑时停在未连接状态', () async {
    final h = await build(seedHost: false);
    expect(h.vm.state.connected, isFalse);
    expect(h.vm.state.restoring, isFalse);
    expect(h.vm.state.hosts, isEmpty);
  });

  test('探活失败时给出可读错误，且复位 connecting', () async {
    final store = MemoryKeyValueStore();
    final hostStore = HostStore(store, MemorySecretBox());
    await hostStore.saveHosts(<Host>[
      Host(
        id: 'h1',
        displayName: 'PC',
        endpoints: <Endpoint>[Endpoint.create('家', 'http://10.9.9.9:3090', 'e1')],
      ),
    ]);
    final http = FakeHttpTransport()..error = Exception('connection refused');
    final deps = AppDeps(
      hostStore: hostStore,
      prefs: AppPreferences(store),
      platform: PlatformDeps(uuid: () => 'u', timeZone: () async => 'UTC', deviceName: () => 'iPhone'),
      http: http,
      socket: FakeWebSocketTransport(),
      timers: FakeTimerBridge(),
    );
    final vm = HarnessViewModel(deps);
    await vm.init();
    expect(vm.state.connected, isFalse);
    expect(vm.state.connecting, isFalse);
    expect(vm.state.restoring, isFalse);
    expect(vm.state.error, isNotNull);
  });

  test('选会话加载历史、审批、模型与权限目录', () async {
    final h = await build();
    await h.vm.selectSession('s1');
    expect(h.vm.state.selectedSessionId, 's1');
    expect(h.vm.state.visibleItems.single.body, '修一下登录');
    expect(h.vm.state.approvals.single.toolName, 'bash');
    expect(h.vm.state.sessionModels!.current.model, 'v4');
    expect(h.vm.state.permissionCatalog!.currentValue, 'auto');
  });

  test('审批决定打到正确端点', () async {
    final h = await build();
    await h.vm.selectSession('s1');
    final approval = h.vm.state.approvals.single;
    await h.vm.decideApproval(approval, allowOnce: true);
    final call = h.http.requests.lastWhere((HttpRequest r) => r.url.endsWith('/decision'));
    expect(call.method, 'POST');
    expect(call.url, '$base/chat/sessions/s1/approvals/a1/decision');
    expect(utf8.decode(call.body!), contains('allowed-once'));
  });

  test('发消息：文本进 text 字段，随后重拉历史', () async {
    final h = await build();
    await h.vm.selectSession('s1');
    await h.vm.sendMessage('  你好  ');
    final call = h.http.requests.lastWhere((HttpRequest r) => r.method == 'POST');
    final body = jsonDecode(utf8.decode(call.body!)) as Map<String, dynamic>;
    expect(body['text'], '你好');
    expect(body['mode'], 'queue');
  });

  test('实时增量只对当前会话生效，并进入可见项', () async {
    final h = await build();
    await h.vm.selectSession('s1');
    h.socket.connection?.call();
    h.socket.emit!(jsonEncode(<String, dynamic>{
      'id': 'ev1',
      'type': 'chat.message.delta',
      'time': 1700000000500,
      'data': <String, dynamic>{
        'sessionId': 's1',
        'turn': 1,
        'step': 1,
        'index': 0,
        'kind': 'text',
        'text': '正在修…',
      },
    }));
    expect(h.vm.state.liveChat, isNotNull);
    expect(
      h.vm.state.visibleItems.any((ChatDisplayItem i) => i.streaming && i.body.contains('正在修')),
      isTrue,
    );

    h.socket.emit!(jsonEncode(<String, dynamic>{
      'id': 'ev2',
      'type': 'chat.message.delta',
      'data': <String, dynamic>{
        'sessionId': 'other',
        'turn': 1,
        'step': 1,
        'index': 0,
        'kind': 'text',
        'text': '不该出现',
      },
    }));
    expect(
      h.vm.state.visibleItems.any((ChatDisplayItem i) => i.body.contains('不该出现')),
      isFalse,
    );
  });

  test('connection.ready 记录能力位与版本', () async {
    final h = await build();
    h.socket.emit!(jsonEncode(<String, dynamic>{
      'type': 'connection.ready',
      'data': <String, dynamic>{
        'bridgeVersion': '2.0.4',
        'capabilities': <String>['approvals-v1', 'questions-v1', 'session-archive-list-v1'],
      },
    }));
    expect(h.vm.state.bridgeVersion, '2.0.4');
    expect(h.vm.state.bridgeCapabilities!.contains('approvals-v1'), isTrue);
    expect(h.vm.state.bridgeCapabilities!.contains('session-archive-list-v1'), isTrue);
  });

  test('导入配置文本会建主机并连接', () async {
    final store = MemoryKeyValueStore();
    final hostStore = HostStore(store, MemorySecretBox());
    final http = await _routes();
    final deps = AppDeps(
      hostStore: hostStore,
      prefs: AppPreferences(store),
      platform: PlatformDeps(uuid: () => 'u', timeZone: () async => 'UTC', deviceName: () => 'iPhone'),
      http: http,
      socket: FakeWebSocketTransport(),
      timers: FakeTimerBridge(),
    );
    final vm = HarnessViewModel(deps);
    await vm.init();
    expect(vm.state.hosts, isEmpty);

    final payload = ConnectionShare.encode(const SharePayload(
      displayName: 'PC',
      endpoints: <ShareEndpoint>[ShareEndpoint(baseUrl: 'http://192.168.1.20:3090')],
      token: 'tok',
    ));
    await vm.importConfiguration(payload);
    expect(vm.state.hosts, hasLength(1));
    expect(vm.state.hosts.single.displayName, 'PC');
    expect(vm.state.connected, isTrue);
  });

  test('坏配置文本给出可读错误且不建连接', () async {
    final store = MemoryKeyValueStore();
    final hostStore = HostStore(store, MemorySecretBox());
    final deps = AppDeps(
      hostStore: hostStore,
      prefs: AppPreferences(store),
      platform: PlatformDeps(uuid: () => 'u', timeZone: () async => 'UTC', deviceName: () => 'iPhone'),
      http: await _routes(),
      socket: FakeWebSocketTransport(),
      timers: FakeTimerBridge(),
    );
    final vm = HarnessViewModel(deps);
    await vm.init();
    await vm.importConfiguration('DSH1:not-base64');
    expect(vm.state.hosts, isEmpty);
    expect(vm.state.error, isNotNull);
    expect(vm.state.error, contains('配置'));
  });

  test('断开连接保留已保存的主机', () async {
    final h = await build();
    expect(h.vm.state.hosts, hasLength(1));
    h.vm.disconnect();
    expect(h.vm.state.connected, isFalse);
    expect(h.vm.state.hosts, hasLength(1));
  });

  test('偏好改动同时落盘', () async {
    final h = await build();
    h.vm.setThemeMode('dark');
    h.vm.setShowContext(true);
    h.vm.setSendMode('steer');
    h.vm.setLanguage('en');
    expect(h.store.values['theme_mode'], 'dark');
    expect(h.store.values['show_context'], 'true');
    expect(h.store.values['busy_send_mode'], 'steer');
    expect(h.store.values['language_tag'], 'en');
    expect(h.vm.state.languageTag, 'en');
  });
}

