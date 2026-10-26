# 测试口径

## 命令

```bash
cd app
flutter analyze --no-fatal-infos   # 0 error / 0 warning
flutter test                       # 195 用例（2026-10-26）
flutter test test/harness_view_model_test.dart          # 单文件
flutter test --plain-name '审批决定打到正确端点'          # 单用例
```

版本基线：Flutter 3.47.8 / Dart 3.13.7（与 CI 一致）。**用例数是快照，不是常量**，
改代码时以实际输出为准，并在本文件与本表同步。

## 用的替身（`test/support/fakes.dart`）

| 替身 | 作用 |
|---|---|
| `MemoryKeyValueStore` | 偏好内存实现；断言「明文没落盘」 |
| `MemorySecretBox` | 反转 + Base64，能验证加解密路径而不用真钥匙串 |
| `FakeHttpTransport` | 按 `方法 + URL` 注册响应；支持前缀匹配（最长优先）与注入异常 |
| `FakeWebSocketTransport` | 记录 URL，暴露 `emit` / `connection` 手动推帧 |
| `FakeTimerBridge` | 退避定时器不睡觉，`flush()` 立即触发 |

`HarnessViewModel` 的所有测试都走假 transport：**不连网、不读钥匙串、不等真实时间**。

## 用例分布

| 文件 | 覆盖什么 | 约 |
|---|---|---:|
| `endpoint_url_test.dart` | `/api/v1` 归一、去尾斜杠、地址类型推断、主机名 | 14 |
| `connection_share_test.dart` | `DSH1:` 往返、脏粘贴、缺填充、非法输入、buildHost | 10 |
| `host_store_test.dart` | 加密落盘、坏数据备份、upsert 时间语义、迁移幂等、四级选路 | 14 |
| `chat_presentation_test.dart` | 事件 → 显示项、只发图不丢、交接说明、工具配对/合并、失败行、流式状态 | 22 |
| `markdown_lite_test.dart` | 块级 12 种、行内标记、未闭合兜底、拼接不变量 | 17 |
| `gen_ui_test.dart` | 围栏切分（未闭合 / 裸围栏 / `dsh-ui-bad`）、组件解析、列表/表格取值、行内标记、列宽 | 17 |
| `mention_and_suggestions_test.dart` | `@` 识别与替换、绝对路径换前缀、目录优先、`/` 前缀与空白、面板互斥 | 24 |
| `session_stats_trajectory_test.dart` | 事件计数、轮次分组、耗时三种不给值、短耗时格式 | 13 |
| `small_parts_test.dart` | 字号/主题/发送方式、体积、分组、时间标签、seq 监控、能力位、请求闸 | 17 |
| `dsh_client_test.dart` | URL 拼装、鉴权头、请求体两种形状、ETag 条件、路径编码、错误映射、WS | 15 |
| `chat_images_test.dart` | 助手消息的 image 块、交接标记、只发图不发字 | 4 |
| `permission_and_socket_test.dart` | 四档权限合并、当前值优先投影、http(s)→ws(s) | 10 |
| `workspace_groups_test.dart` | 按工作区分组、组内/组间排序、未分组置底 | 5 |
| `image_viewer_test.dart` | 全屏图片页：关闭按钮可返回、保存按钮可点 | 1 |
| `harness_view_model_test.dart` | 自动连接、快照、选会话、审批、发消息、实时增量、能力位、导入、断开、偏好 | 11 |
| `widget_test.dart` | 冷启动渲染连接页 | 1 |

合计 **195**（`flutter test` 实测；新增 54 条中 GenUI 17、补全 24、统计与轨迹 13）。

## 三条不变量（必须一直被钉住）

1. **行内 Markdown 拼接等于原文** —— 不允许吞字/造字；链接只丢语法字符。
2. **工具合并只合并显示** —— 每一条 `ToolCallDetail` 都还在，详情视图能逐条展开。
3. **选路四级排序键** —— 延迟升序 → LAN 1.5 倍容差 → preferred → lastCheckedAt。

## 单测覆盖不到、必须真机的

- 手势与滚动（列表跟随、上翻冻结、侧滑返回）。
- 键盘避让与中文输入法候选栏。
- 表格列宽在窄屏上的表现。
- 图片解码（HEIC / 超长边内存）。
- 本地网络权限弹窗、ATS、钥匙串读写。
- WebSocket 前后台挂起与重连。
- 打包 / 签名 / 侧载全链路（见 `docs/RELEASE.md`）。

## 修 bug 的姿势

1. 先写一个**会红**的用例（在对应文件里）。
2. 改代码到绿。
3. 用例名写清「为什么」，不写「test 1」。
4. 如果这个 bug 属于「口径漂移」，同步改 `docs/PORT-MAP.md`；
   如果属于「新坑」，加进 `docs/PITFALLS.md` 与 `AGENTS.md` §8 索引。
