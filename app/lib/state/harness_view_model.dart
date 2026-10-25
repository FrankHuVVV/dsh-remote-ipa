/// 界面主状态机 —— 移植自鸿蒙版 `core/HarnessViewModel*.ts`（连接 / 会话 / 文件 / 设置四层合一）。
///
/// ## 分层纪律
///
/// ```
/// core/      纯逻辑（可单测）：MarkdownLite / ConnectionShare / ChatPresentation ...
/// state/     本文件：持有连接、会话、文件、设置，**唯一**调用 DshClient 的地方
/// ui/        只消费 state、调用本类动作；不自己发请求、不直读偏好当状态
/// ```
///
/// ## 两条不许简化的判据
///
/// 1. **连接成功 = 探活 + 设备信息 + 快照都到位**。探活成功只说明端口开着；
///    后面两步失败时必须把 `connecting` 复位干净，否则界面永远停在「正在探测地址…」。
/// 2. **事件流只报掉线，状态恢复一律靠 REST**。WS 是「订阅之后才收得到」，
///    断线窗口里的事件谁都管不着 —— 所以重连成功要显式重取历史、审批、问答、命令。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/app_preferences.dart';
import '../core/chat_presentation.dart';
import '../core/connection_models.dart';
import '../core/connection_share.dart';
import '../core/dsh_client.dart';
import '../core/endpoint_url.dart';
import '../core/error_messages.dart';
import '../core/host_store.dart';
import '../core/models.dart';
import '../core/small_parts.dart';
import '../l10n/strings.dart';
import '../core/mention_query.dart';
import '../platform/exports.dart';
import '../platform/platform_deps.dart';
import 'harness_state.dart';

part 'harness_chat_actions.dart';
part 'harness_files_actions.dart';

/// ViewModel 的外部依赖（全部可注入，单测里换成假的）。
class AppDeps {
  AppDeps({
    required this.hostStore,
    required this.prefs,
    required this.platform,
    required this.http,
    required this.socket,
    required this.timers,
  });

  final HostStore hostStore;
  final AppPreferences prefs;
  final PlatformDeps platform;
  final HttpTransport http;
  final WebSocketTransport socket;
  final TimerBridge timers;
}

class HarnessViewModel extends ChangeNotifier {
  HarnessViewModel(this.deps) {
    _applyPreferences();
  }

  final AppDeps deps;
  final HarnessState state = HarnessState();

  DshClient? _client;
  EventsChannel? _events;
  bool _eventsPaused = false;
  bool _closed = false;
  String _timeZoneId = 'UTC';
  Timer? _chatRefreshTimer;
  Timer? _sessionsRefreshTimer;
  bool _chatRefreshInFlight = false;
  bool _chatRefreshPending = false;
  int _sessionGeneration = 0;
  String? _lastFailureNotice;

  DshClient? get client => _client;

  /// 当前界面语言。
  Strings get strings => Strings.of(state.languageTag);

  // ---------------------------------------------------------------------------
  // 启动
  // ---------------------------------------------------------------------------

  Future<void> init() async {
    _timeZoneId = await deps.platform.timeZoneId();
    final hosts = await deps.hostStore.loadHosts();
    _update((s) {
      s.hosts = hosts;
      s.restoring = true;
    });
    if (hosts.isEmpty) {
      _update((s) => s.restoring = false);
      return;
    }
    // updatedAt 每次探活都会刷新，所以「最近活动过」近似等于「上次用过的」。
    var target = hosts.first;
    for (final host in hosts.skip(1)) {
      if (host.updatedAt > target.updatedAt) {
        target = host;
      }
    }
    _update((s) {
      s.selectedHostId = target.id;
      s.endpointDraft = target.endpoints.isEmpty ? '' : target.endpoints.first.baseUrl;
    });
    await _connectHostInternal(target);
  }

  void _applyPreferences() {
    final prefs = deps.prefs;
    _update((s) {
      s.busySendMode = prefs.busySendMode;
      s.showContext = prefs.showContext;
      s.fontScale = prefs.fontScale;
      s.fontFollowsSystem = prefs.fontFollowsSystem;
      s.themeMode = prefs.themeMode;
      s.languageTag = prefs.languageTag;
    });
  }

  // ---------------------------------------------------------------------------
  // 连接
  // ---------------------------------------------------------------------------

  void setEndpointDraft(String value) => _update((s) {
        s.endpointDraft = value;
        s.healthOk = false;
        s.error = null;
      });

  /// 只探活，不建立连接（用户点完还留在原页看结果）。
  Future<void> testConnection(String endpoint) async {
    await _launch(() async {
      final normalized = normalizeEndpoint(endpoint);
      final probe = await _probe(endpoint: normalized, endpointId: 'manual');
      if (!probe.ok) {
        throw StateError(probe.error ?? strings.get('no_reachable_endpoint'));
      }
      _update((s) {
        s.endpointDraft = stripApiSuffix(normalized);
        s.healthOk = true;
      });
    });
  }

  /// 用一次性配对码把一台电脑加进来并连接。
  Future<void> pair({
    required String endpoint,
    required String code,
    required String deviceName,
  }) async {
    await _launch(() async {
      if (code.trim().isEmpty) {
        throw StateError(strings.get('pairing_code_label'));
      }
      if (deviceName.trim().isEmpty) {
        throw StateError(strings.get('device_name_label'));
      }
      final anonymous = _makeClient(endpoint, null);
      await anonymous.health();
      final pairing = await anonymous.pair(code, deviceName);
      final host = _hostFromPairing(anonymous.endpoint, pairing.token, pairing.device, deviceName);
      await _saveHost(host);
      _update((s) => s.selectedHostId = host.id);
      await _connectHostInternal(host, device: pairing.device);
    });
  }

  /// 导入一段 `DSH1:` 配置文本，把一台电脑加进来并连接。
  Future<void> importConfiguration(String text) async {
    await _launch(() async {
      final payload = ConnectionShare.decode(text);
      if (payload == null) {
        throw StateError(strings.get('import_invalid'));
      }
      final host = ConnectionShare.buildHost(payload, idFactory: deps.platform.newId);
      await _saveHost(host);
      _update((s) => s.selectedHostId = host.id);
      await _connectHostInternal(host);
    });
  }

  Future<void> connectHost(String hostId) async {
    await _launch(() async {
      final host = _hostById(hostId);
      if (host == null) {
        return;
      }
      _update((s) => s.selectedHostId = hostId);
      await _connectHostInternal(host);
    });
  }

  Future<void> addEndpoint(String hostId, String label, String baseUrl) async {
    await _launch(() async {
      final host = _hostById(hostId);
      if (host == null) {
        return;
      }
      final normalized = stripApiSuffix(normalizeEndpoint(baseUrl));
      if (host.endpoints.any((e) => e.baseUrl == normalized)) {
        return;
      }
      final next = host.copy();
      next.endpoints = <Endpoint>[
        ...host.endpoints,
        Endpoint.create(label, normalized, 'ep-${deps.platform.newId()}'),
      ];
      next.updatedAt = DateTime.now().millisecondsSinceEpoch;
      await _saveHost(next);
    });
  }

  Future<void> removeEndpoint(String hostId, String endpointId) async {
    await _launch(() async {
      final host = _hostById(hostId);
      if (host == null) {
        return;
      }
      if (host.endpoints.length <= 1) {
        throw StateError(strings.get('last_endpoint'));
      }
      final next = host.copy();
      next.endpoints = <Endpoint>[
        for (final e in host.endpoints)
          if (e.id != endpointId) e,
      ];
      if (next.preferredEndpointId == endpointId) {
        next.preferredEndpointId = null;
      }
      next.updatedAt = DateTime.now().millisecondsSinceEpoch;
      await _saveHost(next);
    });
  }

  Future<void> renameHost(String hostId, String displayName) async {
    await _launch(() async {
      final host = _hostById(hostId);
      if (host == null) {
        return;
      }
      final next = host.copy();
      next.displayName = displayName.trim();
      next.updatedAt = DateTime.now().millisecondsSinceEpoch;
      await _saveHost(next);
    });
  }

  /// 删除一台电脑（含凭据）。与「断开」分开：断开只是断连，删除才抹掉令牌。
  Future<void> removeHost(String hostId) async {
    if (state.activeHostId == hostId) {
      disconnect();
    }
    final next = deps.hostStore.remove(state.hosts, hostId);
    await deps.hostStore.saveHosts(next);
    _update((s) {
      s.hosts = next;
      if (s.selectedHostId == hostId) {
        s.selectedHostId = null;
      }
    });
  }

  void selectHost(String? hostId) => _update((s) => s.selectedHostId = hostId);

  /// 断开当前连接。**不清除已保存的主机**：网络抖一下不该逼用户重新配对。
  void disconnect() {
    _events?.close();
    _events = null;
    _eventsPaused = false;
    _client = null;
    _chatRefreshTimer?.cancel();
    _sessionsRefreshTimer?.cancel();
    final next = HarnessState()
      ..restoring = false
      ..hosts = state.hosts
      ..languageTag = state.languageTag;
    _applyPreferencesTo(next);
    _copyInto(next);
    notifyListeners();
  }

  Future<void> _connectHostInternal(Host host, {DeviceView? device}) async {
    _update((s) {
      s.connecting = true;
      s.endpointProbes = <EndpointProbe>[];
      s.error = null;
    });

    final probes = await _probeAll(host);
    var recorded = host;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final probe in probes) {
      recorded = recorded.withEndpointProbe(probe.endpointId, probe.latencyMs, probe.error, now);
    }
    await _saveHost(recorded);

    final ranked = EndpointSelection.rank(probes, recorded.endpoints, recorded.preferredEndpointId);
    if (ranked.isEmpty) {
      _update((s) {
        s.connecting = false;
        s.restoring = false;
        s.endpointProbes = probes;
        s.error = strings.get('no_reachable_endpoint');
      });
      state.hosts = await deps.hostStore.loadHosts();
      notifyListeners();
      return;
    }

    final chosenProbe = ranked.first;
    final endpoint = recorded.endpoint(chosenProbe.endpointId)!;
    final client = _makeClient(endpoint.baseUrl, recorded.credential?.secret);

    try {
      final resolved = device ?? await client.currentDevice();
      await _loadSnapshot(client, resolved);
      _client = client;
      final preferredHosts = deps.hostStore.markPreferred(state.hosts, recorded.id, endpoint.id);
      await deps.hostStore.saveHosts(preferredHosts);
      _update((s) {
        s.roots = _snapshotRoots;
        s.sessions = _snapshotSessions;
        s.chatWorkspaces = _snapshotWorkspaces;
        s.agentPresets = _snapshotPresets;
        s.providerSettings = _snapshotProviders;
        s.pluginInventory = _snapshotPlugins;
        s.restoring = false;
        s.connecting = false;
        s.connected = true;
        s.healthOk = true;
        s.endpoint = client.endpoint;
        s.device = resolved;
        s.hosts = preferredHosts;
        s.activeHostId = recorded.id;
        s.activeEndpointId = endpoint.id;
        s.endpointProbes = probes;
        s.selectedRootId ??= s.roots.isEmpty ? null : s.roots.first.id;
        s.busy = false;
      });
    } on Object catch (error) {
      _client = null;
      _update((s) {
        s.restoring = false;
        s.connecting = false;
        s.connected = false;
        s.error = describeError(error, strings);
      });
      return;
    }

    _connectEvents(client);
  }

  Future<List<EndpointProbe>> _probeAll(Host host) async {
    final endpoints = host.activeEndpoints();
    final results = await Future.wait(<Future<EndpointProbe>>[
      for (final endpoint in endpoints) _probe(endpoint: endpoint.baseUrl, endpointId: endpoint.id),
    ]);
    return results;
  }

  /// 单个地址探活：`health()`（未鉴权），5 秒独立超时。
  Future<EndpointProbe> _probe({required String endpoint, required String endpointId}) async {
    final started = DateTime.now();
    try {
      final client = _makeClient(endpoint, null);
      await client.health().timeout(const Duration(milliseconds: 5000));
      final elapsed = DateTime.now().difference(started).inMilliseconds;
      return EndpointProbe.success(endpointId, elapsed);
    } on Object catch (error) {
      final reason = error is TimeoutException ? 'timeout after 5000ms' : describeError(error, strings);
      return EndpointProbe.failure(endpointId, reason);
    }
  }

  Host _hostFromPairing(String endpoint, String token, DeviceView device, String displayName) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final baseUrl = stripApiSuffix(normalizeEndpoint(endpoint));
    final hostId = 'host-${device.id}';
    Host? existing;
    for (final host in state.hosts) {
      if (host.id == hostId) {
        existing = host;
        break;
      }
    }
    final name = displayName.trim().isNotEmpty ? displayName.trim() : device.name;
    final issuedAt = (existing?.credential?.issuedAt ?? 0) > 0 ? existing!.credential!.issuedAt : now;
    return Host(
      id: hostId,
      displayName: name.isEmpty ? 'DSH' : name,
      endpoints: <Endpoint>[Endpoint.create(name, baseUrl, 'ep-paired')],
      preferredEndpointId: 'ep-paired',
      credential: Credential(
        kind: CredentialKind.deviceToken,
        secret: token,
        deviceId: device.id,
        deviceName: device.name,
        scopes: device.scopes,
        issuedAt: issuedAt,
      ),
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
    );
  }

  // ---------------------------------------------------------------------------
  // 快照
  // ---------------------------------------------------------------------------

  List<RootView> _snapshotRoots = <RootView>[];
  List<ChatSession> _snapshotSessions = <ChatSession>[];
  List<ChatWorkspace> _snapshotWorkspaces = <ChatWorkspace>[];
  List<AgentPreset> _snapshotPresets = <AgentPreset>[];
  ProviderSettings? _snapshotProviders;
  PluginInventory? _snapshotPlugins;

  Future<void> _loadSnapshot(DshClient client, DeviceView device) async {
    _snapshotRoots = await client.roots();
    _snapshotSessions = await client.sessions();
    _snapshotWorkspaces = await _optional(() => client.chatWorkspaces(), <ChatWorkspace>[]);
    _snapshotPresets = await _optional(() => client.agentPresets(), <AgentPreset>[]);
    if (device.scopes.contains('settings.read')) {
      _snapshotProviders = await _optional<ProviderSettings?>(() => client.providerSettings(), null);
      _snapshotPlugins = await _optional<PluginInventory?>(() => client.pluginInventory(), null);
    }
  }

  Future<T> _optional<T>(Future<T> Function() action, T fallback) async {
    try {
      return await action();
    } on Object {
      return fallback;
    }
  }

  Future<void> refreshDashboard() async {
    final client = _client;
    if (client == null) {
      return;
    }
    await _launch(() async {
      final device = await client.currentDevice();
      await _loadSnapshot(client, device);
      final keepSessionId = state.selectedSessionId;
      final keepRootId = state.selectedRootId;
      _update((s) {
        s.device = device;
        s.roots = _snapshotRoots;
        s.sessions = _snapshotSessions;
        s.chatWorkspaces = _snapshotWorkspaces;
        s.agentPresets = _snapshotPresets;
        s.providerSettings = _snapshotProviders;
        s.pluginInventory = _snapshotPlugins;
        s.selectedSessionId =
            _snapshotSessions.any((x) => x.id == keepSessionId) ? keepSessionId : null;
        s.selectedRootId = _snapshotRoots.any((x) => x.id == keepRootId)
            ? keepRootId
            : (_snapshotRoots.isEmpty ? null : _snapshotRoots.first.id);
      });
    });
  }

  // ---------------------------------------------------------------------------
  // 事件流
  // ---------------------------------------------------------------------------

  void _connectEvents(DshClient client) {
    _events?.close();
    _events = client.events(
      listener: _handleEvent,
      connection: _handleConnection,
    );
  }

  void _handleConnection(bool connected) {
    _update((s) => s.eventsConnected = connected);
    if (connected && state.selectedSessionId != null) {
      // 重连成功 = 补拉错过的一切：历史、审批、问答、命令。
      _scheduleChatRefresh();
      unawaited(refreshApprovals());
      unawaited(refreshQuestions());
      unawaited(refreshCommands());
    }
  }

  void _handleEvent(WorkspaceEvent event) {
    final delta = chatDelta(event);
    if (delta != null) {
      if (delta.sessionId == state.selectedSessionId) {
        _update((s) {
          final base = s.liveChat ?? LiveChatState(
            sessionId: delta.sessionId,
            turn: delta.turn,
            step: delta.step,
          );
          s.liveChat = base.append(delta);
          _recomputeVisible(s);
        });
        // 正文一律以 REST 历史为准：每段增量都要让历史跟上，否则流式文字要等落盘才出现。
        _scheduleChatRefresh();
      }
      _observeSeq(event);
      return;
    }

    _observeSeq(event);

    switch (event.type) {
      case 'connection.ready':
        final data = event.dataMap();
        final capabilities = parseCapabilities(data);
        if (capabilities != null) {
          _update((s) {
            s.bridgeCapabilities = capabilities;
            s.bridgeVersion = bridgeVersionOf(data) ?? s.bridgeVersion;
          });
        }
        break;
      case 'chat.turn.failed':
        final failure = chatTurnFailure(event);
        if (failure != null && eventDataString(event, 'sessionId') == state.selectedSessionId) {
          final text = failure.message.isEmpty ? strings.get(failure.titleKey) : failure.message;
          if (text != _lastFailureNotice) {
            _lastFailureNotice = text;
            _update((s) => s.notice = text);
          }
        }
        _scheduleChatRefresh();
        break;
      case 'chat.approval.requested':
      case 'chat.approval.resolved':
        unawaited(refreshApprovals());
        break;
      case 'chat.userQuestions/requested':
        unawaited(refreshQuestions());
        break;
      case 'chat.userQuestions/answered':
      case 'chat.userQuestions/dismissed':
        final callId = eventDataString(event, 'callId');
        if (callId != null) {
          _update((s) {
            s.questions = <PendingQuestionSet>[
              for (final q in s.questions)
                if (q.callId != callId) q,
            ];
          });
        }
        break;
      case 'chat.session.status':
      case 'chat.turn.start':
      case 'chat.turn.end':
        _scheduleSessionsRefresh();
        if (eventDataString(event, 'sessionId') == state.selectedSessionId) {
          _scheduleChatRefresh();
        }
        break;
      case 'chat.deliverables.presented':
        if (eventDataString(event, 'sessionId') == state.selectedSessionId) {
          _scheduleChatRefresh();
        }
        break;
      case 'chat.session.snapshot':
        final cursor = eventDataInt(event, 'cursor');
        if (cursor != null && eventDataString(event, 'sessionId') == state.selectedSessionId) {
          _update((s) => s.baselineCursor = cursor);
          final maxSeq = _maxLocalSeq();
          if (maxSeq == null || maxSeq < cursor) {
            _scheduleChatRefresh();
          }
        }
        break;
      default:
        break;
    }
  }

  /// 严格跳号才重拉整份历史；重复与倒退算去重，不算断档。
  void _observeSeq(WorkspaceEvent event) {
    if (!event.type.startsWith('chat.')) {
      return;
    }
    if (eventDataString(event, 'sessionId') != state.selectedSessionId) {
      return;
    }
    final seq = eventDataInt(event, 'seq');
    if (seq == null) {
      return;
    }
    final monitor = _seqMonitor;
    if (monitor.observe(seq)) {
      _scheduleChatRefresh();
    }
    _update((s) => s.lastEventSeq = seq);
  }

  final ChatSeqMonitor _seqMonitor = ChatSeqMonitor();

  int? _maxLocalSeq() {
    final history = state.history;
    if (history == null || history.events.isEmpty) {
      return null;
    }
    var max = 0;
    for (final entry in history.events) {
      if (entry.event.seq > max) {
        max = entry.event.seq;
      }
    }
    return max == 0 ? null : max;
  }

  /// 熄屏 / 切后台：只关事件流，**保留连接与令牌**（重新探活太贵，且会打断阅读）。
  void pauseEvents() {
    if (_events == null) {
      return;
    }
    _eventsPaused = true;
    _events?.close();
    _events = null;
  }

  Future<void> resumeEvents() async {
    if (!_eventsPaused) {
      return;
    }
    _eventsPaused = false;
    final client = _client;
    if (client == null) {
      return;
    }
    _connectEvents(client);
    _scheduleChatRefresh();
    await refreshApprovals();
    await refreshQuestions();
  }

  // ---------------------------------------------------------------------------

  DshClient _makeClient(String endpoint, String? token) => DshClient(
        endpoint: endpoint,
        token: token,
        http: deps.http,
        deps: DshClientDeps(
          newId: deps.platform.newId,
          timeZoneId: () => _timeZoneId,
          languageTag: () => state.languageTag,
          socket: deps.socket,
          timers: deps.timers,
        ),
      );

  Host? _hostById(String id) {
    for (final host in state.hosts) {
      if (host.id == id) {
        return host;
      }
    }
    return null;
  }

  Future<void> _saveHost(Host host) async {
    final next = deps.hostStore.upsert(state.hosts, host);
    await deps.hostStore.saveHosts(next);
    _update((s) => s.hosts = next);
  }

  Future<void> _launch(Future<void> Function() action) async {
    _update((s) {
      s.busy = true;
      s.error = null;
    });
    try {
      await action();
    } on Object catch (error) {
      _update((s) => s.error = describeError(error, strings));
    } finally {
      _update((s) => s.busy = false);
    }
  }

  void _applyPreferencesTo(HarnessState target) {
    final prefs = deps.prefs;
    target
      ..busySendMode = prefs.busySendMode
      ..showContext = prefs.showContext
      ..fontScale = prefs.fontScale
      ..fontFollowsSystem = prefs.fontFollowsSystem
      ..themeMode = prefs.themeMode
      ..languageTag = prefs.languageTag;
  }

  void _copyInto(HarnessState next) {
    state
      ..restoring = next.restoring
      ..busy = next.busy
      ..endpointDraft = next.endpointDraft
      ..healthOk = next.healthOk
      ..connected = next.connected
      ..endpoint = next.endpoint
      ..hosts = next.hosts
      ..activeHostId = next.activeHostId
      ..activeEndpointId = next.activeEndpointId
      ..endpointProbes = next.endpointProbes
      ..connecting = next.connecting
      ..selectedHostId = next.selectedHostId
      ..device = next.device
      ..bridgeVersion = next.bridgeVersion
      ..bridgeCapabilities = next.bridgeCapabilities
      ..roots = next.roots
      ..sessions = next.sessions
      ..archivedSessions = next.archivedSessions
      ..chatWorkspaces = next.chatWorkspaces
      ..agentPresets = next.agentPresets
      ..sessionModels = next.sessionModels
      ..permissionCatalog = next.permissionCatalog
      ..commands = next.commands
      ..selectedSessionId = next.selectedSessionId
      ..history = next.history
      ..liveChat = next.liveChat
      ..visibleItems = next.visibleItems
      ..todos = next.todos
      ..deliverables = next.deliverables
      ..approvalKind = next.approvalKind
      ..approvals = next.approvals
      ..decidingApproval = next.decidingApproval
      ..questions = next.questions
      ..answeringCallId = next.answeringCallId
      ..answeredCallIds = next.answeredCallIds
      ..eventsConnected = next.eventsConnected
      ..lastEventSeq = next.lastEventSeq
      ..baselineCursor = next.baselineCursor
      ..selectedRootId = next.selectedRootId
      ..currentPath = next.currentPath
      ..directory = next.directory
      ..document = next.document
      ..fileLoading = next.fileLoading
      ..fileError = next.fileError
      ..trash = next.trash
      ..providerSettings = next.providerSettings
      ..pluginInventory = next.pluginInventory
      ..pluginCheckingUpdates = next.pluginCheckingUpdates
      ..notice = next.notice
      ..busySendMode = next.busySendMode
      ..showContext = next.showContext
      ..fontScale = next.fontScale
      ..fontFollowsSystem = next.fontFollowsSystem
      ..themeMode = next.themeMode
      ..languageTag = next.languageTag
      ..error = next.error;
  }

  void _update(void Function(HarnessState s) mutate) {
    if (_closed) {
      return;
    }
    mutate(state);
    notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    _chatRefreshTimer?.cancel();
    _sessionsRefreshTimer?.cancel();
    _events?.close();
    _events = null;
    super.dispose();
  }
}
