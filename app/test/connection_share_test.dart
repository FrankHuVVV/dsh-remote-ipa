import 'package:dsh_companion_ios/core/connection_models.dart';
import 'package:dsh_companion_ios/core/connection_share.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const payload = SharePayload(
    displayName: '家里的电脑',
    endpoints: <ShareEndpoint>[
      ShareEndpoint(label: '家', baseUrl: 'http://192.168.1.126:3090'),
      ShareEndpoint(label: '尾巴', baseUrl: 'http://100.101.2.3:3090'),
    ],
    token: 'tok_abc',
    deviceName: 'Pixel 9',
    scopes: <String>['files.read'],
  );

  test('编码 → 解码往返保真', () {
    final text = ConnectionShare.encode(payload);
    expect(text.startsWith('DSH1:'), isTrue);
    final decoded = ConnectionShare.decode(text);
    expect(decoded, isNotNull);
    expect(decoded!.displayName, '家里的电脑');
    expect(decoded.endpoints.length, 2);
    expect(decoded.endpoints.first.baseUrl, 'http://192.168.1.126:3090');
    expect(decoded.token, 'tok_abc');
    expect(decoded.deviceName, 'Pixel 9');
    expect(decoded.scopes, <String>['files.read']);
  });

  test('编码会去掉 /api/v1 后缀', () {
    final text = ConnectionShare.encode(const SharePayload(
      endpoints: <ShareEndpoint>[ShareEndpoint(baseUrl: 'http://a:1/api/v1')],
    ));
    final decoded = ConnectionShare.decode(text)!;
    expect(decoded.endpoints.single.baseUrl, 'http://a:1');
  });

  test('空地址 / 非法协议在编码时抛错（生成端人在电脑旁）', () {
    expect(() => ConnectionShare.encode(const SharePayload()), throwsFormatException);
    expect(
      () => ConnectionShare.encode(const SharePayload(
        endpoints: <ShareEndpoint>[ShareEndpoint(baseUrl: 'ftp://a')],
      )),
      throwsFormatException,
    );
  });

  test('解码容忍空白、零宽字符、带标签的前缀与混合字母表', () {
    final text = ConnectionShare.encode(payload);
    final dirty = '我的配置：\n${text.substring(0, 5)}\u200B ${text.substring(5)}\n';
    expect(ConnectionShare.decode(dirty), isNotNull);
  });

  test('解码容忍缺失的 = 填充', () {
    final text = ConnectionShare.encode(payload).replaceAll('=', '');
    expect(ConnectionShare.decode(text), isNotNull);
  });

  test('坏输入一律返回 null，绝不抛异常', () {
    expect(ConnectionShare.decode(''), isNull);
    expect(ConnectionShare.decode('DSH1:!!!!'), isNull);
    expect(ConnectionShare.decode('hello world'), isNull);
    expect(ConnectionShare.decode('DSH1:e30'), isNull); // 解出 {}，没有地址
  });

  test('buildHost：id 稳定、地址 id 派生、token 进凭据、preferred 为空', () {
    final host = ConnectionShare.buildHost(
      payload,
      idFactory: () => 'host-x',
      clock: () => 1700000000000,
    );
    expect(host.id, 'host-x');
    expect(host.displayName, '家里的电脑');
    expect(host.endpoints.map((Endpoint e) => e.id), <String>['host-x-ep1', 'host-x-ep2']);
    expect(host.preferredEndpointId, isNull);
    expect(host.credential!.secret, 'tok_abc');
    expect(host.credential!.kind, CredentialKind.deviceToken);
    expect(host.createdAt, 1700000000000);
  });

  test('buildHost：显示名缺失时回退「电脑」', () {
    final host = ConnectionShare.buildHost(
      const SharePayload(endpoints: <ShareEndpoint>[ShareEndpoint(baseUrl: 'http://a:1')]),
      idFactory: () => 'h',
    );
    expect(host.displayName, '电脑');
  });

  test('解析长度在预算内（≤ 600 字符）', () {
    final text = ConnectionShare.encode(payload);
    expect(text.length, lessThan(600));
  });

  test('宽容 Base64 解码：URL-safe 与标准字母表都收', () {
    expect(decodeBase64Either('aGVsbG8'), isNotNull);
    expect(decodeBase64Either('aGVsbG8='), isNotNull);
    expect(decodeBase64Either('a'), isNull); // %4==1 直接判死
  });
}
