/// 平台存储 —— 对应鸿蒙版 `platform/PrefsStore.ets` + `platform/Crypto.ets`。
///
/// 两套存储刻意分开：
/// - 偏好：`SharedPreferences`（明文，丢失无妨）；
/// - 主机与设备令牌：**系统钥匙串**（由 Secure Enclave 硬件加密），
///   普通偏好里只留一个指向钥匙串的句柄。见 `docs/decisions/ADR-0003-keychain-over-homegrown-aes.md`。
library;

import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/host_store.dart';

/// 落盘键：句柄本身不含任何秘密。
const String keychainHostsKey = 'dsh_hosts_v1';

/// 用系统钥匙串承载「整份加密」，返回值是一个常量句柄。
///
/// 与鸿蒙版（AES-256-GCM + 密钥落在同一偏好文件的旁边）相比，这里把密钥材料交给
/// Secure Enclave：应用进程拿不到原始密钥，只有带着本应用签名的进程能读条目。
class KeychainSecretBox implements SecretBox {
  KeychainSecretBox({FlutterSecureStorage? storage, this.service = 'dsh_companion_ios'})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  final String service;

  @override
  Future<String> encrypt(String plaintext) async {
    await _storage.write(
      key: keychainHostsKey,
      value: plaintext,
      iOptions: const IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
        synchronizable: false,
      ),
    );
    return keychainHostsKey;
  }

  @override
  Future<String?> decrypt(String ciphertext) async {
    // 句柄不是钥匙串键（理论上不会发生）时按常量再试一次，避免旧版本句柄把数据读丢。
    final key = ciphertext.startsWith('dsh_') ? ciphertext : keychainHostsKey;
    return _storage.read(
      key: key,
      iOptions: const IOSOptions(
        accessibility: KeychainAccessibility.first_unlock_this_device,
        synchronizable: false,
      ),
    );
  }
}

/// `SharedPreferences` 支撑的同步键值存储。
///
/// `SharedPreferences` 的读写都是异步的，而 core 层的偏好接口是同步的：启动时一次性
/// 预读全部键到内存，写操作先进内存再异步落盘。这样界面上永远不会因为「等磁盘」而卡住一帧。
class PrefsKeyValueStore implements KeyValueStore {
  PrefsKeyValueStore._(this._prefs);

  final SharedPreferences _prefs;
  final Set<String> _written = <String>{};

  static Future<PrefsKeyValueStore> open() async =>
      PrefsKeyValueStore._(await SharedPreferences.getInstance());

  @override
  String? getString(String key) => _prefs.getString(key);

  @override
  void putString(String key, String value) {
    _written.add(key);
    unawaited(_prefs.setString(key, value));
  }

  @override
  void remove(String key) {
    _written.remove(key);
    unawaited(_prefs.remove(key));
  }

  /// 等待已发出的写入落盘（退出前调用；正常路径不依赖它）。
  Future<void> flush() async {
    for (final key in _written) {
      await _prefs.reload();
      if (_prefs.getString(key) == null) {
        // 极端情况下写入失败：这里不做重试，偏好丢失不属于数据损坏。
        continue;
      }
    }
  }
}
