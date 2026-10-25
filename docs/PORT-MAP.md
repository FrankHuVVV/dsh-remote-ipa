# 移植映射表（鸿蒙 ArkTS → iOS Flutter）

**事实来源**：`harmony-reference/harmony-app/docs/PORT-MAP.md`（服务端契约）+ `app/lib/`（实现）。
本文件回答三件事：**协议长什么样**、**每个 ArkTS 模块搬到哪个 Dart 文件**、**哪些口径不许漂**。

---

## 1. 端点总表（全部挂在基地址根上，**不带任何前缀**）

| 方法 | 路径 | 鉴权 | 请求体 | 响应 |
|---|---|---|---|---|
| GET | `healthz` | 否 | — | `HealthView{ok,version,pluginVersion?}` |
| POST | `pairings/exchange` | 否 | `{code,deviceName}` | `PairingResult{token,device}` |
| GET | `devices/self` | 是 | — | `DeviceView{id,name,scopes,rootIds}` |
| GET | `roots` | 是 | — | `{items:[RootView...]}` |
| GET | `roots/{rootId}/entries?path=&cursor=` | 是 | — | `DirectoryPage` |
| GET | `roots/{rootId}/content?path=` | 是 | — | 字节流 + `ETag` / `Content-Type` |
| PUT | `roots/{rootId}/content?path=` | 是 | 字节流 | `ETag`；无 etag 时 `If-None-Match: *`，否则 `If-Match` |
| POST | `roots/{rootId}/entries` | 是 | `{path,kind}` | 空 |
| PATCH | `roots/{rootId}/entries` | 是 | `{path,destinationPath}` | 空 |
| DELETE | `roots/{rootId}/entries?path=` | 是 | — | 空 |
| GET | `trash` / POST `trash/{id}/restore` | 是 | — | `{items:[...]}` / 空 |
| GET | `roots/resolve?path=` | 是 | — | `ResolvedPath`；授权根外 → 404 + 可识别 code |
| GET | `chat/sessions`（`?archived=true`） | 是 | — | `{items:[ChatSession...]}` |
| GET/POST | `chat/workspaces`，PATCH/DELETE `chat/workspaces/{id}` | 是 | — | `{workspace}` |
| GET | `chat/agent-presets` | 是 | — | `{items:[AgentPreset...]}` |
| GET/PUT | `chat/sessions/{id}/models`、`.../model`、`.../agent-preset` | 是 | — | `SessionModels` / `{selected}` / `{agentPreset}` |
| POST | `chat/sessions` | 是 | `{workspaceId,agentPreset?,clientRequestId}` | `{session:{id,agentPreset?}}` |
| PATCH | `chat/sessions/{id}` | 是 | `{title}` | `{title,seq}` |
| POST | `chat/sessions/{id}/fork` | 是 | `{atSeq?}` | `{sessionId}` |
| POST | `chat/sessions/{id}/archive` | 是 | `{}` | 空 |
| GET | `chat/sessions/{id}/messages?beforeSeq=&maxMessages=` | 是 | — | `ChatHistory{events,hasMore,projections?}` |
| GET | `chat/sessions/{id}/approvals` | 是 | — | `{items:[PendingApproval...]}` |
| POST | `chat/sessions/{id}/approvals/{aid}/decision` | 是 | `{outcome}` | 空 |
| GET | `chat/sessions/{id}/questions` | 是 | — | `{items:[PendingQuestionSet...]}` |
| POST | `chat/sessions/{id}/questions/{callId}/answer` | 是 | `{answers:[...]}` | 空 |
| GET/POST | `chat/sessions/{id}/commands` | 是 | `{line}` | `{items}` / `{execution}` |
| POST | `chat/sessions/{id}/messages` | 是 | 见 §2.2 | 空 |
| POST | `chat/sessions/{id}/attachments` | 是 | `{name,data(base64)}` | `UploadedAttachment` |
| POST | `chat/runs/{sessionId}/cancel` | 是 | `{}` | 空 |
| GET | `attachments/{attachmentId}?sessionId=` | 是 | — | 字节流 |
| GET | `settings/providers` / PATCH `{id}` / POST discover | 是 | — | `ProviderSettings` |
| GET/PATCH | `settings/plugins`（`?checkUpdates=1`） | 是 | `{name,loaded}` | `PluginInventory` / `PluginToggleResult` |
| GET | `chat/permission-presets` | 是 | — | `{options,currentValue}` |
| WS | `events` | 是 | — | `WorkspaceEvent{id,type,time,data}` |

> ⚠️ `GET .../questions` 在服务端会 `resolveAgent(..., resume)` —— **只能对当前打开的会话调用**，
> 禁止拿它遍历会话列表（会把冷会话的 Agent 拉活）。iOS 版由 `selectSession` 唯一入口保证。

---

## 2. 请求约定（跨仓契约，改前先改文档）

1. **鉴权头**：`Authorization: Bearer <token>`、`Accept: application/json`、
   `Accept-Language: <界面语言，默认 zh-CN>`。
2. **超时**：连接 15s / 读 45s；WS ping 20s。
3. **WebSocket**：URL 用**同源 http(s)**，由底层升级；不要提前改 `ws://`。
   重连退避 `min(1 << retries, 30)` 秒（1、2、4、8、16、30…）；重连后状态恢复**始终靠 REST**。
4. **空体**：GET 不带 body；POST/PUT/PATCH 零长度体补 `{}`。
5. **端点归一**：必须以 `http(s)://` 开头，路径不以 `/api/v1` 结尾则追加。
   > 3090 是插件端口，路由挂在根上；**不要**带 `/dsh-workspace-api`（那是 3080 上 WebUI 的挂载面）。
6. **错误**：非 2xx 解析 `{error:{code,message}}` → `DshApiException(status, code, message)`。
   `PATH_OUTSIDE_ROOTS` / `PATH_NOT_ABSOLUTE` / `PATH_NOT_FILE` / `PATH_NOT_FOUND` 是**正常结果**；
   其余 404（尤其 `ROUTE_NOT_FOUND`）必须抛出 —— 那是「插件太旧」而不是「路径不对」。

### 2.1 发消息体

```json
{ "text": "...", "mode": "queue|steer", "clientTimeZone": "Asia/Shanghai", "clientRequestId": "<uuid>" }
{ "content": [ {type:"text",text}, {type:"image",mediaType,data,name?}, {type:"file",receiptId} ],
  "mode": "queue|steer", "clientTimeZone": "...", "clientRequestId": "<uuid>" }
```

- 纯文本走旧 `{text}` 形状（不强迫旧插件升级）；带附件才用 `content` 数组。
- 图片 base64 **内联**（≤ 8 MiB）；普通文件先换 `receiptId`（≤ 24 MiB）。
- `mode`：运行中「排队」= `queue`，「插话」= `steer`。

### 2.2 事件语义（聊天页只认这些）

| 帧 | 处理 |
|---|---|
| `chat.message.delta` | `kind` 只认 `text` / `reasoning`；五个必填字段缺一个整帧丢弃 |
| `chat.turn.failed` | 终局失败（限流 / 配额 / 密钥），进失败行 |
| `turn/end`（历史） | `reason.kind=error` 或「退出登录导致 aborted」→ 失败行 |
| `chat.approval.requested/resolved` | 重取审批列表（**不拼装本地状态**） |
| `chat.userQuestions/requested` | 重取问题；`answered/dismissed` 移除对应 callId |
| `chat.session.snapshot` | 记订阅基线 `cursor`；本地历史落后于它 → 重拉历史 |
| `chat.session.status` / `turn.start` / `turn.end` | 列表刷新（去抖）+ 当前会话历史刷新 |
| `connection.ready` | 读 `bridgeVersion` 与 `capabilities`；**读不到保持旧值**（未知 ≠ 缺失） |
| 其他 | 不渲染、不改状态 |

**断档判据**：严格跳号（`seq > last + 1`）才重拉整份历史；重复与倒退算去重，**不算断档**。
序号序列**每会话独立**，切会话即重置。

---

## 3. 文件映射

| 鸿蒙 ArkTS | iOS Dart | 说明 |
|---|---|---|
| `core/Models.ts` + `Models*.ts` | `core/models.dart` + `models_*.dart` | 字段默认值 / 省略 null / 按 type 分派三条规矩照搬 |
| `core/DshClient.ts` | `core/dsh_client.dart` | 注入 HTTP / WS / Timer；URL 拼装、鉴权、错误映射、退避 |
| `core/EndpointUrl.ts` | `core/endpoint_url.dart` | 纯字符串实现，不依赖 `Uri` 的宽松解析 |
| `core/ConnectionModels.ts` | `core/connection_models.dart` | Host / Endpoint / Credential / 选路 |
| `core/ConnectionShare.ts` | `core/connection_share.dart` | `DSH1:` 编解码（容错口径逐条对齐） |
| `core/HostStore.ts` + `ConnectionStorage.ts` | `core/host_store.dart` | 注入 `KeyValueStore` / `SecretBox`；坏数据备份不静默清空 |
| `core/AppPreferences.ts` | `core/app_preferences.dart` | 纯偏好；布尔按字符串落盘 |
| `core/ChatPresentation*.ts` | `core/chat_presentation*.dart` + `chat_tools.dart` | 事件 → 显示项；工具合并 |
| `core/GenUiBlocks.ts` | `core/gen_ui.dart` | `dsh-ui` 围栏切分 / 解析 / 列表与表格取值 |
| `ui/GenUiCard.ets` | `ui/gen_ui_card.dart` | 21 种组件；未知类型丢弃、坏 JSON 回落原文 |
| `core/MentionQuery.ts` + `ComposerSuggestions.ts` | `core/mention_query.dart` + `composer_suggestions.dart` | `@` 绝对路径换算 / `/` 命令前缀 |
| `core/SessionStats.ts` + `Trajectory.ts` | `core/session_stats.dart` + `trajectory.dart` | 统计只数事件；轨迹保留未知类型原名 |
| `core/MarkdownLite.ts` | `core/markdown_lite.dart` | 块级 + 行内；不变量用测试钉住 |
| `core/ChatSeqMonitor.ts` / `SessionGrouping` / `ChatTimeLabel` / `FontScale` / `ThemeMode` / `ComposerSendPolicy` / `BridgeCapabilities` / `RequestGate` | `core/small_parts.dart` | 「一条规则一个文件」的件合并成一个可测模块 |
| `core/HarnessViewModel*.ts` | `state/harness_view_model.dart` + `harness_chat_actions.dart` + `harness_files_actions.dart` | part 扩展拆到 900 行预算内 |
| `ui/*.ets`（30 个文件） | `ui/*.dart`（10 个文件） | Material 3 而非 ArkUI；分节、过滤、审批版式照搬 |
| `platform/HttpTransport.ets` | `platform/http_transport.dart` | `package:http` + 超时；响应头统一小写 |
| `platform/WebSocketTransport.ets` | `platform/ws_transport.dart` | `web_socket_channel`；`onDown` 恰好一次 |
| `platform/Crypto.ets` + `PrefsStore.ets` | `platform/secure_store.dart` | 钥匙串 + SharedPreferences |
| `platform/Platform.ets` | `platform/platform_deps.dart` | UUID / 时区 / 设备名 |
| `platform/Pickers.ets`（保存） | `platform/exports.dart` | 导出到 Documents/Exports（不引分享插件） |
| `core/BuildStamp.ets` | `core/build_stamp.dart` | `--dart-define` 注入 |

---

## 4. 有意差异

| 差异 | 原因 |
|---|---|
| 底部 Tab 取代侧栏抽屉 | iPhone 上抽屉会与返回手势抢；宽屏（iPad）仍用同一套 Tab |
| 连接页只在未连接时出现，换电脑走「设置 → 连接」 | 连上后仍要有入口；比每启动都停在连接页少一次点击 |
| 令牌存钥匙串而非自研 AES-GCM | 见 `decisions/ADR-0003-keychain-over-homegrown-aes.md` |
| `HostStore` 的加密接口是异步的 | 钥匙串 API 本身异步；core 里其余逻辑仍同步可测 |
| 无 `useWebChat` 假开关 | iOS 版没有 WebView 分支，保留只会误导 |
| 权限切换走 `/permission <preset>` 命令 | 服务端没有单独的「改权限」端点，硬造 PATCH 会与内核口径分裂 |
| GenUI 围栏先按代码块显示 | 不丢内容、不假装渲染；组件库在 P5 补 |

---

## 5. 坑位

全部 iOS / Flutter / 侧载特有的坑在 `docs/PITFALLS.md`，名字与 `AGENTS.md` §8 索引一一对应。
