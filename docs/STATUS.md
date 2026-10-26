# 状态

> 更新时间：2026-10-26（版本 0.2.4+6）。**四态必须分清**：打包 → 签名 → 装机 → 验证。
> 本页只写**实测过**的东西；没上过真机的一律 🟡。

## 一句话

iOS 版（Flutter）已完成功能移植：连接 / 会话 / 聊天 / GenUI 卡片 / 审批 / 问答 /
`@` 文件与 `/` 命令补全 / 文件（浏览·编辑·上传·回收站·导出）/ 插件 / 模型（含供应商编辑）/
设置 / 轨迹与统计，全部可用。`flutter analyze` **No issues**、`flutter test` **195 用例全绿**。
**已在 GitHub 的 macOS runner 上出包**（未签名 IPA，见下）；签名与装机尚未执行。

## 真机反馈（2026-10-26，0.2.1 首次侧载）

用户在 iPhone 上实测 6 个问题，全部已修（0.2.2）；**0.2.2 已重新构建出包（见下），待装机复验**：

| # | 现象 | 根因 | 修复 |
|---:|---|---|---|
| 1 | 会话界面看不到工作区 | 聊天页副标题只有运行态 | 副标题显示「运行态 · 工作区 · cwd」，列表行补 cwd |
| 2 | 会话内没有权限档位按钮 | 权限只放在「模型」页 | 聊天页新增档位按钮条，走 `/permission` |
| 3 | 表格/图表显示成竖排单字 | Markdown 表格在横向滚动里用了 `FlexColumnWidth`（无界宽度） | 固定列宽 ≥96vp + 外层横向滚 |
| 4 | 设置页一直显示离线 | WS 握手带 `Accept: application/json`，中继可能拒；且无兜底 | 握手只带鉴权与语言；显示掉线原因；5s 轮询兜底 |
| 5 | 模型回复的图片看不到 | `assistantItems` 忽略 `image` 块与交接标记 | 助手消息解析图片块/交接图，附件正常显示；路径链接改为应用内预览 |
| 6 | “+”无法从图库选图 | 只用了 `file_picker`（文件选择器） | 改为「图库 / 文件」两个来源，图库走 `image_picker` |

## 真机反馈（第二轮，2026-10-26，0.2.2）

| # | 现象 | 根因 | 修复 |
|---:|---|---|---|
| 1 | 设置页仍离线，报 `Unsupported URL scheme 'https'`，但会话可用 | `dart:io WebSocket` 只认 ws/wss | 平台层 `socketUrlOf()` 把 http(s) 换成 ws(s) |
| 2 | 权限只有两个 chip、无选中强调 | 服务端目录缺 `read-only` / `auto`，且当前值取自目录 | 内置四档 + 当前值取会话投影 + 选中强调 |
| 3 | 会话列表按时间分组 | 产品要求按工作区 | `groupSessionsByWorkspace()`，组内/组间按更新时间倒序 |
| 4 | 聊天图片无法保存到手机 | 只有「存到文件」 | 全屏页加「保存到相册」（`gal` + 添加权限说明） |

## 真机反馈（第三轮，2026-10-26，0.2.3）

| # | 现象 | 根因 | 修复 |
|---:|---|---|---|
| 1 | 图片放大后没有关闭/返回按钮 | `Dialog` 内容随图片放大，操作区被挤出屏幕 | 改全屏路由：左上角固定关闭，图片区 `InteractiveViewer` |
| 2 | 点开图片没有保存按钮 | 同上（按钮在 Dialog 底部，被图片顶出可视区） | 底部固定操作条：保存到相册 / 存到文件 |

## 四态

| 阶段 | 状态 | 证据 / 缺口 |
|---|---|---|
| 源码完成 | ✅ | `app/lib/` 约 13.7k 行 Dart（53 个文件），测试 2.1k 行，按 `core/state/ui/platform` 分层 |
| 静态检查 | ✅ | `flutter analyze --no-fatal-infos` → **No issues found**（Flutter 3.47.8） |
| 单测 | ✅ | `flutter test` → **195 passed**（2026-10-25，本机 Windows + Flutter 3.47.8） |
| 打包（未签名 IPA） | ✅ | 最新：[`v0.2.4`](https://github.com/FrankHuVVV/dsh-remote-ipa/releases/tag/v0.2.4)（run 40311179367）IPA **8,012,111 B**，SHA-256 `4ba10022e43545bd8d565df44ea949c9f593e9d2f680cad86c006ccb2f7e5ef3` |
| 签名（爱思助手） | 🟡 | 流程写在 `docs/RELEASE.md`，未用真实 Apple ID 执行过 |
| 装机（iLoader 侧载） | 🟡 | 未上机；iOS 27 开发者模式、证书信任未实测 |
| 真机验证 | 🟡 | **0 项已确认**；清单见 `docs/PARITY.md` §6 |

### 本机出包尝试记录（2026-10-25）

```text
$ cd app && flutter build ios --release --no-codesign
Could not find an option named "--release".

$ flutter build --help
Available subcommands:
  aar  apk  appbundle  bundle  web  windows
```

Windows 版 Flutter **不注册 `ios` 子命令**（iOS 构建只在 macOS 上可用）；
本机也没有 `xcodebuild` / `pod`。因此这一步必须在 macOS 上做：

```bash
bash tools/build_ios.sh 0.2.0 2        # 一键：analyze + test + build + 打包
```

或推 tag 让 `.github/workflows/ios-ipa.yml` 在 `macos-15` 上出包。相关约束写进
`docs/PITFALLS.md#xcode-与-flutter-版本错配` 与 `docs/RELEASE.md` §1.2。

### 云端构建记录

| 次数 | commit / tag | 结果 | 原因 |
|---:|---|---|---|
| #1 | `e71b066` / `v0.2.0` | ❌ 失败于 Build iOS app | 手写 `ios/Podfile` 与 SPM 工程混用 → `sandbox is not in sync with the Podfile.lock` |
| #2 | `e33b8ab` / `v0.2.1` | ✅ 成功 | 删除 Podfile 后纯 SPM 构建通过；IPA 7.54 MiB，SHA-256 `e0563badfd2cf1dcfa6788d3c1cb1ee3a6ec84ba9f28f061a7d6c68ba15366e2` |
| #3 | `d75a748` / `v0.2.2` | ✅ 成功 | 真机反馈修复版；IPA 7,987,474 B，SHA-256 `127b4730c61e896c4cb6c7173b856882705f51ea8f374a1a38f892c2f453904f`（run 40294523178） |
| #4 | `b7fcc83` / `v0.2.3` | ✅ 成功 | WS/权限/分组/相册版；IPA 8,009,457 B，SHA-256 `8a3e208582dad989b051e763c8c948825cdeeda373c8d9e48a008444aa598111`（run 40298363470） |
| #5 | `c516bb5` / `v0.2.4` | ✅ 成功 | 全屏图片查看器版；IPA 8,012,111 B，SHA-256 `4ba10022e43545bd8d565df44ea949c9f593e9d2f680cad86c006ccb2f7e5ef3`（run 40311179367） |

修复提交见 `docs/CHANGELOG.md` 0.2.1 段；坑位说明见 `docs/PITFALLS.md#podfile-与-swift-package-manager-混用`。

> 远端 `v0.2.1` 指向 `e33b8ab`，与本地 `9cb8d23` **树完全一致**（逐 blob 校验过），只是提交元数据不同 ——
> 本机到 `github.com:443` 不通，这次是通过 GitHub Git Data API 推的（`api.github.com` 可直连）。
> 以远端 `main` / `v0.2.1` 为准。

产物：`https://github.com/FrankHuVVV/dsh-remote-ipa/releases/tag/v0.2.1`
（IPA 7,907,704 B + `.sha256`，未签名，需爱思助手签名后再侧载。）

## 已实现

- **连接**：多主机 / 多地址、并发探活 + 四级选路、配对码、`DSH1:` 配置导入、
  冷启动自动重连、断开保留凭据、逐地址诊断。
- **会话**：列表分组、新建、重命名、分叉、归档、归档列表（能力位守卫）。
- **聊天**：WS 流式 + REST 历史合并、Markdown、工具合并与明细、失败行（空 code）、
  思考折叠、上下文块、时间戳、图片（历史附件 + 交接图）、审批、问答、命令执行、
  模型切换、停止运行、会话内图片导出。
- **GenUI**：`dsh-ui` 围栏切成卡片，23 种组件里实现 21 种（text/row/col/grid/card/
  list/table/keyvalue/steps/stat/badge/progress/chart/code/json/diff/callout/timeline/
  divider/spacer/button/radio/submit），未知类型整条丢弃、坏 JSON 回落原文。
  交互组件（button/radio/submit）点下去作为普通用户消息回话。
- **补全**：`@` 文件补全（目录优先、绝对路径、目录补 `/`）与 `/` 命令补全（整行前缀、
  无空白、上限 5 条）；`/` 开头的输入按命令执行而不是当消息发。
- **洞察**：待办、交付物、执行统计（不编 Token 用量）、执行轨迹（按 turn 分组、
  认不得的事件保留类型原名、可看原始 JSON）。
- **文件**：授权根、目录浏览、Markdown 预览/源码、编辑保存（ETag）、图片预览、
  上传新文件、回收站列表与恢复、导出到「文件」App（Documents/Exports）。
- **插件**：清单、四态、启停（提示重启）、查更新。
- **模型**：供应商只读 + 编辑（displayName/baseURL/api/apiKey，**apiKey 不回填**）、
  发现模型、权限档位切换（走 `/permission` 命令）。
- **设置**：主题三档、字号（跟随系统 / 0.8–1.5）、中英、上下文开关、发送方式、
  连接信息与切换、断开、版本与构建水印、隐私说明。
- **平台**：令牌进钥匙串、前后台事件流暂停/恢复、本地网络与 ATS、文件 App 可见、
  全套 AppIcon。

## 尚未实现（与鸿蒙版的差距）

- 图片**存入相册**：改成导出到「文件」App（`Documents/Exports`）。见 `docs/PARITY.md` §5。
- `dsh-ui` 的交互结果不回写历史（选中态随消息重建，照鸿蒙版：刷新后回到没选）。
- 会话列表里的**摘要**（TODO / 当前工具）只在会话洞察面板里看，不在列表行上。
- 文件「替换当前文件」的上传入口没有单独做（上传新文件 + 编辑保存已覆盖）。
- 鸿蒙版的 `useWebChat` 假开关（iOS 无 WebView 分支，刻意不保留）。

## 已知风险

1. **只在 CI 上跑过一次 iOS 构建**：本地没有 macOS，未复现；签名与侧载仍未执行。
2. **免费签名 7 天到期**：分发方式的固有约束，不是 bug。
3. **重新签名后钥匙串可能读不到**：旧令牌取不出时需重新配对。
4. **局域网明文 HTTP**：只放行本地网络；公网中继必须 https。
