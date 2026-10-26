/// 文件、附件、插件与供应商动作（HarnessViewModel 的 part 扩展）。
part of 'harness_view_model.dart';

extension HarnessFilesActions on HarnessViewModel {
  // ---------------------------------------------------------------------------
  // 文件
  // ---------------------------------------------------------------------------

  Future<void> selectRoot(String rootId) async {
    _update((s) {
      s.selectedRootId = rootId;
      s.currentPath = '';
      s.document = null;
      s.fileError = null;
    });
    await openDirectory('');
  }

  Future<void> openDirectory(String path) async {
    final client = _client;
    final rootId = state.selectedRootId;
    if (client == null || rootId == null) {
      return;
    }
    _update((s) {
      s.fileLoading = true;
      s.fileError = null;
    });
    try {
      final directory = await client.entries(rootId, path: path);
      _update((s) {
        s.directory = directory;
        s.currentPath = path;
        s.document = null;
        s.fileLoading = false;
      });
    } on Object catch (error) {
      _update((s) {
        s.fileLoading = false;
        s.fileError = describeError(error, strings);
      });
    }
  }

  Future<void> openFile(FileEntry entry) async {
    final client = _client;
    final rootId = state.selectedRootId;
    if (client == null || rootId == null) {
      return;
    }
    if (entry.isDirectory()) {
      await openDirectory(entry.path);
      return;
    }
    _update((s) {
      s.fileLoading = true;
      s.fileError = null;
    });
    try {
      final content = await client.readFile(rootId, entry.path);
      final isImage = _contentTypeOf(entry.name)?.startsWith('image/') ?? false;
      final tooLarge = content.bytes.length > maxEditBytes;
      String? text;
      if (!isImage && !tooLarge) {
        text = _decodeText(content.bytes);
      }
      _update((s) {
        s.fileLoading = false;
        s.document = OpenDocument(
          entry: entry,
          text: text,
          etag: content.etag,
          contentType: content.contentType,
          bytes: isImage || tooLarge ? content.bytes : null,
          skippedForSize: tooLarge,
        );
      });
    } on Object catch (error) {
      _update((s) {
        s.fileLoading = false;
        s.fileError = describeError(error, strings);
      });
    }
  }

  /// 保存当前文档。ETag 冲突（HTTP 409 / 412）时保留编辑器内容并报「文件已被改动」。
  Future<bool> saveDocument(String text) async {
    final client = _client;
    final rootId = state.selectedRootId;
    final document = state.document;
    if (client == null || rootId == null || document == null) {
      return false;
    }
    try {
      final etag = await client.writeFile(rootId, document.entry.path, utf8.encode(text),
          etag: document.etag.isEmpty ? null : document.etag);
      _update((s) {
        s.document = OpenDocument(
          entry: document.entry.withSize(utf8.encode(text).length),
          text: text,
          etag: etag,
          contentType: document.contentType,
        );
        s.notice = strings.get('file_saved');
      });
      return true;
    } on Object catch (error) {
      if (error is DshApiException && (error.status == 409 || error.status == 412)) {
        _update((s) => s.fileError = strings.get('etag_conflict'));
      } else {
        _update((s) => s.fileError = describeError(error, strings));
      }
      return false;
    }
  }

  String? _contentTypeOf(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.md') || lower.endsWith('.markdown')) return 'text/markdown';
    return null;
  }

  String? _decodeText(List<int> bytes) {
    if (bytes.take(4096).contains(0)) {
      return null; // 二进制：不做文本预览
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  // ---------------------------------------------------------------------------
  // 插件 / 供应商
  // ---------------------------------------------------------------------------

  Future<void> refreshPlugins({bool checkUpdates = false}) async {
    final client = _client;
    if (client == null) {
      return;
    }
    _update((s) => s.pluginCheckingUpdates = checkUpdates);
    try {
      final inventory =
          checkUpdates ? await client.pluginInventoryWithUpdates() : await client.pluginInventory();
      _update((s) {
        s.pluginInventory = inventory;
        s.pluginCheckingUpdates = false;
      });
    } on Object catch (error) {
      _update((s) {
        s.pluginCheckingUpdates = false;
        s.error = describeError(error, strings);
      });
    }
  }

  Future<void> togglePlugin(PluginEntry entry, bool loaded) async {
    final client = _client;
    if (client == null) {
      return;
    }
    await _launch(() async {
      final result = await client.setPluginLoaded(entry.name, loaded);
      _update((s) => s.checkedPluginName = result.name);
      await refreshPlugins();
      _update((s) => s.notice = strings.get('plugin_restart_required'));
    });
  }

  Future<void> refreshProviders() async {
    final client = _client;
    if (client == null) {
      return;
    }
    try {
      final settings = await client.providerSettings();
      _update((s) => s.providerSettings = settings);
    } on Object catch (error) {
      _update((s) => s.error = describeError(error, strings));
    }
  }

  // ---------------------------------------------------------------------------
  // 中转刷新（去抖 + 单飞）
  // ---------------------------------------------------------------------------

  void _scheduleChatRefresh() {
    _chatRefreshTimer?.cancel();
    _chatRefreshTimer = Timer(const Duration(milliseconds: 400), () => unawaited(_flushChatRefresh()));
  }

  Future<void> _flushChatRefresh() async {
    if (_chatRefreshInFlight) {
      _chatRefreshPending = true;
      return;
    }
    _chatRefreshInFlight = true;
    try {
      await loadHistory();
      await refreshApprovals();
    } finally {
      _chatRefreshInFlight = false;
      if (_chatRefreshPending) {
        _chatRefreshPending = false;
        _scheduleChatRefresh();
      }
    }
  }

  void _scheduleSessionsRefresh() {
    _sessionsRefreshTimer?.cancel();
    _sessionsRefreshTimer = Timer(const Duration(milliseconds: 600), () => unawaited(refreshSessions()));
  }

  // ---------------------------------------------------------------------------
  // 偏好
  // ---------------------------------------------------------------------------

  void setThemeMode(String value) {
    deps.prefs.themeMode = value;
    _update((s) => s.themeMode = normalizeThemeMode(value));
  }

  void setFontScale(double value) {
    deps.prefs.fontScale = value;
    _update((s) => s.fontScale = normalizeFontScale(value));
  }

  void setFontFollowsSystem(bool value) {
    deps.prefs.fontFollowsSystem = value;
    _update((s) => s.fontFollowsSystem = value);
  }

  void setShowContext(bool value) {
    deps.prefs.showContext = value;
    _update((s) => s.showContext = value);
  }

  void setSendMode(String value) {
    deps.prefs.busySendMode = value;
    _update((s) => s.busySendMode = normalizeSendMode(value));
  }

  void setLanguage(String value) {
    deps.prefs.languageTag = value;
    _update((s) => s.languageTag = deps.prefs.languageTag);
  }

  void clearError() => _update((s) => s.error = null);

  void clearNotice() => _update((s) => s.notice = null);

  // ---------------------------------------------------------------------------
  // 内部
  // ---------------------------------------------------------------------------
  // 输入框 @ 补全
  // ---------------------------------------------------------------------------

  /// 读会话工作目录下的条目，供 `@` 补全面板用。
  ///
  /// 三态很重要：`null` = 还没读，`空列表` = 目录确实是空的，`mentionFailed` = 读失败。
  /// 把三者混成一个空列表，界面就只能说「没有文件」—— 用户会去查自己的目录。
  Future<void> loadMentionEntries() async {
    final client = _client;
    final session = state.currentSession;
    if (client == null || session == null) {
      return;
    }
    try {
      final page = await client.entries(session.rootId, path: session.cwd);
      _update((s) {
        s.mentionEntries = page.entries;
        s.mentionFailed = false;
      });
    } on Object {
      _update((s) {
        s.mentionEntries = null;
        s.mentionFailed = true;
      });
    }
  }

  /// 把候选条目拼成插进输入框的绝对路径。
  String mentionAbsolutePath(FileEntry entry) => absolutePath(
        cwdAbsolute: state.currentSession?.cwdAbsolute,
        cwdRelative: state.currentSession?.cwd ?? '',
        entryPath: entry.path,
      );

  // ---------------------------------------------------------------------------
  // 按服务器绝对路径打开文件（交付物 / 会话文件面板用）
  // ---------------------------------------------------------------------------

  /// 解析绝对路径并读进 `document`；返回 false 表示不属于任何授权根（正常结果）。
  /// 从聊天里打开一个「路径状」的链接：绝对路径、`file://`、或相对会话 cwd 的路径。
  ///
  /// 模型回复里给的图片/文件常是这三种形态之一；先按绝对路径试，再按 cwd 拼，
  /// 最后再交给服务端解析 —— 每一步都是「能打开就停」，不会因为一种形态失败就整条打不开。
  Future<bool> openChatPath(String raw) async {
    var path = raw.trim();
    if (path.isEmpty) {
      return false;
    }
    if (path.startsWith('file://')) {
      path = Uri.parse(path).toFilePath();
    } else if (!path.startsWith('/') && !path.contains('://')) {
      try {
        path = Uri.decodeComponent(path);
      } on Object {
        // 保留原样：不是合法编码时按字面路径处理。
      }
    }
    final cwd = state.currentSession?.cwdAbsolute;
    final candidates = <String>[
      path,
      if (!path.startsWith('/') && cwd != null && cwd.isNotEmpty) '$cwd/$path',
    ];
    for (final candidate in candidates) {
      if (await openAbsolutePath(candidate)) {
        return true;
      }
    }
    return false;
  }

  Future<bool> openAbsolutePath(String absolutePath) async {
    final client = _client;
    if (client == null) {
      return false;
    }
    _update((s) {
      s.fileLoading = true;
      s.fileError = null;
    });
    try {
      final resolved = await client.resolvePath(absolutePath);
      if (resolved == null) {
        _update((s) {
          s.fileLoading = false;
          s.fileError = strings.get('unknown_error').replaceAll('{reason}', 'PATH_OUTSIDE_ROOTS');
        });
        return false;
      }
      final content = await client.readFile(resolved.rootId, resolved.path);
      final name = resolved.path.split('/').last;
      final entry = FileEntry(
        name: name,
        path: resolved.path,
        kind: resolved.kind,
        size: content.bytes.length,
        modifiedAt: resolved.modifiedAt,
        writable: true,
      );
      final isImage = (resolved.contentType ?? '').startsWith('image/') ||
          (content.contentType ?? '').startsWith('image/');
      final tooLarge = content.bytes.length > maxEditBytes;
      _update((s) {
        s.fileLoading = false;
        s.selectedRootId = resolved.rootId;
        s.document = OpenDocument(
          entry: entry,
          text: isImage || tooLarge ? null : _decodeText(content.bytes),
          etag: content.etag,
          contentType: content.contentType ?? resolved.contentType,
          bytes: isImage || tooLarge ? content.bytes : null,
          skippedForSize: tooLarge,
        );
      });
      return true;
    } on Object catch (error) {
      _update((s) {
        s.fileLoading = false;
        s.fileError = describeError(error, strings);
      });
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // 回收站 / 上传 / 导出
  // ---------------------------------------------------------------------------

  Future<void> refreshTrash() async {
    final client = _client;
    if (client == null) {
      return;
    }
    try {
      final entries = await client.trash();
      _update((s) => s.trash = entries);
    } on Object catch (error) {
      _update((s) => s.error = describeError(error, strings));
    }
  }

  Future<void> restoreTrashEntry(String id) async {
    final client = _client;
    if (client == null) {
      return;
    }
    await _launch(() async {
      await client.restoreTrash(id);
      await refreshTrash();
    });
  }

  /// 往当前目录写一个新文件。已存在时服务端回 409（`If-None-Match: *`）。
  Future<bool> uploadIntoCurrentDirectory(String name, List<int> bytes) async {
    final client = _client;
    final rootId = state.selectedRootId;
    if (client == null || rootId == null) {
      return false;
    }
    final path = state.currentPath.isEmpty ? name : '${state.currentPath}/$name';
    try {
      await client.writeFile(rootId, path, bytes);
      await openDirectory(state.currentPath);
      _update((s) => s.notice = strings.get('file_uploaded'));
      return true;
    } on Object catch (error) {
      _update((s) => s.fileError = describeError(error, strings));
      return false;
    }
  }

  /// 把当前文档导出到 App 的 Documents/Exports（用户在「文件」App 里能看到）。
  Future<String?> exportCurrentDocument() async {
    final document = state.document;
    final text = document?.text;
    if (document == null) {
      return null;
    }
    final bytes = document.bytes ?? (text == null ? null : utf8.encode(text));
    if (bytes == null) {
      return null;
    }
    return exportBytes(document.entry.name, bytes);
  }

  Future<String?> exportBytes(String name, List<int> bytes) async {
    try {
      final path = await exportToDocuments(name, bytes);
      _update((s) => s.notice = strings.format('file_exported', <String, String>{'path': path}));
      return path;
    } on Object catch (error) {
      _update((s) => s.error = strings.format('io_error', <String, String>{'reason': '$error'}));
      return null;
    }
  }
  // ---------------------------------------------------------------------------
  // 供应商编辑
  // ---------------------------------------------------------------------------

  /// 更新供应商配置：只发用户**真的填了**的字段（apiKey 留空 = 不修改）。
  Future<bool> updateProviderConfig(
    String providerId, {
    String? displayName,
    String? baseURL,
    String? api,
    String? apiKey,
  }) async {
    final client = _client;
    if (client == null) {
      return false;
    }
    if (state.providerSettings != null && !state.providerSettings!.writable) {
      _update((s) => s.error = strings.get('provider_write_forbidden'));
      return false;
    }
    var ok = false;
    await _launch(() async {
      final settings = await client.updateProvider(
        providerId,
        ProviderPatch(
          displayName: displayName,
          baseURL: baseURL,
          api: api,
          apiKey: apiKey,
          expectedRevision: state.providerSettings?.revision('providers'),
        ),
      );
      _update((s) {
        s.providerSettings = settings;
        s.notice = strings.get('saved');
      });
      ok = true;
    });
    return ok;
  }

  /// 让服务端探测该供应商的模型列表（用刚填的 baseURL / apiKey 试一次）。
  Future<List<ProviderModel>> discoverModels(String providerId, {String? baseURL, String? api, String? apiKey}) async {
    final client = _client;
    if (client == null) {
      return const <ProviderModel>[];
    }
    try {
      return await client.discoverModels(providerId, baseURL: baseURL, api: api, apiKey: apiKey);
    } on Object catch (error) {
      _update((s) => s.error = describeError(error, strings));
      return const <ProviderModel>[];
    }
  }
}
