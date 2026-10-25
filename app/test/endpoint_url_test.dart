import 'package:dsh_companion_ios/core/connection_models.dart';
import 'package:dsh_companion_ios/core/endpoint_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeEndpoint', () {
    test('补齐 /api/v1 并去尾斜杠', () {
      expect(normalizeEndpoint('http://192.168.1.20:3090/'), 'http://192.168.1.20:3090/api/v1');
      expect(normalizeEndpoint('  https://relay.example.com  '), 'https://relay.example.com/api/v1');
    });

    test('已经带 /api/v1 时不重复追加', () {
      expect(normalizeEndpoint('http://10.0.0.2:3090/api/v1'), 'http://10.0.0.2:3090/api/v1');
      expect(normalizeEndpoint('http://10.0.0.2:3090/api/v1/'), 'http://10.0.0.2:3090/api/v1');
    });

    test('缺协议时抛错（唯一故意抛异常的入口）', () {
      expect(() => normalizeEndpoint('192.168.1.20:3090'), throwsFormatException);
    });

    test('路径里带别的段时照样追加 /api/v1', () {
      expect(normalizeEndpoint('https://x.example.com/dsh'), 'https://x.example.com/dsh/api/v1');
    });
  });

  group('stripApiSuffix / 基地址归一', () {
    test('去掉 /api/v1 后缀', () {
      expect(stripApiSuffix('http://a:1/api/v1'), 'http://a:1');
      expect(stripApiSuffix('http://a:1/api/v2'), 'http://a:1/api/v2');
    });

    test('share 口径不抛异常且协议小写', () {
      expect(shareNormalizeBaseUrl('HTTP://A:3090/api/v1/'), 'http://A:3090');
      expect(shareNormalizeBaseUrl('  a:3090  '), 'a:3090');
    });

    test('store 口径缺协议补 http://', () {
      expect(storeNormalizeBaseUrl('192.168.1.20:3090'), 'http://192.168.1.20:3090');
      expect(storeNormalizeBaseUrl(''), '');
    });

    test('isUsableBaseUrl 要求主机名', () {
      expect(isUsableBaseUrl('http://192.168.1.20:3090'), isTrue);
      expect(isUsableBaseUrl('https://relay.example.com/api/v1'), isTrue);
      expect(isUsableBaseUrl('http://'), isFalse);
      expect(isUsableBaseUrl('ftp://a'), isFalse);
    });
  });

  group('hostNameOf', () {
    test('去协议、端口、路径与 IPv6 方括号', () {
      expect(hostNameOf('http://192.168.1.20:3090/api/v1'), '192.168.1.20');
      expect(hostNameOf('https://relay.example.com/x?y=1'), 'relay.example.com');
      expect(hostNameOf('http://[fe80::1]:3090'), 'fe80::1');
    });
  });

  group('inferEndpointKind', () {
    test('局域网段', () {
      expect(inferEndpointKind('http://192.168.1.2:3090'), EndpointKind.lan);
      expect(inferEndpointKind('http://10.1.2.3'), EndpointKind.lan);
      expect(inferEndpointKind('http://172.16.5.4'), EndpointKind.lan);
      expect(inferEndpointKind('http://localhost:3090'), EndpointKind.lan);
      expect(inferEndpointKind('http://mac.local'), EndpointKind.lan);
    });

    test('CGNAT 视为虚拟网（Tailscale / BeyondTunnel）', () {
      expect(inferEndpointKind('http://100.101.2.3:3090'), EndpointKind.virtualNet);
      expect(inferEndpointKind('http://100.127.0.1'), EndpointKind.virtualNet);
      expect(inferEndpointKind('http://100.128.0.1'), EndpointKind.wan);
    });

    test('公网 IPv4 与未知', () {
      expect(inferEndpointKind('http://8.8.8.8'), EndpointKind.wan);
      expect(inferEndpointKind('https://relay.example.com'), EndpointKind.unknown);
      expect(inferEndpointKind('http://256.1.1.1'), EndpointKind.unknown);
      expect(inferEndpointKind(''), EndpointKind.unknown);
    });

    test('Endpooint.create 归一基地址并推断 kind', () {
      final endpoint = Endpoint.create('家', 'http://192.168.1.126:3090/api/v1', 'ep1');
      expect(endpoint.baseUrl, 'http://192.168.1.126:3090');
      expect(endpoint.kind, EndpointKind.lan);
      expect(endpoint.label, '家');
    });
  });
}
