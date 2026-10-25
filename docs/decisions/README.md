# 架构决策记录（ADR）

一事一文件。每条写清：**背景 / 决定 / 后果 / 替代方案为什么不行**。
编号不复用；被推翻的条目保留，标 `Superseded by ADR-xxxx`。

| 编号 | 标题 | 状态 |
|---|---|---|
| [ADR-0001](ADR-0001-native-rendering-no-webview.md) | 原生渲染，不用 WebView | 已采纳 |
| [ADR-0002](ADR-0002-unsigned-ipa-sideload.md) | CI 只出未签名 IPA，本地签名 + 侧载 | 已采纳 |
| [ADR-0003](ADR-0003-keychain-over-homegrown-aes.md) | 令牌进系统钥匙串，不自研 AES-GCM | 已采纳 |
| [ADR-0004](ADR-0004-pure-dart-core-with-injected-transports.md) | core 纯 Dart + 注入 transport | 已采纳 |

新增 ADR 的判据：**这个决定会让后来的维护者想问「为什么不是另一种」**。
纯实现细节（变量命名、目录细分）不写 ADR。
