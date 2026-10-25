import 'package:dsh_companion_ios/core/connection_models.dart';
import 'package:dsh_companion_ios/core/host_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

void main() {
  group('HostStore', () {
    test('落盘的是加密串，明文令牌不出现在偏好里', () async {
      final store = MemoryKeyValueStore();
      final box = MemorySecretBox();
      final hostStore = HostStore(store, box, clock: () => DateTime.fromMillisecondsSinceEpoch(1000));

      await hostStore.saveHosts(<Host>[
        Host(
          id: 'h1',
          displayName: 'PC',
          endpoints: <Endpoint>[Endpoint.create('家', 'http://192.168.1.2:3090', 'e1')],
          credential: Credential(secret: 'SECRET_TOKEN'),
        ),
      ]);

      expect(store.values[keyHosts], isNotNull);
      expect(store.values[keyHosts]!.contains('SECRET_TOKEN'), isFalse);
      expect(box.encryptions, 1);
    });

    test('坏数据返回空列表，并把原值备份到 hosts_v1_corrupt', () async {
      final store = MemoryKeyValueStore()..putString(keyHosts, 'not-a-box');
      final hostStore = HostStore(store, MemorySecretBox());
      expect(await hostStore.loadHosts(), isEmpty);
      expect(store.values[keyHostsCorrupt], 'not-a-box');
      expect(store.values[keyHosts], 'not-a-box', reason: '不许静默清空');
    });

    test('upsert 保留原 createdAt 并刷新 updatedAt', () async {
      final store = MemoryKeyValueStore();
      final hostStore = HostStore(store, MemorySecretBox(), clock: () => DateTime.fromMillisecondsSinceEpoch(5000));
      final original = Host(id: 'h1', displayName: 'PC', createdAt: 111);
      await hostStore.saveHosts(<Host>[original]);

      final hosts = hostStore.upsert(<Host>[original], Host(id: 'h1', displayName: '新名字'));
      expect(hosts.single.createdAt, 111);
      expect(hosts.single.updatedAt, 5000);
      expect(hosts.single.displayName, '新名字');
    });

    test('upsert 新 host 且 createdAt=0 时补当前时间', () {
      final hostStore = HostStore(MemoryKeyValueStore(), MemorySecretBox(),
          clock: () => DateTime.fromMillisecondsSinceEpoch(7000));
      final hosts = hostStore.upsert(<Host>[], Host(id: 'new', displayName: 'x'));
      expect(hosts.single.createdAt, 7000);
      expect(hosts.single.updatedAt, 7000);
    });

    test('markPreferred 只改地址偏好，不动 updatedAt', () {
      final hostStore = HostStore(MemoryKeyValueStore(), MemorySecretBox());
      final host = Host(id: 'h1', displayName: 'PC', updatedAt: 42);
      final hosts = hostStore.markPreferred(<Host>[host], 'h1', 'e2');
      expect(hosts.single.preferredEndpointId, 'e2');
      expect(hosts.single.updatedAt, 42);
    });

    test('migrateLegacy：空地址不写任何东西；id 幂等', () {
      final hostStore = HostStore(MemoryKeyValueStore(), MemorySecretBox());
      expect(hostStore.migrateLegacy('  ', 'tok'), isNull);
      final first = hostStore.migrateLegacy('http://192.168.1.5:3090', 'tok')!;
      final second = hostStore.migrateLegacy('http://192.168.1.5:3090', 'tok')!;
      expect(first.id, second.id);
      expect(first.id.startsWith('legacy-'), isTrue);
      expect(first.preferredEndpointId, isNotNull);
      expect(first.credential!.secret, 'tok');
    });

    test('读回的主机保持字段与地址', () async {
      final store = MemoryKeyValueStore();
      final hostStore = HostStore(store, MemorySecretBox());
      final host = Host(
        id: 'h1',
        displayName: 'PC',
        endpoints: <Endpoint>[Endpoint.create('家', 'http://10.0.0.2:3090', 'e1')],
        preferredEndpointId: 'e1',
        credential: Credential(secret: 't', scopes: const <String>['chat.read']),
      );
      await hostStore.saveHosts(<Host>[host]);
      final loaded = await hostStore.loadHosts();
      expect(loaded.single.endpoints.single.baseUrl, 'http://10.0.0.2:3090');
      expect(loaded.single.credential!.scopes, <String>['chat.read']);
    });
  });

  group('EndpointSelection.rank', () {
    Endpoint ep(String id, EndpointKind kind, {int? checkedAt}) =>
        Endpoint(id: id, baseUrl: 'http://$id', kind: kind, lastCheckedAt: checkedAt);

    test('全失败返回空', () {
      final ranked = EndpointSelection.rank(
        <EndpointProbe>[EndpointProbe.failure('a', 'timeout')],
        <Endpoint>[ep('a', EndpointKind.lan)],
        null,
      );
      expect(ranked, isEmpty);
    });

    test('延迟升序，且 LAN 在 1.5 倍容差内优先', () {
      final endpoints = <Endpoint>[
        ep('lan', EndpointKind.lan),
        ep('wan', EndpointKind.wan),
      ];
      final probes = <EndpointProbe>[
        EndpointProbe.success('wan', 10),
        EndpointProbe.success('lan', 14),
      ];
      final ranked = EndpointSelection.rank(probes, endpoints, null);
      expect(ranked.first.endpointId, 'lan');
    });

    test('LAN 超出容差时按延迟排', () {
      final endpoints = <Endpoint>[
        ep('lan', EndpointKind.lan),
        ep('wan', EndpointKind.wan),
      ];
      final probes = <EndpointProbe>[
        EndpointProbe.success('wan', 10),
        EndpointProbe.success('lan', 100),
      ];
      final ranked = EndpointSelection.rank(probes, endpoints, null);
      expect(ranked.first.endpointId, 'wan');
    });

    test('并列时 preferred 优先', () {
      final endpoints = <Endpoint>[ep('a', EndpointKind.wan), ep('b', EndpointKind.wan)];
      final probes = <EndpointProbe>[
        EndpointProbe.success('a', 20),
        EndpointProbe.success('b', 20),
      ];
      expect(EndpointSelection.rank(probes, endpoints, 'b').first.endpointId, 'b');
    });

    test('并列时 lastCheckedAt 更旧者排前', () {
      final endpoints = <Endpoint>[
        ep('new', EndpointKind.wan, checkedAt: 200),
        ep('old', EndpointKind.wan, checkedAt: 100),
      ];
      final probes = <EndpointProbe>[
        EndpointProbe.success('new', 20),
        EndpointProbe.success('old', 20),
      ];
      expect(EndpointSelection.rank(probes, endpoints, null).first.endpointId, 'old');
    });
  });

  test('凭据过期判定', () {
    final credential = Credential(secret: 't', issuedAt: 100, expiresAt: 200);
    expect(credential.isExpired(199), isFalse);
    expect(credential.isExpired(200), isTrue);
    expect(Credential(secret: 't').isExpired(999999), isFalse);
  });

  test('Host.activeEndpoints 过滤停用与空地址', () {
    final host = Host(
      id: 'h',
      displayName: 'h',
      endpoints: <Endpoint>[
        Endpoint(id: 'a', baseUrl: 'http://a', enabled: true),
        Endpoint(id: 'b', baseUrl: 'http://b', enabled: false),
        Endpoint(id: 'c', baseUrl: '  ', enabled: true),
      ],
    );
    expect(host.activeEndpoints().map((Endpoint e) => e.id), <String>['a']);
  });
}
