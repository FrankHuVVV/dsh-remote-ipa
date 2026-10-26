# 技术债台账

**规则**（同 `AGENTS.md` §4.2）：每条写清「位置 / 为什么是债 / 清账阶段」；
**只许收紧** —— 债务消失时在**同一提交**里删掉该条目；新增超预算文件必须先入账再写码。
这不是许可清单，是待办清单。

当前行数预算：**900 行/文件**。实测最大文件 `ui/chat_screen.dart` 812 行（0.2.0 加补全面板后）。

---

## 在册

### T-1 · 对话框里的中文字面量

- **位置**：`app/lib/ui/widgets.dart`（`confirmDialog` / `textInputDialog` 的「取消 / 确定」）
- **为什么是债**：违反「界面文案一律走 `Strings`」的约定。英文界面下这两个按钮仍是中文。
- **清账**：P4。把按钮文案改成必传参数，调用点传 `s.get('cancel')` / `s.get('confirm')`。

### T-2 · 聊天页承担了四块职责

- **位置**：`app/lib/ui/chat_screen.dart`（812 行）
- **为什么是债**：输入区、审批卡、问答卡、模型面板挤在一个文件里，已接近 900 行预算；
  审批与问答的版式规则与聊天流无关，混在一起改一处要看三处。
- **清账**：P4。拆 `chat_composer.dart`（输入区 + 附件）、`approval_card.dart`、`question_cards.dart`。

### T-3 · 状态拷贝靠手写字段列表

- **位置**：`app/lib/state/harness_view_model.dart` 的 `_copyInto`
- **为什么是债**：新增 `HarnessState` 字段时必须手工加一行，漏了不会报错。
  `attachmentUploading` 已经漏过一次（断开后上传状态残留）。
- **清账**：P4。改为 `HarnessState.copyFrom(other)` 单一实现，并加一条「字段清单」用例
  （用反射做不到，改用一个显式的 `describe()` 字符串快照比对）。

### T-4 · 图片缓存无上限

- **位置**：`HarnessState.attachmentImages`
- **为什么是债**：长会话 + 多图会持续吃内存，iOS 会先杀后台再杀前台。
- **清账**：P4。改成 LRU（例如最多 16 张或 24 MiB），淘汰时重新按需取。

### T-5 · `_arrayLabels` 的名字与返回类型不符

- **位置**：`app/lib/core/chat_presentation.dart`
- **为什么是债**：名字像返回 `List<String>`，实际返回拼接后的 `String`；
  读代码的人会误用 `.first`。目前只有一个调用点，但这是典型的「下次一定踩」。
- **清账**：P3。改名 `joinedLabels` 或返回 `List<String>` 由调用方拼接，并补一条用例。

### T-6 · 自研 JSON 缩进器

- **位置**：`app/lib/core/chat_tools.dart` 的 `JsonPretty`
- **为什么是债**：`JsonEncoder.withIndent('    ')` 就能做到，自研版本还要自己处理转义，
  多一处可能和标准实现不一致的地方。
- **清账**：P3。直接换标准库，用例不变。

### T-7 · 文件页缺少「未保存离开」保护

- **位置**：`app/lib/ui/files_screen.dart`
- **为什么是债**：编辑器里改了内容后左滑返回会静默丢弃，用户没有任何提示。
- **清账**：P4。`PopScope` + 脏标记 + 二次确认。

---

## 已清账（保留记录，证明台账会收紧）

| 条目 | 清账日期 | 说明 |
|---|---|---|
| 初始版本单文件 1488 行 | 2026-10-25 | 拆为 `harness_view_model.dart`(776) + 两个 part 扩展（469 / 260） |
| 初始版本 `chat_presentation.dart` 1151 行 | 2026-10-25 | 拆为 types / tools / 解析构造三份（233 / 398 / 546） |

### T-8 · GenUI 卡片里的交互态不持久

- **位置**：`app/lib/ui/gen_ui_card.dart`（`_GenUiCardViewState._selected`）
- **为什么是债**：选中态住在组件里，消息一重建就回到没选。这与鸿蒙版一致（「刷新后回到没选」），
  但用户如果在同一张卡片上改了主意，之前的点击没有任何痕迹可循。
- **清账**：P5。需要服务端能识别「卡片回答的是哪一次提问」，否则只能保持现状；
  先记为「已知行为」，等能力位。

### T-9 · 供应商编辑不做字段级校验

- **位置**：`app/lib/ui/models_screen.dart`（`_ProviderEditSheet`）
- **为什么是债**：baseURL 只做非空判断，没有 URL 语法校验；填错只有点「发现模型」才会暴露。
- **清账**：P4。保存前用 `Uri.tryParse` + scheme 白名单校验，错误就地显示在输入框下方。

### T-10 · 洞察面板一次性铺开所有信息

- **位置**：`app/lib/ui/session_insights.dart`
- **为什么是债**：待办 + 交付物 + 两个入口塞一个滚动面板；交付物多时统计与轨迹入口会被推到屏幕外，
  用户以为没有。
- **清账**：P4。改成两个 tab（数据 / 排查），或把统计与轨迹提到顶部的两个按钮。

### T-11 · WS 断开时的 5s 轮询兜底

- **位置**：`app/lib/state/harness_view_model.dart`（`_startFallbackPolling`）
- **为什么是债**：固定 5s 轮询在「WS 长期连不上」时会持续发请求（耗电与流量），
  且不区分前后台。
- **清账**：P4。改成指数退避（5s → 30s 封顶），并在 `pauseEvents` 时一并停掉。

