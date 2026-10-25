# ADR-0002 · CI 只出未签名 IPA，本地签名 + 侧载

- **日期**：2026-10-25
- **状态**：已采纳

## 背景

目标是「用 GitHub Actions 打包，爱思助手签名，iLoader 侧载到 iOS 27 手机」。
可选路径有两条：

1. CI 里用导出的 `.p12` + `.mobileprovision` 直接出已签名 IPA；
2. CI 只出未签名 IPA，签名与装机全部在本地完成。

## 决定

走第 2 条：`.github/workflows/ios-ipa.yml` 只做 `flutter build ios --release --no-codesign`
并打包成 `Payload/Runner.app` 的 zip；签名由用户在爱思助手里用**自己的 Apple ID** 完成。

## 后果

- ✅ 仓库与 CI 里**不存在**证书、描述文件、Apple ID 凭据；泄露面最小。
- ✅ 签名身份可随设备/账号变化，不影响代码。
- ⚠️ 多两个手工步骤（签名、安装），且**免费 Apple ID 只有 7 天有效期**、最多 3 个 App。
- ⚠️ 重新签名后钥匙串条目可能读不到（签名身份变了），需要重新配对 —— 见
  `docs/PITFALLS.md#重新签名后钥匙串读不到`。
- ⚠️ 未签名 IPA 不能直接安装；任何「跳过签名」的想法都会在设备上失败。

## 替代方案与为什么不选

| 方案 | 为什么不行 |
|---|---|
| CI 里放 `.p12` | 把签名身份复制到第三个地方；GitHub Secrets 泄露即等于证书泄露 |
| App Store / TestFlight | 需要 Apple Developer Program（付费）、审核、且这是个人自用工具 |
| 越狱 + 自签工具 | 与「原样 iOS 27」的目标不符 |
