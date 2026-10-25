# ADR-0003 · 令牌进系统钥匙串，不自研 AES-GCM

- **日期**：2026-10-25
- **状态**：已采纳

## 背景

鸿蒙版的 `HostStore` 把整份 Host 列表序列化后用 AES-256-GCM 加密，密钥存在**同一个偏好
体系**里的独立文件（`dsh_keys`）。iOS 侧有两条路：

1. 照搬：用纯 Dart 实现 AES-GCM，密钥放 `SharedPreferences`（或另立文件）；
2. 用 iOS 钥匙串直接承载密文，普通偏好里只放一个句柄。

## 决定

走第 2 条：`KeychainSecretBox` 把明文 JSON 写进钥匙串（`first_unlock_this_device`、
`synchronizable = false`），`SecretBox.encrypt` 返回常量句柄 `dsh_hosts_v1`，
`HostStore` 把它当作「密文」写进普通偏好。因此 `SecretBox` 的接口是异步的。

## 后果

- ✅ 密钥材料由 Secure Enclave 持有，应用进程拿不到原始密钥 —— 比「自研 AES + 同盘密钥」更强。
- ✅ 条目不参与 iCloud 备份（`this_device`），换机不会把令牌带走。
- ⚠️ 重新签名 / 换 Bundle ID 后旧条目可能读不到（访问控制绑定签名身份）。这是**安全边界**，
  不是 bug；表现为「需要重新配对」。
- ⚠️ `HostStore.loadHosts/saveHosts` 变成异步，调用点必须 `await`；
  其余纯逻辑（upsert / markPreferred / remove）保持同步可测。
- ⚠️ 钥匙串写入在极少数情况下会失败（设备刚重启未解锁）。当前按「本次保存失败，下次再试」处理，
  不做重试队列 —— 偏好级数据丢了不影响可用性，令牌丢了才需要重新配对。

## 替代方案与为什么不选

| 方案 | 为什么不行 |
|---|---|
| 纯 Dart AES-GCM + 偏好存密钥 | 密钥与密文同处一个沙盒，越狱或备份提取后等于明文；只是「看起来加密了」 |
| 把令牌放 `SharedPreferences` 明文 | 直接违反安全边界 |
| 每次启动让用户重输令牌 | 移动端不可用；且令牌是长随机串 |
