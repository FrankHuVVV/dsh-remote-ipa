# 变更记录

格式：每个版本一段，倒序。仓内约定见 `AGENTS.md` §3（改代码 → 改文档 → 校验 → 打包）。

## [未发布]

（尚无）

## 0.2.2 — 2026-10-26

首次真机侧载（0.2.1）后按用户反馈修的六处问题。

### 修复

- **会话工作区看不到**：会话行补 `cwd`，聊天页副标题改为「运行态 · 工作区 · cwd」。
- **会话内没有权限档位**：聊天页新增权限按钮条，候选项来自 `chat/permission-presets`，
  切换走 `/permission <preset>`（与鸿蒙版同一条命令路径），切换前二次确认。
- **表格/图表显示成竖排单字**：Markdown 表格此前用 `FlexColumnWidth` 放在**横向滚动**里，
  宽度无界会被压成每列接近 0；改为 `LayoutBuilder` 算固定列宽（≥96vp）后外层横向滚。
- **一直显示离线**：① WS 握手去掉 `Accept: application/json`（部分中继会把它当普通 GET 拒掉）；
  ② 设置页显示 WS 掉线原因；③ WS 未连上时以 5s 轮询兜底补历史与审批，不再「在线但不动」。
- **模型回复的图片看不到**：`assistantItems` 以前只认 text / reasoning，`image` 块整类丢弃；
  现在助手消息里的图片块与 `[Image: source: …]` 交接图都会变成附件并显示；
  正文里的本地路径链接改为交给 ViewModel `resolvePath` + 文件预览，而不是丢给系统浏览器。
- **“+”选不了相册**：附件入口改为「从图库选择 / 从文件选择」，图库走 `image_picker`（PHPicker，
  无需相册写入权限），文件仍走 `file_picker`。

### 变更

- 版本 / 构建号：`0.2.2+4`；`build_stamp` 与 `MARKETING_VERSION` 同步。
- 新增依赖：`image_picker ^1.2.4`（仅用于从相册选图）。
- 单测：179 条（新增 4 条助手图片/交接图回归）。

### 验证

- `flutter analyze` → No issues；`flutter test` → 179 passed。
- GitHub `macos-15` 构建 **通过**（run 40294523178）：未签名 IPA 7,987,474 B，
  SHA-256 `127b4730c61e896c4cb6c7173b856882705f51ea8f374a1a38f892c2f453904f`，随 Release v0.2.2 发布。
  待装机复验六项修复（见 `docs/STATUS.md` 的「真机反馈」小节）。

## 0.2.1 — 2026-10-25

修复首次云端构建失败（`v0.2.0` 的 run 在 Build iOS app 步骤报
`The sandbox is not in sync with the Podfile.lock`）。

### 修复

- **删除 `app/ios/Podfile`**：Flutter 3.47 的模板是 Swift Package Manager 工程
  （`project.pbxproj` 已引用 `FlutterGeneratedPluginSwiftPackage`），所有插件也都带
  `Package.swift`；手写 Podfile 会让项目同时启用 CocoaPods，两套依赖系统互相改
  project / xcconfig，构建期必然对不上。
- **CI**：新增 `Enable Swift Package Manager` 步骤（`flutter config --enable-swift-package-manager`），
  并断言 `test ! -f ios/Podfile` —— 再有人加回 Podfile，构建会**立刻**报一句可读的错误，
  而不是等到 Xcode 阶段才出现 sandbox 报错。

### 变更

- 版本 / 构建号：`0.2.1+3`；`build_stamp` 与 `MARKETING_VERSION` 同步。
- 文档：`PITFALLS` 用「Podfile 与 Swift Package Manager 混用」替换原 Podfile 部署目标条目，
  `STATUS` 增加云端构建记录，`AGENTS` 坑位索引同步。

### 验证

- `flutter analyze` → No issues；`flutter test` → 175 passed（仅构建配置变更，逻辑未动）。
- GitHub `macos-15` 构建 **通过**（run 40207148670）：未签名 IPA 7,907,704 B，
  SHA-256 `e0563badfd2cf1dcfa6788d3c1cb1ee3a6ec84ba9f28f061a7d6c68ba15366e2`，已随 Release v0.2.1 发布。
  结构校验：arm64、`com.dsh.companion.ios`、0.2.1(3)、MinimumOSVersion 15.0、
  Frameworks = Flutter / App / objective_c、**无** `embedded.mobileprovision`（未签名）。

## 0.2.0 — 2026-10-25

把 0.1.0 里列为「未实现」的能力补齐，并补上一条可在 macOS 上执行的出包脚本。

### 新增

- **GenUI 卡片**：`core/gen_ui.dart`（切分 / 解析 / 列表与表格取值）+ `ui/gen_ui_card.dart`
  （21 种组件、交互组件回话、未知类型丢弃、坏 JSON 回落原文）。
  围栏未闭合时不切，等闭合再切 —— 流式输出中不会出现半张卡片。
- **输入框补全**：`core/mention_query.dart` + `core/composer_suggestions.dart`；
  `@` 文件补全（目录优先、绝对路径、目录补 `/`）、`/` 命令补全（整行前缀、无空白、上限 5）；
  `/` 开头的输入按命令执行。
- **会话洞察**：待办、交付物、执行统计（`core/session_stats.dart`，不显示读不到的 Token）、
  执行轨迹（`core/trajectory.dart` + 页面，认不得的事件保留原名并可看原始 JSON）。
- **文件**：上传新文件、回收站列表与恢复、导出到 Documents/Exports（`platform/exports.dart`）；
  Info.plist 加 `UIFileSharingEnabled` / `LSSupportsOpeningDocumentsInPlace`。
- **模型**：供应商编辑（apiKey 不回填、留空不修改）、发现模型、权限档位切换
  （走 `/permission` 命令，与鸿蒙版同一条路径）。
- **图片**：全屏查看里可导出到「文件」App。
- `tools/build_ios.sh`：macOS 上一条命令完成 analyze + test + build + 打包（非 macOS 直接报错退出）。

### 变更

- 版本 / 构建号：`0.2.0+2`；`build_stamp` 默认值、`MARKETING_VERSION` 同步。
- 文档：`STATUS` / `PARITY` / `TESTING` / `PITFALLS` / `ROADMAP` / `TECH-DEBT` 按新能力重写。

### 验证

- `flutter analyze` → **No issues found**；`flutter test` → **175 passed**（新增 54 条：
  GenUI 17、补全 24、统计与轨迹 13）。
- **未执行**：macOS 构建、签名、侧载、真机验证（本机 Windows 无法构建 iOS，见 `STATUS.md`）。

### 已知缺口

- 图片存相册（改为导出到文件）、会话列表行内摘要、文件「替换」入口（`docs/PARITY.md` §5）。
## 0.1.0 — 2026-10-25

首个 iOS 版本（Flutter 3.47.8 / Dart 3.13.7），对照 `harmony-reference/harmony-app` 移植。

### 新增

- **工程**：`app/` Flutter iOS 工程；`core / state / ui / platform` 四层；
  `.github/workflows/ios-ipa.yml` 出未签名 IPA；`tools/package_ipa.sh`、
  `tools/make_app_icons.py`；`AGENTS.md` 与 `docs/`（状态、发布、对等、契约、坑位、测试、债务、决策）。
- **连接**：多主机 / 多地址、并发探活 + 四级选路、配对码、`DSH1:` 配置导入、
  冷启动自动重连、断开保留凭据、逐地址诊断（延迟 / 错误）。
- **会话**：列表按时间分组、新建、重命名、分叉（二次确认）、归档、归档列表（能力位守卫）。
- **聊天**：WS 流式 + REST 历史合并、Markdown（标题/列表/引用/代码块/GFM 表格/分隔线/行内标记）、
  工具调用合并与逐条明细、失败行（空 code 原样显示）、思考折叠、上下文块（可关）、
  时间戳、图片附件（历史附件 + 交接图两条取字节路径）、全屏查看、
  审批（本次允许/拒绝）、问答（选项/自由文本）、命令执行、模型切换、停止运行。
- **文件**：授权根、目录浏览与面包屑、Markdown 预览/源码、文本编辑保存（ETag 并发控制）、
  图片预览、二进制与大文件降级。
- **插件**：清单、四态、启停（提示重启 DSH）、主动查更新。
- **模型**：供应商只读视图（凭据存在性，不读正文）、权限档位只读。
- **设置**：主题三档、字号（跟随系统 / 0.8–1.5）、中英界面、上下文块开关、
  发送方式（排队/插话）、连接信息与切换、断开、版本与构建水印、隐私说明。
- **平台**：令牌进钥匙串；前后台事件流暂停/恢复；`NSLocalNetworkUsageDescription`、
  `NSPhotoLibraryUsageDescription`、`NSAllowsLocalNetworking`；Bundle ID `com.dsh.companion.ios`；
  全套 AppIcon。

### 验证

- `flutter analyze` 0 issue；`flutter test` 121 用例全绿。
- **未执行**：macOS 构建、签名、侧载、真机验证 —— 见 `docs/STATUS.md` 的四态表。

### 已知缺口

- GenUI 卡片、`@`/`/` 补全面板、执行轨迹与统计、会话摘要、交付物展示、
  回收站/上传替换/导出、权限档位切换、供应商编辑（`docs/PARITY.md` §5）。
