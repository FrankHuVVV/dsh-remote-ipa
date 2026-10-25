# 架构

单 `MaterialApp` + 单 `HarnessViewModel`。所有屏幕共享同一份状态；页面之间不互相调用业务动作。

```
┌──────────────────────────── lib/ui/ ────────────────────────────┐
│ ConnectScreen · AppShell(底部 5 分节) · SessionsScreen · ChatScreen│
│ FilesScreen · PluginsScreen · ModelsScreen · SettingsScreen      │
│ 只做三件事：读 state、调 vm 的方法、渲染                              │
└───────────────────────────────┬──────────────────────────────────┘
                                │ AnimatedBuilder(animation: vm)
┌───────────────────────────────▼──────────────────────────────────┐
│ lib/state/harness_view_model.dart（+ 两个 part 扩展）               │
│ 连接：探活 / 选路 / 重连    会话：历史 + 实时合并                    │
│ 文件：目录 / 预览 / 保存    设置：偏好镜像                          │
│ **唯一** 调用 DshClient 的地方                                      │
└───────────────────────────────┬──────────────────────────────────┘
                                │ DshClient（REST + WS）
┌───────────────────────────────▼──────────────────────────────────┐
│ lib/core/ 纯 Dart：Models · DshClient · ChatPresentation ·          │
│ MarkdownLite · ConnectionShare · HostStore · EndpointUrl ·          │
│ small_parts（字号/主题/分组/时间/能力位/seq 监控）                    │
│ 不 import flutter/material，不 import dart:io                       │
└───────────────────────────────┬──────────────────────────────────┘
                                │ 注入 HttpTransport / WebSocketTransport
┌───────────────────────────────▼──────────────────────────────────┐
│ lib/platform/：package:http · web_socket_channel · 钥匙串 ·          │
│ SharedPreferences · flutter_timezone · UUID                          │
└──────────────────────────────────────────────────────────────────┘
```

## 数据流

1. **启动**：`main` 组装依赖（偏好 → 钥匙串 → HTTP/WS/timer）→ `HarnessViewModel.init()`：
   读主机 → 取 `updatedAt` 最新的一台 → 并发探活 → 四级选路 → `devices/self` → 快照 → 开 WS。
2. **聊天**：WS `chat.message.delta` → `LiveChatState.append`（只保留当前 turn+step）→
   `visibleItems = displayItemsOf(history) ++ live`。同时 400ms 去抖重拉历史 ——
   正文**始终以 REST 历史为准**，流式只是「提前看到」。
3. **渲染**：助手正文先按 `dsh-ui` 围栏切成「文字段 + 卡片段」：文字走 `MarkdownLite`，
   卡片走 `GenUiCardView`（未知类型丢弃、坏 JSON 回落原文）。输入框里 `@` / `/` 只改草稿，
   发送时 `/` 开头走命令端点、其余走消息端点。
4. **审批 / 问答**：事件只用来触发**重取**，不在本地拼装状态。重连成功也重取一遍：
   「卡片没弹」和「本来就没有待审批」在屏幕上长得一模一样。
5. **写**：`HarnessViewModel._update(fn)` 是唯一写入口，写完全局通知；UI 不持有业务状态。

## 关键取舍

| 取舍 | 理由 |
|---|---|
| 不用 WebView | 不可信的会话内容 / 文件不得在手机上取得执行权（ADR-0001） |
| `core/` 纯 Dart | 531 → 121 的用例全在离线环境跑；网络/钥匙串/时钟全部注入 |
| 单一网络边界 | 「点了不动」几乎都是页面自己发请求、口径分裂导致的 |
| 流式只做显示 | 历史是权威副本；WS 只是更早看到，掉线也不会丢字 |
| 令牌进钥匙串 | 见 ADR-0003；普通偏好里只有常量句柄 |
| iOS 15 起 | Flutter 3.47 的下限 + `Table`/`ColorScheme` 等 API 的可用性 |

## 存储

| 内容 | 位置 | 加密 |
|---|---|---|
| 主机 / 地址 / 设备令牌 | iOS 钥匙串（`dsh_hosts_v1`） | 系统（Secure Enclave） |
| 主题 / 字号 / 语言 / 发送方式 / 上下文开关 | `SharedPreferences` | 否（非敏感） |
| 会话图片 | 内存（`attachmentImages`） | 不落盘 |

应用数据不参与 iCloud 备份（钥匙串 `accessibility = first_unlock_this_device`，
且 `UIApplicationSupportsMultipleScenes = false`）。

## 生命周期

- `paused/inactive`：`pauseEvents()` 关 WS，保留连接与令牌。
- `resumed`：`resumeEvents()` 重开 WS + 重取历史 / 审批 / 问答 / 命令。
- `dispose`：取消去抖定时器、关 WS、停止监听。

## 与鸿蒙版的对应

逐文件映射见 `docs/PORT-MAP.md` §3；能力差异见 `docs/PARITY.md`。
