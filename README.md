# dsh-remote-ipa — DSH 伴侣 iOS 版

DeepSeek Harness 的 **iOS 原生客户端**（Flutter）。配合电脑上的 `dsh-remote-bridge` 插件使用：
在手机上连到你自己的电脑，看会话、发消息、批准工具调用、浏览工作区文件、管理插件与模型。

- **聊天 / Markdown / 表格 / 代码块全部原生渲染**，不使用 WebView。
- **GitHub Actions 出未签名 IPA**，用爱思助手签名后 iLoader 侧载到 iPhone（iOS 15+，含 iOS 27）。
- 令牌只进 **iOS 钥匙串**；仓库里没有证书、描述文件或任何密码。

---

## 目录

| 路径 | 内容 |
|---|---|
| `app/` | Flutter 工程（iOS only）：`lib/` 四层、`test/` 121 用例、`ios/` 工程配置 |
| `.github/workflows/ios-ipa.yml` | 唯一构建入口：macOS runner → analyze / test → 未签名 IPA |
| `tools/package_ipa.sh` | 本机（macOS）打包未签名 IPA |
| `tools/make_app_icons.py` | 由一张 1024 母图生成整套 AppIcon |
| `docs/` | 状态、发布、对等矩阵、协议契约、坑位、测试、债务、ADR |
| `harmony-reference/` | 鸿蒙 ArkTS 版只读快照（行为口径以它为准） |
| `AGENTS.md` | 工程宪法：命令、契约、铁律、坑位索引 |

---

## 快速开始

```bash
cd app
flutter pub get
flutter analyze --no-fatal-infos
flutter test
```

出包（**必须在 macOS 上**；Windows 版 Flutter 不注册 `ios` 子命令）：

```bash
bash tools/build_ios.sh 0.2.0 2    # analyze + test + build + 打包，一条命令
```

然后在 Windows 上用 **爱思助手 → 工具箱 → IPA 签名**（登录自己的 Apple ID），
再用 **iLoader** 装到手机。完整步骤、故障表、7 天到期与重新配对的说明见
[`docs/RELEASE.md`](docs/RELEASE.md)。

首次启动要允许两件事：**本地网络**（连 `192.168.x.x:3090`）与**照片**（选附件）。
iOS 27 首次侧载还需要打开「设置 → 隐私与安全性 → 开发者模式」并重启。

---

## 状态

`flutter analyze` 0 issue、`flutter test` 175 用例全绿；**尚未在 macOS 上出过 IPA，也未上机**。
四态表与待验清单见 [`docs/STATUS.md`](docs/STATUS.md) 与 [`docs/PARITY.md`](docs/PARITY.md) §6。

| 能力 | 状态 |
|---|---|
| 连接（多主机 / 选路 / 配对 / 配置导入） | 已实现 |
| 会话（新建 / 重命名 / 分叉 / 归档） | 已实现 |
| 聊天（流式、Markdown、GenUI 卡片、工具、审批、问答、图片） | 已实现 |
| `@` 文件补全 / `/` 命令补全 | 已实现 |
| 文件（浏览 / 预览 / 编辑保存 / 上传 / 回收站 / 导出） | 已实现 |
| 插件 / 模型（含供应商编辑）/ 设置 | 已实现 |
| 执行轨迹 / 统计 / 待办 / 交付物 | 已实现 |
| 图片存相册、会话列表行内摘要 | 未实现（差异见 PARITY §5） |

---

## 与鸿蒙版的关系

`harmony-reference/harmony-app` 是 ArkTS / ArkUI 的参考实现，**只读、不修改**。
移植映射、协议契约与有意差异见 [`docs/PORT-MAP.md`](docs/PORT-MAP.md)；
能力对照表见 [`docs/PARITY.md`](docs/PARITY.md)。

---

## 环境说明

- Flutter **3.47.8** / Dart **3.13.7**（与 CI 的 `FLUTTER_VERSION` 一致）。
- 版本 `0.2.0+2`；Bundle ID `com.dsh.companion.ios`；部署目标 iOS 15.0。
- 本机若没有 Flutter：`_toolchain/flutter` 是生成本仓库时下载的 SDK（已被 `.gitignore` 忽略），
  加到 `PATH` 即可复现 analyze/test；iOS 构建仍然只能在 macOS 上做。
