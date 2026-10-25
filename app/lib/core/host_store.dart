/// 多主机持久化 —— 移植自鸿蒙版 `core/HostStore.ts`。
///
/// 抽象注入两个能力，便于单测与平台替换：
/// - [KeyValueStore]：字符串读写（App 里是 `SharedPreferences`）；
/// - [SecretBox]：整份加密 / 解密（App 里是 iOS Keychain，见 `platform/secure_store.dart`）。
///
/// 铁律：**明文（含设备令牌）绝不落普通偏好**。整份 Host 列表先序列化、再交给
/// [SecretBox] 加密，最后才落盘。读坏数据时返回空列表但**不清空原值** ——
/// 静默清空等于把用户的配对记录无声删掉。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'connection_models.dart';
import 'json.dart';

/// 字符串键值存储。
abstract class KeyValueStore {
  String? getString(String key);

  void putString(String key, String value);

  void remove(String key);
}

/// 整份加密 / 解密。
///
/// iOS 侧的实现直接把明文写进系统钥匙串（由 Secure Enclave 硬件加密），
/// 普通偏好里只留一个句柄 —— 比「自己实现 AES 再把密钥落在同一个偏好文件里」更强，
/// 见 `docs/decisions/ADR-0003-keychain-over-homegrown-aes.md`。方法因此是异步的。
abstract class SecretBox {
  Future<String> encrypt(String plaintext);

  Future<String?> decrypt(String ciphertext);
}

/// 落盘键。
const String keyHosts = 'hosts_v1';
const String keyHostsCorrupt = 'hosts_v1_corrupt';

class HostStore {
  HostStore(this.store, this.secretBox, {DateTime Function()? clock})
      : clock = clock ?? DateTime.now;

  final KeyValueStore store;
  final SecretBox secretBox;
  final DateTime Function() clock;

  /// 读出全部主机。坏数据返回空列表，并把原值备份到 `hosts_v1_corrupt`。
  Future<List<Host>> loadHosts() async {
    final raw = store.getString(keyHosts);
    if (raw == null || raw.isEmpty) {
      return <Host>[];
    }
    final plain = await secretBox.decrypt(raw);
    if (plain == null) {
      store.putString(keyHostsCorrupt, raw);
      return <Host>[];
    }
    final decoded = parseJson(plain);
    if (decoded is! List) {
      store.putString(keyHostsCorrupt, raw);
      return <Host>[];
    }
    final out = <Host>[];
    for (final item in decoded) {
      final m = asMap(item);
      if (m == null) {
        continue;
      }
      final host = Host.fromJson(m);
      if (host.id.isEmpty) {
        continue;
      }
      out.add(host);
    }
    return out;
  }

  /// 整份覆盖写入。
  Future<void> saveHosts(List<Host> hosts) async {
    final json = jsonEncode([for (final h in hosts) h.toMap()]);
    store.putString(keyHosts, await secretBox.encrypt(json));
  }

  /// 增或改：同 id 保留原 `createdAt`，刷新 `updatedAt`；新 host 且 `createdAt=0` 时补当前时间。
  List<Host> upsert(List<Host> hosts, Host host) {
    final now = clock().millisecondsSinceEpoch;
    final next = <Host>[];
    var replaced = false;
    for (final existing in hosts) {
      if (existing.id != host.id) {
        next.add(existing);
        continue;
      }
      replaced = true;
      final merged = host.copy()..createdAt = existing.createdAt;
      merged.updatedAt = now;
      next.add(merged);
    }
    if (!replaced) {
      final merged = host.copy();
      if (merged.createdAt == 0) {
        merged.createdAt = now;
      }
      merged.updatedAt = now;
      next.add(merged);
    }
    return next;
  }

  /// 只改选路偏好，**不改 `updatedAt`**（那不是一次内容变更）。
  List<Host> markPreferred(List<Host> hosts, String hostId, String? endpointId) => [
        for (final h in hosts)
          if (h.id == hostId) h.withPreferred(endpointId) else h,
      ];

  List<Host> remove(List<Host> hosts, String hostId) =>
      [for (final h in hosts) if (h.id != hostId) h];

  /// 旧版单连接（endpoint + token）迁移成 Host。
  ///
  /// 地址为空返回 null 且**不写任何东西**；id 由地址 SHA-256 派生，保证幂等
  /// （重复迁移不会产生两台「同名电脑」）。
  Host? migrateLegacy(String endpoint, String token, {Host? existing}) {
    final base = endpoint.trim();
    if (base.isEmpty) {
      return null;
    }
    final now = clock().millisecondsSinceEpoch;
    final hostId = 'legacy-${stableId(base)}';
    final endpointId = 'legacy-ep-${stableId(base)}';
    final credential = token.trim().isEmpty
        ? null
        : Credential(
            kind: CredentialKind.deviceToken,
            secret: token.trim(),
            issuedAt: existing?.credential?.issuedAt ?? now,
          );
    return Host(
      id: hostId,
      displayName: hostId.isEmpty ? '电脑' : _hostDisplayName(base),
      endpoints: [
        Endpoint.create(_hostDisplayName(base), base, endpointId),
      ],
      preferredEndpointId: endpointId,
      credential: credential,
      createdAt: now,
      updatedAt: now,
    );
  }

  static String _hostDisplayName(String baseUrl) {
    final withoutScheme = baseUrl.replaceFirst(RegExp(r'^https?://'), '');
    final host = withoutScheme.split('/').first.split(':').first;
    return host.isEmpty ? '电脑' : host;
  }

  /// 稳定 id：SHA-256 前 16 个十六进制字符。
  static String stableId(String value) =>
      sha256.convert(utf8.encode(value)).toString().substring(0, 16);
}
