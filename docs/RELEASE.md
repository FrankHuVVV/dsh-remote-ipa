# 发版：未签名 IPA → 爱思助手签名 → iLoader 侧载

> 目标形态：**GitHub Actions 只出未签名 IPA**，签名与装机全部在本机用你自己的 Apple ID 完成。
> 仓库里不存在任何证书、描述文件或密码。

---

## 0. 流水线一图

```
git tag v1.0.0 → push
        │
        ▼
GitHub Actions（macos-15）
  flutter analyze → flutter test → flutter build ios --no-codesign
        │
        ▼
DSHCompanion-1.0.0-<build>-unsigned.ipa  (artifact / Release 附件)
        │
        ▼
爱思助手（Windows）→ 工具箱 → IPA 签名（Apple ID 免费或开发者账号）
        │
        ▼
iLoader / 同类侧载工具 → 安装到 iPhone（iOS 27）
        │
        ▼
iPhone：设置 → 通用 → VPN与设备管理 → 信任该开发者
```

---

> 本工程是 **Swift Package Manager** 工程（Flutter 3.47 模板），**没有 Podfile**。
> 不要往 `ios/` 里加 Podfile —— 会和 SPM 混用，构建期报
> `sandbox is not in sync with the Podfile.lock`（见 `docs/PITFALLS.md`）。

## 1. 出包（二选一）

### 1.1 云端（推荐）

1. 打 tag 并推送（**需用户明确同意**）：

   ```bash
   git tag v1.0.0 && git push origin v1.0.0
   ```

2. Actions 里跑 `.github/workflows/ios-ipa.yml`，产物：
   - artifact `DSHCompanion-unsigned-ipa`（保留 30 天）；
   - tag 构建会额外挂到 GitHub Release 上。
3. 记下 `.ipa.sha256` —— 装完出问题时，它是「装的是不是这一版」的唯一凭证。

也可以手动触发 `workflow_dispatch`，`build_number` 留空则用 run number。

### 1.2 本机（macOS）

```bash
# 一条命令：pub get → analyze → test → build ios --no-codesign → 打包 IPA
bash tools/build_ios.sh 0.2.0 2
```

> **必须在 macOS 上执行**。Windows 版 Flutter 根本不注册 `ios` 子命令
> （`flutter build --help` 里只有 aar/apk/appbundle/bundle/web/windows），
> 本机也没有 `xcodebuild` / `pod`。在 Windows 上只能跑 analyze / test。
> 想拆开跑也可以：`cd app && flutter pub get && flutter analyze --no-fatal-infos && flutter test`
> 然后 `flutter build ios --release --no-codesign`，最后 `bash tools/package_ipa.sh 0.2.0 2`。

产物：`app/DSHCompanion-1.0.0-1-unsigned.ipa`。

> **未签名 IPA 不能直接装**。它的 `Payload/Runner.app` 里没有有效签名，
> iOS 会直接拒绝；必须经过第 2 步。

---

## 2. 用爱思助手签名

1. Windows 安装 [爱思助手](https://www.i4.cn/)（i4Tools），USB 连上 iPhone，确认「设备信息」能读到机型与 iOS 版本。
2. 工具箱 → **IPA 签名** → 选择第 1 步的 `DSHCompanion-*-unsigned.ipa`。
3. 登录 Apple ID：
   - **免费 Apple ID**：7 天有效、最多 3 个自签 App、每周要重签一次；
   - **付费开发者账号**：1 年有效，可长期使用。
4. 如提示 Bundle ID 冲突（`com.dsh.companion.ios` 已被别的 App 占用），在签名界面把它改成
   你自己的唯一值，例如 `com.yourname.dsh.companion`。
5. 签名完成后会得到 `*_signed.ipa`。

> 签名工具做的是：重签 `Runner.app`（含 Frameworks 里的每个动态库）→ 生成新的
> `embedded.mobileprovision` → 重新打包。**Bundle ID 必须与描述文件里的 App ID 一致**，
> 否则装到一半报 `ApplicationVerificationFailed`。

**不要**把签名后的 IPA 提交到仓库：它内含你的证书与设备 UDID 关联信息。

---

## 3. 侧载到 iPhone（iOS 27）

1. iPhone 打开 **设置 → 隐私与安全性 → 开发者模式**，打开后按提示重启，重启后再次确认开启。
   > iOS 16 起，非 App Store 安装的应用需要开发者模式；没开时表现为「装完闪退」或装不上。
2. 用 iLoader（或同类侧载工具）连接设备，选择第 2 步的 `*_signed.ipa` 安装。
3. 安装完成后首次启动若提示「不受信任的开发者」：
   **设置 → 通用 → VPN与设备管理 → 开发者 App → 信任**。
4. 打开 App → 连接页 → 粘贴 `DSH1:` 配置文本或输入一次性配对码。

### 首次启动必须允许的两件事

| 提示 | 为什么 | 不允许的后果 |
|---|---|---|
| **本地网络** | App 要连你电脑的 `192.168.x.x:3090` | 连接一直失败（表现为超时），日志里是网络不可达 |
| **照片（选择附件时）** | 选图作为消息附件 | 选图器直接报错 |

这两条在 `ios/Runner/Info.plist` 里都有用途说明（`NSLocalNetworkUsageDescription` /
`NSPhotoLibraryUsageDescription`），缺了会弹一段空说明甚至直接崩。

---

## 4. 常见故障

| 现象 | 最可能的原因 | 处理 |
|---|---|---|
| 签名报 `no profiles for 'com.dsh.companion.ios'` | Bundle ID 未在该 Apple ID 下注册 / 已被占用 | 在签名工具里改 Bundle ID 后重签 |
| 安装到 80% 失败 | 设备未开开发者模式 / 证书过期 / 免费账号 3 个 App 上限 | 开开发者模式、重新签名、先卸载旧的自签 App |
| 装好点开就闪退 | 证书未信任；或签名只签了主 App 没签 `Frameworks/*.framework` | 信任证书；用签名工具的「完整签名」选项 |
| 连接一直超时 | 不在同一网络 / 端口不是 3090 / 本地网络权限被拒 | 先用 Safari 打开 `http://<电脑IP>:3090/api/v1/healthz` 验证；检查「设置 → 隐私与安全性 → 本地网络」 |
| 连上了但看不到会话 | 设备令牌没有 `chat.read` scope | 在电脑上重新生成配对（带 chat.read）或换配置文本 |
| 装完原来的配对没了 | **重新签名后钥匙串条目可能读不到**（签名身份变了） | 重新配对；见 `docs/PITFALLS.md#重新签名后钥匙串读不到` |
| 7 天后打不开 | 免费证书到期 | 用同一 Apple ID 重新签名并覆盖安装（配对数据通常还在） |

---

## 5. 版本与产物记录（每次发版必须填）

| 版本 | 构建号 | commit | IPA SHA-256 | 签名方式 | 装机验证 |
|---|---|---|---|---|---|
| 0.1.0 | 1 | — | — | 未执行 | 未执行 |
| 0.2.1 | 3 | `e33b8ab` | `e0563badfd2cf1dcfa6788d3c1cb1ee3a6ec84ba9f28f061a7d6c68ba15366e2` | 未签名（CI 产物）；爱思助手签名待执行 | 已装机（6 项问题反馈） |
| 0.2.2 | 4 | `d75a748` | `127b4730c61e896c4cb6c7173b856882705f51ea8f374a1a38f892c2f453904f` | 未签名（CI 产物）；爱思助手签名待执行 | 待装机复验 |

---

## 6. 改名 / 换 Bundle ID

四处必须同时改，缺一处就会出现「装上了但打不开」或「配对数据丢失」：

1. `app/ios/Runner/Info.plist` → `CFBundleDisplayName`（桌面显示名）；
2. `app/ios/Runner.xcodeproj/project.pbxproj` → `PRODUCT_BUNDLE_IDENTIFIER`（3 处 Runner + 3 处 RunnerTests）；
3. 重新用 `tools/make_app_icons.py` 出图标（可选，仅换图形时）；
4. 签名时填同一个 Bundle ID，并在 `docs/STATUS.md` / 本文件记录。

Bundle ID 也是钥匙串条目的归属维度之一 —— 换 ID 等于换应用身份，旧配对读不到是**预期行为**。
