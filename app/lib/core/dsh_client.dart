/// DSH 服务端客户端 —— 移植自鸿蒙版 `core/DshClient.ts`（对应上游 Kotlin `data/DshClient.kt`）。
///
/// 分层原则（本文件最重要的设计决定）：**逻辑层不碰任何平台 API**。
/// 于是抽出三个注入点：
/// - [HttpTransport]：一次请求 → 一次响应；
/// - [WebSocketTransport] + [TimerBridge]：长连接与「延迟重连」的定时能力；
/// - [DshClientDeps]：id / 时区 / 语言。
///
/// 逻辑层只负责 URL 拼装、鉴权头、错误映射、WS 退避，以及把 JSON 解成模型。
///
/// 契约要点：
/// - 端点全部挂在基地址根上，**不带任何前缀**（基地址已含 `/api/v1`）；
/// - 超时：连接 15s / 读 45s；
/// - WS 请求 URL 用**同源 http(s)**，由底层做协议升级，不要提前改写 `ws://`；
/// - WS 重连退避 `min(1<<retries, 30)` 秒；重连后状态恢复始终靠 REST；
/// - GET 绝不带 body；POST/PUT/PATCH 的零长度体补 `{}`。
library;

import 'dart:async';
import 'dart:convert';

import 'endpoint_url.dart';
import 'json.dart';
import 'models.dart';

/// 连接超时（与上游 OkHttp 一致）。
const int connectTimeoutMs = 15000;

/// 读超时。
const int readTimeoutMs = 45000;

/// WebSocket 心跳间隔。
const int wsPingIntervalMs = 20000;

/// WS 退避上限（秒）。
const int wsMaxBackoffSeconds = 30;

/// 界面语言兜底（从未设置过时按中文，那是插件原本的口径）。
const String defaultLanguageTag = 'zh-CN';

/// 「这个路径打不开」的权威错误码集合 —— 都属于正常结果，不是故障。
///
/// 刻意**不含** `ROUTE_NOT_FOUND`：那表示服务端没有这个端点（插件版本过旧），
/// 把它当成「不在授权根内」会把用户引向错误的方向。
const List<String> unresolvableCodes = <String>[
  'PATH_OUTSIDE_ROOTS',
  'PATH_NOT_ABSOLUTE',
  'PATH_NOT_FILE',
  'PATH_NOT_FOUND',
];

bool isUnresolvableCode(String code) => unresolvableCodes.contains(code);

// ---------------------------------------------------------------------------
// 注入点
// ---------------------------------------------------------------------------

class HttpRequest {
  HttpRequest({
    required this.method,
    required this.url,
    this.headers = const <String, String>{},
    this.body,
    this.connectTimeoutMs = defaultConnectTimeoutMs,
    this.readTimeoutMs = defaultReadTimeoutMs,
  });

  final String method;
  final String url;
  final Map<String, String> headers;

  /// GET 必须为 null；其余方法零长度体给 `{}` 的字节。
  final List<int>? body;
  final int connectTimeoutMs;
  final int readTimeoutMs;
}

/// 默认超时（常量与参数同名会触发「初始化器里访问实例成员」的错误，故另起名字）。
const int defaultConnectTimeoutMs = 15000;
const int defaultReadTimeoutMs = 45000;

class HttpResponse {
  HttpResponse({required this.status, required this.headers, required this.body});

  final int status;

  /// 键必须是小写（平台层负责转小写）。
  final Map<String, String> headers;
  final List<int> body;

  bool get isSuccessful => status >= 200 && status < 300;

  String? header(String name) => headers[name.toLowerCase()];

  String text() => utf8.decode(body, allowMalformed: true);
}

abstract class HttpTransport {
  Future<HttpResponse> request(HttpRequest request);
}

class WebSocketCallbacks {
  const WebSocketCallbacks({required this.onOpen, required this.onMessage, required this.onDown});

  final void Function() onOpen;
  final void Function(String text) onMessage;

  /// 关闭或失败时**恰好调用一次**。
  final void Function(String reason) onDown;
}

abstract class EventSocketHandle {
  void close();
}

/// 平台 WS 实现：给定**同源 http(s) URL** 与握手头，打开长连接。
abstract class WebSocketTransport {
  EventSocketHandle open(String url, Map<String, String> headers, WebSocketCallbacks callbacks);
}

/// 延迟执行能力，供 WS 退避使用。
abstract class TimerBridge {
  int schedule(int delayMs, void Function() action);

  void cancel(int handle);
}

class DshClientDeps {
  const DshClientDeps({
    required this.newId,
    required this.timeZoneId,
    required this.languageTag,
    this.socket,
    this.timers,
  });

  final String Function() newId;
  final String Function() timeZoneId;
  final String Function() languageTag;
  final WebSocketTransport? socket;
  final TimerBridge? timers;
}

// ---------------------------------------------------------------------------
// 事件通道
// ---------------------------------------------------------------------------

/// 长连接事件通道。重连后状态恢复始终靠 REST —— 这里只负责送帧与报掉线。
class EventsChannel {
  EventsChannel({
    required this.url,
    required this.headers,
    required this.socket,
    required this.timers,
    required this.listener,
    required this.connectionListener,
  });

  final String url;
  final Map<String, String> headers;
  final WebSocketTransport socket;
  final TimerBridge timers;
  final void Function(WorkspaceEvent event) listener;
  final void Function(bool open) connectionListener;

  bool _closed = false;
  int _retries = 0;
  EventSocketHandle? _handle;
  int _timerHandle = -1;

  void start() => _connect();

  void _connect() {
    if (_closed) {
      return;
    }
    // 每次连接尝试独立一个终态标记：同一次尝试里 onDown 只处理一次
    // （平台层可能先报 error 再报 close）。
    var terminal = false;
    _handle = socket.open(url, headers, WebSocketCallbacks(
      onOpen: () {
        _retries = 0;
        connectionListener(true);
      },
      onMessage: (text) {
        final event = WorkspaceEvent.fromJsonText(text);
        if (event != null) {
          listener(event);
        }
      },
      onDown: (reason) {
        if (terminal) {
          return;
        }
        terminal = true;
        if (_closed) {
          return;
        }
        connectionListener(false);
        final delaySeconds = (1 << (_retries > 5 ? 5 : _retries)).clamp(1, wsMaxBackoffSeconds);
        _retries += 1;
        _timerHandle = timers.schedule(delaySeconds * 1000, _connect);
      },
    ));
  }

  void close() {
    _closed = true;
    connectionListener(false);
    if (_timerHandle >= 0) {
      timers.cancel(_timerHandle);
      _timerHandle = -1;
    }
    _handle?.close();
    _handle = null;
  }
}

// ---------------------------------------------------------------------------
// 客户端
// ---------------------------------------------------------------------------

class DshClient {
  DshClient({
    required String endpoint,
    required this.token,
    required this.http,
    required this.deps,
  }) : endpoint = normalizeEndpoint(endpoint);

  /// 归一化后的端点（含 `/api/v1`，无尾斜杠）。
  final String endpoint;

  /// 设备令牌。可为 null（配对前）。
  final String? token;

  final HttpTransport http;
  final DshClientDeps deps;

  String get _base => '$endpoint/';

  // --- 健康检查 / 配对 / 设备 -----------------------------------------------

  Future<HealthView> health() async =>
      HealthView.fromJson(await _getJson('healthz', authenticated: false));

  Future<PairingResult> pair(String code, String deviceName) async {
    final body = encodeJson(<String, dynamic>{
      'code': code.trim(),
      'deviceName': deviceName.trim(),
    });
    return PairingResult.fromJson(await _postJson('pairings/exchange', body, authenticated: false));
  }

  Future<DeviceView> currentDevice() async =>
      DeviceView.fromJson(await _getJson('devices/self', authenticated: true));

  // --- 根 / 文件 ------------------------------------------------------------

  Future<List<RootView>> roots() async {
    final map = await _getJson('roots', authenticated: true);
    return [for (final item in objArr(map, 'items')) RootView.fromJson(item)];
  }

  Future<DirectoryPage> entries(String rootId, {String path = '', String? cursor}) async {
    var url = _pathUrl(<String>['roots', rootId, 'entries']);
    url += '?path=${Uri.encodeComponent(path)}';
    if (cursor != null) {
      url += '&cursor=${Uri.encodeComponent(cursor)}';
    }
    return DirectoryPage.fromJson(await _getJsonUrl(url, authenticated: true));
  }

  Future<FileContent> readFile(String rootId, String path) async {
    final url = '${_pathUrl(<String>['roots', rootId, 'content'])}?path=${Uri.encodeComponent(path)}';
    final res = await _send('GET', url, null, _authHeaders());
    _ensureSuccess(res);
    return FileContent(
      bytes: res.body,
      etag: res.header('ETag') ?? '',
      contentType: res.header('Content-Type'),
    );
  }

  Future<String> writeFile(String rootId, String path, List<int> bytes, {String? etag}) async {
    final url = '${_pathUrl(<String>['roots', rootId, 'content'])}?path=${Uri.encodeComponent(path)}';
    final headers = _authHeaders()..['Content-Type'] = 'application/octet-stream';
    if (etag == null) {
      headers['If-None-Match'] = '*';
    } else {
      headers['If-Match'] = etag;
    }
    final res = await _send('PUT', url, bytes, headers);
    _ensureSuccess(res);
    return res.header('ETag') ?? '';
  }

  Future<void> createEntry(String rootId, String path, bool directory) async {
    final body = encodeJson(<String, dynamic>{
      'path': path,
      'kind': directory ? 'directory' : 'file',
    });
    await _postUnit(_pathUrl(<String>['roots', rootId, 'entries']), body);
  }

  Future<void> moveEntry(String rootId, String path, String destinationPath) async {
    final body = encodeJson(<String, dynamic>{'path': path, 'destinationPath': destinationPath});
    await _patchUnit(_pathUrl(<String>['roots', rootId, 'entries']), body);
  }

  Future<void> trashEntry(String rootId, String path) async {
    final url = '${_pathUrl(<String>['roots', rootId, 'entries'])}?path=${Uri.encodeComponent(path)}';
    final res = await _send('DELETE', url, null, _authHeaders());
    _ensureSuccess(res);
  }

  Future<List<TrashEntry>> trash() async {
    final map = await _getJson('trash', authenticated: true);
    return [for (final item in objArr(map, 'items')) TrashEntry.fromJson(item)];
  }

  Future<void> restoreTrash(String id) async {
    await _postUnit(_pathUrl(<String>['trash', id, 'restore']), '{}');
  }

  // --- 会话与工作区 ---------------------------------------------------------

  Future<List<ChatSession>> sessions({bool archived = false}) async {
    final path = archived ? 'chat/sessions?archived=true' : 'chat/sessions';
    final map = await _getJson(path, authenticated: true);
    return [for (final item in objArr(map, 'items')) ChatSession.fromJson(item)];
  }

  Future<List<ChatWorkspace>> chatWorkspaces() async {
    final map = await _getJson('chat/workspaces', authenticated: true);
    return [for (final item in objArr(map, 'items')) ChatWorkspace.fromJson(item)];
  }

  Future<ChatWorkspace> createChatWorkspace(String rootId, String path) async {
    final body = encodeJson(<String, dynamic>{'rootId': rootId, 'path': path});
    final map = await _postJson('chat/workspaces', body, authenticated: true);
    return ChatWorkspace.fromJson(obj(map, 'workspace'));
  }

  Future<ChatWorkspace> renameChatWorkspace(String workspaceId, String title) async {
    final body = encodeJson(<String, dynamic>{'title': title});
    final map = await _patchJson(_pathUrl(<String>['chat', 'workspaces', workspaceId]), body);
    return ChatWorkspace.fromJson(obj(map, 'workspace'));
  }

  Future<void> deleteChatWorkspace(String workspaceId) async {
    final res = await _send('DELETE', _pathUrl(<String>['chat', 'workspaces', workspaceId]), null,
        _authHeaders());
    _ensureSuccess(res);
  }

  Future<List<AgentPreset>> agentPresets() async {
    final map = await _getJson('chat/agent-presets', authenticated: true);
    return [for (final item in objArr(map, 'items')) AgentPreset.fromJson(item)];
  }

  Future<String> selectAgentPreset(String sessionId, String agentPreset) async {
    final body = encodeJson(<String, dynamic>{'agentPreset': agentPreset});
    final map = await _putJson(_pathUrl(<String>['chat', 'sessions', sessionId, 'agent-preset']), body);
    return stringOrNull(map, 'agentPreset') ?? '';
  }

  Future<SessionModels> sessionModels(String sessionId) async => SessionModels.fromJson(
      await _getJsonUrl(_pathUrl(<String>['chat', 'sessions', sessionId, 'models']),
          authenticated: true));

  Future<ModelSelection> selectModel(String sessionId, ModelSelection selection) async {
    final map = await _putJson(
        _pathUrl(<String>['chat', 'sessions', sessionId, 'model']), encodeJson(selection.toMap()));
    return ModelSelection.fromJson(obj(map, 'selected'));
  }

  /// 服务器绝对路径 → `rootId` + 相对路径。
  ///
  /// 返回 null 表示服务端**明确拒绝了这个路径**（正常结果，不是故障）；
  /// 其他 404/400 必须抛出去（插件版本过旧时该端点不存在）。
  Future<ResolvedPath?> resolvePath(String absolutePath) async {
    final url = '${_urlOf('roots/resolve')}?path=${Uri.encodeComponent(absolutePath)}';
    final res = await _send('GET', url, null, _authHeaders());
    if (res.isSuccessful) {
      return ResolvedPath.fromJson(parseMap(res.text()));
    }
    final code = _errorCodeOf(res);
    if (isUnresolvableCode(code)) {
      return null;
    }
    throw _apiError(res, code);
  }

  Future<CreatedSession> createSession(String workspaceId, {String? agentPreset}) async {
    final body = <String, dynamic>{
      'workspaceId': workspaceId,
      'clientRequestId': deps.newId(),
    };
    if (agentPreset != null) {
      body['agentPreset'] = agentPreset;
    }
    final map = await _postJson('chat/sessions', encodeJson(body), authenticated: true);
    return CreatedSession.fromJson(obj(map, 'session'));
  }

  Future<RenamedSession> renameSession(String sessionId, String title) async {
    final body = encodeJson(<String, dynamic>{'title': title});
    final map = await _patchJson(_pathUrl(<String>['chat', 'sessions', sessionId]), body);
    return RenamedSession.fromJson(map);
  }

  Future<String> forkSession(String sessionId, {int? atSeq}) async {
    final body = atSeq == null ? '{}' : encodeJson(<String, dynamic>{'atSeq': atSeq});
    final map = await _postJson(_pathUrl(<String>['chat', 'sessions', sessionId, 'fork']), body,
        authenticated: true);
    return stringOrNull(map, 'sessionId') ?? '';
  }

  Future<void> archiveSession(String sessionId) async {
    await _postUnit(_pathUrl(<String>['chat', 'sessions', sessionId, 'archive']), '{}');
  }

  Future<ChatHistory> history(String sessionId, {int? beforeSeq, int? maxMessages}) async {
    var url = _pathUrl(<String>['chat', 'sessions', sessionId, 'messages']);
    final query = <String>[
      if (beforeSeq != null) 'beforeSeq=$beforeSeq',
      if (maxMessages != null) 'maxMessages=$maxMessages',
    ];
    if (query.isNotEmpty) {
      url += '?${query.join('&')}';
    }
    return ChatHistory.fromJson(await _getJsonUrl(url, authenticated: true));
  }

  // --- 审批 -----------------------------------------------------------------

  /// 权限预设目录。投影只带 `currentValue`、**不带候选项**，所以菜单必须读这一份。
  Future<PermissionSelect> permissionPresets() async => PermissionSelect.fromJson(
      await _getJsonUrl(_pathUrl(<String>['chat', 'permission-presets']), authenticated: true));

  Future<List<PendingApproval>> pendingApprovals(String sessionId) async {
    final map = await _getJsonUrl(
        _pathUrl(<String>['chat', 'sessions', sessionId, 'approvals']),
        authenticated: true);
    return [for (final item in objArr(map, 'items')) PendingApproval.fromJson(item)];
  }

  Future<void> decideApproval(String sessionId, String approvalId, bool allowOnce) async {
    final body = encodeJson(<String, dynamic>{
      'outcome': allowOnce ? approvalOutcomeAllowedOnce : approvalOutcomeRejected,
    });
    await _postUnit(
      _pathUrl(<String>['chat', 'sessions', sessionId, 'approvals', approvalId, 'decision']),
      body,
    );
  }

  // --- 问答 -----------------------------------------------------------------

  /// 当前会话里待回答的问题。
  ///
  /// 服务端在这条路上会 `resolveAgent(..., resume)` —— 对**冷**会话调用会把 Agent 拉活，
  /// 所以只能传当前打开的那个会话，绝不能拿它遍历会话列表。
  Future<List<PendingQuestionSet>> pendingQuestions(String sessionId) async {
    final map = await _getJsonUrl(
        _pathUrl(<String>['chat', 'sessions', sessionId, 'questions']),
        authenticated: true);
    return [for (final item in objArr(map, 'items')) PendingQuestionSet.fromJson(item)];
  }

  Future<void> answerQuestions(String sessionId, String callId, List<QuestionAnswer> answers) async {
    final body = encodeJson(<String, dynamic>{
      'answers': [for (final a in answers) a.toMap()],
    });
    await _postUnit(
        _pathUrl(<String>['chat', 'sessions', sessionId, 'questions', callId, 'answer']), body);
  }

  // --- 命令 -----------------------------------------------------------------

  Future<List<CommandDescriptor>> sessionCommands(String sessionId) async {
    final map = await _getJsonUrl(
        _pathUrl(<String>['chat', 'sessions', sessionId, 'commands']),
        authenticated: true);
    return [for (final item in objArr(map, 'items')) CommandDescriptor.fromJson(item)];
  }

  Future<CommandExecution> executeCommand(String sessionId, String line) async {
    final body = encodeJson(<String, dynamic>{'line': line});
    final map = await _postJson(_pathUrl(<String>['chat', 'sessions', sessionId, 'commands']), body,
        authenticated: true);
    return CommandExecution.fromJson(obj(map, 'execution'));
  }

  // --- 发消息 / 附件 ---------------------------------------------------------

  /// 发一条消息。纯文本走旧的 `{"text":...}`，带附件才用 `{"content":[...]}`。
  Future<void> sendMessage(String sessionId, List<PromptPart> parts, {bool steer = false}) async {
    final body = messageBody(parts, steer ? sendModeSteerValue : sendModeQueueValue);
    await _postUnit(_pathUrl(<String>['chat', 'sessions', sessionId, 'messages']), body);
  }

  Future<void> sendText(String sessionId, String text, {bool steer = false}) =>
      sendMessage(sessionId, <PromptPart>[PromptPart.text(text)], steer: steer);

  /// 上传一个文件附件，换回消息里引用的 `receiptId`。
  Future<UploadedAttachment> uploadAttachment(
      String sessionId, List<int> bytes, String name) async {
    final body = encodeJson(<String, dynamic>{
      'name': name,
      'data': base64Encode(bytes),
    });
    final map = await _postJson(
        _pathUrl(<String>['chat', 'sessions', sessionId, 'attachments']), body,
        authenticated: true);
    return UploadedAttachment.fromJson(map);
  }

  Future<void> cancel(String sessionId) async {
    await _postUnit(_pathUrl(<String>['chat', 'runs', sessionId, 'cancel']), '{}');
  }

  /// 取回会话历史里某个图片附件的字节。
  ///
  /// `attachmentId` 形如 `sha256:<hex>`，**含冒号**；路径段编码后是 `sha256%3A…`，
  /// 这正是服务端 `decodeURIComponent` 期待的形式。必须带 `sessionId`。
  Future<List<int>> readAttachment(String sessionId, String attachmentId) async {
    final url =
        '${_pathUrl(<String>['attachments', attachmentId])}?sessionId=${Uri.encodeComponent(sessionId)}';
    final res = await _send('GET', url, null, _authHeaders());
    _ensureSuccess(res);
    return res.body;
  }

  // --- 设置：供应商 ---------------------------------------------------------

  Future<ProviderSettings> providerSettings() async =>
      ProviderSettings.fromJson(await _getJson('settings/providers', authenticated: true));

  Future<ProviderSettings> updateProvider(String providerId, ProviderPatch patch) async {
    final map = await _patchJson(
        _pathUrl(<String>['settings', 'providers', providerId]), patch.toJsonString());
    return ProviderSettings.fromJson(map);
  }

  Future<ProviderSettings> createCustomProvider(CustomProviderCreate provider) async {
    final map = await _postJson('settings/providers', provider.toJsonString(), authenticated: true);
    return ProviderSettings.fromJson(map);
  }

  Future<List<ProviderModel>> discoverModels(
    String providerId, {
    String? baseURL,
    String? api,
    String? apiKey,
  }) async {
    final payload = <String, dynamic>{};
    if (baseURL != null) {
      payload['baseURL'] = baseURL;
    }
    if (api != null) {
      payload['api'] = api;
    }
    if (apiKey != null) {
      payload['apiKey'] = apiKey;
    }
    final body = encodeJson(payload);
    final map = await _postJson(
        _pathUrl(<String>['settings', 'providers', providerId, 'discover']), body,
        authenticated: true);
    return [for (final item in objArr(map, 'models')) ProviderModel.fromJson(item)];
  }

  // --- 设置：插件 -----------------------------------------------------------

  Future<PluginInventory> pluginInventory() async =>
      PluginInventory.fromJson(await _getJson('settings/plugins', authenticated: true));

  /// 带版本检查地拉插件清单（慢：每个已装包一次 registry 请求，仅在用户主动查更新时走）。
  Future<PluginInventory> pluginInventoryWithUpdates() async => PluginInventory.fromJson(
      await _getJson('settings/plugins?checkUpdates=1', authenticated: true));

  Future<PluginToggleResult> setPluginLoaded(String name, bool loaded) async {
    final body = encodeJson(<String, dynamic>{'name': name, 'loaded': loaded});
    final map = await _patchJson(_pathUrl(<String>['settings', 'plugins']), body);
    return PluginToggleResult.fromJson(map);
  }

  // --- 事件流 ---------------------------------------------------------------

  /// 打开事件流。未注入 WS 时抛错（调用方应改为轮询）。
  EventsChannel events({
    required void Function(WorkspaceEvent event) listener,
    required void Function(bool open) connection,
  }) {
    final socket = deps.socket;
    final timers = deps.timers;
    if (socket == null || timers == null) {
      throw StateError('DshClient: 未注入 WebSocketTransport/TimerBridge，无法打开事件流');
    }
    final channel = EventsChannel(
      url: eventsUrl,
      headers: _authHeaders(),
      socket: socket,
      timers: timers,
      listener: listener,
      connectionListener: connection,
    );
    channel.start();
    return channel;
  }

  /// WS 请求 URL：**同源 http(s)**，由底层做协议升级。
  String get eventsUrl => _urlOf('events');

  // --- 内部：URL / 头 / 错误 ------------------------------------------------

  String _urlOf(String relative) {
    // 有些调用点传的是拼好的完整 URL，有些传相对路径：完整 URL 不能再拼 base，
    // 否则会变成 `/api/v1/https://relay.../...`。
    if (relative.startsWith('http://') || relative.startsWith('https://')) {
      return relative;
    }
    return _base + relative;
  }

  String _pathUrl(List<String> segments) =>
      _base + segments.map(Uri.encodeComponent).join('/');

  Map<String, String> _authHeaders() {
    final token = this.token;
    if (token == null) {
      throw StateError('DshClient: 该请求需要鉴权，但未提供设备令牌');
    }
    return <String, String>{
      'Accept': 'application/json',
      'Authorization': 'Bearer $token',
      // 界面语言随每个请求出海：服务端的图片交接说明要说用户看得懂的语言。
      'Accept-Language': deps.languageTag(),
    };
  }

  Map<String, String> _jsonBodyHeaders({required bool authenticated}) {
    final headers = authenticated ? _authHeaders() : <String, String>{};
    headers['Content-Type'] = 'application/json';
    return headers;
  }

  Future<HttpResponse> _send(String method, String url, List<int>? body,
          Map<String, String> headers) =>
      http.request(HttpRequest(method: method, url: url, headers: headers, body: body));

  Future<Map<String, dynamic>?> _getJson(String relative, {required bool authenticated}) =>
      _getJsonUrl(_urlOf(relative), authenticated: authenticated);

  Future<Map<String, dynamic>?> _getJsonUrl(String url, {required bool authenticated}) async {
    final headers = authenticated ? _authHeaders() : <String, String>{};
    final res = await _send('GET', url, null, headers);
    _ensureSuccess(res);
    return parseMap(res.text());
  }

  Future<Map<String, dynamic>?> _postJson(String relative, String body,
      {required bool authenticated}) async {
    final res = await _send('POST', _urlOf(relative), utf8.encode(body),
        _jsonBodyHeaders(authenticated: authenticated));
    _ensureSuccess(res);
    return parseMap(res.text());
  }

  Future<Map<String, dynamic>?> _patchJson(String url, String body) async {
    final res = await _send('PATCH', url, utf8.encode(body), _jsonBodyHeaders(authenticated: true));
    _ensureSuccess(res);
    return parseMap(res.text());
  }

  Future<Map<String, dynamic>?> _putJson(String url, String body) async {
    final res = await _send('PUT', url, utf8.encode(body), _jsonBodyHeaders(authenticated: true));
    _ensureSuccess(res);
    return parseMap(res.text());
  }

  Future<void> _postUnit(String url, String body) async {
    final res = await _send('POST', url, utf8.encode(body), _jsonBodyHeaders(authenticated: true));
    _ensureSuccess(res);
  }

  Future<void> _patchUnit(String url, String body) async {
    final res = await _send('PATCH', url, utf8.encode(body), _jsonBodyHeaders(authenticated: true));
    _ensureSuccess(res);
  }

  String _errorCodeOf(HttpResponse res) {
    final error = obj(parseMap(res.text()), 'error');
    return stringOrNull(error, 'code') ?? 'HTTP_ERROR';
  }

  DshApiException _apiError(HttpResponse res, String code) {
    final error = obj(parseMap(res.text()), 'error');
    final message = stringOrNull(error, 'message') ?? 'HTTP ${res.status}';
    return DshApiException(res.status, code, message);
  }

  void _ensureSuccess(HttpResponse res) {
    if (res.isSuccessful) {
      return;
    }
    throw _apiError(res, _errorCodeOf(res));
  }
}

/// 发消息体：纯文本走旧的 `{"text":...}`，带附件才用 `content` 数组。
String messageBody(List<PromptPart> parts, String mode) {
  final onlyText = parts.length == 1 && parts.first.type == partTypeText;
  final payload = <String, dynamic>{
    if (onlyText) 'text': parts.first.text,
    if (!onlyText) 'content': [for (final part in parts) part.toMap()],
    'mode': mode,
  };
  return encodeJson(payload);
}

/// 线上 `mode` 取值（与 `ComposerSendPolicy` 的 `queue` / `steer` 一致）。
const String sendModeQueueValue = 'queue';
const String sendModeSteerValue = 'steer';
