# 坑位

> 名字 = 触发词 = 锚点，与 `AGENTS.md` §8 索引**必须同名**。
> 每条写清：**长什么样 → 为什么 → 怎么绕**。不看就改 = 重踩。

---

### 本地网络权限缺 NSLocalNetworkUsageDescription

**长什么样**：模拟器 / 首次真机点「连接」永远超时；或者权限弹窗只有一行空白说明。
**为什么**：iOS 14 起，访问 `192.168.x.x`、`10.x`、`*.local` 会触发本地网络隐私授权；
Info.plist 没有用途说明时系统不会给出可读文案，且拒绝后**所有**本地连接都失败。
**怎么绕**：`ios/Runner/Info.plist` 里保留 `NSLocalNetworkUsageDescription`；
真机第一次连不上先看「设置 → 隐私与安全性 → 本地网络」里本 App 是否被关掉。
普通公网中继不触发这个权限，别拿它当「网络层坏了」的通用解释。

### ATS 拦住明文 HTTP

**长什么样**：`SocketException` 或 `-1022`（`App Transport Security has blocked a cleartext HTTP`）。
**为什么**：ATS 默认只允许 https。家里电脑的 DSH 通常监听 `3090` 且没有证书。
**怎么绕**：Info.plist 只开 `NSAppTransportSecurity.NSAllowsLocalNetworking = true`（放行本地网络），
**不**开 `NSAllowsArbitraryLoads` —— 那等于给所有域名开后门。
公网中继必须用 https；如果确实要用明文域名，只给那一个域加 `NSExceptionDomains`，别全局放开。

### 重新签名后钥匙串读不到

**长什么样**：覆盖安装后 App 起来了，但「已保存的电脑」是空的；重新配对又能用。
**为什么**：钥匙串条目的访问控制绑定签名身份 / entitlements（team + keychain access group）。
用爱思助手换证书重签后，旧条目读不到是**预期**的（系统按 `errSecMissingEntitlement` 处理）。
**怎么绕**：这是安全边界，不要试图绕过（把令牌挪回普通偏好等于自废武功）。
正确做法：重新配对；`docs/RELEASE.md` 的故障表里明确写了这一条。
提示文案在设置页「重新签名安装后，旧令牌可能读不到」。

### 免费证书 7 天到期

**长什么样**：第 8 天点开 App 直接闪退 / 提示无法验证 App。
**为什么**：免费 Apple ID 的个人团队描述文件有效期 7 天，最多 3 个自签 App。
**怎么绕**：到期前用同一 Apple ID 重签并**覆盖安装**（配对数据通常在）；或者买付费开发者账号（1 年）。
这是分发方式的固有约束，不是代码 bug —— 别在代码里加「证书续期」之类的假功能。

### Bundle ID 与描述文件不一致

**长什么样**：安装到一半报 `ApplicationVerificationFailed` / `A valid provisioning profile ... does not match`。
**为什么**：签名工具按描述文件的 App ID 校验；`PRODUCT_BUNDLE_IDENTIFIER` 改了但签名时没同步，
或者该 Bundle ID 已被别的 Apple ID 注册。
**怎么绕**：签名界面把 Bundle ID 改成与工程一致（`com.dsh.companion.ios`）或改成你自己的唯一值；
改 Bundle ID 要**四处同步**（见 `docs/RELEASE.md` §6）。

### 未签名 IPA 直接装必失败

**长什么样**：侧载工具报签名无效 / 装完闪退。
**为什么**：CI 产物是 `flutter build ios --no-codesign` 的裸 `Runner.app`，
里面既没有 `embedded.mobileprovision`，`Frameworks/*.framework` 也没被重签。
**怎么绕**：先签名再装。**不要**在 CI 里塞证书来「省一步」——
那会把签名身份复制到第三个地方（`decisions/ADR-0002`）。

### iOS 27 开发者模式没开

**长什么样**：装上了但点开立即退出，或者侧载工具提示设备不受信任。
**为什么**：iOS 16 起，非 App Store 渠道安装的 App 需要「开发者模式」；它需要重启一次才生效。
**怎么绕**：设置 → 隐私与安全性 → 开发者模式 → 打开 → 重启 → 解锁后确认。
装完若提示「不受信任的开发者」，再去 设置 → 通用 → VPN与设备管理 里信任证书。

### Xcode 与 Flutter 版本错配

**长什么样**：`flutter build ios` 报 `Xcode is too old` / 链接期找不到符号 / Swift 版本冲突。
**为什么**：Flutter 3.47 需要较新的 Xcode；GitHub 的 `macos-15` 镜像里 Xcode 版本会随时间滚动。
**怎么绕**：CI 里先打印 `xcodebuild -version`（workflow 已做）；本地失败先跑 `flutter doctor -v`。
升级 Xcode 与升级 Flutter **一次只动一个**，否则出问题分不清是谁的锅。

### Podfile 与 Swift Package Manager 混用

**长什么样**：CI 上 `flutter build ios` 走了 `pod install`，Xcode 阶段报
`The sandbox is not in sync with the Podfile.lock. Run 'pod install' or update your CocoaPods installation.`
**为什么**：Flutter 3.47 的 iOS 模板是 **SPM 工程**（`project.pbxproj` 里已经有
`FlutterGeneratedPluginSwiftPackage` 的 `XCLocalSwiftPackageReference`），
所有插件也都带 `Package.swift`。此时再放一个手写 `Podfile`，Flutter 会同时启用
CocoaPods 集成，两套依赖系统互相改 project / xcconfig，构建期必然对不上。
构建日志里会先给一句提示：
`All plugins found for ios are Swift Packages, but your project still has CocoaPods integration.`
**怎么绕**：**不要有 `ios/Podfile`**。CI 里显式 `flutter config --enable-swift-package-manager`，
并在构建前断言 `test ! -f ios/Podfile`。部署目标在 `project.pbxproj` 的
`IPHONEOS_DEPLOYMENT_TARGET` 里改（三处），不需要 Podfile。

### file_picker 13 的静态 API

**长什么样**：`The getter 'platform' isn't defined for the type 'FilePicker'`。
**为什么**：`file_picker` 13 把入口改成静态方法（`FilePicker.pickFile()` / `pickFiles()`），
旧的 `FilePicker.platform.pickFiles(...)` 已移除；返回的 `PlatformFile` 也不再直接给 `bytes`。
**怎么绕**：用 `await FilePicker.pickFile()`，再 `await file.readAsBytes()`（本仓库 `chat_screen.dart`）。
升级依赖时先看 CHANGELOG，别凭记忆写 API。

### TextScaler 双重缩放

**长什么样**：把应用内字号拖到 1.4，文字变成 2 倍甚至更大。
**为什么**：`MediaQuery` 的系统字号已经乘了一次；如果直接用 `textScaler: TextScaler.linear(scale)`，
会把系统值覆盖掉而不是叠加，或在两处各乘一次。
**怎么绕**：只在一处生效：`systemScale * appScale`，且 `fontFollowsSystem = true` 时 `appScale = 1`。
见 `app.dart` 的 `builder` 与 `small_parts.dart` 的 `effectiveFontScale`。

### 键盘顶起输入区

**长什么样**：键盘弹出后输入框被遮住，或者整个页面被顶飞。
**为什么**：iOS 的键盘避让由 `Scaffold.resizeToAvoidBottomInset` 与 `SafeArea` 共同决定；
聊天页用 `Expanded` 列表 + 底部输入区时，任何一层自己再包 `SafeArea(bottom: true)` 都会重复避让。
**怎么绕**：整页一个 `Scaffold`，输入区用 `SafeArea(top: false)`；列表靠 `Expanded` 自适应。
真机上必须逐档键盘高度看一遍（含中文输入法的候选栏）。

### 后台 WebSocket 被系统挂起

**长什么样**：App 切后台 2 分钟后回来，消息停在旧位置，直到手动刷新。
**为什么**：iOS 会挂起后台进程，socket 被断开且不会通知；重连后的「订阅之后」才有事件。
**怎么绕**：`AppLifecycleState.paused` 时 `pauseEvents()` 主动关流，`resumed` 时 `resumeEvents()`
重开并**显式重取**历史 / 审批 / 问答 / 命令 —— 不能假设断线期间的事件会被补发。

### 滚动跟随抢走位置

**长什么样**：用户上翻看历史，新消息一来就被拽回底部。
**为什么**：把「有新项」直接等同于「滚到底」，忽略了用户正在阅读。
**怎么绕**：只在「距底部 < 80px」时才自动跟随（`chat_screen.dart` 的 `_nearBottom`）；
用户上翻后新消息只更新列表，不抢位置。

### PATCH 经代理被改写

**长什么样**：重命名会话 / 移动文件 / 开关插件在局域网直连时正常，走某些网关或中继时 405。
**为什么**：部分反代 / CDN 默认不放行 PATCH，或把它改写成 POST。
**怎么绕**：客户端无法绕 —— 这是中继配置问题。诊断顺序：先直连 3090 排除客户端，
再查中继的 `Access-Control-Allow-Methods` 与转发规则。错误会以 `HTTP 405` 出现，不是超时。

### 响应头键必须小写

**长什么样**：`ETag` 永远取不到 → 每次保存都当成「新建文件」→ 覆盖别人改动。
**为什么**：不同 HTTP 实现对响应头大小写的处理不一致；如果取值处用 `headers['ETag']`，
换个平台就静默失效。
**怎么绕**：平台层把**所有**响应头键转小写，逻辑层用 `HttpResponse.header('ETag')`
（内部 `toLowerCase`）。测试 `dsh_client_test.dart` 里有一条专门钉住这个行为。

### SecretBox 是异步的

**长什么样**：为了让 `HostStore` 保持同步接口，给 `encrypt` 加 `.then` 或阻塞等待，结果读到半份数据。
**为什么**：iOS 钥匙串 API 本身异步；把异步硬拗成同步只能靠轮询或阻塞，二者都会在启动路径上卡住 UI。
**怎么绕**：`SecretBox` 接口声明为 `Future`，`HostStore.loadHosts/saveHosts` 也是 `Future`；
其余纯逻辑（upsert / markPreferred / remove）保持同步，单测里用内存实现。

### 空体请求补 {}

**长什么样**：取消运行、归档会话、恢复回收站返回 400 / 415。
**为什么**：服务端的 JSON 解析器要求 `Content-Type: application/json` 且有 body；
零长度 body 会让它直接拒绝。
**怎么绕**：`DshClient` 里所有 `_postUnit` 调用点传 `'{}'`；GET 一律 `body: null`
（带 body 的 GET 会被某些代理拒绝或缓存错）。

### 附件 id 含冒号

**长什么样**：历史图片 404，且服务端日志里路径变成两段。
**为什么**：`attachmentId` 形如 `sha256:<hex>`，冒号在路径里必须编码成 `%3A`；
服务端按 `decodeURIComponent` 还原。不编码会被当成 scheme 或路径分隔。
**怎么绕**：路径段一律 `Uri.encodeComponent`（`_pathUrl`），查询参数也编码；
测试 `dsh_client_test.dart` 有 `sha256%3Aaa` 的断言。

### 分页游标不能当历史 seq

**长什么样**：往上翻历史时重复拉同一页，或者「加载更早」一直转圈。
**为什么**：`beforeSeq` 要的是**本地最小 seq**，而 `nextCursor` 是目录分页游标，
两者不是同一个序列。混用会让服务端每次返回同一段。
**怎么绕**：历史用 `chat/sessions/{id}/messages?beforeSeq=<本地最小 seq>`（`loadOlder`）；
文件目录才用 `nextCursor`。合并后按 seq 去重排序。

### 归档能力位未知 ≠ 缺失

**长什么样**：老插件明明没有归档接口，界面却显示「已归档：0 条」，用户以为归档全丢了。
**为什么**：老 bridge 会**忽略** `archived=true` 并返回未归档列表 —— 照显示就是假结论。
**怎么绕**：入口按能力位 `session-archive-list-v1` 守卫；能力清单读不到时视为**未知**，
一律不显示入口、不降级（`small_parts.dart` 的 `supportsArchiveListing`）。
「未知」与「空清单」必须分开：空清单也只当未知（服务端不会声明「我一条能力都没有」）。

### 工具结果配不上 callId 就不显示

**长什么样**：用户说「工具明明跑了，客户端里没有输出」。
**为什么**：`tool/result` 的 callId 藏在 `data.message.toolCallId`，退路是
`data.message.source.callId`；配对要跨事件。早先只认一个字段，内核换了字段就整类丢失。
**怎么绕**：两个都读，两个都没有就**整条不显示**（宁可少一行，不编一行）；
合并工具行时把每一条 `ToolCallDetail` 都留着，详情视图逐条展开。

### 围栏未闭合不切卡片

**长什么样**：流式输出到一半，`dsh-ui` 卡片区域闪一下就消失，或者变成半截 JSON 代码块。
**为什么**：模型逐字输出围栏。开头 ` ```dsh-ui ` 已经到了、结尾 ` ``` ` 还没到；此时切出去
只能拿到半截 JSON，解析必然失败。
**怎么绕**：`splitMessageBody` 找不到闭合围栏时**整段按原文返回**（`core/gen_ui.dart`）；
等闭合了再切。退化行为是「显示原始代码块」，比「卡片凭空消失 / 闪烁」诚实。

### dsh-ui 标记必须整词

**长什么样**：网页版能渲染的卡片，App 里是一个 JSON 代码块。
**为什么**：模型写围栏的方式不统一，` ```dsh-ui ` 与 ` ```json dsh-ui ` 都合法。
只匹配精确前缀会漏掉后一种；反过来，` ```dsh-ui-bad ` 又不该被认成卡片（否则会吞掉别的语言名）。
**怎么绕**：判据是「围栏标记按空白切开后**含有一个恰好等于 `dsh-ui` 的整词**」，
不是 `indexOf('dsh-ui')`，也不是前缀匹配。

### 未知组件不画空壳

**长什么样**：界面上出现一个空白圆角框，点它没反应。
**为什么**：`dsh-ui` 的组件词表有 40 多种，App 只实现了 21 种。把不认识的类型画成一个空容器，
用户只会以为界面坏了。
**怎么绕**：`genUiSupportedTypes` 之外的类型**整条跳过**；整份 spec 坏掉时回落展示原始 JSON。
少一个组件是「没有」，空壳是「坏了」。

### 导出走 Documents 而不是相册

**长什么样**：用户点「保存图片」，以为会在相册里，结果在「文件」App 里。
**为什么**：写相册要 `PHPhotoLibrary` + 相册写入用途说明 + 权限被拒的降级路径；
为了一个次要动作引一套原生权限，收益不抵风险。
**怎么绕**：统一导出到 `Documents/Exports`，并在 Info.plist 开 `UIFileSharingEnabled` /
`LSSupportsOpeningDocumentsInPlace`，让它在「文件 → 我的 iPhone → DSH 伴侣 → Exports」里可见。
提示文案必须写清落在哪，否则用户会一直翻相册。

### @ 补全用绝对路径

**长什么样**：`@` 选完文件，消息发出去，模型说「找不到这个文件」。
**为什么**：列举接口给的是**相对授权根**的路径，而内核要的是绝对路径；相对路径会让模型
先猜「相对于谁」，猜错就是一次无效工具调用。
**怎么绕**：把条目路径里的 `cwdRelative` 前缀换成 `cwdAbsolute`（`core/mention_query.dart`
的 `absolutePath`）。两种降级都返回相对路径而不是硬拼一个错的绝对路径：
老服务端不给 `cwdAbsolute`，或条目竟然不在 cwd 之下。

### 斜杠命令不当消息发

**长什么样**：用户输入 `/compact` 点发送，聊天里多了一条内容为 `/compact` 的普通消息，
命令没执行。
**为什么**：发送按钮只有一条路径（发消息）；命令是**服务端语法**，要走
`POST .../commands`，而不是 `POST .../messages`。
**怎么绕**：输入以 `/` 开头且没有附件时走 `executeCommand`（`chat_screen.dart` 的 `_send`）；
同时保留 `/` 前缀候选面板（整行、无空白才出）。

### Markdown 表格在横向滚动里被压成竖排

**长什么样**：表格每一格只剩一个字符宽，整张表变成一列竖排文字（真机截图里就是“值 / W / 4 / d / 0 …”）。
**为什么**：`Table` 的 `FlexColumnWidth` 需要一个**有界**宽度；把它放进横向 `SingleChildScrollView`
后约束变成无界，列宽被算成接近 0，文字只能逐字换行。
**怎么绕**：用 `LayoutBuilder` 拿可用宽度，自己算固定列宽（不低于 96vp），
再用 `SizedBox(width: 列宽 × 列数)` 包住 `Table`，横向滚动只负责“装不下时能滑”。
GenUI 的 `table` 节点同理（`genUiTableColumnWidth` 已有下限）。

### 助手消息里的 image 块被丢弃

**长什么样**：用户自己发的图能预览，**模型回复的图看不到**；PC 端点一下能出预览，手机端点没反应。
**为什么**：`assistantItems` 只处理 `text` / `reasoning` 两类内容块，`{type:"image",attachment:{…}}`
落到兜底分支被整类丢掉；而用户消息走的是 `contentAttachments`，所以只有“发出去的图”能显示。
**怎么绕**：助手消息解析时同样收集 `image` 块与 `[Image: source: …]` 交接标记，
挂到对应显示项上；正文里的本地路径链接交给 ViewModel 的 `openChatPath`（resolvePath + 预览），
不要丢给 `url_launcher`（它只会打开一个空白页）。

### WS 经中继被拒时界面像在线但不动

**长什么样**：会话列表能刷出来、发消息有回，但设置页一直「离线」；新消息不自己出现，要退出重进。
**为什么**：REST 走的是普通 HTTPS，WS 要经过网关的 Upgrade。部分中继会把带
`Accept: application/json` 的握手当普通 GET 处理（406/400），于是事件流永远连不上；
而界面只在 WS `onOpen` 时才显示在线——REST 通、WS 不通时看起来就是“在线却显示离线”。
**怎么绕**：① 握手只带 `Authorization` 与 `Accept-Language`；② 设置页显示 WS 掉线原因；
③ WS 未连上时用 5s 轮询兜底补历史与审批，避免“消息永远不动”。

### file_picker 只能选文件，不是相册

**长什么样**：点聊天框的「+」，弹出的是「文件」App，没有照片图库。
**为什么**：`file_picker` 在 iOS 上走的是 `UIDocumentPicker`；相册需要 `PHPicker`
（`image_picker`），两者不是同一个系统面板。
**怎么绕**：附件入口给两个来源：「从图库选择」走 `image_picker`（PHPicker 不需要相册写入权限），
「从文件选择」走 `file_picker`。不要试图用 `FileType.image` 让文件选择器去翻相册。

### dart:io WebSocket 不认 https

**长什么样**：设置页一直离线，显示 `WS: WebSocketException: Unsupported URL scheme 'https'`；
REST 一切正常（会话能刷、能发指令）。
**为什么**：服务端契约要求「同源 http(s) URL，由底层做协议升级」——那是 OkHttp / 鸿蒙的口径。
Dart 的 `dart:io WebSocket` 在握手前就检查 scheme，只接受 `ws` / `wss`，
`https` 直接抛异常，连尝试升级的机会都没有。
**怎么绕**：在**平台层入口**做一次换算（`core/socket_url.dart` 的 `socketUrlOf`：
`http→ws`、`https→wss`），core 继续只产出同源地址。不要把换算散到各个调用点。

### 权限目录只有两项

**长什么样**：会话里的权限只有「工作区内修改」「完全权限」两个 chip，没有「只读」「自动审查」，
而且当前是 `auto` 时一个都不高亮。
**为什么**：`/chat/permission-presets` 只返回 workspace-write 与 danger-full-access，
但 `/permission <preset>` 实际支持 `read-only` 与 `auto`；当前值又来自会话投影，
目录里的 `currentValue` 不一定同步。
**怎么绕**：内置四档 + 目录里多出的值追加；当前值**优先取投影**
（`projections.values.permissions.currentValue`），切换后重拉历史让投影跟上。

### 相册保存要 NSPhotoLibraryAddUsageDescription

**长什么样**：点「保存到相册」没反应，或第一次就报权限错误。
**为什么**：写相册属于「添加」权限，iOS 要求 Info.plist 里有专门的
`NSPhotoLibraryAddUsageDescription`（不是读取用的那条）；缺了会直接失败。
**怎么绕**：补这条说明；用 `gal` 的 `hasAccess(toAlbum: true)` / `requestAccess(...)`，
只申请添加权限，不申请读取整库。

### Dialog 放大图片会把按钮挤出屏幕

**长什么样**：点开会话里的图，图片本身正常；双指放大后**没有关闭/保存按钮**，只能杀进程退出。
**为什么**：`showDialog` + `Column(mainAxisSize: min)` 里的 `InteractiveViewer` 没有高度约束，
图片按原始比例撑开，底部的操作行被顶到屏幕外；`Dialog` 又不会滚动，按钮等于不存在。
**怎么绕**：图片查看用**全屏路由**（`ui/image_viewer.dart`）：
`AppBar` 左上角固定关闭按钮，图片在 `Expanded` + `InteractiveViewer` 里，
底部 `bottomNavigationBar` 固定操作条。Dialog 只适合“小、且不会长高”的内容。

