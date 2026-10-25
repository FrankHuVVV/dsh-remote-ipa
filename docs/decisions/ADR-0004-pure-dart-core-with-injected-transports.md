# ADR-0004 · core 纯 Dart + 注入 transport

- **日期**：2026-10-25
- **状态**：已采纳

## 背景

鸿蒙版把 `DshClient` 与平台 API（`@ohos.net.http`、`@ohos.net.webSocket`）解耦，靠注入
`HttpTransport` / `WebSocketTransport` / `TimerBridge`，于是网络层可以在 node 下跑契约测试。
iOS 侧照搬这套结构，还是直接用 `http` / `web_socket_channel` 的单例？

## 决定

沿用注入：`core/dsh_client.dart` 只依赖三个抽象（HTTP、WS、Timer）与 `DshClientDeps`
（id / 时区 / 语言）。真实实现在 `platform/`；测试用 `test/support/fakes.dart`。

## 后果

- ✅ 121 条用例全部离线运行：不连网、不睡觉、不读钥匙串，CI 里 1 秒内跑完。
- ✅ 协议行为（URL 拼装、鉴权头、错误映射、退避序列）可以逐条钉住。
- ✅ 平台替换成本低（例如以后换 `cupertino_http` 或加代理）。
- ⚠️ 多一层抽象，读代码要跳一次 `platform/http_transport.dart`。
- ⚠️ `TimerBridge` 与 VM 内部的去抖定时器是两套（前者给 WS 退避，后者给 UI 刷新），
  新人容易混 —— 已在 `docs/ARCHITECTURE.md` 的数据流小节写明。

## 替代方案与为什么不选

| 方案 | 为什么不行 |
|---|---|
| 直接 `http.get` | 无法在测试里制造 404 / 409 / 超时；协议口径只能靠真机试 |
| mockito 生成 mock | 能用，但 `HttpTransport` 只有 3 个方法，手写替身更直观、零代码生成 |
