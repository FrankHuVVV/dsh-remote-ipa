# AGENTS.md — dsh-companion-ios 工程宪法

> 每次会话**必然读到**的那份约定。规矩写在这里，不靠记忆、不靠口头。
> 制度沿袭自 `dsh-companion`（Android）→ `dsh-companion-harmony`（鸿蒙）→ 本工程（iOS/Flutter），
> 差异见第 9 节。
>
> **体积纪律**：本文件只写**命令、契约、触发词与铁律**；「说不清、要摆证据」的内容进 `docs/`，这里只留指针。

---

## 0. 一分钟上手

| 我想… | 先读 |
|---|---|
| 知道现在到哪了 | `docs/STATUS.md` |
| 知道某能力有没有、差什么 | `docs/PARITY.md` |
| 改代码前避坑 | `docs/PITFALLS.md`（名字 = 锚点）与 `docs/PORT-MAP.md` §4 |
| 发版 / 签名 / 侧载到手机 | `docs/RELEASE.md` |
| 为什么这么设计 | `docs/ARCHITECTURE.md` + `docs/decisions/` |
| 这次改了什么 | `docs/CHANGELOG.md`（`[未发布]` 段） |
| 测试口径 / 用例数 | `docs/TESTING.md` |
| 债务台账（只许收紧） | `docs/TECH-DEBT.md` |

> **每轮开工先读 `docs/STATUS.md`**。本应用是 `dsh-remote-bridge` 插件客户端，
> **不自带任何 DSH 能力**；发现服务端能力不足时先在插件侧加接口，再接入本应用。

---

## 1. 本项目是什么（一句话与边界）

- **定位**：DeepSeek Harness 的 iOS **原生客户端**（Flutter / Dart，Material 3）。
  聊天、Markdown、表格、代码块全部**原生渲染，不使用 WebView**。
- **参考实现**：`harmony-reference/harmony-app`（鸿蒙 ArkTS 版，只读快照）。
  行为口径以它为准；**实现语言可以不同，判定条件不许漂**。
- **与谁配**：服务端插件 `dsh-remote-bridge`（**≥ 2.0.4**，旧名 `dsh-workspace`）。
- **兼容**：iOS 15.0+（`IPHONEOS_DEPLOYMENT_TARGET = 15.0`），iOS 26 / 27 上按系统向下兼容运行。
- **分发方式**：GitHub Actions 出**未签名 IPA** → 爱思助手用 Apple ID 签名 → iLoader 侧载。
  **不通过 App Store**，仓库里**不放任何证书 / 描述文件 / 密码**。
- **不做什么**：不跑内核、不代理官方 WebUI、不打包 Ubuntu、不做 WebView 版聊天。

---

## 2. 命令（本地唯一可信口径）

Flutter 版本以 CI 为准：**3.47.8 / Dart 3.13.7**（`.github/workflows/ios-ipa.yml` 的 `FLUTTER_VERSION`）。

```bash
cd app
flutter pub get
flutter analyze --no-fatal-infos     # 必须 0 error / 0 warning；info 级不阻塞
flutter test                         # 当前 194 用例，随代码变化勿当常量
```

构建与打包**只能在 macOS 上做**（Windows 上能跑 analyze/test，不能出 IPA）：

```bash
cd app
flutter build ios --release --no-codesign \
  --build-name 1.0.0 --build-number 1 \
  --dart-define=BUILD_COMMIT="$(git rev-parse HEAD)" \
  --dart-define=BUILD_TIME="$(date -u +%Y-%m-%dT%H:%MZ)"

# 打包成未签名 IPA（等同于 CI 里的 Package 步骤）
bash ../tools/package_ipa.sh 1.0.0 1

# 或者在 macOS 上一条命令跑完（analyze + test + build + 打包）
bash tools/build_ios.sh 0.2.0 2
```

远端唯一构建入口：`.github/workflows/ios-ipa.yml`（tag `v*` 或手动 `workflow_dispatch`）。
**本地失败不许靠 CI 兜底**：CI 只做同一套 `analyze / test / build`，口径必须一致。

---

## 3. 版本与文档同步（最高频失分点）

| 改动 | 必须同步 |
|---|---|
| `version`（`app/pubspec.yaml`） | `docs/CHANGELOG.md` + `docs/STATUS.md`（tag 时由 CI 用 `--build-name` 覆盖） |
| 测试用例数 | `docs/TESTING.md` |
| 发布产物 / 体积 / SHA-256 | `docs/STATUS.md` + `docs/RELEASE.md` |
| 应用名 / Bundle ID | `ios/Runner/Info.plist`（`CFBundleDisplayName`）+ `project.pbxproj`（`PRODUCT_BUNDLE_IDENTIFIER`）+ `docs/RELEASE.md` 的「改名」小节 + 用 `tools/make_app_icons.py` 重出图标 |
| 新增 / 修改能力 | `docs/PARITY.md` 对应行 + `docs/PORT-MAP.md` 端点表 |
| 新踩的坑 | `docs/PITFALLS.md` + 本文件第 8 节索引（名字必须同名） |

**铁律**：改代码 → 改文档与版本号 → `analyze` + `test` → 才打包。**顺序不可倒** ——
先打包再改文档，文档会描述一个不存在的状态。

---

## 4. 架构纪律

### 4.1 分层与依赖方向

```
lib/core/    ← 纯 Dart 逻辑（可单测）：MarkdownLite / ConnectionShare / ChatPresentation /
               HostStore / AppPreferences / EndpointUrl / small_parts ...
lib/state/   ← HarnessViewModel：持有连接、会话、文件、设置；**唯一**调用 DshClient 的地方
lib/ui/      ← 只消费 HarnessState、调 ViewModel 动作；不自己发请求、不直读偏好当状态
lib/platform/← 唯一碰系统 API 的一层（HTTP / WS / 钥匙串 / 时区 / UUID）
```

- **`DshClient` 是唯一网络边界**（REST + WebSocket）。`lib/ui/` 里出现 `http`、
  `WebSocket` 或裸 URL 拼接，即为违规 —— 它会导致「点了不动」与超时口径分裂。
- **会话展示走 `displayItemsOf` + `chatVisibleItems` 单一出口**；
  `step/end`、`turn/end`、token 序列、未知事件**不渲染为聊天卡片**。
- **不使用 WebView**：聊天与 HTML/Markdown 预览都是原生组件，避免不可信文件取得执行权
  （`docs/decisions/ADR-0001-native-rendering-no-webview.md`）。
- 平台层之外**不许** `import 'dart:io'`；`core/` 与 `state/` 不许 import `flutter/material.dart`
  （`state/` 只允许 `flutter/foundation.dart` 的 `ChangeNotifier`）。
- **状态就地改、不重建**：`HarnessViewModel._update` 是唯一写入口，写完全局 `notifyListeners()`；
  UI 通过 `AnimatedBuilder(animation: vm)` 订阅。

### 4.2 行数预算与债务台账

- 单文件预算：**900 行**（含注释）。超了先入 `docs/TECH-DEBT.md` 再写码，**不许悄悄超**。
- 台账**只许收紧**：债务消失时在**同一提交**里删掉该条（自证不是空转）。
- 上调预算必须带理由 + 下一阶段拆回的计划。

### 4.3 协议口径不可漂移

`docs/PORT-MAP.md` §1 的端点表与 §2 的请求约定是**跨仓契约**。改动任何一条（路径、字段、
超时、退避、错误码）都意味着服务端与鸿蒙端同时过期 —— 先改文档、再改两端。

---

## 5. 测试纪律

- 修 bug 必须带**回归用例**（在 `app/test/` 下，文件名与被测模块对应）。
- 纯逻辑一律可测：`core/` 里出现 `DateTime.now()` 直接调用即为可疑（应注入 clock）；
  `state/` 的测试用 `test/support/fakes.dart` 的假 HTTP / 假 WS / 假定时器，**不睡真时间**。
- **单测绿 ≠ 行为对**：手势、键盘避让、滚动跟随、表格列宽、图片解码、WS 后台挂起
  一律真机确认；没确认的写 🟡，不许写成 ✅。
- 三条必须被测试钉住的不变量：
  1. 行内 Markdown 片段拼接后逐字符等于原文（`markdown_lite_test.dart`）；
  2. 连续工具调用合并后**每条明细都还在**（`chat_presentation_test.dart`）；
  3. 选路排序的四级键与鸿蒙版一致（`host_store_test.dart`）。

---

## 6. 发版与侧载纪律

1. **CI 只出未签名 IPA**；签名永远在本地用用户自己的 Apple ID 做（`docs/RELEASE.md`）。
2. 禁止把 `.p12` / `.mobileprovision` / Apple ID 密码 / 应用专用密码提交进仓库；
   `app/ios/.gitignore` 已忽略 `*.p12`、`*.mobileprovision`。
3. **「打包成功」≠「已签名」≠「装到手机上」≠「用户吃到了」**，四态必须分清；
   `docs/STATUS.md` 按四态记录。
4. 免费 Apple ID 签名**有效期 7 天**、最多 3 个 App、需重新签名；这是分发方式的
   固有约束，不是 bug（见 `docs/decisions/ADR-0002-unsigned-ipa-sideload.md`）。
5. 禁止 `push` / `tag` / `release` 未经用户明确同意；本地 commit、构建、测试、写文档可直接做。

---

## 7. 安全边界

- 设备令牌只进 **iOS 钥匙串**（`platform/secure_store.dart` 的 `KeychainSecretBox`），
  普通偏好里只有常量句柄；**不写日志、不进剪贴板、不进崩溃上报**。
- `DSH1:` 配置文本**本身就是凭据**（内含设备令牌），UI 只提示「发给自己」；
  解码永不抛异常，编码遇非法输入才抛。
- 服务端返回的文件内容一律按**不可信文本**渲染：不执行、不解析为 HTML、不自动打开外链
  （用户点击才交给系统浏览器）。
- 应用数据不参与 iCloud 备份（钥匙串 `accessibility = first_unlock_this_device`）。

---

## 8. 坑位索引（名字 = 触发词 = 锚点）

正文在 `docs/PITFALLS.md`，动手前按名字读对应小节。**不看就改 = 重踩。**

- `本地网络权限缺 NSLocalNetworkUsageDescription`
- `ATS 拦住明文 HTTP`
- `重新签名后钥匙串读不到`
- `免费证书 7 天到期`
- `Bundle ID 与描述文件不一致`
- `未签名 IPA 直接装必失败`
- `iOS 27 开发者模式没开`
- `Xcode 与 Flutter 版本错配`
- `Podfile 与 Swift Package Manager 混用`
- `file_picker 13 的静态 API`
- `TextScaler 双重缩放`
- `键盘顶起输入区`
- `后台 WebSocket 被系统挂起`
- `滚动跟随抢走位置`
- `PATCH 经代理被改写`
- `响应头键必须小写`
- `SecretBox 是异步的`
- `空体请求补 {}`
- `附件 id 含冒号`
- `分页游标不能当历史 seq`
- `归档能力位未知 ≠ 缺失`
- `工具结果配不上 callId 就不显示`
- `围栏未闭合不切卡片`
- `dsh-ui 标记必须整词`
- `未知组件不画空壳`
- `导出走 Documents 而不是相册`
- `@ 补全用绝对路径`
- `斜杠命令不当消息发`
- `Markdown 表格在横向滚动里被压成竖排`
- `助手消息里的 image 块被丢弃`
- `WS 经中继被拒时界面像在线但不动`
- `file_picker 只能选文件，不是相册`
- `dart:io WebSocket 不认 https`
- `权限目录只有两项`
- `相册保存要 NSPhotoLibraryAddUsageDescription`

> 新坑位：名字加进上面清单 + 原文写进 `docs/PITFALLS.md`，并补 `### 同名` 锚点。

---

## 9. 制度来源与差异

| 借鉴项 | 本工程 |
|---|---|
| 工程宪法 + 文档路由表 | 保留；命令换为 `flutter / xcodebuild` |
| 债务台账（TECH-DEBT） | 已立账，900 行/文件 |
| 能力对等矩阵（PARITY） | 已建立：`docs/PARITY.md`（能力 / 插件 API / 鸿蒙版 / iOS 版 / 状态） |
| 任务台账（ROADMAP） | 已建立：`docs/ROADMAP.md` |
| 架构决策记录（ADR） | 已建立：`docs/decisions/`（一事一文件） |
| 发版说明 | `docs/CHANGELOG.md`（版本段）+ GitHub Release（tag 时自动附 IPA） |
| 坑位索引 | 保留，内容换为 iOS / Flutter / 侧载特有坑 |
| 架构纪律可执行门禁 | **刻意未引入**（当前无 CI 门禁脚本）：行数预算靠人守，若连续两次超预算，再加 `tools/check_budget.dart` |
| 中英双语 | **已内建**：`lib/l10n/strings.dart` 两份表，缺键显示 `[key]`（一眼看得见） |

**刻意没抄的**：CDP 探针体系（本工程无 WebUI 宿主）、鸿蒙的资源系统（Flutter 用代码内文案表）。

---

## 10. 交付物与目录

| 路径 | 内容 |
|---|---|
| `app/` | Flutter 工程（iOS only；`lib/`、`test/`、`ios/`） |
| `.github/workflows/ios-ipa.yml` | 未签名 IPA 的唯一构建入口 |
| `tools/build_ios.sh` | **一键出包**（macOS）：analyze + test + build + 打包 |
| `tools/package_ipa.sh` | 只做打包：把已构建的 `Runner.app` 封成 IPA |
| `tools/make_app_icons.py` | 由一张 1024 母图生成整套 AppIcon |
| `docs/` | 状态、发布、对等、契约、坑位、测试、债务、决策 |
| `harmony-reference/` | 鸿蒙端只读参考（**不修改**） |
